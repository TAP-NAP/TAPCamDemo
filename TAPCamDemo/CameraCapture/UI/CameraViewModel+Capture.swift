//
//  CameraViewModel+Capture.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import AppAttestKit
import Foundation
import Photos
import UIKit

/// Shutter and thumbnail work for the SingleCam screen.
///
/// Capture remains asynchronous: the UI queues a job, the pipeline packages and
/// writes it in the background, and the preview stays attached to the session.
@MainActor
extension CameraViewModel {
    func capture(
        appAttestClient: (any AppAttestClient)? = nil,
        suppressesShutterSound: Bool = false
    ) async {
        guard !isPausedForAnalysis else {
            statusMessage = "Camera paused for analysis."
            return
        }

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

            let location = locationProvider.cachedCaptureLocation()
            locationProvider.warmLocationCache()
            let context = CaptureSourceContext(
                sessionConfiguration: captureConfiguration,
                capturedAt: job.createdAt,
                location: location,
                suppressesShutterSound: suppressesShutterSound
            )
            let queueWaitDuration = Date().timeIntervalSince(queueEnteredAt)
            Task { [pipeline, jobQueue, metricsStore] in
                let result = await pipeline.runSingleCamJob(
                    job: job,
                    context: context,
                    assertionSigner: nil,
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
                        self.statusMessage = writeResult.signatureStatus.captureStatusMessage
                        if let pendingCaptureID = writeResult.pendingCaptureID {
                            Task {
                                await self.loadRecentPendingCapturePreview(captureID: pendingCaptureID)
                                if let appAttestClient {
                                    await self.processPendingCaptures(appAttestClient: appAttestClient)
                                }
                            }
                        } else if let assetID = writeResult.assetLocalIdentifier {
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
    func loadRecentTAPLibraryPreviewIfAvailable() async {
        if let latestPending = try? await pendingCaptureStore.visiblePendingRecords().first,
           await loadRecentPendingCapturePreview(captureID: latestPending.captureID) {
            return
        }

        guard let asset = PhotoLibraryWriter.latestDepthAssetIfAuthorized() else {
            return
        }

        loadRecentDepthAssetPreview(assetID: asset.localIdentifier)
    }

    @discardableResult
    func loadRecentPendingCapturePreview(captureID: String) async -> Bool {
        guard let data = try? await pendingCaptureStore.thumbnailData(captureID: captureID),
              let image = UIImage(data: data) else {
            return false
        }

        recentThumbnail = image
        return true
    }

    func processPendingCaptures(appAttestClient: any AppAttestClient) async {
        await pendingCaptureProcessor.processPendingCaptures(
            store: pendingCaptureStore,
            appAttestClient: appAttestClient
        )
        await loadRecentTAPLibraryPreviewIfAvailable()
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
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        var didReceiveFinalImage = false
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 256, height: 256),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard !didReceiveFinalImage else {
                return
            }

            if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
                didReceiveFinalImage = true
                return
            }

            guard info?[PHImageResultIsDegradedKey] as? Bool != true else {
                return
            }

            didReceiveFinalImage = true
            Task { @MainActor in
                self?.recentThumbnail = image
            }
        }
    }
}

private extension CaptureSignatureStatus {
    var captureStatusMessage: String {
        switch self {
        case .pending:
            "Capture queued for signing"
        case .signed:
            "Capture saved"
        case .unsigned:
            "Capture saved unsigned"
        }
    }
}
