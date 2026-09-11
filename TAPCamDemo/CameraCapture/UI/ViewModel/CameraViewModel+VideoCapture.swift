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
        guard activeVideoRecordingCaptureID == failure.captureID else {
            return
        }
        #if DEBUG
        TAPDiagnostics.cameraCapture.error(
            "video writer failed during recording captureID=\(failure.captureID, privacy: .private) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
        )
        #endif
        reportCaptureFailure(NSError(domain: failure.domain, code: failure.code))
        if !isVideoRecording {
            // The router can report a failed first frame before start returns.
            // Its pending operation owns recorder/workspace cleanup.
            activeVideoRecordingCaptureID = nil
            statusMessage = "Video recording failed · please record again."
            return
        }
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
        activeVideoRecordingCaptureID = nil
        videoPreparationState = .preparing
        videoRecordingStartedAt = nil
        statusMessage = "Video recording failed · rebuilding video mode..."

        try? await sessionController.cancelVideoRecordingAfterWriterFailure()
        try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
        videoRecordingTemporaryDirectoryURL = nil

        guard generation == configurationGeneration, !isCameraSuspended else { return }
        videoPreparationState = .idle
        let didPrepare = await prepareVideoModeIfNeeded()
        statusMessage = didPrepare
            ? "TAP video ready · please record again."
            : "Video mode unavailable"
        videoWriterFailureRecoveryTask = nil
    }

    @discardableResult
    func prepareVideoModeIfNeeded() async -> Bool {
        guard !isCameraSuspended,
              !isVideoRecording,
              !isCapturingPhoto,
              !isPreparingVideoMode || videoPreparationTask != nil,
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
        let videoRotationAngle = videoCaptureRotationAngle
        let isVideoMirrored = activeSessionConfiguration.device.position == .front
        let depthFilteringEnabled = DepthAnalyzerPreferences.appleDepthFilteringEnabled()

        return await prepareVideoMode(isPrepared: { [sessionController] in
            await sessionController.isVideoRecordingPrepared(
                configuration: activeSessionConfiguration,
                recordsAudio: recordsAudio,
                videoRotationAngle: videoRotationAngle,
                isVideoMirrored: isVideoMirrored,
                depthFilteringEnabled: depthFilteringEnabled
            )
        }) { [sessionController] in
            try await sessionController.prepareVideoRecording(
                configuration: activeSessionConfiguration,
                recordsAudio: recordsAudio,
                videoRotationAngle: videoRotationAngle,
                isVideoMirrored: isVideoMirrored,
                depthFilteringEnabled: depthFilteringEnabled
            )
        }
    }

    /// The session operation, rather than animation time, owns readiness.
    @discardableResult
    func prepareVideoMode(
        isPrepared: @escaping @MainActor () async -> Bool = { false },
        using operation: @escaping @MainActor () async throws -> Void
    ) async -> Bool {
        let generation = configurationGeneration
        let rotation = videoCaptureRotationAngle
        // AVFoundation work already on the session queue must drain. Every
        // waiter then rechecks its own parameters against the retained graph.
        while let task = videoPreparationTask {
            _ = await task.value
        }
        guard !Task.isCancelled, generation == configurationGeneration,
              !isCameraSuspended, !isCapturingPhoto else { return false }

        let task = Task { @MainActor in
            defer { videoPreparationTask = nil }
            do {
                let alreadyPrepared = await isPrepared()
                guard !Task.isCancelled, generation == configurationGeneration,
                      !isCameraSuspended else { return false }
                if !alreadyPrepared {
                    videoPreparationState = .preparing
                    statusMessage = "Preparing TAP video..."
                    try await operation()
                }
                guard !Task.isCancelled, generation == configurationGeneration,
                      !isCameraSuspended else { return false }
                let currentRotationPrepared = rotation == videoCaptureRotationAngle
                let nextState: CameraVideoPreparationState = currentRotationPrepared ? .ready : .needsPreparation
                statusMessage = currentRotationPrepared ? "TAP video ready." : "Preparing TAP video..."
                if videoPreparationState != nextState { videoPreparationState = nextState }
                return true
            } catch {
                guard !Task.isCancelled, generation == configurationGeneration,
                      !isCameraSuspended else { return false }
                statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
                #if DEBUG
                TAPDiagnostics.cameraCapture.error("video mode warmup failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                videoPreparationState = .idle
                return false
            }
        }
        videoPreparationTask = task
        let ready = await task.value
        return ready && !Task.isCancelled
    }

    func invalidateVideoPreparation() {
        videoPreparationTask?.cancel()
        if !isVideoRecording { activeVideoRecordingCaptureID = nil }
        videoPreparationState = .idle
    }

    /// Retire a shutter request before any asynchronous lifecycle cleanup.
    /// Keep a running recording available for normal stop/finalization.
    func cancelPendingVideoStartForLifecycle() {
        guard videoPreparationTask != nil
            || (!isVideoRecording && activeVideoRecordingCaptureID != nil) else { return }
        configurationGeneration += 1
        invalidateVideoPreparation()
    }

    func teardownPreparedVideoModeIfNeeded() async {
        guard !isVideoRecording else {
            return
        }
        let generation = configurationGeneration
        _ = await videoPreparationTask?.value
        guard generation == configurationGeneration else { return }
        videoPreparationState = .preparing
        await sessionController.discardPreparedVideoRecording(reason: "mode-switch")
        guard generation == configurationGeneration else { return }
        videoPreparationState = .idle
    }

    func toggleVideoRecording(
        pendingCaptureWorkerClient: (any AppAttestClient)? = nil,
        onAccepted: @MainActor () -> Void = {}
    ) async {
        if isVideoRecording {
            onAccepted()
            await stopVideoRecording(
                reason: .userStop,
                pendingCaptureWorkerClient: pendingCaptureWorkerClient
            )
        } else {
            await startVideoRecording(pendingCaptureWorkerClient: pendingCaptureWorkerClient, onAccepted: onAccepted)
        }
    }

    func stopActiveVideoRecordingForLifecycleIfNeeded(
        pendingCaptureWorkerClient: (any AppAttestClient)? = nil
    ) async {
        guard isVideoRecording else {
            if activeVideoRecordingCaptureID != nil {
                cancelPendingVideoStartForLifecycle()
            }
            return
        }
        await stopVideoRecording(
            reason: .appLifecycle,
            pendingCaptureWorkerClient: pendingCaptureWorkerClient
        )
    }

    private func startVideoRecording(
        pendingCaptureWorkerClient: (any AppAttestClient)?,
        onAccepted: @MainActor () -> Void
    ) async {
        let generation = configurationGeneration
        _ = await videoPreparationTask?.value
        guard !Task.isCancelled, generation == configurationGeneration else { return }
        guard !isCameraSuspended else {
            statusMessage = "Camera paused."
            return
        }
        guard !isVideoRecording else {
            statusMessage = "TAP video recording is already running."
            return
        }
        guard videoPreparationState == .ready, !isCapturingPhoto else { return }
        guard let configuration = activeSessionConfiguration else {
            reportCaptureFailure(TAPDepthCaptureError.depthDeliveryUnsupported)
            return
        }
        guard configuration.depthDeliverySupported else {
            reportCaptureFailure(TAPDepthCaptureError.depthDeliveryUnsupported)
            return
        }
        guard pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs else {
            reportCaptureFailure(TAPDepthCaptureError.captureBackpressureLimitReached)
            return
        }
        await submitPreparedVideoRecording(
            configuration: configuration,
            videoRotationAngle: videoCaptureRotationAngle,
            generation: generation,
            pendingCaptureWorkerClient: pendingCaptureWorkerClient,
            onAccepted: onAccepted
        )
    }

    private func submitPreparedVideoRecording(
        configuration: SessionConfigurationResult,
        videoRotationAngle: CGFloat?,
        generation: Int,
        pendingCaptureWorkerClient: (any AppAttestClient)?,
        onAccepted: @MainActor () -> Void
    ) async {
        let captureID = UUID().uuidString
        let capturedAt = Date()
        let location = CameraCaptureDataUsePreferences.usesLocationData()
            ? locationProvider.cachedCaptureLocation().map(TAPPendingCaptureLocation.init)
            : nil

        var recorder: TAPVideoRecorder?
        let didStart = await startVideoRecording(
            captureID: captureID,
            generation: generation,
            prepareAndStart: { [self] in
                let workspace = try await pendingCaptureStore.beginVideoCaptureWorkspace(
                    captureID: captureID
                )
                try checkVideoRecordingStart(captureID: captureID, generation: generation)
                recorder = try await sessionController.startVideoRecording(
                    captureID: captureID,
                    capturedAt: capturedAt,
                    outputURL: workspace.artifactURL,
                    configuration: configuration,
                    expectedVideoRotationAngle: videoRotationAngle,
                    location: location
                )
                return workspace.bundleURL
        }, cancelRecording: { [self] in
            if let recorder {
                await sessionController.cancelVideoRecording(recorder)
            }
        }, onAccepted: onAccepted)
        guard didStart, isVideoRecording, activeVideoRecordingCaptureID == captureID else { return }
        installVideoRecordingLimitTask(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
        installVideoThermalObserver(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
    }

    func checkVideoRecordingStart(captureID: String, generation: Int) throws {
        guard !Task.isCancelled, generation == configurationGeneration,
              !isCameraSuspended, !isCapturingPhoto,
              activeVideoRecordingCaptureID == captureID else {
            throw CancellationError()
        }
    }

    @discardableResult
    func startVideoRecording(
        captureID: String,
        generation: Int,
        prepareAndStart: @escaping @MainActor () async throws -> URL,
        cancelRecording: @escaping @MainActor () async -> Void,
        onAccepted: @MainActor () -> Void = {}
    ) async -> Bool {
        guard videoPreparationTask == nil, videoPreparationState == .ready,
              !isVideoRecording, !isCapturingPhoto,
              generation == configurationGeneration, !isCameraSuspended else { return false }
        activeVideoRecordingCaptureID = captureID
        videoPreparationState = .preparing
        statusMessage = "Preparing TAP video..."
        onAccepted()
        // Reuse the preparation tail so retries wait for physical start and
        // cancellation to drain, including a late native start completion.
        let task = Task { @MainActor in
            defer { videoPreparationTask = nil }
            do {
                try checkVideoRecordingStart(captureID: captureID, generation: generation)
                let directory = try await prepareAndStart()
                try checkVideoRecordingStart(captureID: captureID, generation: generation)
                videoRecordingTemporaryDirectoryURL = directory
                isVideoRecording = true
                videoPreparationState = .idle
                videoRecordingStartedAt = Date()
                statusMessage = "Recording TAP video..."
                return true
            } catch {
                await cancelRecording()
                try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
                if activeVideoRecordingCaptureID == captureID {
                    activeVideoRecordingCaptureID = nil
                    if generation == configurationGeneration, !isCameraSuspended {
                        if !(error is CancellationError) { reportCaptureFailure(error) }
                    }
                }
                guard generation == configurationGeneration, !isCameraSuspended else { return false }
                isVideoRecording = false
                videoPreparationState = .needsPreparation
                videoRecordingStartedAt = nil
                videoRecordingTemporaryDirectoryURL = nil
                #if DEBUG
                TAPDiagnostics.cameraCapture.error("video recording start failed captureID=\(captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                return false
            }
        }
        videoPreparationTask = task
        return await task.value
    }

    func stopVideoRecording(
        reason: TAPVideoManifest.StopReason,
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) async {
        await stopVideoRecording(
            reason: reason,
            finishRecording: { try await sessionController.stopVideoRecording(reason: reason) },
            isVideoModePrepared: {
                await sessionController.isVideoRecordingPrepared(videoRotationAngle: videoCaptureRotationAngle)
            },
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
        activeVideoRecordingCaptureID = nil
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
            if reason == .userStop, !(error is CancellationError) {
                reportCaptureFailure(error)
            } else {
                statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            }
            #if DEBUG
            TAPDiagnostics.cameraCapture.error("video recording stop failed captureID=\(captureID ?? "none", privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
        let hasPreparedVideo = await isVideoModePrepared()
        if generation == configurationGeneration, !isCameraSuspended {
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
            let cacheKey = LibraryThumbnailCacheKey.make(
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

    func observeVideoCaptureRotation() {
        let device = activeSessionConfiguration?.device
        guard videoCaptureRotationCoordinator?.device?.uniqueID != device?.uniqueID else { return }
        videoCaptureRotationObservation = nil
        videoCaptureRotationCoordinator = nil
        videoCaptureRotationAngle = nil
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        videoCaptureRotationCoordinator = coordinator
        videoCaptureRotationDidChange(coordinator.videoRotationAngleForHorizonLevelCapture)
        videoCaptureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) {
            [weak self, weak coordinator] _, _ in
            Task { @MainActor [weak self, weak coordinator] in
                guard let self, let coordinator,
                      self.videoCaptureRotationCoordinator === coordinator else { return }
                self.videoCaptureRotationDidChange(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
        }
    }

    func videoCaptureRotationDidChange(_ angle: CGFloat) {
        guard videoCaptureRotationAngle.map({ abs($0 - angle) >= 0.01 }) ?? true else { return }
        videoCaptureRotationAngle = angle
        if !isVideoRecording, videoPreparationState == .ready {
            videoPreparationState = .needsPreparation
        }
    }
}
