//
//  TAPCamDemoApp.swift
//  TAPCamDemo
//
//  Created by Harold on 2026/4/24.
//

import LockedCameraCapture
import OSLog
import SwiftUI
import UIKit

/// Locks the SwiftUI scene in portrait so the camera screen behaves like a
/// camera chrome instead of a normal rotating app page.
///
/// Device rotation is still observed by `CameraChromeOrientationController`.
/// That lets individual controls rotate in place while the preview, shutter
/// rail, and overlay anchors keep their portrait layout positions.
final class TAPCamAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct TAPCamDemoApp: App {
    #if DEBUG
    @UIApplicationDelegateAdaptor(TAPCamAppDelegate.self) private var appDelegate
    @StateObject private var lockedCaptureImportRuntime = LockedCaptureSessionContentImportRuntime()
    #endif

    var body: some Scene {
        #if DEBUG
        WindowGroup {
            #if DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS
            if ProcessInfo.processInfo.isCameraControlsUITestHarness {
                CameraControlsUITestHarnessView()
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.isXCTestHost {
                XCTestHostView()
            } else {
                startupView
            }
            #else
            if ProcessInfo.processInfo.isXCTestHost {
                XCTestHostView()
            } else {
                startupView
            }
            #endif
        }
        #else
        WindowGroup {
            LockedCameraR4EMinimalAppHost()
                .preferredColorScheme(.dark)
        }
        #endif
    }

    #if DEBUG
    private var startupView: some View {
        StartupGateView()
            .preferredColorScheme(.dark)
            .onAppear {
                lockedCaptureImportRuntime.start()
            }
    }
    #endif
}

#if !DEBUG
private struct LockedCameraR4EMinimalAppHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var activityCount = 0

    private static let logger = Logger(
        subsystem: "TAP-NAP.TAPCamDemo",
        category: "LockedCameraR4E"
    )

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("TAPCam")
                    .font(.headline)
                Text("R4E MINIMAL APP")
                    .font(.caption.monospaced())
                Text("ACTIVITY \(activityCount)")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("locked-camera-r4e-minimal-app")
        .onAppear {
            logHostAppear()
        }
        .onContinueUserActivity(NSUserActivityTypeLockedCameraCapture) { activity in
            activityCount += 1
            Self.logger.notice(
                "r4e_minimal_app_activity_received count=\(activityCount, privacy: .public) activityType=\(activity.activityType, privacy: .public) \(sceneSnapshot(), privacy: .public)"
            )
        }
        .onChange(of: scenePhase) { _, phase in
            Self.logger.notice(
                "r4e_minimal_app_scene_phase phase=\(Self.label(for: phase), privacy: .public) \(sceneSnapshot(), privacy: .public)"
            )
        }
    }

    private func logHostAppear() {
        Self.logger.notice(
            "r4e_minimal_app_host_appear phase=\(Self.label(for: scenePhase), privacy: .public) cameraViewCreated=false libraryViewCreated=false photoKitRequested=false managerStreamStarted=false pendingWorkerStarted=false \(sceneSnapshot(), privacy: .public)"
        )
    }

    private func sceneSnapshot() -> String {
        let identifiers = UIApplication.shared.connectedScenes
            .compactMap { $0.session.persistentIdentifier }
            .sorted()
            .joined(separator: "|")
        return "sceneCount=\(UIApplication.shared.connectedScenes.count) sceneIDs=\(identifiers)"
    }

    private static func label(for phase: ScenePhase) -> String {
        switch phase {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
    }
}
#endif

private struct XCTestHostView: View {
    var body: some View {
        Color.black
    }
}

private extension ProcessInfo {
    #if DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS
    var isCameraControlsUITestHarness: Bool {
        environment["TAPCAM_UI_TEST_CAMERA_CONTROLS"] == "1"
            || arguments.contains("--tapcam-camera-controls-ui-test-harness")
    }
    #endif

    var isXCTestHost: Bool {
        guard environment["TAPCAM_UI_TEST_REAL_APP"] != "1" else {
            return false
        }

        return environment["TAPCAM_XCTEST_HOST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}
