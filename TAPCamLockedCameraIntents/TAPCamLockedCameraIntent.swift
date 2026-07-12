//
//  TAPCamLockedCameraIntent.swift
//  TAPCamDemo
//

import AppIntents
import OSLog

nonisolated enum TAPCamLockedCameraDiagnostics {
    static let subsystem = "TAP-NAP.TAPCamDemo"

    static func logger(category: String = "LockedCameraR0") -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

nonisolated struct TAPCamLockedCameraIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "TAPCam R0 Camera"
    static let description = IntentDescription(
        "Open the minimal TAPCam camera experience from the Lock Screen."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraIntent")
            .info("r0_camera_capture_intent_perform")
        return .result()
    }
}
