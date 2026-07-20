import AppIntents
import Foundation
import OSLog

nonisolated enum LockedCameraReproDiagnostics {
    static let subsystem = "TAP-NAP.TAPCam.LockedCameraOpenRepro"

    static var processID: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

nonisolated struct LockedCameraReproIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "LCC Repro Camera"
    static let description = IntentDescription(
        "Open the isolated locked-camera lifecycle reproduction."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        LockedCameraReproDiagnostics.logger(category: "Intent")
            .notice("lccr5_intent_perform pid=\(LockedCameraReproDiagnostics.processID)")
        return .result()
    }
}
