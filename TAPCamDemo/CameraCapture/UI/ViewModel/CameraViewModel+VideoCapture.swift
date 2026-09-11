//
//  CameraViewModel+VideoCapture.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import OSLog

nonisolated enum CameraVideoPreparationState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case needsPreparation
}

@MainActor
extension CameraViewModel {
    func handleVideoRecordingWriterFailure(
        _ failure: CaptureSessionVideoRecordingFailure
    ) {
        guard isVideoRecording,
              activeVideoRecordingCaptureID == failure.captureID else {
            return
        }
        #if DEBUG
        TAPDiagnostics.cameraCapture.error(
            "video writer failed during recording captureID=\(failure.captureID, privacy: .private) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
        )
        #endif
        videoWriterFailureRecoveryTask?.cancel()
        videoWriterFailureRecoveryTask = Task { @MainActor [weak self] in
            await self?.recoverVideoRecordingAfterWriterFailure(
                captureID: failure.captureID
            )
        }
    }

    private func recoverVideoRecordingAfterWriterFailure(captureID: String) async {
        guard activeVideoRecordingCaptureID == captureID else {
            return
        }
        let generation = configurationGeneration
        cancelVideoRecordingStopTriggers()
        isVideoRecording = false
        videoPreparationState = .preparing
        videoRecordingStartedAt = nil
        statusMessage = "Video recording failed · rebuilding video mode..."

        try? await sessionController.cancelVideoRecordingAfterWriterFailure()
        try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
        activeVideoRecordingCaptureID = nil
        videoRecordingTemporaryDirectoryURL = nil

        guard generation == configurationGeneration, !isPausedForAnalysis else { return }
        videoPreparationState = .idle
        let didPrepare = await prepareVideoModeIfNeeded()
        statusMessage = didPrepare
            ? "TAP video ready · please record again."
            : "Video mode unavailable"
        videoWriterFailureRecoveryTask = nil
    }

    @discardableResult
    func prepareVideoModeIfNeeded(depthFilteringEnabled: Bool? = nil) async -> Bool {
        guard !isPausedForAnalysis,
              !isVideoRecording,
              !isPreparingVideoMode,
              let activeSessionConfiguration else {
            return false
        }
        guard activeSessionConfiguration.depthDeliverySupported else {
            videoPreparationState = .idle
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
                context: .capture
            )
            return false
        }

        let recordsAudio = CameraCaptureDataUsePreferences.usesMicrophoneData()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let videoRotationAngle = Self.videoRotationAngleForHorizonLevelCapture(
            device: activeSessionConfiguration.device
        )
        let isVideoMirrored = activeSessionConfiguration.device.position == .front

        let didPrepare = await prepareVideoMode {
            try await sessionController.prepareVideoRecording(
                configuration: activeSessionConfiguration,
                recordsAudio: recordsAudio,
                videoRotationAngle: videoRotationAngle,
                isVideoMirrored: isVideoMirrored,
                depthFilteringEnabled: depthFilteringEnabled ?? DepthAnalyzerPreferences.appleDepthFilteringEnabled()
            )
        }
        return didPrepare
    }

    /// The session operation, rather than animation time, owns readiness.
    @discardableResult
    func prepareVideoMode(using operation: () async throws -> Void) async -> Bool {
        let generation = configurationGeneration
        videoPreparationState = .preparing
        statusMessage = "Preparing TAP video..."
        do {
            try await operation()
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return false
            }
            statusMessage = "TAP video ready."
            videoPreparationState = .ready
            return true
        } catch {
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return false
            }
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            #if DEBUG
            TAPDiagnostics.cameraCapture.error("video mode warmup failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            videoPreparationState = .idle
            return false
        }
    }

    func teardownPreparedVideoModeIfNeeded() async {
        guard !isVideoRecording else {
            return
        }
        let generation = configurationGeneration
        videoPreparationState = .preparing
        await sessionController.discardPreparedVideoRecording(reason: "mode-switch")
        guard generation == configurationGeneration else { return }
        videoPreparationState = .idle
    }

    func toggleVideoRecording(
        pendingCaptureWorkerClient: (any AppAttestClient)? = nil
    ) async {
        if isVideoRecording {
            await stopVideoRecording(
                reason: .userStop,
                pendingCaptureWorkerClient: pendingCaptureWorkerClient
            )
        } else {
            await startVideoRecording(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
        }
    }

    func stopActiveVideoRecordingForLifecycleIfNeeded(
        pendingCaptureWorkerClient: (any AppAttestClient)? = nil
    ) async {
        guard isVideoRecording else {
            return
        }
        await stopVideoRecording(
            reason: .appLifecycle,
            pendingCaptureWorkerClient: pendingCaptureWorkerClient
        )
    }

    private func startVideoRecording(
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) async {
        guard !isPausedForAnalysis else {
            statusMessage = "Camera paused for analysis."
            return
        }
        guard !isVideoRecording else {
            statusMessage = "TAP video recording is already running."
            return
        }
        guard !isPreparingVideoMode else { return }
        guard let configuration = activeSessionConfiguration else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
                context: .capture
            )
            return
        }
        guard configuration.depthDeliverySupported else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
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
        let generation = configurationGeneration
        let depthFilteringEnabled = DepthAnalyzerPreferences.appleDepthFilteringEnabled()
        videoPreparationState = .preparing
        statusMessage = "Preparing TAP video..."

        await prepareAndStartVideoRecording(
            configuration: configuration,
            depthFilteringEnabled: depthFilteringEnabled,
            generation: generation,
            pendingCaptureWorkerClient: pendingCaptureWorkerClient
        )
    }

    private func prepareAndStartVideoRecording(
        configuration: SessionConfigurationResult,
        depthFilteringEnabled: Bool,
        generation: Int,
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) async {
        let captureID = UUID().uuidString
        let capturedAt = Date()
        let recordsAudio = CameraCaptureDataUsePreferences.usesMicrophoneData()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let location = CameraCaptureDataUsePreferences.usesLocationData()
            ? locationProvider.cachedCaptureLocation().map(TAPPendingCaptureLocation.init)
            : nil

        do {
            let workspace = try await pendingCaptureStore.beginVideoCaptureWorkspace(
                captureID: captureID
            )
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
                return
            }
            let request = Self.videoRecordingRequest(
                captureID: captureID,
                capturedAt: capturedAt,
                outputURL: workspace.artifactURL,
                configuration: configuration,
                recordsAudio: recordsAudio,
                depthFilteringEnabled: depthFilteringEnabled
            )
            try await sessionController.prepareVideoRecording(
                configuration: configuration,
                recordsAudio: request.recordsAudio,
                videoRotationAngle: request.videoRotationAngle,
                isVideoMirrored: request.isVideoMirrored,
                depthFilteringEnabled: request.depthFilteringEnabled
            )
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
                return
            }
            let recorder = try await sessionController.startVideoRecording(
                request: request,
                configuration: configuration,
                location: location
            )
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                await sessionController.cancelVideoRecording(recorder)
                try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
                return
            }

            videoRecordingTemporaryDirectoryURL = workspace.bundleURL
            activeVideoRecordingCaptureID = captureID
            isVideoRecording = true
            videoPreparationState = .idle
            videoRecordingStartedAt = Date()
            statusMessage = "Recording TAP video..."
            installVideoRecordingLimitTask(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
            installVideoThermalObserver(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
        } catch {
            try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return
            }
            isVideoRecording = false
            videoPreparationState = .needsPreparation
            videoRecordingStartedAt = nil
            activeVideoRecordingCaptureID = nil
            videoRecordingTemporaryDirectoryURL = nil
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            #if DEBUG
            TAPDiagnostics.cameraCapture.error("video recording start failed captureID=\(captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
    }

    func stopVideoRecording(
        reason: TAPVideoManifest.StopReason,
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) async {
        await stopVideoRecording(
            reason: reason,
            finishRecording: { try await sessionController.stopVideoRecording(reason: reason) },
            isVideoModePrepared: { await sessionController.isVideoRecordingPrepared() },
            processPendingCaptures: {
                if let pendingCaptureWorkerClient {
                    await retryPendingCaptures(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
                }
            }
        )
    }

    func stopVideoRecording(
        reason: TAPVideoManifest.StopReason,
        finishRecording: () async throws -> TAPVideoRecordingArtifact,
        isVideoModePrepared: () async -> Bool,
        processPendingCaptures: () async -> Void
    ) async {
        guard isVideoRecording else {
            return
        }

        let generation = configurationGeneration
        let captureID = activeVideoRecordingCaptureID
        cancelVideoRecordingStopTriggers()
        isVideoRecording = false
        videoPreparationState = .preparing
        videoRecordingStartedAt = nil
        statusMessage = "Finishing TAP video..."

        var ingestedRecord: TAPPendingCaptureRecord?
        do {
            let artifact = try await finishRecording()
            let hasRecordedDepth = artifact.manifest.payload.depthCoverage.sampleCount > 0
            let record = try await pendingCaptureStore.ingestVideo(
                artifact.pendingArtifact
            )
            ingestedRecord = record
            statusMessage = hasRecordedDepth
                ? "TAP video queued for signing · depth samples \(artifact.manifest.payload.depthCoverage.sampleCount)"
                : "TAP video queued for signing · Depth unavailable"
            activeVideoRecordingCaptureID = nil
            videoRecordingTemporaryDirectoryURL = nil
        } catch {
            activeVideoRecordingCaptureID = nil
            if let captureID {
                try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
            }
            videoRecordingTemporaryDirectoryURL = nil
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            #if DEBUG
            TAPDiagnostics.cameraCapture.error("video recording stop failed captureID=\(captureID ?? "none", privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
        let hasPreparedVideo = await isVideoModePrepared()
        if generation == configurationGeneration, !isPausedForAnalysis {
            videoPreparationState = hasPreparedVideo ? .ready : .needsPreparation
        }
        guard let record = ingestedRecord else { return }
        await persistVideoPosterIfPossible(for: record)
        scheduleRecentTAPLibraryPreviewRefresh(afterNanoseconds: 0)
        await processPendingCaptures()
    }

    /// Poster generation is derivative-only and deliberately completes before
    /// export cleanup can remove the pending MP4. Any failure leaves the record
    /// usable and lets startup backfill retry while the artifact still exists.
    private func persistVideoPosterIfPossible(
        for record: TAPPendingCaptureRecord
    ) async {
        guard record.artifactKind == .tapVideo,
              record.thumbnailFilename == nil else {
            return
        }
        do {
            let videoURL = try await pendingCaptureStore.videoArtifactURL(
                captureID: record.captureID
            )
            let cacheKey = DepthAlbumThumbnailCacheKey.make(
                mediaID: .tapCapture(record.captureID),
                version: "video-poster-v1|\(record.updatedAt.timeIntervalSince1970)",
                pixelLength: 512
            )
            let data = try await videoPosterGenerator.posterData(
                for: videoURL,
                cacheKey: cacheKey,
                pixelLength: 512
            )
            _ = try await pendingCaptureStore.storeVideoPoster(
                data,
                captureID: record.captureID,
                posterRevision: 1
            )
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            TAPDiagnostics.pendingCapture.error(
                "video poster generation failed captureID=\(record.captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)"
            )
            #endif
        }
    }

    private static func videoRecordingRequest(
        captureID: String,
        capturedAt: Date,
        outputURL: URL,
        configuration: SessionConfigurationResult,
        recordsAudio: Bool,
        depthFilteringEnabled: Bool
    ) -> TAPVideoRecordingRequest {
        TAPVideoRecordingRequest(
            captureID: captureID,
            capturedAt: capturedAt,
            outputURL: outputURL,
            maximumDuration: TAPVideoRecordingRequest.defaultMaximumDuration,
            videoRotationAngle: videoRotationAngleForHorizonLevelCapture(
                device: configuration.device
            ),
            isVideoMirrored: configuration.device.position == .front,
            recordsAudio: recordsAudio,
            depthFilteringEnabled: depthFilteringEnabled
        )
    }

    private func installVideoRecordingLimitTask(
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) {
        videoDurationLimitTask?.cancel()
        videoDurationLimitTask = Task { [weak self] in
            let nanoseconds = UInt64(TAPVideoRecordingRequest.defaultMaximumDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await self?.stopVideoRecording(
                reason: .durationLimit,
                pendingCaptureWorkerClient: pendingCaptureWorkerClient
            )
        }
    }

    private func installVideoThermalObserver(
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) {
        if let videoThermalObserver {
            NotificationCenter.default.removeObserver(videoThermalObserver)
        }
        videoThermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard ProcessInfo.processInfo.thermalState == .serious
                || ProcessInfo.processInfo.thermalState == .critical else {
                return
            }
            Task { @MainActor [weak self] in
                self?.statusMessage = "Device is hot · stopping TAP video..."
                await self?.stopVideoRecording(
                    reason: .thermalPressure,
                    pendingCaptureWorkerClient: pendingCaptureWorkerClient
                )
            }
        }
    }

    private func cancelVideoRecordingStopTriggers() {
        videoDurationLimitTask?.cancel()
        videoDurationLimitTask = nil
        if let videoThermalObserver {
            NotificationCenter.default.removeObserver(videoThermalObserver)
            self.videoThermalObserver = nil
        }
    }

    @MainActor
    private static func videoRotationAngleForHorizonLevelCapture(device: AVCaptureDevice) -> CGFloat? {
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return rotationCoordinator.videoRotationAngleForHorizonLevelCapture
    }
}
