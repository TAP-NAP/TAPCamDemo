//
//  StartupGateView.swift
//  TAPCamDemo
//

import LockedCameraCapture
import SwiftUI

struct StartupGateView: View {
    @AppStorage(StartupGateDefaults.didCompleteFirstInstallSetupKey)
    private var didCompleteFirstInstallSetup = false

    @StateObject private var startupCoordinator = StartupGateCoordinator()
    @State private var isPreparingFirstInstallCameraReadiness = false

    var body: some View {
        Group {
            if isPreparingFirstInstallCameraReadiness {
                CameraView(initialReadinessGate: .firstInstall {
                    completeFirstInstallSetupAfterCameraReadiness()
                })
            } else if didCompleteFirstInstallSetup {
                CameraView()
            } else {
                WelcomeStartupSetupView(coordinator: startupCoordinator) {
                    beginFirstInstallCameraReadinessIfReady()
                }
            }
        }
        .onContinueUserActivity(NSUserActivityTypeLockedCameraCapture) { activity in
            LockedCameraOpenActivityRouter.handle(activity)
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
