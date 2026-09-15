//
//  RequiredPermissionCheckView.swift
//  TAPCamDemo
//

import SwiftUI

/// App-owned recovery surface for the two permissions that can block camera
/// entry after Setup. Each Continue requests its permission; the root reducer
/// observes the refreshed snapshot and returns to the camera automatically.
struct RequiredPermissionCheckView: View {
    @ObservedObject var coordinator: StartupGateCoordinator
    let onRequestPhotoLibraryAccess: () async -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(spacing: 10) {
                        StartupRequirementRow(
                            iconName: "camera",
                            title: "Camera",
                            message: "Camera access is required to capture.",
                            status: coordinator.cameraStatus,
                            deniedMessage: "Camera access denied. Open Settings.",
                            restrictedMessage: "Camera access is restricted."
                        ) {
                            Task { await coordinator.requestCameraAccess() }
                        }

                        StartupRequirementRow(
                            iconName: "photo.on.rectangle",
                            title: "Photo Library",
                            message: "Photo library access is required.",
                            status: coordinator.photoLibraryStatus,
                            deniedMessage: "Photo library access denied. Open Settings.",
                            restrictedMessage: "Photo library access is restricted."
                        ) {
                            Task { await onRequestPhotoLibraryAccess() }
                        }
                    }

                    if [coordinator.cameraStatus, coordinator.photoLibraryStatus].contains(.denied) {
                        Button("Open Settings", action: onOpenSettings)
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
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
