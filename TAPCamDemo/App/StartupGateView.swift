//
//  StartupGateView.swift
//  TAPCamDemo
//

import SwiftUI

struct StartupGateView: View {
    @AppStorage(StartupGateDefaults.didCompleteFirstInstallPermissionsKey)
    private var didCompleteFirstInstallPermissions = false

    @StateObject private var permissionCoordinator = StartupPermissionCoordinator()

    var body: some View {
        Group {
            if didCompleteFirstInstallPermissions {
                CameraView()
            } else {
                WelcomePermissionsView(coordinator: permissionCoordinator) {
                    completeFirstInstallPermissionsIfReady()
                }
            }
        }
    }

    private func completeFirstInstallPermissionsIfReady() {
        guard permissionCoordinator.hasRequiredPermissions else {
            return
        }
        didCompleteFirstInstallPermissions = true
    }
}
