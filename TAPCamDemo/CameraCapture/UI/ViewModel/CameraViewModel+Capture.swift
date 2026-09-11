//
//  CameraViewModel+Capture.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

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
    @discardableResult
    func capture(
        pendingCaptureWorkerClient: (any AppAttestClient)? = nil,
        suppressesShutterSound: Bool = false,
        flashMode: CaptureFlashMode = .auto,
        livePhotoRequest: CaptureLivePhotoRequest = .disabled
    ) -> Bool {
        guard !isCapturingPhoto, !isConfiguringSession,
              !photographerModeState.isTransitioning, !isPreparingVideoMode,
              !isVideoRecording else { return false }
        guard !isCameraSuspended else {
            statusMessage = "Camera paused."
            return false
        }

        guard let activeSessionConfiguration else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
                context: .capture
            )
            return false
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
            return false
        }

        guard pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.captureBackpressureLimitReached,
                context: .capture
            )
            return false
        }

        let queueEnteredAt = Date()
        let job = CaptureJob()
        isCapturingPhoto = true

        Task { [pipeline, jobQueue, metricsStore] in
            do {
                let pendingCount = try await jobQueue.beginJob()
                pendingJobCount = pendingCount
                statusMessage = "Capture queued..."

                let usesLocationData = CameraCaptureDataUsePreferences.usesLocationData()
                let location = usesLocationData ? locationProvider.cachedCaptureLocation() : nil
                if usesLocationData {
                    locationProvider.warmLocationCache()
                }
                let context = CaptureSourceContext(
                    sessionConfiguration: captureConfiguration,
                    capturedAt: job.createdAt,
                    location: location,
                    suppressesShutterSound: suppressesShutterSound,
                    flashMode: flashMode,
                    livePhotoRequest: livePhotoRequest
                )
                let queueWaitDuration = Date().timeIntervalSince(queueEnteredAt)
                let result = await pipeline.runSingleCamJob(
                    job: job,
                    context: context,
                    queueWaitDuration: queueWaitDuration,
                    onPhotoCaptureFinished: { self.finishPhotoCapture() }
                )
                let remaining = await jobQueue.finishJob()
                let metrics = await metricsStore.recent()

                self.pendingJobCount = remaining
                self.recentMetrics = metrics
                switch result {
                case .success(let writeResult):
                    self.statusMessage = writeResult.signatureStatus.captureStatusMessage
                    if let hint = writeResult.depthAvailability.viewfinderHint {
                        self.latestCaptureDepthHint = CameraCaptureDepthHint(message: hint)
                    }
                    self.scheduleRecentTAPLibraryPreviewRefresh(afterNanoseconds: 0)
                    if let pendingCaptureWorkerClient {
                        Task {
                            await self.retryPendingCaptures(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
                        }
                    }
                case .failure(let error):
                    #if DEBUG
                    TAPDiagnostics.pendingCapture.error("capture pipeline failed jobID=\(job.id.uuidString, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                    #endif
                    self.reportCaptureFailure(error)
                }
            } catch {
                #if DEBUG
                TAPDiagnostics.pendingCapture.error("capture queue failed jobID=\(job.id.uuidString, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                finishPhotoCapture()
                reportCaptureFailure(error)
                pendingJobCount = await jobQueue.pendingCount()
            }
        }
        return true
    }

    private func finishPhotoCapture() {
        isCapturingPhoto = false
        schedulePendingSelectionReconfigurationIfNeeded()
    }

    func reportCaptureFailure(_ error: Error) {
        statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
        captureFailureID = UUID()
    }

    /// Loads the latest TAP Library thumbnail without prompting for Photos
    /// access. Exported captures keep their small app-private thumbnail so the
    /// camera affordance is stable even when Photos is in limited-library mode.
    func loadRecentTAPLibraryPreviewIfAvailable() async {
        guard hasReleasedDeferredLibraryCoverWork else { return }
        let loadedSnapshot = await libraryStore.cachedSnapshotOrRefresh()
        guard !Task.isCancelled else {
            return
        }
        guard loadedSnapshot != nil || libraryStore.loadError == nil else {
            clearRecentLibraryPresentation()
            return
        }
        lastHandledLibrarySnapshotRevision = libraryStore.snapshot.revision
        await loadRecentLibraryCoverFromCanonicalSnapshot()
    }

    func scheduleRecentTAPLibraryPreviewRefresh(afterNanoseconds delay: UInt64 = 900_000_000) {
        guard hasReleasedDeferredLibraryCoverWork else { return }
        recentLibraryPreviewRefreshTask?.cancel()
        recentLibraryPreviewRefreshTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.loadRecentTAPLibraryPreviewIfIdle()
        }
    }

    private func loadRecentTAPLibraryPreviewIfIdle() async {
        guard !isBusyForNonCaptureStartupWork else {
            return
        }

        await loadRecentTAPLibraryPreviewIfAvailable()
    }

    func loadRecentLibraryCoverFromCanonicalSnapshot() async {
        recentLibraryFetchGeneration &+= 1
        let generation = recentLibraryFetchGeneration
        guard let item = libraryStore.latestItem else {
            clearRecentLibraryPresentation()
            return
        }

        let request = MediaFetchRequestKey(
            itemID: item.mediaID,
            generation: generation,
            purpose: .recentCover
        )
        let kind = item.summary.kind
        publishRecentLibraryPhase(.resolving(nil), request: request, kind: kind)

        let pixelLength = 256
        let cacheKey = item.thumbnailCacheKey(pixelLength: pixelLength)
        if let poster = LibraryThumbnailMemoryCache.shared.poster(for: cacheKey) {
            publishRecentLibraryPhase(.ready(poster), request: request, kind: kind)
            return
        }

        do {
            var phase = try await localRecentPosterPhase(
                for: item,
                cacheKey: cacheKey,
                pixelLength: pixelLength
            )
            guard !Task.isCancelled, isCurrentRecentLibraryRequest(request) else {
                return
            }

            if case .cloudOnly(let preview) = phase,
               LibraryMediaFetchPolicy.allowsNetworkAccess(
                purpose: .recentCover,
                item: item.summary,
                currentItemID: libraryStore.snapshot.latest?.id
               ),
               let posterRequest = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: pixelLength
               ) {
                publishRecentLibraryPhase(
                    .downloadingFromICloud(preview, progress: nil), request: request, kind: kind
                )
                let progress: @Sendable (Double?) -> Void = { [weak self] value in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.isCurrentRecentLibraryRequest(request) else {
                            return
                        }
                        self.publishRecentLibraryPhase(
                            .downloadingFromICloud(preview, progress: value),
                            request: request,
                            kind: kind
                        )
                    }
                }
                let downloaded = try await libraryMediaFetcher.posterPhase(
                    for: posterRequest,
                    allowsNetworkAccess: true,
                    progress: progress
                )
                phase = downloaded.preservingFailurePreview(preview)
            } else if case .cloudOnly(let preview) = phase {
                phase = .failed(preview, reason: .download, retryable: false)
            }

            guard !Task.isCancelled, isCurrentRecentLibraryRequest(request) else {
                return
            }
            publishRecentLibraryPhase(phase, request: request, kind: kind)
        } catch is CancellationError {
            return
        } catch let failure as MediaFetchFailure {
            guard isCurrentRecentLibraryRequest(request) else {
                return
            }
            publishRecentLibraryPhase(
                .failed(nil, reason: failure, retryable: failure.isRetryable),
                request: request,
                kind: kind
            )
        } catch {
            guard isCurrentRecentLibraryRequest(request) else {
                return
            }
            publishRecentLibraryPhase(
                .failed(nil, reason: .download, retryable: true),
                request: request,
                kind: kind
            )
        }
    }

    private func localRecentPosterPhase(
        for item: TAPLibraryItem,
        cacheKey: String,
        pixelLength: Int
    ) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> {
        switch item.source {
        case .pending(let record):
            if let data = try await pendingCaptureStore.thumbnailData(captureID: record.captureID) {
                return await decodedRecentPosterPhase(data: data, cacheKey: cacheKey)
            }
            guard item.isVideo else {
                return .failed(nil, reason: .decode, retryable: false)
            }
            let videoURL = try await pendingCaptureStore.bestAvailableVideoURL(captureID: record.captureID)
            let data = try await videoPosterGenerator.posterData(
                for: videoURL,
                cacheKey: cacheKey,
                pixelLength: pixelLength
            )
            return await decodedRecentPosterPhase(data: data, cacheKey: cacheKey)
        case .ownedPhoto(let record, _):
            if let data = try await pendingCaptureStore.thumbnailData(captureID: record.captureID) {
                return await decodedRecentPosterPhase(data: data, cacheKey: cacheKey)
            }
            if item.isVideo,
               let videoURL = try? await pendingCaptureStore.bestAvailableVideoURL(captureID: record.captureID),
               let data = try? await videoPosterGenerator.posterData(
                for: videoURL,
                cacheKey: cacheKey,
                pixelLength: pixelLength
               ) {
                return await decodedRecentPosterPhase(data: data, cacheKey: cacheKey)
            }
            guard let request = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: pixelLength
            ) else {
                return .failed(nil, reason: .assetRemoved, retryable: false)
            }
            return try await libraryMediaFetcher.posterPhase(
                for: request,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
        case .photos:
            guard let request = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: pixelLength
            ) else {
                return .failed(nil, reason: .assetRemoved, retryable: false)
            }
            return try await libraryMediaFetcher.posterPhase(
                for: request,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
        }
    }

    private func decodedRecentPosterPhase(
        data: Data,
        cacheKey: String
    ) async -> MediaFetchPhase<MediaPoster, MediaPoster> {
        guard let poster = await LibraryThumbnailDecoder.shared.decodedThumbnail(
            data: data, cacheKey: cacheKey
        ) else {
            return .failed(nil, reason: .decode, retryable: false)
        }
        return .ready(poster)
    }

    private func publishRecentLibraryPhase(
        _ phase: MediaFetchPhase<MediaPoster, MediaPoster>,
        request: MediaFetchRequestKey,
        kind: LibraryMediaKind
    ) {
        guard isCurrentRecentLibraryRequest(request) else {
            return
        }
        switch phase {
        case .idle, .resolving:
            if recentLibraryPresentation.poster == nil {
                recentLibraryPresentation = .resolving(itemID: request.itemID, kind: kind)
            }
        case .localPreview(let poster), .ready(let poster):
            recentLibraryPresentation = .ready(
                itemID: request.itemID,
                kind: kind,
                poster: poster
            )
        case .cloudOnly(let preview):
            recentLibraryPresentation = .loading(
                itemID: request.itemID,
                kind: kind,
                preview: preview ?? recentLibraryPresentation.poster,
                progress: nil
            )
        case .downloadingFromICloud(let preview, let progress):
            recentLibraryPresentation = .loading(
                itemID: request.itemID,
                kind: kind,
                preview: preview ?? recentLibraryPresentation.poster,
                progress: progress
            )
        case .failed(let preview, _, let retryable):
            recentLibraryPresentation = .failed(
                itemID: request.itemID,
                kind: kind,
                preview: preview,
                retryable: retryable
            )
        }
    }

    private func isCurrentRecentLibraryRequest(_ request: MediaFetchRequestKey) -> Bool {
        request.generation == recentLibraryFetchGeneration
            && request.itemID == libraryStore.snapshot.latest?.id
    }

    private func clearRecentLibraryPresentation() {
        recentLibraryFetchGeneration &+= 1
        recentLibraryPresentation = .empty
    }

    func retryPendingCaptures(pendingCaptureWorkerClient: any AppAttestClient) async {
        await pendingCaptureProcessor.processPendingCaptures(
            store: pendingCaptureStore,
            appAttestClient: pendingCaptureWorkerClient
        )
        scheduleRecentTAPLibraryPreviewRefresh(afterNanoseconds: 300_000_000)
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
