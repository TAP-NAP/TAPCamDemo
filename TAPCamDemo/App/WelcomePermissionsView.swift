//
//  WelcomePermissionsView.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

struct WelcomePermissionsView: View {
    @ObservedObject var coordinator: StartupPermissionCoordinator
    let onContinue: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(spacing: 10) {
                        PermissionChecklistRow(
                            iconName: "network",
                            title: "Network Access",
                            message: "Used for first-run security setup and device verification.",
                            status: coordinator.networkStatus,
                            actionTitle: "Allow"
                        ) {
                            Task { await coordinator.requestNetworkAccess() }
                        }

                        PermissionChecklistRow(
                            iconName: "camera",
                            title: "Camera Access",
                            message: "Used to capture photos with depth data.",
                            status: coordinator.cameraStatus,
                            actionTitle: "Allow"
                        ) {
                            Task { await coordinator.requestCameraAccess() }
                        }

                        PermissionChecklistRow(
                            iconName: "photo.on.rectangle",
                            title: "Photo Library Access",
                            message: "Used to save and read photos.",
                            status: coordinator.photoLibraryStatus,
                            actionTitle: "Allow"
                        ) {
                            Task { await coordinator.requestPhotoLibraryAccess() }
                        }

                        PermissionChecklistRow(
                            iconName: "location",
                            title: "Location Access",
                            message: "Optional. Used to write capture location into photo metadata.",
                            status: coordinator.locationStatus,
                            actionTitle: "Allow",
                            secondaryActionTitle: "Skip"
                        ) {
                            Task { await coordinator.requestLocationAccess() }
                        } secondaryAction: {
                            coordinator.skipLocationAccess()
                        }
                    }

                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)
                .padding(.bottom, 34)
            }
        }
        .onAppear {
            coordinator.refreshAuthorizationStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            coordinator.refreshAuthorizationStatuses()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to TAPCam")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            Text("First launch needs required permissions before camera setup can continue.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if coordinator.hasRequiredPermissions {
            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if coordinator.hasBlockingDenial {
                    Text("Enable the required permissions in Settings, then return to continue.")
                        .font(.footnote)
                        .foregroundStyle(.yellow)

                    Button {
                        openAppSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                } else {
                    Text("Finish network, camera, and photo library access first. Location is optional.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }
}

private struct PermissionChecklistRow: View {
    let iconName: String
    let title: String
    let message: String
    let status: StartupPermissionStatus
    let actionTitle: String
    var secondaryActionTitle: String? = nil
    let primaryAction: () -> Void
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(.white)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            actions
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityLabel("Completed")
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityLabel("Skipped")
        case .requesting:
            ProgressView()
                .tint(.white)
                .frame(width: 34, height: 34)
                .accessibilityLabel("Requesting")
        case .denied:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.yellow)
                .accessibilityLabel("Needs Settings")
        case .idle:
            VStack(spacing: 7) {
                Button(actionTitle) {
                    primaryAction()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)

                if let secondaryActionTitle,
                   let secondaryAction {
                    Button(secondaryActionTitle) {
                        secondaryAction()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}
