//
//  StartupGateView.swift
//  TAPCamDemo
//

import LockedCameraCapture
import OSLog
import SwiftUI

struct StartupGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(StartupGateDefaults.didCompleteFirstInstallSetupKey)
    private var didCompleteFirstInstallSetup = false

    @StateObject private var startupCoordinator = StartupGateCoordinator()
    @StateObject private var routeStore = CameraRouteStore()
    @State private var isPreparingFirstInstallCameraReadiness = false
    @State private var isLockedCameraInertLanding = false

    var body: some View {
        Group {
            if isLockedCameraInertLanding {
                LockedCameraOpenDiagnosticLandingView()
            } else if isPreparingFirstInstallCameraReadiness {
                CameraView(routeStore: routeStore, initialReadinessGate: .firstInstall {
                    completeFirstInstallSetupAfterCameraReadiness()
                })
                .onAppear(perform: logCameraHostAppear)
                .onDisappear(perform: logCameraHostDisappear)
            } else if didCompleteFirstInstallSetup {
                CameraView(routeStore: routeStore)
                    .onAppear(perform: logCameraHostAppear)
                    .onDisappear(perform: logCameraHostDisappear)
            } else {
                WelcomeStartupSetupView(coordinator: startupCoordinator) {
                    beginFirstInstallCameraReadinessIfReady()
                }
            }
        }
        .onContinueUserActivity(NSUserActivityTypeLockedCameraCapture) { activity in
            handleLockedCameraActivity(activity)
        }
        .onChange(of: scenePhase) { _, phase in
            LockedCameraDiagnostics.logger.notice(
                "r4c_app_scene_phase phase=\(Self.label(for: phase), privacy: .public) inertLanding=\(isLockedCameraInertLanding)"
            )
        }
    }

    private func handleLockedCameraActivity(_ activity: NSUserActivity) {
        guard LockedCameraOpenActivityRouter.handle(activity) else { return }

        isLockedCameraInertLanding = true
        LockedCameraDiagnostics.logger.notice(
            "r4c_app_inert_landing_route phase=\(Self.label(for: scenePhase), privacy: .public) cameraHostRequested=false libraryRequested=false"
        )
    }

    private func logCameraHostAppear() {
        LockedCameraDiagnostics.logger.notice(
            "r4c_app_camera_host_appear phase=\(Self.label(for: scenePhase), privacy: .public)"
        )
    }

    private func logCameraHostDisappear() {
        LockedCameraDiagnostics.logger.notice(
            "r4c_app_camera_host_disappear phase=\(Self.label(for: scenePhase), privacy: .public) inertLanding=\(isLockedCameraInertLanding)"
        )
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

    private func beginFirstInstallCameraReadinessIfReady() {
        guard StartupGatePolicy.firstInstallContinueAction(
            for: startupCoordinator.statusSnapshot
        ) == .enterCameraReadiness else {
            return
        }
        isPreparingFirstInstallCameraReadiness = true
    }

    private func completeFirstInstallSetupAfterCameraReadiness() {
        didCompleteFirstInstallSetup = true
    }
}

private struct LockedCameraOpenDiagnosticLandingView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 38, weight: .regular))

                Text("TAPCam")
                    .font(.headline)
            }
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("locked-camera-r4c-inert-app-landing")
        .onAppear {
            LockedCameraDiagnostics.logger.notice(
                "r4c_app_inert_host_appear cameraViewCreated=false libraryViewCreated=false photoKitRequested=false"
            )
        }
        .onDisappear {
            LockedCameraDiagnostics.logger.notice("r4c_app_inert_host_disappear")
        }
    }
}
