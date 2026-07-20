//
//  CameraViewModel+VideoCapture.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import Foundation
import OSLog

@MainActor
extension CameraViewModel {
    func prepareVideoModeIfNeeded() async {
        guard !isPausedForAnalysis,
              !isVideoRecording,
              !isPreparingVideoMode,
              let activeSessionConfiguration else {
            return
        }
        guard activeSessionConfiguration.depthDeliverySupported else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
                context: .capture
            )
            return
        }

        isPreparingVideoMode = true
        statusMessage = "Preparing TAP video..."
        let recordsAudio = CameraCaptureDataUsePreferences.usesMicrophoneData()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let videoRotationAngle = Self.videoRotationAngleForHorizonLevelCapture(
            device: activeSessionConfiguration.device
        )
        let isVideoMirrored = activeSessionConfiguration.device.position == .front

        do {
            try await sessionController.prepareVideoRecording(
                configuration: activeSessionConfiguration,
                recordsAudio: recordsAudio,
                videoRotationAngle: videoRotationAngle,
                isVideoMirrored: isVideoMirrored
            )
            statusMessage = "TAP video ready."
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.info("video mode warmup complete recordsAudio=\(recordsAudio, privacy: .public) depthDeliverySupported=\(activeSessionConfiguration.depthDeliverySupported, privacy: .public)")
            #endif
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error("video mode warmup failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }

        isPreparingVideoMode = false
    }

    func teardownPreparedVideoModeIfNeeded() async {
        guard !isVideoRecording else {
            return
        }
        isPreparingVideoMode = false
        await sessionController.discardPreparedVideoRecording(reason: "mode-switch")
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
        guard let activeSessionConfiguration else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.depthDeliveryUnsupported,
                context: .capture
            )
            return
        }
        guard activeSessionConfiguration.depthDeliverySupported else {
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
            videoRecordingTemporaryDirectoryURL = workspace.bundleURL
            let request = TAPVideoRecordingRequest(
                captureID: captureID,
                capturedAt: capturedAt,
                outputURL: workspace.artifactURL,
                maximumDuration: TAPVideoRecordingRequest.defaultMaximumDuration,
                videoRotationAngle: Self.videoRotationAngleForHorizonLevelCapture(
                    device: activeSessionConfiguration.device
                ),
                isVideoMirrored: activeSessionConfiguration.device.position == .front,
                recordsAudio: recordsAudio
            )
            _ = try await sessionController.startVideoRecording(
                request: request,
                configuration: activeSessionConfiguration,
                location: location
            )

            activeVideoRecordingCaptureID = captureID
            isVideoRecording = true
            statusMessage = "Recording TAP video..."
            installVideoRecordingLimitTask(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
            installVideoThermalObserver(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.info("video recording requested captureID=\(captureID, privacy: .private) recordsAudio=\(recordsAudio, privacy: .public) depthDeliverySupported=\(activeSessionConfiguration.depthDeliverySupported, privacy: .public)")
            #endif
        } catch {
            isVideoRecording = false
            activeVideoRecordingCaptureID = nil
            videoRecordingTemporaryDirectoryURL = nil
            try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error("video recording start failed captureID=\(captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
    }

    private func stopVideoRecording(
        reason: TAPVideoManifest.StopReason,
        pendingCaptureWorkerClient: (any AppAttestClient)?
    ) async {
        guard isVideoRecording else {
            return
        }

        let captureID = activeVideoRecordingCaptureID
        cancelVideoRecordingStopTriggers()
        isVideoRecording = false
        statusMessage = "Finishing TAP video..."
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("video recording stop requested captureID=\(captureID ?? "none", privacy: .private) reason=\(reason.rawValue, privacy: .public)")
        #endif

        do {
            let artifact = try await sessionController.stopVideoRecording(reason: reason)
            let hasRecordedDepth = artifact.manifest.payload.depthCoverage.sampleCount > 0
            let record = try await pendingCaptureStore.ingestVideo(
                artifact.pendingArtifact,
                terminalFailureCode: hasRecordedDepth ? nil : .missingDepthData
            )
            statusMessage = hasRecordedDepth
                ? "TAP video queued for signing · depth samples \(artifact.manifest.payload.depthCoverage.sampleCount)"
                : "TAP video stopped · no depth samples were recorded"
            activeVideoRecordingCaptureID = nil
            videoRecordingTemporaryDirectoryURL = nil
            await persistVideoPosterIfPossible(for: record)
            scheduleRecentTAPLibraryPreviewRefresh(afterNanoseconds: 0)
            if hasRecordedDepth, let pendingCaptureWorkerClient {
                await retryPendingCaptures(pendingCaptureWorkerClient: pendingCaptureWorkerClient)
            }
            if reason == .userStop {
                await prepareVideoModeIfNeeded()
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("video pending ingest complete captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) depthSamples=\(artifact.manifest.payload.depthCoverage.sampleCount, privacy: .public)")
            #endif
        } catch {
            activeVideoRecordingCaptureID = nil
            if let captureID {
                try? await pendingCaptureStore.abortVideoCaptureWorkspace(captureID: captureID)
            }
            videoRecordingTemporaryDirectoryURL = nil
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error("video recording stop failed captureID=\(captureID ?? "none", privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
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
                version: "video-poster-v1|\(record.videoFormatRevision ?? 0)|\(record.updatedAt.timeIntervalSince1970)",
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
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
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

    @MainActor
    private static func videoRotationAngleForHorizonLevelCapture(device: AVCaptureDevice) -> CGFloat? {
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return rotationCoordinator.videoRotationAngleForHorizonLevelCapture
    }
}
