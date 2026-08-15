//
//  RequiredPermissionCheckView.swift
//  TAPCamDemo
//

import SwiftUI

/// App-owned recovery surface for the two permissions that can block camera
/// entry after Setup. It has no Continue action: the root reducer observes the
/// refreshed snapshot and routes automatically.
struct RequiredPermissionCheckView: View {
    @ObservedObject var coordinator: StartupGateCoordinator
    let onRequestPhotoLibraryAccess: () async -> Void
    let onOpenSettings: (StartupGateRequirementKind) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(spacing: 10) {
                        StartupRequirementRow(
                            iconName: "camera",
                            title: "Camera Access",
                            message: "Camera access is required for capture and the viewfinder.",
                            status: coordinator.cameraStatus,
                            actionTitle: "Allow",
                            deniedMessage: "Camera access was denied. You can change it in Settings.",
                            restrictedMessage: "Camera access is restricted by system policy.",
                            recoveryActionTitle: "Open Settings"
                        ) {
                            Task { await coordinator.requestCameraAccess() }
                        } recoveryAction: {
                            onOpenSettings(.camera)
                        }

                        StartupRequirementRow(
                            iconName: "photo.on.rectangle",
                            title: "Photo Library Access",
                            message: "Authorized or Limited Access is required to save and browse.",
                            status: coordinator.photoLibraryStatus,
                            actionTitle: "Allow",
                            deniedMessage: "Photo Library access was denied. You can change it in Settings.",
                            restrictedMessage: "Photo Library access is restricted by system policy.",
                            recoveryActionTitle: "Open Settings"
                        ) {
                            Task { await onRequestPhotoLibraryAccess() }
                        } recoveryAction: {
                            onOpenSettings(.photoLibrary)
                        }
                    }

                    Text("Network, Location, and Microphone do not participate in this check.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)
                .padding(.bottom, 34)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text("Required Permission Check")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            Text("Restore Camera or Photo Library access to return to the viewfinder.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
