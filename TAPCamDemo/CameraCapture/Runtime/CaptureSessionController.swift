//
//  CaptureSessionController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import OSLog

nonisolated enum CaptureSessionFocusRuntimeEvent: Equatable, Sendable {
    case focusStarted
    case focusSettled
    case subjectAreaChanged
}

nonisolated enum CaptureSessionExposureRuntimeEvent: Equatable, Sendable {
    case exposureStarted
    case exposureSettled
}

nonisolated struct CaptureSessionRuntimeFailure: Equatable, Sendable {
    let domain: String
    let code: Int
    let isMediaServicesReset: Bool
}

nonisolated struct CaptureSessionVideoRecordingFailure: Equatable, Sendable {
    let captureID: String
    let domain: String
    let code: Int
}

/// Owns the managed SingleCam `AVCaptureSession` and its mutation queue.
///
/// This is the only production type that changes the AVFoundation session
/// graph. UI, the photo provider, packagers, and writers interact with it
/// through value requests and capture calls, keeping all format, depth-delivery,
/// and zoom mutation serialized on the session queue.
nonisolated final class CaptureSessionController: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let manualFocusPreviewStream = CameraManualFocusPreviewStream()

    private let sessionQueue = DispatchQueue(label: "tapcam.camera-capture.singlecam.session")
    // Session-queue-owned intent survives a system interruption. Explicit
    // pause/stop clears it so interruption recovery cannot reopen the camera.
    private var shouldRunSession = false
    private var canResumeSessionConfiguration = false
    private var isSceneActive = true
    private var focusRuntimeEventHandler: (@Sendable (CaptureSessionFocusRuntimeEvent) -> Void)?
    private var exposureRuntimeEventHandler: (@Sendable (CaptureSessionExposureRuntimeEvent) -> Void)?
    private var subjectAreaChangeObserver: NSObjectProtocol?
    private var sessionRuntimeErrorObserver: NSObjectProtocol?
    private var sessionInterruptedObserver: NSObjectProtocol?
    private var sessionInterruptionEndedObserver: NSObjectProtocol?
    private var sessionDidStopRunningObserver: NSObjectProtocol?
    private var focusAdjustingObservation: NSKeyValueObservation?
    private var exposureAdjustingObservation: NSKeyValueObservation?
    private var activeVideoRecordingGraph: ActiveVideoRecordingGraph?
    private var preparedVideoRecordingGraph: PreparedVideoRecordingGraph?
    private var pendingZoomConfiguration: PendingZoomConfiguration?
    private let runtimeFailureHandlerLock = NSLock()
    private var runtimeFailureHandler: (@Sendable (CaptureSessionRuntimeFailure) -> Void)?
    private let videoRecordingFailureHandlerLock = NSLock()
    private var videoRecordingFailureHandler: (@Sendable (CaptureSessionVideoRecordingFailure) -> Void)?

    init() {
        CameraControlService.registerSessionQueue(sessionQueue)
        observeSessionLifecycle()
    }

    deinit {
        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
        }
        if let sessionRuntimeErrorObserver {
            NotificationCenter.default.removeObserver(sessionRuntimeErrorObserver)
        }
        if let sessionInterruptedObserver {
            NotificationCenter.default.removeObserver(sessionInterruptedObserver)
        }
        if let sessionInterruptionEndedObserver {
            NotificationCenter.default.removeObserver(sessionInterruptionEndedObserver)
        }
        if let sessionDidStopRunningObserver {
            NotificationCenter.default.removeObserver(sessionDidStopRunningObserver)
        }
        focusAdjustingObservation?.invalidate()
        exposureAdjustingObservation?.invalidate()
    }

    var isShutterSoundSuppressionSupported: Bool {
        photoOutput.isShutterSoundSuppressionSupported
    }

    func setFocusRuntimeEventHandler(
        _ handler: (@Sendable (CaptureSessionFocusRuntimeEvent) -> Void)?
    ) {
        sessionQueue.async { [weak self] in
            self?.focusRuntimeEventHandler = handler
        }
    }

    func setExposureRuntimeEventHandler(
        _ handler: (@Sendable (CaptureSessionExposureRuntimeEvent) -> Void)?
    ) {
        sessionQueue.async { [weak self] in
            self?.exposureRuntimeEventHandler = handler
        }
    }

    func setRuntimeFailureHandler(
        _ handler: (@Sendable (CaptureSessionRuntimeFailure) -> Void)?
    ) {
        runtimeFailureHandlerLock.lock()
        runtimeFailureHandler = handler
        runtimeFailureHandlerLock.unlock()
    }

    func setVideoRecordingFailureHandler(
        _ handler: (@Sendable (CaptureSessionVideoRecordingFailure) -> Void)?
    ) {
        videoRecordingFailureHandlerLock.lock()
        videoRecordingFailureHandler = handler
        videoRecordingFailureHandlerLock.unlock()
    }

    private func observeSessionLifecycle() {
        sessionRuntimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
                return
            }
            let failure = CaptureSessionRuntimeFailure(
                domain: error.domain,
                code: error.code,
                isMediaServicesReset: error.code == AVError.Code.mediaServicesWereReset.rawValue
            )
            #if DEBUG
            TAPDiagnostics.cameraCapture.error("capture session runtime error domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) mediaServicesReset=\(failure.isMediaServicesReset, privacy: .public)")
            #endif
            sessionQueue.async { [self] in
                self.canResumeSessionConfiguration = false
            }
            stopInterruptedMotionRecording()
            emitRuntimeFailure(failure)
        }

        sessionInterruptedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.stopInterruptedMotionRecording()
            #if DEBUG
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
            TAPDiagnostics.cameraCapture.error("capture session interrupted reason=\(reason, privacy: .public)")
            #endif
        }

        sessionInterruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in
                self?.startSessionIfNeeded()
            }
        }

        sessionDidStopRunningObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStopRunningNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.stopInterruptedMotionRecording()
        }
    }

    private func stopInterruptedMotionRecording() {
        sessionQueue.async { [weak self] in
            self?.cancelPendingZoomConfiguration()
            self?.activeVideoRecordingGraph?.recorder.stopMotionRecording(recordingError: true)
        }
    }

    private func emitRuntimeFailure(_ failure: CaptureSessionRuntimeFailure) {
        runtimeFailureHandlerLock.lock()
        let handler = runtimeFailureHandler
        runtimeFailureHandlerLock.unlock()
        handler?(failure)
    }

    /// Applies a planned SingleCam photo-depth configuration.
    ///
    /// All AVFoundation graph mutation is serialized here. FOV-only changes can
    /// reuse the current graph and apply only raw zoom.
    ///
    /// - Tag: ConfigureSingleCamSession
    func configure(
        _ request: SessionConfigurationRequest,
        zoomDuration: TimeInterval? = nil,
        beforeImmediateZoom: (@MainActor @Sendable () async throws -> Void)? = nil
    ) async throws -> SessionConfigurationResult {
        if let zoomDuration {
            return try await configureZoom(request, duration: zoomDuration, beforeImmediateZoom: beforeImmediateZoom)
        }
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                cancelPendingZoomConfiguration()
                do {
                    let result = try applySessionConfiguration(request)
                    continuation.resume(returning: result)
                } catch {
                    #if DEBUG
                    TAPDiagnostics.cameraCapture.error("capture session configure failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                    #endif
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applySessionConfiguration(_ request: SessionConfigurationRequest) throws -> SessionConfigurationResult {
        canResumeSessionConfiguration = false
        discardPreparedVideoRecordingGraphLocked(session: session, reason: "configure")
        let result = try Self.configureSession(
            session: session, photoOutput: photoOutput,
            manualFocusPreviewStream: manualFocusPreviewStream, request: request
        )
        if request.auxiliaryPreviewPolicy == .manualFocusLoupe {
            manualFocusPreviewStream.activate(for: result.device)
        } else {
            manualFocusPreviewStream.deactivate()
        }
        observeRuntimeEvents(for: result.device)
        canResumeSessionConfiguration = true
        shouldRunSession = true
        startSessionIfNeeded()
        return result
    }

    private func configureZoom(
        _ request: SessionConfigurationRequest,
        duration: TimeInterval,
        beforeImmediateZoom: (@MainActor @Sendable () async throws -> Void)?
    ) async throws -> SessionConfigurationResult {
        let pending = PendingZoomConfiguration(request: request)
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                sessionQueue.async { [self] in
                    cancelPendingZoomConfiguration()
                    pending.continuation = continuation
                    pendingZoomConfiguration = pending
                    guard !pending.isCancelled, isSceneActive, !session.isInterrupted else {
                        finishZoomConfiguration(pending, result: .failure(CancellationError()))
                        return
                    }
                    do {
                        if let result = try reusableZoomConfiguration(for: request) {
                            pending.device = result.device
                            pending.observation = result.device.observe(\.isRampingVideoZoom, options: [.new]) {
                                [weak self, weak pending] _, _ in
                                self?.sessionQueue.async { [weak self, weak pending] in
                                    guard let pending else { return }
                                    self?.finishZoomIfSettled(pending)
                                }
                            }
                            let target = request.capturePlan.zoom?.rawVideoZoomFactor ?? 1
                            if CameraControlService.hasReachedZoom(target, actual: Double(result.device.videoZoomFactor)) {
                                finishZoomIfSettled(pending)
                            } else {
                                try CameraControlService.rampZoom(target, on: result.device, duration: duration)
                                sessionQueue.asyncAfter(deadline: .now() + 3) { [weak self, weak pending] in
                                    guard let pending else { return }
                                    self?.finishZoomConfiguration(pending, result: .failure(ZoomConfigurationError.timedOut))
                                }
                            }
                        } else {
                            // Preserve the old preview before discarding even a
                            // prepared video graph. Continue only on our queue.
                            pending.presentationTask = Task { @MainActor [weak self, weak pending] in
                                do {
                                    try await beforeImmediateZoom?()
                                    self?.sessionQueue.async { [weak self, weak pending] in
                                        guard let pending else { return }
                                        self?.configureImmediateZoom(pending)
                                    }
                                } catch {
                                    self?.sessionQueue.async { [weak self, weak pending] in
                                        guard let pending else { return }
                                        self?.finishZoomConfiguration(pending, result: .failure(error))
                                    }
                                }
                            }
                        }
                    } catch {
                        finishZoomConfiguration(pending, result: .failure(error))
                    }
                }
            }
        } onCancel: {
            pending.cancel()
            sessionQueue.async { [self] in
                finishZoomConfiguration(pending, result: .failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        return result
    }

    private func reusableZoomConfiguration(for request: SessionConfigurationRequest) throws -> SessionConfigurationResult? {
        let plan = request.capturePlan
        guard session.isRunning, activeVideoRecordingGraph == nil,
              !plan.resolvedCaptureDevice.isRampingVideoZoom,
              CameraControlService.canRampZoom(plan.zoom?.rawVideoZoomFactor ?? 1, on: plan.resolvedCaptureDevice) else {
            return nil
        }
        let resolvedOutput = try SingleCamPhotoSettingsFactory.resolvedOutput(
            photoOutput: photoOutput,
            activeFormat: Self.targetActiveFormat(for: plan),
            assumesDepthDeliverySupported: true,
            outputProfile: request.outputProfile
        )
        try resolvedOutput.validateCapturePlanDepthConfiguration(
            depthDataDeliveryEnabled: plan.captureConfig.depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: plan.captureConfig.embedsDepthDataInPhoto
        )
        let hasAudio = Self.shouldConfigureLivePhotoAudioInput()
        guard Self.canReuseCurrentGraph(
            session: session,
            photoOutput: photoOutput,
            manualFocusPreviewOutput: manualFocusPreviewStream.videoOutput,
            plan: plan,
            resolvedOutput: resolvedOutput,
            shouldConfigureLivePhotoAudioInput: hasAudio,
            auxiliaryPreviewPolicy: request.auxiliaryPreviewPolicy
        ) else { return nil }
        return Self.makeConfigurationResult(
            plan: plan, photoOutput: photoOutput, request: request,
            resolvedOutput: resolvedOutput, livePhotoAudioInputConfigured: hasAudio
        )
    }

    private func configureImmediateZoom(_ pending: PendingZoomConfiguration) {
        guard pendingZoomConfiguration === pending else { return }
        guard !pending.isCancelled, isSceneActive, !session.isInterrupted else {
            finishZoomConfiguration(pending, result: .failure(CancellationError()))
            return
        }
        do {
            let result = try applySessionConfiguration(pending.request)
            guard CameraControlService.hasReachedZoom(
                pending.request.capturePlan.zoom?.rawVideoZoomFactor ?? 1,
                actual: Double(result.device.videoZoomFactor)
            ) else { throw ZoomConfigurationError.targetNotReached }
            finishZoomConfiguration(pending, result: .success(result))
        } catch {
            finishZoomConfiguration(pending, result: .failure(error))
        }
    }

    private func finishZoomIfSettled(_ pending: PendingZoomConfiguration) {
        guard pendingZoomConfiguration === pending,
              let device = pending.device, !device.isRampingVideoZoom else { return }
        do {
            let target = pending.request.capturePlan.zoom?.rawVideoZoomFactor ?? 1
            guard CameraControlService.hasReachedZoom(target, actual: Double(device.videoZoomFactor)),
                  let result = try reusableZoomConfiguration(for: pending.request) else {
                throw ZoomConfigurationError.targetNotReached
            }
            finishZoomConfiguration(pending, result: .success(result))
        } catch {
            finishZoomConfiguration(pending, result: .failure(error))
        }
    }

    private func cancelPendingZoomConfiguration() {
        guard let pending = pendingZoomConfiguration else { return }
        finishZoomConfiguration(pending, result: .failure(CancellationError()))
    }

    private func finishZoomConfiguration(
        _ pending: PendingZoomConfiguration,
        result: Result<SessionConfigurationResult, Error>
    ) {
        guard pendingZoomConfiguration === pending else { return }
        pendingZoomConfiguration = nil
        pending.observation?.invalidate()
        pending.presentationTask?.cancel()
        let completionResult = pending.isCancelled || !isSceneActive || session.isInterrupted
            ? .failure(CancellationError()) : result
        if case .failure(let error) = completionResult {
            if let device = pending.device {
                // Direct assignment cancels a ramp immediately. The native
                // cancel API eases out and could continue after configuration ends.
                do {
                    try CameraControlService.applyZoom(Double(device.videoZoomFactor), to: device)
                } catch {
                    #if DEBUG
                    TAPDiagnostics.cameraCapture.error("capture session zoom cancellation failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                    #endif
                }
            }
            #if DEBUG
            if !(error is CancellationError) {
                TAPDiagnostics.cameraCapture.error("capture session zoom failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            }
            #endif
        }
        pending.continuation?.resume(with: completionResult)
        pending.continuation = nil
    }

    /// Waits behind all already-enqueued AVFoundation work without mutating the
    /// session. A transition watchdog uses this as a single liveness probe: a
    /// retry is not offered until the possibly blocked configuration closure has
    /// left the queue.
    func waitUntilSessionQueueIsResponsive() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume()
            }
        }
    }

    private func observeRuntimeEvents(for device: AVCaptureDevice) {
        focusAdjustingObservation?.invalidate()
        focusAdjustingObservation = nil
        exposureAdjustingObservation?.invalidate()
        exposureAdjustingObservation = nil

        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
            self.subjectAreaChangeObserver = nil
        }

        subjectAreaChangeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: nil
        ) { [weak self] _ in
            self?.emitFocusRuntimeEvent(.subjectAreaChanged)
        }

        focusAdjustingObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
            guard let isAdjustingFocus = change.newValue else {
                return
            }
            self?.emitFocusRuntimeEvent(isAdjustingFocus ? .focusStarted : .focusSettled)
        }

        exposureAdjustingObservation = device.observe(\.isAdjustingExposure, options: [.new]) { [weak self] _, change in
            guard let isAdjustingExposure = change.newValue else {
                return
            }
            self?.emitExposureRuntimeEvent(isAdjustingExposure ? .exposureStarted : .exposureSettled)
        }
    }

    private func emitFocusRuntimeEvent(_ event: CaptureSessionFocusRuntimeEvent) {
        sessionQueue.async { [weak self] in
            self?.focusRuntimeEventHandler?(event)
        }
    }

    private func emitExposureRuntimeEvent(_ event: CaptureSessionExposureRuntimeEvent) {
        sessionQueue.async { [weak self] in
            self?.exposureRuntimeEventHandler?(event)
        }
    }

    func setSceneActive(_ isActive: Bool) {
        sessionQueue.async { [self] in
            isSceneActive = isActive
            if !isActive { cancelPendingZoomConfiguration() }
            startSessionIfNeeded()
        }
    }

    private func startSessionIfNeeded() {
        guard shouldRunSession, isSceneActive,
              !session.isInterrupted, !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        sessionQueue.async { [self, session, photoOutput, manualFocusPreviewStream] in
            shouldRunSession = false
            canResumeSessionConfiguration = false
            cancelPendingZoomConfiguration()
            manualFocusPreviewStream.deactivate()
            discardPreparedVideoRecordingGraphLocked(
                session: session,
                reason: "stop"
            )
            photoOutput.setPreparedPhotoSettingsArray([], completionHandler: nil)
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Stop the sensor while browsing without dismantling a reusable graph.
    func pause() {
        sessionQueue.async { [self] in
            shouldRunSession = false
            cancelPendingZoomConfiguration()
            if session.isRunning { session.stopRunning() }
        }
    }

    func resumeIfConfigured(_ configuration: SessionConfigurationResult) async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard isSceneActive, canResumeSessionConfiguration,
                      activeVideoRecordingGraph == nil,
                      Self.canReuseCurrentGraph(
                        session: session, photoOutput: photoOutput,
                        manualFocusPreviewOutput: manualFocusPreviewStream.videoOutput,
                        plan: configuration.capturePlan, resolvedOutput: configuration.resolvedOutput,
                        shouldConfigureLivePhotoAudioInput: configuration.livePhotoAudioInputConfigured
                            || preparedVideoRecordingGraph?.audioInputAddedByRecording != nil,
                        auxiliaryPreviewPolicy: configuration.auxiliaryPreviewPolicy
                      ) else {
                    continuation.resume(returning: false)
                    return
                }
                // In PRO Video the shared preview connection belongs to the
                // retained graph. Reactivating it would reset rotation/mirroring.
                shouldRunSession = true
                startSessionIfNeeded()
                continuation.resume(returning: session.isRunning || session.isInterrupted)
            }
        }
    }

    func capturePhoto(
        settings: AVCapturePhotoSettings,
        delegate: AVCapturePhotoCaptureDelegate,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool
    ) {
        sessionQueue.async { [photoOutput] in
            if let connection = photoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isVideoMirrored
                }

                if let videoRotationAngle,
                   connection.isVideoRotationAngleSupported(videoRotationAngle) {
                    connection.videoRotationAngle = videoRotationAngle
                }
            }

            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func prepareVideoRecording(
        configuration: SessionConfigurationResult,
        recordsAudio: Bool,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        depthFilteringEnabled: Bool = false
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self, session] in
                let isProVideoGraph = configuration.device.deviceType == .builtInLiDARDepthCamera
                    && configuration.auxiliaryPreviewPolicy == .manualFocusLoupe
                do {
                    guard activeVideoRecordingGraph == nil else {
                        throw TAPDepthCaptureError.videoRecordingAlreadyActive
                    }
                    if let preparedVideoRecordingGraph,
                       preparedVideoRecordingGraph.matches(
                        configuration: configuration,
                        recordsAudio: recordsAudio,
                        videoRotationAngle: videoRotationAngle,
                        isVideoMirrored: isVideoMirrored,
                        depthFilteringEnabled: depthFilteringEnabled
                       ) {
                        continuation.resume()
                        return
                    }

                    if preparedVideoRecordingGraph != nil {
                        discardPreparedVideoRecordingGraphLocked(
                            session: session,
                            reason: "warmup-replace"
                        )
                    }

                    let usesSharedManualFocusVideoOutput = isProVideoGraph
                    let videoOutput = usesSharedManualFocusVideoOutput
                        ? manualFocusPreviewStream.videoOutput
                        : Self.makeVideoRecordingVideoOutput()
                    let audioOutput = recordsAudio ? AVCaptureAudioDataOutput() : nil
                    let depthOutput = Self.makeVideoRecordingDepthOutput(filteringEnabled: depthFilteringEnabled)

                    session.beginConfiguration()
                    var addedOutputs: [AVCaptureOutput] = []
                    var addedAudioInput: AVCaptureDeviceInput?
                    let previousActiveDepthDataFormat = configuration.device.activeDepthDataFormat
                    var didApplyVideoDepthDataFormat = false
                    do {
                        let actualRecordsAudio = try installVideoRecordingOutputs(
                            videoOutput: videoOutput,
                            audioOutput: audioOutput,
                            depthOutput: depthOutput,
                            configuration: configuration,
                            videoRotationAngle: videoRotationAngle,
                            isVideoMirrored: isVideoMirrored,
                            addedOutputs: &addedOutputs,
                            addedAudioInput: &addedAudioInput,
                            didApplyVideoDepthDataFormat: &didApplyVideoDepthDataFormat
                        )

                        let outputRouter = TAPVideoGraphOutputRouter(
                            videoOutput: videoOutput,
                            manualFocusPreviewStream: usesSharedManualFocusVideoOutput
                                ? manualFocusPreviewStream : nil
                        )
                        let dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(
                            dataOutputs: [videoOutput, depthOutput]
                        )
                        dataOutputSynchronizer.setDelegate(
                            outputRouter,
                            queue: outputRouter.callbackQueue
                        )
                        if actualRecordsAudio {
                            audioOutput?.setSampleBufferDelegate(
                                outputRouter,
                                queue: outputRouter.callbackQueue
                            )
                        }
                        session.commitConfiguration()

                        let videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
                            ?? Self.fallbackVideoSettings(for: configuration.device)
                        preparedVideoRecordingGraph = PreparedVideoRecordingGraph(
                            outputs: addedOutputs,
                            videoOutput: videoOutput,
                            depthOutput: depthOutput,
                            audioInputAddedByRecording: addedAudioInput,
                            device: configuration.device,
                            recordsAudio: actualRecordsAudio,
                            requestedRecordsAudio: recordsAudio,
                            videoRotationAngle: videoRotationAngle,
                            isVideoMirrored: isVideoMirrored,
                            depthFilteringEnabled: depthFilteringEnabled,
                            videoSettings: videoSettings,
                            previousActiveDepthDataFormat: previousActiveDepthDataFormat,
                            didApplyVideoDepthDataFormat: didApplyVideoDepthDataFormat,
                            dataOutputSynchronizer: dataOutputSynchronizer,
                            outputRouter: outputRouter,
                            usesSharedManualFocusVideoOutput: usesSharedManualFocusVideoOutput
                        )
                        continuation.resume()
                    } catch {
                        Self.clearVideoRecordingOutputDelegates(addedOutputs)
                        Self.removeVideoRecordingOutputs(
                            addedOutputs,
                            audioInputAddedByRecording: addedAudioInput,
                            from: session
                        )
                        restoreVideoRecordingConfiguration(
                            device: configuration.device,
                            previousActiveDepthDataFormat: previousActiveDepthDataFormat,
                            didApplyVideoDepthDataFormat: didApplyVideoDepthDataFormat,
                            sharedManualFocusVideoOutput: usesSharedManualFocusVideoOutput ? videoOutput : nil,
                            reason: "warmup-rollback"
                        )
                        session.commitConfiguration()
                        throw error
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func discardPreparedVideoRecording(reason: String) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self, session] in
                discardPreparedVideoRecordingGraphLocked(
                    session: session,
                    reason: reason
                )
                continuation.resume()
            }
        }
    }

    func startVideoRecording(
        request: TAPVideoRecordingRequest,
        configuration: SessionConfigurationResult,
        location: TAPPendingCaptureLocation?
    ) async throws -> TAPVideoRecorder {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self, session] in
                do {
                    guard activeVideoRecordingGraph == nil else {
                        throw TAPDepthCaptureError.videoRecordingAlreadyActive
                    }

                    guard let preparedGraph = preparedVideoRecordingGraph,
                          preparedGraph.matches(
                            configuration: configuration,
                            recordsAudio: request.recordsAudio,
                            videoRotationAngle: request.videoRotationAngle,
                            isVideoMirrored: request.isVideoMirrored,
                            depthFilteringEnabled: request.depthFilteringEnabled
                          ) else {
                        discardPreparedVideoRecordingGraphLocked(
                            session: session,
                            reason: "start-mismatch"
                        )
                        throw TAPDepthCaptureError.videoRecordingFailed(
                            "Video graph must be prepared before recording"
                        )
                    }
                    let recorder = try TAPVideoRecorder(
                        request: request,
                        sessionConfiguration: configuration,
                        videoSettings: preparedGraph.videoSettings,
                        recordsAudio: preparedGraph.recordsAudio,
                        recordsDepth: true,
                        location: location,
                        callbackQueue: preparedGraph.outputRouter.callbackQueue,
                        writerFailureHandler: { [weak self] failure in
                            self?.emitVideoRecordingFailure(failure)
                        }
                    )
                    preparedVideoRecordingGraph = nil

                    recorder.useSynchronizedOutputs(
                        videoOutput: preparedGraph.videoOutput,
                        depthOutput: preparedGraph.depthOutput
                    )
                    recorder.startMotionRecording(captureClock: session.synchronizationClock)
                    preparedGraph.outputRouter.activate(recorder)

                    activeVideoRecordingGraph = ActiveVideoRecordingGraph(
                        recorder: recorder,
                        preparedGraph: preparedGraph
                    )
                    continuation.resume(returning: recorder)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func isVideoRecordingPrepared() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: preparedVideoRecordingGraph != nil
                    && shouldRunSession && isSceneActive && session.isRunning && !session.isInterrupted)
            }
        }
    }

    func isVideoRecordingPrepared(
        configuration: SessionConfigurationResult,
        recordsAudio: Bool,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        depthFilteringEnabled: Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: preparedVideoRecordingGraph?.matches(
                    configuration: configuration, recordsAudio: recordsAudio,
                    videoRotationAngle: videoRotationAngle, isVideoMirrored: isVideoMirrored,
                    depthFilteringEnabled: depthFilteringEnabled
                ) == true)
            }
        }
    }

    func stopVideoRecording(
        reason: TAPVideoManifest.StopReason
    ) async throws -> TAPVideoRecordingArtifact {
        let recorder = try await detachActiveVideoRecording(
            keepPreparedGraph: reason == .userStop || reason == .durationLimit
        )
        return try await recorder.finish(reason: reason)
    }

    func cancelVideoRecordingAfterWriterFailure() async throws {
        let recorder = try await detachActiveVideoRecording()
        await recorder.cancelAfterWriterFailure()
    }

    func cancelVideoRecording(_ recorder: TAPVideoRecorder) async {
        _ = try? await detachActiveVideoRecording(expectedRecorder: recorder)
        await recorder.cancelAfterWriterFailure()
    }

    private func detachActiveVideoRecording(
        expectedRecorder: TAPVideoRecorder? = nil,
        keepPreparedGraph: Bool = false
    ) async throws -> TAPVideoRecorder {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self, session] in
                guard let graph = activeVideoRecordingGraph,
                      expectedRecorder == nil || graph.recorder === expectedRecorder else {
                    continuation.resume(throwing: TAPDepthCaptureError.videoRecordingNotActive)
                    return
                }
                // Stop clock conversions before removing inputs can replace
                // the session's synchronization clock.
                graph.recorder.stopMotionRecording()
                activeVideoRecordingGraph = nil
                let retainsPreparedGraph = keepPreparedGraph && shouldRunSession && isSceneActive
                    && session.isRunning && !session.isInterrupted
                if retainsPreparedGraph {
                    // Keep the committed graph flowing with no recording consumer.
                    graph.preparedGraph.outputRouter.deactivateRecorder()
                }
                preparedVideoRecordingGraph = graph.preparedGraph
                if !retainsPreparedGraph {
                    discardPreparedVideoRecordingGraphLocked(session: session, reason: "stop")
                }
                continuation.resume(returning: graph.recorder)
            }
        }
    }

    private func emitVideoRecordingFailure(_ failure: TAPVideoWriterFailure) {
        videoRecordingFailureHandlerLock.lock()
        let handler = videoRecordingFailureHandler
        videoRecordingFailureHandlerLock.unlock()
        handler?(CaptureSessionVideoRecordingFailure(
            captureID: failure.captureID,
            domain: failure.domain,
            code: failure.code
        ))
    }

    func applyManualControlCommandPlan(
        _ plan: CameraManualControlCommandPlan,
        to device: AVCaptureDevice
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try CameraControlService.applyManualControlCommandPlan(plan, to: device)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs the request-local, focus-only AF phase for MF tap assist.
    ///
    /// The observation is installed before the command and belongs to this
    /// operation token, so an old global focus-settled event cannot complete a
    /// newer tap. The caller keeps this wait and the following `.current` lock
    /// inside one `CameraManualFocusTransportQueue` transaction.
    func autoFocusOnlyAndWaitForManualFocusTapAssist(
        at point: CameraManualControlIntent.NormalizedPoint,
        expectedDeviceID: String,
        expectedControlSignature: CameraManualControlCommandPlan.ControlSurfaceSignature,
        operationToken: CameraManualFocusOperationToken,
        on device: AVCaptureDevice
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ManualFocusAutoFocusSettleContinuationGate(continuation: continuation)
            gate.bind(to: operationToken)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.2) {
                gate.resumeForTimeout()
            }

            sessionQueue.async { [session] in
                do {
                    guard operationToken.isValid else {
                        throw CancellationError()
                    }
                    try Self.validateManualFocusTarget(
                        session: session,
                        device: device,
                        expectedDeviceID: expectedDeviceID,
                        expectedControlSignature: expectedControlSignature
                    )

                    let observation = device.observe(
                        \.isAdjustingFocus,
                        options: [.new]
                    ) { _, change in
                        guard let isAdjustingFocus = change.newValue else {
                            return
                        }
                        gate.observe(isAdjustingFocus: isAdjustingFocus)
                    }
                    gate.attach(observation: observation)
                    try CameraControlService.startManualFocusTapAssistAutoFocus(
                        at: point,
                        on: device
                    )
                    gate.markRequestApplied(isAdjustingFocus: device.isAdjustingFocus)
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    /// Applies one MF write and waits for AVFoundation's first-applied-buffer
    /// completion. The timeout prevents a session reset from leaving UI work
    /// suspended forever.
    func setManualFocusLocked(
        _ target: CameraManualFocusLockTarget,
        expectedDeviceID: String,
        expectedControlSignature: CameraManualControlCommandPlan.ControlSurfaceSignature,
        generation: Int,
        operationToken: CameraManualFocusOperationToken,
        on device: AVCaptureDevice
    ) async throws -> CameraManualControlReadbackSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ManualFocusLockContinuationGate(continuation: continuation)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5) {
                gate.resumeForTimeout(operationToken: operationToken)
            }
            sessionQueue.async { [self, session] in
                do {
                    guard operationToken.isValid else {
                        throw CancellationError()
                    }
                    try Self.validateManualFocusTarget(
                        session: session,
                        device: device,
                        expectedDeviceID: expectedDeviceID,
                        expectedControlSignature: expectedControlSignature
                    )
                    try CameraControlService.setManualFocusLocked(target, on: device) { [self] _ in
                        sessionQueue.async { [session] in
                            do {
                                guard operationToken.isValid else {
                                    throw CancellationError()
                                }
                                try Self.validateManualFocusTarget(
                                    session: session,
                                    device: device,
                                    expectedDeviceID: expectedDeviceID,
                                    expectedControlSignature: expectedControlSignature
                                )
                                gate.resume(returning: Self.manualControlSnapshot(
                                    reason: .userInteractionEnded,
                                    generation: generation,
                                    from: device
                                ))
                            } catch {
                                gate.resume(throwing: error)
                            }
                        }
                    }
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    func applyManualControlIntent(
        _ intent: CameraManualControlIntent,
        against capability: CameraControlCapabilitySnapshot,
        to device: AVCaptureDevice
    ) async throws -> CameraManualControlResolutionPresentation {
        let resolution = intent.resolved(against: capability)
        let presentation = CameraManualControlResolutionPresentation(resolution: resolution)
        guard resolution.isExecutable else {
            return presentation
        }

        try await applyManualControlCommandPlan(
            CameraManualControlCommandPlan(resolution: resolution),
            to: device
        )
        return presentation
    }

    func applyExposureTargetBias(_ exposureBias: Double, to device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try CameraControlService.applyExposureTargetBias(exposureBias, to: device)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func readManualControlSnapshot(
        reason: CameraManualControlReadbackReason,
        generation: Int,
        from device: AVCaptureDevice
    ) async -> CameraManualControlReadbackSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: Self.manualControlSnapshot(
                    reason: reason,
                    generation: generation,
                    from: device
                ))
            }
        }
    }

    private static func validateManualFocusTarget(
        session: AVCaptureSession,
        device: AVCaptureDevice,
        expectedDeviceID: String,
        expectedControlSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
    ) throws {
        guard device.uniqueID == expectedDeviceID,
              session.inputs.contains(where: { input in
                  (input as? AVCaptureDeviceInput)?.device.uniqueID == expectedDeviceID
              }) else {
            throw TAPDepthCaptureError.cameraControlTargetDeviceChanged
        }
        let currentSignature = CameraManualControlCommandPlan.ControlSurfaceSignature(
            capability: CameraControlCapabilitySnapshot.make(device: device)
        )
        guard currentSignature == expectedControlSignature else {
            throw TAPDepthCaptureError.cameraControlTargetSurfaceChanged
        }
    }

    private static func manualControlSnapshot(
        reason: CameraManualControlReadbackReason,
        generation: Int,
        from device: AVCaptureDevice
    ) -> CameraManualControlReadbackSnapshot {
        let capability = CameraControlCapabilitySnapshot.make(device: device)
        return CameraManualControlReadbackSnapshot(
            deviceID: device.uniqueID,
            controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(capability: capability),
            generation: generation,
            iso: capability.exposure.currentISO,
            shutterDurationSeconds: capability.exposure.currentShutterDurationSeconds,
            exposureTargetOffset: capability.exposure.currentExposureTargetOffset,
            exposureTargetBias: Double(device.exposureTargetBias),
            lensPosition: capability.focus.currentLensPosition,
            exposureMode: CameraManualControlReadbackExposureMode(device.exposureMode),
            focusMode: CameraManualControlReadbackFocusMode(device.focusMode),
            isAdjustingExposure: device.isAdjustingExposure,
            isAdjustingFocus: device.isAdjustingFocus,
            reason: reason
        )
    }

    func restoreAutoPhotoControls(
        globalExposureBias: Double,
        to device: AVCaptureDevice
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try CameraControlService.restoreAutoPhotoControls(
                        globalExposureBias: globalExposureBias,
                        to: device
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func configureSession(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        manualFocusPreviewStream: CameraManualFocusPreviewStream,
        request: SessionConfigurationRequest
    ) throws -> SessionConfigurationResult {
        let plan = request.capturePlan
        let zoom = plan.zoom?.rawVideoZoomFactor ?? 1.0
        let resolvedOutput = try SingleCamPhotoSettingsFactory.resolvedOutput(
            photoOutput: photoOutput,
            activeFormat: targetActiveFormat(for: plan),
            assumesDepthDeliverySupported: true,
            outputProfile: request.outputProfile
        )
        let shouldConfigureLivePhotoAudioInput = shouldConfigureLivePhotoAudioInput()
        try resolvedOutput.validateCapturePlanDepthConfiguration(
            depthDataDeliveryEnabled: plan.captureConfig.depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: plan.captureConfig.embedsDepthDataInPhoto
        )

        /*
         Release FOV chips such as 24mm, 48mm, and 77mm usually resolve to raw
         `videoZoomFactor` values on the same Apple-paired photo-depth graph.
         When the active graph already matches the requested device, format, and
         depth state, changing only zoom keeps the preview continuous and avoids
         an input teardown that can briefly show the virtual camera's wide
         baseline.
         */
        if canReuseCurrentGraph(
            session: session,
            photoOutput: photoOutput,
            manualFocusPreviewOutput: manualFocusPreviewStream.videoOutput,
            plan: plan,
            resolvedOutput: resolvedOutput,
            shouldConfigureLivePhotoAudioInput: shouldConfigureLivePhotoAudioInput,
            auxiliaryPreviewPolicy: request.auxiliaryPreviewPolicy
        ) {
            try CameraControlService.applyZoom(zoom, to: plan.resolvedCaptureDevice)
            return makeConfigurationResult(
                plan: plan,
                photoOutput: photoOutput,
                request: request,
                resolvedOutput: resolvedOutput,
                livePhotoAudioInputConfigured: shouldConfigureLivePhotoAudioInput
            )
        }

        let livePhotoAudioInputConfigured = try rebuildSessionGraph(
            session: session,
            photoOutput: photoOutput,
            manualFocusPreviewOutput: manualFocusPreviewStream.videoOutput,
            plan: plan,
            resolvedOutput: resolvedOutput,
            zoom: zoom,
            shouldConfigureLivePhotoAudioInput: shouldConfigureLivePhotoAudioInput,
            auxiliaryPreviewPolicy: request.auxiliaryPreviewPolicy
        )

        /*
         Apply zoom after the session graph has committed and photo depth delivery
         is enabled. Some virtual depth devices accept a zoom value while the
         graph is being configured, then reset it during `commitConfiguration()`.
         Setting zoom on the committed device is what makes the preview FOV match
         the semantic capture plan. This matters when a label such as `48mm`
         resolves to raw zoom `4.0` on a depth-safe virtual-camera format instead
         of the familiar UI shorthand of `2x`.
         */
        try CameraControlService.applyZoom(zoom, to: plan.resolvedCaptureDevice)

        return makeConfigurationResult(
            plan: plan,
            photoOutput: photoOutput,
            request: request,
            resolvedOutput: resolvedOutput,
            livePhotoAudioInputConfigured: livePhotoAudioInputConfigured
        )
    }

    /// Rebuilds the AVFoundation graph for real source, format, or depth-state
    /// changes. FOV-only changes should take the fast path above instead.
    private static func rebuildSessionGraph(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        manualFocusPreviewOutput: AVCaptureVideoDataOutput,
        plan: CaptureSourcePlan,
        resolvedOutput: ResolvedCaptureOutputProfile,
        zoom: Double,
        shouldConfigureLivePhotoAudioInput: Bool,
        auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy
    ) throws -> Bool {
        let previousDeviceInputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        let hadManualFocusPreviewOutput = session.outputs.contains(manualFocusPreviewOutput)
        let needsManualFocusPreviewOutput = auxiliaryPreviewPolicy == .manualFocusLoupe
        session.beginConfiguration()
        var livePhotoAudioInputConfigured = false
        do {
            session.sessionPreset = .photo
            let videoInputs = previousDeviceInputs.filter { $0.device.hasMediaType(.video) }
            let audioInputs = previousDeviceInputs.filter { $0.device.hasMediaType(.audio) }
            videoInputs.forEach { session.removeInput($0) }

            if !shouldConfigureLivePhotoAudioInput {
                audioInputs.forEach { session.removeInput($0) }
            }

            try CameraControlService.configureBaselineControls(
                for: plan.resolvedCaptureDevice,
                formatSelection: plan.formatSelection
            )

            /*
             Include the target raw zoom in the configuration transaction. When
             moving to or from the 77mm semantic FOV, some virtual cameras can
             briefly present their wide baseline during commit if zoom is only
             applied afterwards. We still re-apply after commit because several
             formats reset zoom during graph changes.
             */
            try CameraControlService.applyZoom(zoom, to: plan.resolvedCaptureDevice)

            let input = try AVCaptureDeviceInput(device: plan.resolvedCaptureDevice)
            guard session.canAddInput(input) else {
                throw TAPDepthCaptureError.unableToAddCameraInput
            }
            session.addInput(input)

            if shouldConfigureLivePhotoAudioInput {
                if hasLivePhotoAudioInput(session) {
                    livePhotoAudioInputConfigured = true
                } else if let audioInput = try? makeLivePhotoAudioInput(),
                          session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    livePhotoAudioInputConfigured = true
                }
            }

            if !session.outputs.contains(photoOutput) {
                guard session.canAddOutput(photoOutput) else {
                    throw TAPDepthCaptureError.unableToAddPhotoOutput
                }
                session.addOutput(photoOutput)
            }

            if needsManualFocusPreviewOutput {
                if !session.outputs.contains(manualFocusPreviewOutput) {
                    guard session.canAddOutput(manualFocusPreviewOutput) else {
                        throw TAPDepthCaptureError.unableToAddVideoOutput
                    }
                    session.addOutput(manualFocusPreviewOutput)
                }
                if let connection = manualFocusPreviewOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(0) {
                    // The loupe rotates its display layer, avoiding per-frame
                    // physical buffer rotation on this auxiliary output.
                    connection.videoRotationAngle = 0
                }
            } else if session.outputs.contains(manualFocusPreviewOutput) {
                session.removeOutput(manualFocusPreviewOutput)
            }

            photoOutput.maxPhotoQualityPrioritization = resolvedOutput.maxPhotoQualityPrioritization
            if let maxPhotoDimensions = resolvedOutput.maxPhotoDimensions {
                photoOutput.maxPhotoDimensions = maxPhotoDimensions.cmVideoDimensions
            }
            let availableCapabilities = CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: plan.resolvedCaptureDevice.activeFormat
            )
            try resolvedOutput.validatePhotoOutputCapabilities(availableCapabilities)
            photoOutput.isDepthDataDeliveryEnabled = resolvedOutput.depthDataDeliveryEnabled
            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
            let configuredCapabilities = CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: plan.resolvedCaptureDevice.activeFormat
            )
            try resolvedOutput.validatePhotoOutputCapabilities(
                configuredCapabilities,
                requireConfiguredState: true
            )
            session.commitConfiguration()
            return livePhotoAudioInputConfigured
        } catch {
            #if DEBUG
            TAPDiagnostics.cameraCapture.error("capture session graph rebuild failed before rollback commit deviceType=\(plan.resolvedCaptureDevice.deviceType.rawValue, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            let currentDeviceInputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            currentDeviceInputs.forEach { session.removeInput($0) }
            for previousInput in previousDeviceInputs where session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            let hasManualFocusPreviewOutput = session.outputs.contains(manualFocusPreviewOutput)
            if hasManualFocusPreviewOutput && !hadManualFocusPreviewOutput {
                session.removeOutput(manualFocusPreviewOutput)
            } else if !hasManualFocusPreviewOutput,
                      hadManualFocusPreviewOutput,
                      session.canAddOutput(manualFocusPreviewOutput) {
                session.addOutput(manualFocusPreviewOutput)
            }
            session.commitConfiguration()
            throw error
        }
    }

    /// Returns true when the current SingleCam graph already represents the
    /// requested photo-depth pipeline and only the raw zoom factor needs to move.
    ///
    /// - Tag: ReuseSingleCamGraph
    private static func canReuseCurrentGraph(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        manualFocusPreviewOutput: AVCaptureVideoDataOutput,
        plan: CaptureSourcePlan,
        resolvedOutput: ResolvedCaptureOutputProfile,
        shouldConfigureLivePhotoAudioInput: Bool,
        auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy
    ) -> Bool {
        guard session.sessionPreset == .photo || session.sessionPreset == .inputPriority else {
            return false
        }

        let inputDevices = session.inputs.compactMap { input in
            (input as? AVCaptureDeviceInput)?.device
        }
        let videoInputDevices = inputDevices.filter { $0.hasMediaType(.video) }
        guard videoInputDevices.count == 1 else {
            return false
        }

        guard hasLivePhotoAudioInput(session) == shouldConfigureLivePhotoAudioInput else {
            return false
        }

        let activeDevice = videoInputDevices[0]
        guard activeDevice.uniqueID == plan.resolvedCaptureDevice.uniqueID else {
            return false
        }

        if let requestedFormat = plan.formatSelection?.videoFormat,
           !formatsHaveSamePhotoDepthPreviewSignature(
            activeDevice.activeFormat,
            requestedFormat
           ) {
            return false
        }

        guard session.outputs.contains(photoOutput) else {
            return false
        }

        let hasManualFocusPreviewOutput = session.outputs.contains(manualFocusPreviewOutput)
        guard hasManualFocusPreviewOutput == (auxiliaryPreviewPolicy == .manualFocusLoupe) else {
            return false
        }

        guard photoOutput.isDepthDataDeliveryEnabled == resolvedOutput.depthDataDeliveryEnabled else {
            return false
        }

        if photoOutput.isLivePhotoCaptureSupported && !photoOutput.isLivePhotoCaptureEnabled {
            return false
        }

        guard (try? resolvedOutput.validatePhotoOutputCapabilities(
            CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: activeDevice.activeFormat
            ),
            requireConfiguredState: true
        )) != nil else {
            return false
        }

        return true
    }

    private static func shouldConfigureLivePhotoAudioInput() -> Bool {
        CameraCaptureDataUsePreferences.usesMicrophoneData()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private static func makeLivePhotoAudioInput() throws -> AVCaptureDeviceInput? {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            return nil
        }
        return try AVCaptureDeviceInput(device: audioDevice)
    }

    private static func hasLivePhotoAudioInput(_ session: AVCaptureSession) -> Bool {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .contains { $0.hasMediaType(.audio) }
    }

    private static func makeVideoRecordingVideoOutput() -> AVCaptureVideoDataOutput {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        return videoOutput
    }

    private static func makeVideoRecordingDepthOutput(filteringEnabled: Bool) -> AVCaptureDepthDataOutput {
        let depthOutput = AVCaptureDepthDataOutput()
        depthOutput.isFilteringEnabled = filteringEnabled
        depthOutput.alwaysDiscardsLateDepthData = true
        return depthOutput
    }

    /// Installs RGB and depth outputs and returns whether optional audio was
    /// added. Each mutation updates the caller's rollback ledger immediately.
    private func installVideoRecordingOutputs(
        videoOutput: AVCaptureVideoDataOutput,
        audioOutput: AVCaptureAudioDataOutput?,
        depthOutput: AVCaptureDepthDataOutput,
        configuration: SessionConfigurationResult,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        addedOutputs: inout [AVCaptureOutput],
        addedAudioInput: inout AVCaptureDeviceInput?,
        didApplyVideoDepthDataFormat: inout Bool
    ) throws -> Bool {
        let usesSharedManualFocusVideoOutput = videoOutput === manualFocusPreviewStream.videoOutput
        if !usesSharedManualFocusVideoOutput {
            guard session.canAddOutput(videoOutput) else {
                throw TAPDepthCaptureError.unableToAddVideoOutput
            }
            session.addOutput(videoOutput)
            addedOutputs.append(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.preferredVideoStabilizationMode = .off
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = isVideoMirrored
            }
            if let videoRotationAngle,
               connection.isVideoRotationAngleSupported(videoRotationAngle) {
                connection.videoRotationAngle = videoRotationAngle
            }
            if usesSharedManualFocusVideoOutput {
                manualFocusPreviewStream.setSharedOutputRotationAngle(connection.videoRotationAngle)
            }
        }

        var actualRecordsAudio = false
        if let audioOutput {
            if !Self.hasLivePhotoAudioInput(session),
               let audioInput = try? Self.makeLivePhotoAudioInput(),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
                addedAudioInput = audioInput
            }
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                addedOutputs.append(audioOutput)
                actualRecordsAudio = true
            }
        }

        guard configuration.depthDeliverySupported,
              !Self.activeFormatRejectsDepthDataOutput(configuration.device.activeFormat),
              session.canAddOutput(depthOutput) else {
            throw TAPDepthCaptureError.unableToAddDepthOutput
        }
        if let depthFormat = Self.videoRecordingDepthFormat(for: configuration) {
            try CameraControlService.applyActiveDepthDataFormat(depthFormat, to: configuration.device)
            didApplyVideoDepthDataFormat = true
        }
        session.addOutput(depthOutput)
        addedOutputs.append(depthOutput)
        guard Self.configureCanonicalVideoDepthConnection(depthOutput) else {
            throw TAPDepthCaptureError.unableToAddDepthOutput
        }
        return actualRecordsAudio
    }

    /// Registration descriptors use an unrotated, unmirrored depth grid and
    /// carry the RGB connection transform separately. Pin the depth connection
    /// instead of relying on device-specific AVFoundation defaults.
    private static func configureCanonicalVideoDepthConnection(
        _ depthOutput: AVCaptureDepthDataOutput
    ) -> Bool {
        guard let connection = depthOutput.connection(with: .depthData) else {
            return false
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        return !connection.isVideoMirrored
            && connection.videoRotationAngle == 0
    }

    private static func restoreManualFocusPreviewConnection(
        _ videoOutput: AVCaptureVideoDataOutput
    ) {
        guard let connection = videoOutput.connection(with: .video) else {
            return
        }
        if connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// The caller supplies only recording-owned outputs, excluding the shared
    /// manual-focus video output whose delegate belongs to its preview stream.
    static func clearVideoRecordingOutputDelegates(_ outputs: [AVCaptureOutput]) {
        for output in outputs {
            (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            (output as? AVCaptureDepthDataOutput)?.setDelegate(nil, callbackQueue: nil)
        }
    }

    static func removeVideoRecordingOutputs(
        _ outputs: [AVCaptureOutput],
        audioInputAddedByRecording: AVCaptureDeviceInput?,
        from session: AVCaptureSession
    ) {
        for output in outputs where session.outputs.contains(output) {
            session.removeOutput(output)
        }
        if let audioInputAddedByRecording,
           session.inputs.contains(audioInputAddedByRecording) {
            session.removeInput(audioInputAddedByRecording)
        }
    }

    private func restoreVideoRecordingConfiguration(
        device: AVCaptureDevice,
        previousActiveDepthDataFormat: AVCaptureDevice.Format?,
        didApplyVideoDepthDataFormat: Bool,
        sharedManualFocusVideoOutput: AVCaptureVideoDataOutput?,
        reason: String
    ) {
        if didApplyVideoDepthDataFormat {
            do {
                try CameraControlService.applyActiveDepthDataFormat(
                    previousActiveDepthDataFormat,
                    to: device
                )
            } catch {
                #if DEBUG
                TAPDiagnostics.cameraCapture.error("video depth format restore failed reason=\(reason, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
            }
        }
        if let sharedManualFocusVideoOutput {
            Self.restoreManualFocusPreviewConnection(sharedManualFocusVideoOutput)
            manualFocusPreviewStream.setSharedOutputRotationAngle(nil)
        }
    }

    private func discardPreparedVideoRecordingGraphLocked(
        session: AVCaptureSession,
        reason: String
    ) {
        guard let graph = preparedVideoRecordingGraph else {
            return
        }
        preparedVideoRecordingGraph = nil
        graph.outputRouter.deactivateRecorder()
        graph.dataOutputSynchronizer.setDelegate(nil, queue: nil)
        Self.clearVideoRecordingOutputDelegates(graph.outputs)

        session.beginConfiguration()
        Self.removeVideoRecordingOutputs(
            graph.outputs,
            audioInputAddedByRecording: graph.audioInputAddedByRecording,
            from: session
        )
        restoreVideoRecordingConfiguration(
            device: graph.device,
            previousActiveDepthDataFormat: graph.previousActiveDepthDataFormat,
            didApplyVideoDepthDataFormat: graph.didApplyVideoDepthDataFormat,
            sharedManualFocusVideoOutput: graph.usesSharedManualFocusVideoOutput ? graph.videoOutput : nil,
            reason: reason
        )
        session.commitConfiguration()
    }

    private static func fallbackVideoSettings(for device: AVCaptureDevice) -> [String: Any] {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
    }

    private static func videoRecordingDepthFormat(
        for configuration: SessionConfigurationResult
    ) -> AVCaptureDevice.Format? {
        guard let requestedDepthFormat = configuration.capturePlan.formatSelection?.depthFormat else {
            return nil
        }
        return configuration.device.activeFormat.supportedDepthDataFormats.first { candidate in
            formatsHaveSameDepthSignature(candidate, requestedDepthFormat)
        }
    }

    private static func formatsHaveSameDepthSignature(
        _ lhs: AVCaptureDevice.Format,
        _ rhs: AVCaptureDevice.Format
    ) -> Bool {
        let lhsDescription = lhs.formatDescription
        let rhsDescription = rhs.formatDescription
        let lhsDimensions = CMVideoFormatDescriptionGetDimensions(lhsDescription)
        let rhsDimensions = CMVideoFormatDescriptionGetDimensions(rhsDescription)
        return CMFormatDescriptionGetMediaSubType(lhsDescription) == CMFormatDescriptionGetMediaSubType(rhsDescription)
            && lhsDimensions.width == rhsDimensions.width
            && lhsDimensions.height == rhsDimensions.height
    }

    private static func activeFormatRejectsDepthDataOutput(_ format: AVCaptureDevice.Format) -> Bool {
        format.unsupportedCaptureOutputClasses.contains { outputClass in
            outputClass == AVCaptureDepthDataOutput.self
        }
    }

    private static func formatsHaveSamePhotoDepthPreviewSignature(
        _ activeFormat: AVCaptureDevice.Format,
        _ requestedFormat: AVCaptureDevice.Format
    ) -> Bool {
        if activeFormat === requestedFormat {
            return true
        }

        /*
         `AVCaptureDevice.activeFormat` can return an equivalent format object
         instead of the exact instance discovered by the capability layer. For
         FOV-only switches, requiring exact object, subtype, or range identity is
         too strict and forces a full input rebuild, which can make virtual
         devices flash their wide baseline before the target zoom is applied.

         The reusable graph check only needs to prove the active format has the
         same visual photo-depth signature. The selected raw zoom and depth-safe
         range were already validated by the capability layer, and the caller
         separately requires `AVCapturePhotoOutput` depth delivery to remain
         enabled and supported.
         */
        let activeDescription = activeFormat.formatDescription
        let requestedDescription = requestedFormat.formatDescription
        let activeDimensions = CMVideoFormatDescriptionGetDimensions(activeDescription)
        let requestedDimensions = CMVideoFormatDescriptionGetDimensions(requestedDescription)

        return activeDimensions.width == requestedDimensions.width
            && activeDimensions.height == requestedDimensions.height
            && abs(Double(activeFormat.videoFieldOfView - requestedFormat.videoFieldOfView)) < 0.01
            && abs(Double(activeFormat.videoMaxZoomFactor - requestedFormat.videoMaxZoomFactor)) < 0.01
    }

    private static func targetActiveFormat(for plan: CaptureSourcePlan) -> AVCaptureDevice.Format {
        plan.formatSelection?.videoFormat ?? plan.resolvedCaptureDevice.activeFormat
    }

    private static func makeConfigurationResult(
        plan: CaptureSourcePlan,
        photoOutput: AVCapturePhotoOutput,
        request: SessionConfigurationRequest,
        resolvedOutput: ResolvedCaptureOutputProfile,
        livePhotoAudioInputConfigured: Bool
    ) -> SessionConfigurationResult {
        let focalLabel = plan.requestedFocalLengthLabel.label
        let nativePreviewAspectRatio = portraitPreviewAspectRatio(for: plan.resolvedCaptureDevice.activeFormat)

        return SessionConfigurationResult(
            depthDeliverySupported: resolvedOutput.depthDataDeliveryEnabled && photoOutput.isDepthDataDeliverySupported,
            cameraDisplayName: "\(focalLabel) · \(plan.depthSource?.displayName ?? "No Depth")",
            nativePreviewAspectRatio: nativePreviewAspectRatio,
            capturePlan: plan,
            outputProfile: request.outputProfile,
            resolvedOutput: resolvedOutput,
            device: plan.resolvedCaptureDevice,
            livePhotoAudioInputConfigured: livePhotoAudioInputConfigured,
            controlCapabilities: CameraControlCapabilitySnapshot.make(device: plan.resolvedCaptureDevice),
            selectionContext: request.selectionContext,
            auxiliaryPreviewPolicy: request.auxiliaryPreviewPolicy
        )
    }

    private static func portraitPreviewAspectRatio(for format: AVCaptureDevice.Format) -> Double {
        /*
         A camera preview should match the active capture format, not a UI guess
         such as "always 4:3" or "always 16:9". AVFoundation reports video
         formats in sensor/video orientation, usually landscape dimensions. The
         SwiftUI viewfinder is portrait, so this converts the active format into
         a width/height ratio with the shorter edge as the portrait width.

         Typical still-photo formats on iPhone resolve to 3:4 in portrait, but a
         16:9 active format will resolve to 9:16. Keeping this value tied to the
         configured format also keeps preview-crop metadata meaningful when the
         selected source changes.
         */
        let presentationSize = CMVideoFormatDescriptionGetPresentationDimensions(
            format.formatDescription,
            usePixelAspectRatio: true,
            useCleanAperture: true
        )
        let width = Double(presentationSize.width)
        let height = Double(presentationSize.height)
        guard width > 0, height > 0 else {
            return 3.0 / 4.0
        }

        return min(width, height) / max(width, height)
    }
}

/// Only the cancellation bit crosses queues; all other fields belong to the
/// controller's session queue and are released by its single completion path.
private nonisolated final class PendingZoomConfiguration: @unchecked Sendable {
    let request: SessionConfigurationRequest
    var continuation: CheckedContinuation<SessionConfigurationResult, Error>?
    var device: AVCaptureDevice?
    var observation: NSKeyValueObservation?
    var presentationTask: Task<Void, Never>?
    private let lock = NSLock()
    private var cancelled = false

    init(request: SessionConfigurationRequest) { self.request = request }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private nonisolated enum ZoomConfigurationError: LocalizedError {
    case timedOut
    case targetNotReached

    var errorDescription: String? {
        "The camera did not finish changing the field of view."
    }
}

private nonisolated final class ManualFocusLockContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CameraManualControlReadbackSnapshot, Error>?

    init(continuation: CheckedContinuation<CameraManualControlReadbackSnapshot, Error>) {
        self.continuation = continuation
    }

    func resume(returning snapshot: CameraManualControlReadbackSnapshot) {
        takeContinuation()?.resume(returning: snapshot)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    func resumeForTimeout(operationToken: CameraManualFocusOperationToken) {
        guard let continuation = takeContinuation() else {
            return
        }
        operationToken.invalidate()
        continuation.resume(throwing: TAPDepthCaptureError.cameraManualFocusLockTimedOut)
    }

    private func takeContinuation() -> CheckedContinuation<CameraManualControlReadbackSnapshot, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

private nonisolated final class ManualFocusAutoFocusSettleContinuationGate: @unchecked Sendable {
    private struct CompletionResources {
        let continuation: CheckedContinuation<Void, Error>
        let observation: NSKeyValueObservation?
        let operationToken: CameraManualFocusOperationToken?
        let invalidationHandlerID: UUID?
    }

    private static let noAdjustmentGrace: TimeInterval = 0.18
    private static let stableSettleWindow: TimeInterval = 0.06

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var settleState = CameraManualFocusAutoFocusSettleState()
    private var observation: NSKeyValueObservation?
    private var operationToken: CameraManualFocusOperationToken?
    private var invalidationHandlerID: UUID?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func bind(to operationToken: CameraManualFocusOperationToken) {
        let handlerID = operationToken.addInvalidationHandler { [weak self] in
            self?.resume(throwing: CancellationError())
        }

        lock.lock()
        let isActive = continuation != nil
        if isActive {
            self.operationToken = operationToken
            invalidationHandlerID = handlerID
        }
        lock.unlock()

        if !isActive {
            operationToken.removeInvalidationHandler(handlerID)
        }
    }

    func attach(observation: NSKeyValueObservation) {
        lock.lock()
        let isActive = continuation != nil
        if isActive {
            self.observation = observation
        }
        lock.unlock()

        if !isActive {
            observation.invalidate()
        }
    }

    func markRequestApplied(isAdjustingFocus: Bool) {
        let stableRevision: Int?
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            return
        }
        stableRevision = settleState.markRequestApplied(isAdjustingFocus: isAdjustingFocus)
        lock.unlock()

        scheduleStableSettleIfNeeded(revision: stableRevision)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + Self.noAdjustmentGrace
        ) { [weak self] in
            self?.resumeAfterNoAdjustmentGrace()
        }
    }

    func observe(isAdjustingFocus: Bool) {
        let stableRevision: Int?
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            return
        }
        stableRevision = settleState.observe(isAdjustingFocus: isAdjustingFocus)
        lock.unlock()

        scheduleStableSettleIfNeeded(revision: stableRevision)
    }

    func resumeForTimeout() {
        resume(throwing: TAPDepthCaptureError.cameraManualFocusAssistTimedOut)
    }

    func resume(throwing error: Error) {
        finish(with: .failure(error))
    }

    private func scheduleStableSettleIfNeeded(revision: Int?) {
        guard let revision else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + Self.stableSettleWindow
        ) { [weak self] in
            self?.resumeAfterStableSettleWindow(revision: revision)
        }
    }

    private func resumeAfterStableSettleWindow(revision: Int) {
        let resources: CompletionResources?
        lock.lock()
        if settleState.canSettle(
            at: revision,
            allowingNoObservedAdjustment: false
        ) {
            resources = takeCompletionResourcesLocked()
        } else {
            resources = nil
        }
        lock.unlock()
        if let resources {
            complete(resources, with: .success(()))
        }
    }

    private func resumeAfterNoAdjustmentGrace() {
        let resources: CompletionResources?
        lock.lock()
        if !settleState.didObserveAdjustment
            && settleState.canSettle(
                at: settleState.revision,
                allowingNoObservedAdjustment: true
            ) {
            resources = takeCompletionResourcesLocked()
        } else {
            resources = nil
        }
        lock.unlock()
        if let resources {
            complete(resources, with: .success(()))
        }
    }

    private func finish(with result: Result<Void, Error>) {
        let resources: CompletionResources?
        lock.lock()
        resources = takeCompletionResourcesLocked()
        lock.unlock()
        if let resources {
            complete(resources, with: result)
        }
    }

    private func takeCompletionResourcesLocked() -> CompletionResources? {
        guard let continuation else {
            return nil
        }
        let resources = CompletionResources(
            continuation: continuation,
            observation: observation,
            operationToken: operationToken,
            invalidationHandlerID: invalidationHandlerID
        )
        self.continuation = nil
        self.observation = nil
        self.operationToken = nil
        self.invalidationHandlerID = nil
        return resources
    }

    private func complete(
        _ resources: CompletionResources,
        with result: Result<Void, Error>
    ) {
        resources.observation?.invalidate()
        resources.operationToken?.removeInvalidationHandler(resources.invalidationHandlerID)
        resources.continuation.resume(with: result)
    }
}

private struct ActiveVideoRecordingGraph {
    let recorder: TAPVideoRecorder
    let preparedGraph: PreparedVideoRecordingGraph
}

private nonisolated struct PreparedVideoRecordingGraph {
    let outputs: [AVCaptureOutput]
    let videoOutput: AVCaptureVideoDataOutput
    let depthOutput: AVCaptureDepthDataOutput
    let audioInputAddedByRecording: AVCaptureDeviceInput?
    let device: AVCaptureDevice
    let recordsAudio: Bool
    let requestedRecordsAudio: Bool
    let videoRotationAngle: CGFloat?
    let isVideoMirrored: Bool
    let depthFilteringEnabled: Bool
    let videoSettings: [String: Any]
    let previousActiveDepthDataFormat: AVCaptureDevice.Format?
    let didApplyVideoDepthDataFormat: Bool
    let dataOutputSynchronizer: AVCaptureDataOutputSynchronizer
    let outputRouter: TAPVideoGraphOutputRouter
    let usesSharedManualFocusVideoOutput: Bool

    func matches(
        configuration: SessionConfigurationResult,
        recordsAudio: Bool,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        depthFilteringEnabled: Bool
    ) -> Bool {
        device.uniqueID == configuration.device.uniqueID
            && requestedRecordsAudio == recordsAudio
            && self.isVideoMirrored == isVideoMirrored
            && self.depthFilteringEnabled == depthFilteringEnabled
            && Self.sameRotation(self.videoRotationAngle, videoRotationAngle)
    }

    private static func sameRotation(_ lhs: CGFloat?, _ rhs: CGFloat?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let lhs), .some(let rhs)):
            return abs(Double(lhs - rhs)) < 0.01
        case (.none, .some), (.some, .none):
            return false
        }
    }
}

private extension CameraManualControlReadbackExposureMode {
    nonisolated init(_ mode: AVCaptureDevice.ExposureMode) {
        switch mode {
        case .continuousAutoExposure, .autoExpose:
            self = .continuousAuto
        case .locked:
            self = .locked
        case .custom:
            self = .custom
        @unknown default:
            self = .unknown
        }
    }
}

private extension CameraManualControlReadbackFocusMode {
    nonisolated init(_ mode: AVCaptureDevice.FocusMode) {
        switch mode {
        case .continuousAutoFocus:
            self = .continuousAuto
        case .autoFocus:
            self = .autoFocus
        case .locked:
            self = .locked
        @unknown default:
            self = .unknown
        }
    }
}
