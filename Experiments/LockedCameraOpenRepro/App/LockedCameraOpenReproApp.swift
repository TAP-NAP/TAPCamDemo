import AVFoundation
import LockedCameraCapture
import OSLog
import SwiftUI

@main
struct LockedCameraOpenReproApp: App {
    init() {
        LockedCameraReproDiagnostics.logger(category: "App")
            .notice("lccr5_app_init pid=\(LockedCameraReproDiagnostics.processID)")
    }

    var body: some Scene {
        WindowGroup {
            LockedCameraReproAppHost()
        }
    }
}

private struct LockedCameraReproAppHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var activityCount = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("TAPCam LCC Repro")
                .font(.title2.weight(.semibold))

            LabeledContent("Camera", value: authorizationLabel)
            LabeledContent("Locked handoffs", value: "\(activityCount)")

            if authorization != .authorized {
                Button("Request Camera Access") {
                    Task {
                        await requestCameraAccessIfNeeded()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .task {
            LockedCameraReproDiagnostics.logger(category: "App")
                .notice("lccr5_app_host_appear pid=\(LockedCameraReproDiagnostics.processID) phase=\(String(describing: scenePhase), privacy: .public)")
            await requestCameraAccessIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            LockedCameraReproDiagnostics.logger(category: "App")
                .notice("lccr5_app_scene_phase pid=\(LockedCameraReproDiagnostics.processID) phase=\(String(describing: newValue), privacy: .public)")
        }
        .onContinueUserActivity(NSUserActivityTypeLockedCameraCapture) { activity in
            activityCount += 1
            LockedCameraReproDiagnostics.logger(category: "App")
                .notice("lccr5_app_activity_received pid=\(LockedCameraReproDiagnostics.processID) count=\(activityCount) type=\(activity.activityType, privacy: .public) userInfoCount=\(activity.userInfo?.count ?? 0)")
        }
    }

    private var authorizationLabel: String {
        switch authorization {
        case .authorized:
            "Authorized"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .notDetermined:
            "Not Determined"
        @unknown default:
            "Unknown"
        }
    }

    @MainActor
    private func requestCameraAccessIfNeeded() async {
        let before = AVCaptureDevice.authorizationStatus(for: .video)
        LockedCameraReproDiagnostics.logger(category: "App")
            .notice("lccr5_camera_authorization_begin pid=\(LockedCameraReproDiagnostics.processID) status=\(before.rawValue)")

        if before == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }

        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        LockedCameraReproDiagnostics.logger(category: "App")
            .notice("lccr5_camera_authorization_finish pid=\(LockedCameraReproDiagnostics.processID) status=\(authorization.rawValue)")
    }
}
