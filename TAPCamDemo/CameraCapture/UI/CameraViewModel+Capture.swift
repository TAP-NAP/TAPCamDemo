//
//  CameraViewModel+Capture.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import AppAttestKit
import Foundation
import OSLog
import Photos
import UIKit

/// Shutter and thumbnail work for the SingleCam screen.
///
/// Capture remains asynchronous: the UI queues a job, the pipeline packages and
/// writes it in the background, and the preview stays attached to the session.
@MainActor
extension CameraViewModel {
    func capture(
        pendingCaptureWorkerClient: (any AppAttestClient)? = nil,
        suppressesShutterSound: Bool = false
    ) async {
        guard !isPausedForAnalysis else {
            statusMessage = "Camera paused for analysis."
            return
        }

        guard let activeSessionConfiguration else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
                context: .capture
            )
            return
        }

        let captureConfiguration = PreCaptureConfigurationBuilder.configuration(
            from: activeSessionConfiguration,
            previewCropRectNormalized: previewCropRectNormalized
        )
        guard captureConfiguration.depthDeliverySupported,
              captureConfiguration.capturePlan.canCapturePhotoDepth else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.incompatibleRGBDepthPairing,
                context: .capture
            )
            return
        }

        guard pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.captureBackpressureLimitReached,
                context: .capture
            )
            return
        }

        let queueEnteredAt = Date()
        let job = CaptureJob()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("capture requested jobID=\(job.id.uuidString, privacy: .public) suppressesShutterSound=\(suppressesShutterSound, privacy: .public)")
        #endif

        do {
            let pendingCount = try await jobQueue.beginJob()
            pendingJobCount = pendingCount
            statusMessage = "Capture queued..."
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("capture queued jobID=\(job.id.uuidString, privacy: .public) pendingJobCount=\(pendingCount, privacy: .public)")
            #endif

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
                    // Foreground capture stages an unsigned photo file first. App
                    // Attest signing/export retry starts only after the pending
                    // artifact has been written.
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
                        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                        TAPDiagnostics.pendingCapture.info("capture pipeline success jobID=\(job.id.uuidString, privacy: .public) pendingCaptureIDPresent=\(writeResult.pendingCaptureID != nil, privacy: .public) assetIDPresent=\(writeResult.assetLocalIdentifier != nil, privacy: .public) remainingJobs=\(remaining, privacy: .public)")
                        #endif
                        self.statusMessage = writeResult.signatureStatus.captureStatusMessage
                        if let pendingCaptureID = writeResult.pendingCaptureID {
                            Task {
                                await self.loadRecentPendingCapturePreview(captureID: pendingCaptureID)
                                if let pendingCaptureWorkerClient {
                                    await self.retryPendingCaptures(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
                                }
                            }
                        } else if let assetID = writeResult.assetLocalIdentifier {
                            self.loadRecentDepthAssetPreview(assetID: assetID)
                        }
                    case .failure(let error):
                        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                        TAPDiagnostics.pendingCapture.error("capture pipeline failed jobID=\(job.id.uuidString, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                        #endif
                        self.statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
                    }
                }
            }
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("capture queue failed jobID=\(job.id.uuidString, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            pendingJobCount = await jobQueue.pendingCount()
        }
    }

    /// Loads the latest TAP Library thumbnail without prompting for Photos
    /// access. Exported captures keep their small app-private thumbnail so the
    /// camera affordance is stable even when Photos is in limited-library mode.
    func loadRecentTAPLibraryPreviewIfAvailable() async {
        if await loadRecentStoredCapturePreviewIfAvailable() {
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

    private func loadRecentStoredCapturePreviewIfAvailable() async -> Bool {
        guard let records = try? await pendingCaptureStore.allRecords() else {
            return false
        }

        for record in records where recordCanBeDisplayedInTAPLibrary(record) {
            if await loadRecentPendingCapturePreview(captureID: record.captureID) {
                return true
            }
        }
        return false
    }

    private func recordCanBeDisplayedInTAPLibrary(_ record: TAPPendingCaptureRecord) -> Bool {
        guard record.status == .exported else {
            return true
        }
        guard let assetID = record.assetLocalIdentifier else {
            return false
        }
        return PhotoLibraryWriter.asset(localIdentifier: assetID) != nil
    }

    func retryPendingCaptures(pendingCaptureWorkerClient: any AppAttestClient) async {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("viewModel retryPendingCaptures start")
        #endif
        await pendingCaptureProcessor.processPendingCaptures(
            store: pendingCaptureStore,
            appAttestClient: pendingCaptureWorkerClient
        )
        await loadRecentTAPLibraryPreviewIfAvailable()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("viewModel retryPendingCaptures finish")
        #endif
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
