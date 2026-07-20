import ExtensionKit
import LockedCameraCapture
import OSLog
import SwiftUI

@main
struct LockedCameraOpenReproCaptureExtension: LockedCameraCaptureExtension {
    init() {
        LockedCameraReproDiagnostics.logger(category: "Capture")
            .notice("lccr5_capture_extension_init pid=\(LockedCameraReproDiagnostics.processID)")
    }

    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCameraReproRoot(session: session)
        }
    }
}

private struct LockedCameraReproRoot: View {
    let session: LockedCameraCaptureSession

    @State private var openState = OpenState.idle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LockedCameraReproViewFinder(session: session)
                .ignoresSafeArea()

            Button(action: requestOpen) {
                VStack(spacing: 5) {
                    Image(systemName: openState.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .background(.black.opacity(0.5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white, lineWidth: 1.5)
                        }

                    Text(openState.label)
                        .font(.caption2.bold())
                }
                .foregroundStyle(openState == .failed ? Color.red : Color.white)
            }
            .buttonStyle(.plain)
            .disabled(openState == .requesting)
            .padding(.leading, 24)
            .padding(.bottom, 132)
            .accessibilityIdentifier("lccr5-open")
        }
        .background(Color.black)
        .onAppear {
            LockedCameraReproDiagnostics.logger(category: "Capture")
                .notice("lccr5_capture_root_appear pid=\(LockedCameraReproDiagnostics.processID)")
        }
        .onDisappear {
            LockedCameraReproDiagnostics.logger(category: "Capture")
                .notice("lccr5_capture_root_disappear pid=\(LockedCameraReproDiagnostics.processID)")
        }
    }

    private func requestOpen() {
        guard openState != .requesting else {
            return
        }

        openState = .requesting
        let requestID = UUID().uuidString
        LockedCameraReproDiagnostics.logger(category: "Capture")
            .notice("lccr5_open_tap pid=\(LockedCameraReproDiagnostics.processID) requestID=\(requestID, privacy: .public)")

        Task { @MainActor in
            let activity = NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)
            LockedCameraReproDiagnostics.logger(category: "Capture")
                .notice("lccr5_open_begin pid=\(LockedCameraReproDiagnostics.processID) requestID=\(requestID, privacy: .public) userInfoCount=0")
            do {
                try await session.openApplication(for: activity)
                openState = .accepted
                LockedCameraReproDiagnostics.logger(category: "Capture")
                    .notice("lccr5_open_accepted pid=\(LockedCameraReproDiagnostics.processID) requestID=\(requestID, privacy: .public)")
            } catch {
                openState = .failed
                let nsError = error as NSError
                LockedCameraReproDiagnostics.logger(category: "Capture")
                    .error("lccr5_open_failed pid=\(LockedCameraReproDiagnostics.processID) requestID=\(requestID, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            }
        }
    }
}

private extension LockedCameraReproRoot {
    enum OpenState {
        case idle
        case requesting
        case accepted
        case failed

        var label: String {
            switch self {
            case .idle: "OPEN"
            case .requesting: "OPENING"
            case .accepted: "OPENED"
            case .failed: "RETRY"
            }
        }

        var symbolName: String {
            switch self {
            case .requesting: "ellipsis"
            case .failed: "exclamationmark.triangle"
            case .idle, .accepted: "arrow.up.forward.app"
            }
        }
    }
}
