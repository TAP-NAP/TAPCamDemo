//
//  TAPCamLockedCaptureService.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import OSLog

nonisolated enum TAPCamLockedCaptureServiceError: LocalizedError, Sendable {
    case cameraAccessDenied
    case noDepthCapableCamera
    case cannotCreateInput(String)
    case cannotAddInput(String)
    case cannotAddPhotoOutput
    case depthPhotoDeliveryUnavailable
    case sessionDidNotStart
    case photoCaptureUnavailable
    case photoCaptureAlreadyInProgress
    case missingPhotoData
    case missingDepthData
    case photoCaptureFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied:
            "Camera access is unavailable. Open TAPCam after unlocking to review camera permission."
        case .noDepthCapableCamera:
            "No supported depth-capable rear camera is available."
        case let .cannotCreateInput(reason):
            "The camera input could not be created: \(reason)"
        case let .cannotAddInput(device):
            "The camera session could not use \(device)."
        case .cannotAddPhotoOutput:
            "The camera session could not add a photo output."
        case .depthPhotoDeliveryUnavailable:
            "The selected camera cannot deliver depth photos in its current configuration."
        case .sessionDidNotStart:
            "The camera session did not start."
        case .photoCaptureUnavailable:
            "The camera is not ready to capture a photo."
        case .photoCaptureAlreadyInProgress:
            "A photo capture is already in progress."
        case .missingPhotoData:
            "The capture completed without photo data."
        case .missingDepthData:
            "The capture completed without depth data."
        case let .photoCaptureFailed(reason):
            "Photo capture failed: \(reason)"
        }
    }
}

actor TAPCamLockedCaptureService {
    nonisolated enum Event: Sendable {
        case interrupted(reason: String?)
        case resumed
        case unavailable(reason: String)
    }

    nonisolated let previewSource: any TAPCamLockedCameraPreviewSource
    nonisolated let events: AsyncStream<Event>

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchSerialQueue(
        label: "TAP-NAP.TAPCamDemo.LockedCameraR1.session"
    )
    private let eventContinuation: AsyncStream<Event>.Continuation

    private var activeVideoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var notificationTasks: [Task<Void, Never>] = []
    private var inFlightPhotoDelegates: [Int64: TAPCamLockedPhotoCaptureDelegate] = [:]

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }

    init() {
        previewSource = TAPCamLockedCameraDefaultPreviewSource(session: captureSession)
        let stream = AsyncStream.makeStream(of: Event.self)
        events = stream.stream
        eventContinuation = stream.continuation
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info("r1_capture_service_init")
    }

    func start() async throws -> String {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info("r1_session_start_begin configured=\(self.isConfigured) running=\(self.captureSession.isRunning)")

        guard await isAuthorized else {
            throw TAPCamLockedCaptureServiceError.cameraAccessDenied
        }

        let device = try configureIfNeeded()
        guard !captureSession.isRunning else {
            return device.localizedName
        }

        captureSession.startRunning()
        guard captureSession.isRunning else {
            throw TAPCamLockedCaptureServiceError.sessionDidNotStart
        }

        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info("r1_session_start_finish running=true device=\(device.localizedName, privacy: .public)")
        return device.localizedName
    }

    func captureDepthPhoto() async throws -> TAPCamLockedPhotoCaptureResult {
        guard captureSession.isRunning,
              isConfigured,
              photoOutput.isDepthDataDeliveryEnabled else {
            throw TAPCamLockedCaptureServiceError.photoCaptureUnavailable
        }
        guard inFlightPhotoDelegates.isEmpty else {
            throw TAPCamLockedCaptureServiceError.photoCaptureAlreadyInProgress
        }

        let settings = makeDepthPhotoSettings()
        let uniqueID = settings.uniqueID
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR2APhoto")
            .notice(
                "r2a_photo_capture_requested id=\(uniqueID) running=\(self.captureSession.isRunning) depthEnabled=\(self.photoOutput.isDepthDataDeliveryEnabled)"
            )

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = TAPCamLockedPhotoCaptureDelegate { [weak self] result in
                guard let self else {
                    continuation.resume(throwing: TAPCamLockedCaptureServiceError.photoCaptureUnavailable)
                    return
                }
                Task {
                    await self.finishPhotoCapture(
                        uniqueID: uniqueID,
                        result: result,
                        continuation: continuation
                    )
                }
            }
            inFlightPhotoDelegates[uniqueID] = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined {
                return await AVCaptureDevice.requestAccess(for: .video)
            }
            return status == .authorized
        }
    }

    private func configureIfNeeded() throws -> AVCaptureDevice {
        if isConfigured, let device = activeVideoInput?.device {
            return device
        }

        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info("r1_session_configure_begin")

        let device = try depthCapableRearCamera()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw TAPCamLockedCaptureServiceError.cannotCreateInput(error.localizedDescription)
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .photo
        guard captureSession.canAddInput(input) else {
            throw TAPCamLockedCaptureServiceError.cannotAddInput(device.localizedName)
        }

        captureSession.addInput(input)
        guard captureSession.canAddOutput(photoOutput) else {
            captureSession.removeInput(input)
            throw TAPCamLockedCaptureServiceError.cannotAddPhotoOutput
        }

        captureSession.addOutput(photoOutput)
        guard photoOutput.isDepthDataDeliverySupported else {
            captureSession.removeOutput(photoOutput)
            captureSession.removeInput(input)
            throw TAPCamLockedCaptureServiceError.depthPhotoDeliveryUnavailable
        }

        photoOutput.isDepthDataDeliveryEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .quality
        activeVideoInput = input
        isConfigured = true
        observeNotifications()

        let depthFormatCount = device.formats.filter {
            !$0.supportedDepthDataFormats.isEmpty
        }.count
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info(
                "r1_session_configure_finish device=\(device.localizedName, privacy: .public) type=\(device.deviceType.rawValue, privacy: .public) depthFormatCount=\(depthFormatCount)"
            )
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR2APhoto")
            .notice(
                "r2a_photo_output_configured depthSupported=\(self.photoOutput.isDepthDataDeliverySupported) depthEnabled=\(self.photoOutput.isDepthDataDeliveryEnabled)"
            )
        return device
    }

    private func makeDepthPhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [
                AVVideoCodecKey: AVVideoCodecType.hevc
            ])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.isDepthDataDeliveryEnabled = true
        settings.embedsDepthDataInPhoto = true
        settings.isDepthDataFiltered = true
        settings.photoQualityPrioritization = .quality
        return settings
    }

    private func finishPhotoCapture(
        uniqueID: Int64,
        result: Result<TAPCamLockedPhotoCaptureResult, TAPCamLockedCaptureServiceError>,
        continuation: CheckedContinuation<TAPCamLockedPhotoCaptureResult, Error>
    ) {
        inFlightPhotoDelegates[uniqueID] = nil

        switch result {
        case let .success(capture):
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR2APhoto")
                .notice(
                    "r2a_photo_capture_succeeded id=\(uniqueID) bytes=\(capture.photoByteCount) photo=\(capture.photoWidth)x\(capture.photoHeight) depth=\(capture.depthWidth)x\(capture.depthHeight) depthFormat=\(capture.depthPixelFormat) filtered=\(capture.isDepthDataFiltered)"
                )
            continuation.resume(returning: capture)
        case let .failure(error):
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR2APhoto")
                .error(
                    "r2a_photo_capture_failed id=\(uniqueID) error=\(error.localizedDescription, privacy: .public)"
                )
            continuation.resume(throwing: error)
        }
    }

    private func depthCapableRearCamera() throws -> AVCaptureDevice {
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: .back
        ).devices

        for deviceType in preferredTypes {
            if let device = devices.first(where: {
                $0.deviceType == deviceType
                    && $0.formats.contains(where: { !$0.supportedDepthDataFormats.isEmpty })
            }) {
                return device
            }
        }

        throw TAPCamLockedCaptureServiceError.noDepthCapableCamera
    }

    private func observeNotifications() {
        guard notificationTasks.isEmpty else { return }

        let session = captureSession
        notificationTasks = [
            Task { [weak self] in
                for await notification in NotificationCenter.default.notifications(
                    named: AVCaptureSession.wasInterruptedNotification,
                    object: session
                ) {
                    guard !Task.isCancelled, let self else { return }
                    await self.handleInterruption(notification)
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: AVCaptureSession.interruptionEndedNotification,
                    object: session
                ) {
                    guard !Task.isCancelled, let self else { return }
                    await self.handleInterruptionEnded()
                }
            },
            Task { [weak self] in
                for await notification in NotificationCenter.default.notifications(
                    named: AVCaptureSession.runtimeErrorNotification,
                    object: session
                ) {
                    guard !Task.isCancelled, let self else { return }
                    await self.handleRuntimeError(notification)
                }
            }
        ]
    }

    private func handleInterruption(_ notification: Notification) {
        let reasonRawValue = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        let reason = reasonRawValue.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        let reasonDescription = reason.map { "AVCaptureSession interruption \($0.rawValue)" }

        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .error(
                "r1_session_interrupted reason=\(reasonRawValue ?? -1) running=\(self.captureSession.isRunning)"
            )
        eventContinuation.yield(.interrupted(reason: reasonDescription))
    }

    private func handleInterruptionEnded() {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info("r1_session_interruption_ended running=\(self.captureSession.isRunning)")

        if !captureSession.isRunning {
            captureSession.startRunning()
        }

        if captureSession.isRunning {
            eventContinuation.yield(.resumed)
        } else {
            eventContinuation.yield(
                .unavailable(reason: TAPCamLockedCaptureServiceError.sessionDidNotStart.localizedDescription)
            )
        }
    }

    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        let code = error?.code.rawValue ?? -1
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .error(
                "r1_session_runtime_error code=\(code) running=\(self.captureSession.isRunning) description=\(error?.localizedDescription ?? "unknown", privacy: .public)"
            )

        if error?.code == .mediaServicesWereReset {
            if !captureSession.isRunning {
                captureSession.startRunning()
            }

            if captureSession.isRunning {
                eventContinuation.yield(.resumed)
                return
            }
        }

        eventContinuation.yield(
            .unavailable(reason: error?.localizedDescription ?? "The camera encountered an unknown runtime error.")
        )
    }

    deinit {
        notificationTasks.forEach { $0.cancel() }
        eventContinuation.finish()
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Session")
            .info("r1_capture_service_deinit")
    }
}
