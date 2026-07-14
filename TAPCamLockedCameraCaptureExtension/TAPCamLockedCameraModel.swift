//
//  TAPCamLockedCameraModel.swift
//  TAPCamDemo
//

import Foundation
import Observation
import OSLog

enum TAPCamLockedCameraPhase: Equatable, Sendable {
    case starting
    case live
    case interrupted(reason: String?)
    case unavailable(reason: String)

    var shortLabel: String {
        switch self {
        case .starting:
            "STARTING"
        case .live:
            "LIVE"
        case .interrupted:
            "PAUSED"
        case .unavailable:
            "UNAVAILABLE"
        }
    }

    var title: String {
        switch self {
        case .starting:
            "Starting Camera"
        case .live:
            "Camera Live"
        case .interrupted:
            "Camera Paused"
        case .unavailable:
            "Unlock to Continue"
        }
    }

    var detail: String? {
        switch self {
        case .starting, .live:
            nil
        case let .interrupted(reason):
            reason ?? "Another system activity interrupted the camera."
        case let .unavailable(reason):
            reason
        }
    }

    var systemImage: String {
        switch self {
        case .starting, .live:
            "camera.viewfinder"
        case .interrupted:
            "pause.fill"
        case .unavailable:
            "lock.open.fill"
        }
    }
}

enum TAPCamLockedPhotoCaptureState: Equatable, Sendable {
    case ready
    case capturing
    case saved(sequence: Int, result: TAPCamLockedPhotoCaptureResult)
    case failed(reason: String)

    var shortLabel: String {
        switch self {
        case .ready:
            "DEPTH READY"
        case .capturing:
            "CAPTURING"
        case let .saved(sequence, result):
            "SAVED \(result.depthWidth)x\(result.depthHeight)  #\(sequence)"
        case .failed:
            "CAPTURE FAILED"
        }
    }

    var isCapturing: Bool {
        if case .capturing = self {
            true
        } else {
            false
        }
    }
}

enum TAPCamLockedCaptureTrigger: String, Sendable {
    case shutterButton = "shutter"
    case hardwareEvent = "hardware"
}

@MainActor
@Observable
final class TAPCamLockedCameraModel {
    private(set) var phase = TAPCamLockedCameraPhase.starting
    private(set) var photoCaptureState = TAPCamLockedPhotoCaptureState.ready
    private(set) var shouldFlashCaptureFeedback = false

    var isPhotoCaptureEnabled: Bool {
        phase == .live && !photoCaptureState.isCapturing
    }

    let previewSource: any TAPCamLockedCameraPreviewSource

    private let captureService: TAPCamLockedCaptureService
    private var eventTask: Task<Void, Never>?
    private var captureFeedbackTask: Task<Void, Never>?
    private var successfulPhotoCount = 0

    init(captureService: TAPCamLockedCaptureService = TAPCamLockedCaptureService()) {
        self.captureService = captureService
        previewSource = captureService.previewSource
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1")
            .info("r1_camera_model_init")
    }

    func start() async {
        switch phase {
        case .live, .interrupted:
            break
        case .starting, .unavailable:
            phase = .starting
        }

        observeCaptureService()

        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1")
            .info("r1_camera_model_start_begin phase=\(self.phase.shortLabel, privacy: .public)")

        do {
            let device = try await captureService.start()
            if phase == .starting {
                phase = .live
            }
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1")
                .info(
                    "r1_camera_model_start_finish device=\(device, privacy: .public) phase=\(self.phase.shortLabel, privacy: .public)"
                )
        } catch {
            phase = .unavailable(reason: error.localizedDescription)
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1")
                .error("r1_camera_model_start_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func captureDepthPhoto(
        trigger: TAPCamLockedCaptureTrigger,
        sessionContentURL: URL
    ) async {
        guard isPhotoCaptureEnabled else {
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR2BPhoto")
                .info(
                    "r2b_photo_capture_ignored trigger=\(trigger.rawValue, privacy: .public) cameraPhase=\(self.phase.shortLabel, privacy: .public) captureState=\(self.photoCaptureState.shortLabel, privacy: .public)"
                )
            return
        }

        photoCaptureState = .capturing
        flashCaptureFeedback()
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR2BPhoto")
            .notice("r2b_photo_trigger trigger=\(trigger.rawValue, privacy: .public)")

        do {
            let result = try await captureService.captureDepthPhoto(
                sessionContentURL: sessionContentURL
            )
            successfulPhotoCount += 1
            photoCaptureState = .saved(sequence: successfulPhotoCount, result: result)
        } catch {
            photoCaptureState = .failed(reason: error.localizedDescription)
        }
    }

    private func flashCaptureFeedback() {
        captureFeedbackTask?.cancel()
        shouldFlashCaptureFeedback = true
        captureFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            self?.shouldFlashCaptureFeedback = false
        }
    }

    private func observeCaptureService() {
        guard eventTask == nil else { return }

        let events = captureService.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                apply(event)
            }
        }
    }

    private func apply(_ event: TAPCamLockedCaptureService.Event) {
        switch event {
        case let .interrupted(reason):
            phase = .interrupted(reason: reason)
        case .resumed:
            phase = .live
        case let .unavailable(reason):
            phase = .unavailable(reason: reason)
        }
    }

    deinit {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1")
            .info("r1_camera_model_deinit")
    }
}
