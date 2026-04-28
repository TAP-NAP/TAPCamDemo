//
//  CameraViewModel+Capture.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Photos
import UIKit

/// Shutter and thumbnail work for the SingleCam screen.
///
/// Capture remains asynchronous: the UI queues a job, the pipeline packages and
/// writes it in the background, and the preview stays attached to the session.
@MainActor
extension CameraViewModel {
    func capture() async {
        guard let activeSessionConfiguration else {
            statusMessage = TAPDepthCaptureError.depthDeliveryUnsupported.localizedDescription
            return
        }

        guard let captureConfiguration = configurationForCurrentCapture(from: activeSessionConfiguration),
              captureConfiguration.capturePlan.canCapturePhotoDepth else {
            statusMessage = TAPDepthCaptureError.incompatibleRGBDepthPairing.localizedDescription
            return
        }

        guard pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs else {
            statusMessage = TAPDepthCaptureError.captureBackpressureLimitReached.localizedDescription
            return
        }

        let queueEnteredAt = Date()
        let job = CaptureJob()

        do {
            let pendingCount = try await jobQueue.beginJob()
            pendingJobCount = pendingCount
            statusMessage = "Capture queued..."

            let location = await locationProvider.requestOneShotLocation()
            let context = CaptureSourceContext(
                sessionConfiguration: captureConfiguration,
                capturedAt: job.createdAt,
                location: location
            )
            let queueWaitDuration = Date().timeIntervalSince(queueEnteredAt)

            Task { [pipeline, jobQueue, metricsStore] in
                let result = await pipeline.runSingleCamJob(
                    job: job,
                    context: context,
                    pendingJobCount: pendingCount,
                    queueWaitDuration: queueWaitDuration
                )
                let remaining = await jobQueue.finishJob()
                let metrics = await metricsStore.recent()

                await MainActor.run {
                    self.pendingJobCount = remaining
                    self.recentMetrics = metrics
                    switch result {
                    case .success(let writeResult):
                        self.statusMessage = "Saved \(writeResult.destinationDescription)"
                        if let assetID = writeResult.assetLocalIdentifier {
                            self.loadRecentDepthAssetPreview(assetID: assetID)
                        }
                    case .failure(let error):
                        self.statusMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            pendingJobCount = await jobQueue.pendingCount()
        }
    }

    /// Loads the latest saved TAPCamDepth thumbnail without prompting for Photos
    /// access. The camera remains usable even when the user has not granted photo
    /// library read access; in that case the album button simply shows its generic
    /// placeholder until a new capture succeeds.
    func loadRecentDepthAssetPreviewIfAvailable() {
        guard let asset = PhotoLibraryWriter.latestDepthAssetIfAuthorized() else {
            return
        }

        loadRecentDepthAssetPreview(assetID: asset.localIdentifier)
    }

    /// Updates the camera chrome's recent-photo entry point after a successful
    /// write. The full analysis flow still lives in `DepthAnalysisView`; the camera
    /// screen only owns the small thumbnail affordance and the sheet presentation.
    func loadRecentDepthAssetPreview(assetID: String) {
        guard let asset = PhotoLibraryWriter.asset(localIdentifier: assetID) else {
            recentThumbnail = nil
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 144, height: 144),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            Task { @MainActor in
                self?.recentThumbnail = image
            }
        }
    }}
