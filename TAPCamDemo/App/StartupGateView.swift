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
    @State private var isLockedCameraLibraryLanding = false

    var body: some View {
        Group {
            if isLockedCameraLibraryLanding, routeStore.isDepthAlbumPresented {
                LockedCameraLibraryLandingView(routeStore: routeStore)
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
        .onChange(of: routeStore.isDepthAlbumPresented) { _, isPresented in
            guard !isPresented, isLockedCameraLibraryLanding else { return }
            isLockedCameraLibraryLanding = false
            LockedCameraDiagnostics.logger.notice("r4b_app_library_landing_finished")
        }
        .onChange(of: scenePhase) { _, phase in
            LockedCameraDiagnostics.logger.notice(
                "r4b_app_scene_phase phase=\(Self.label(for: phase), privacy: .public) directLibrary=\(isLockedCameraLibraryLanding)"
            )
        }
    }

    private func handleLockedCameraActivity(_ activity: NSUserActivity) {
        guard LockedCameraOpenActivityRouter.handle(activity) else { return }

        isLockedCameraLibraryLanding = true
        routeStore.presentDepthAlbum()
        LockedCameraDiagnostics.logger.notice(
            "r4b_app_direct_library_route phase=\(Self.label(for: scenePhase), privacy: .public) cameraHostRequested=false"
        )
    }

    private func logCameraHostAppear() {
        LockedCameraDiagnostics.logger.notice(
            "r4b_app_camera_host_appear phase=\(Self.label(for: scenePhase), privacy: .public)"
        )
    }

    private func logCameraHostDisappear() {
        LockedCameraDiagnostics.logger.notice(
            "r4b_app_camera_host_disappear phase=\(Self.label(for: scenePhase), privacy: .public) directLibrary=\(isLockedCameraLibraryLanding)"
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

private struct LockedCameraLibraryLandingView: View {
    @ObservedObject var routeStore: CameraRouteStore

    var body: some View {
        NavigationStack {
            DepthAlbumPickerView(routeStore: routeStore)
                .toolbar(.visible, for: .navigationBar)
        }
        .onAppear {
            LockedCameraDiagnostics.logger.notice(
                "r4b_app_library_host_appear cameraViewCreated=false"
            )
        }
        .onDisappear {
            LockedCameraDiagnostics.logger.notice("r4b_app_library_host_disappear")
        }
    }
}
