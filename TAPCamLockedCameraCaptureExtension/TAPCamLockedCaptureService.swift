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
    case sessionDidNotStart

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
        case .sessionDidNotStart:
            "The camera session did not start."
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
    private let sessionQueue = DispatchSerialQueue(
        label: "TAP-NAP.TAPCamDemo.LockedCameraR1.session"
    )
    private let eventContinuation: AsyncStream<Event>.Continuation

    private var activeVideoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var notificationTasks: [Task<Void, Never>] = []

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
        return device
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
