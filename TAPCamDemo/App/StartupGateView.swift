//
//  StartupGateView.swift
//  TAPCamDemo
//

import SwiftUI

struct StartupGateView: View {
    @AppStorage(StartupGateDefaults.didCompleteFirstInstallSetupKey)
    private var didCompleteFirstInstallSetup = false

    @StateObject private var startupCoordinator = StartupGateCoordinator()

    var body: some View {
        Group {
            if didCompleteFirstInstallSetup {
                CameraView()
            } else {
                WelcomeStartupSetupView(coordinator: startupCoordinator) {
                    completeFirstInstallSetupIfReady()
                }
            }
        }
    }

    private func completeFirstInstallSetupIfReady() {
        guard startupCoordinator.hasCompletedRequiredStartupChecks else {
            return
        }
        didCompleteFirstInstallSetup = true
    }
}
