//
//  WelcomeStartupSetupView.swift
//  TAPCamDemo
//

import SwiftUI

struct WelcomeStartupSetupView: View {
    let mode: StartupSetupMode
    @ObservedObject var coordinator: StartupGateCoordinator
    let onContinue: () -> Void
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
                            iconName: "wifi",
                            title: "Network",
                            message: "Connect to TAPCam services.",
                            status: coordinator.networkStatus,
                            deniedMessage: "Network access denied. Open Settings."
                        ) {
                            coordinator.requestNetworkAccess()
                        }

                        StartupRequirementRow(
                            iconName: "camera",
                            title: "Camera",
                            message: "Take photos and videos.",
                            status: coordinator.cameraStatus,
                            deniedMessage: "Camera access denied. Open Settings.",
                            restrictedMessage: "Camera access is restricted."
                        ) {
                            Task { await coordinator.requestCameraAccess() }
                        }

                        StartupRequirementRow(
                            iconName: "photo.on.rectangle",
                            title: "Photo Library",
                            message: "Save photos and videos.",
                            status: coordinator.photoLibraryStatus,
                            deniedMessage: "Photo library access denied. Open Settings.",
                            restrictedMessage: "Photo library access is restricted."
                        ) {
                            Task { await onRequestPhotoLibraryAccess() }
                        }

                        StartupRequirementRow(
                            iconName: "location",
                            title: "Location",
                            message: "**Optional** · Save capture location.",
                            status: coordinator.locationStatus,
                            deniedMessage: "**Optional** · Location access denied.",
                            restrictedMessage: "**Optional** · Location access is restricted."
                        ) {
                            Task { await coordinator.requestLocationAccess() }
                        }

                        StartupRequirementRow(
                            iconName: "mic",
                            title: "Microphone",
                            message: "**Optional** · Record sound when capture.",
                            status: coordinator.microphoneStatus,
                            deniedMessage: "**Optional** · Microphone access denied.",
                            restrictedMessage: "**Optional** · Microphone access is restricted."
                        ) {
                            Task { await coordinator.requestMicrophoneAccess() }
                        }
                    }

                    footer

                    if [coordinator.networkStatus, coordinator.cameraStatus,
                        coordinator.photoLibraryStatus, coordinator.locationStatus,
                        coordinator.microphoneStatus].contains(.denied) {
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
        .onAppear {
            coordinator.refreshAuthorizationStatuses()
            coordinator.refreshNetworkAccessStatus()
        }
        .onDisappear {
            coordinator.cancelNetworkAccessRequest()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .initial ? "Welcome to TAPCam" : "Setup Recovery")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            Text(
                mode == .initial
                    ? "Set up camera and photo library access to start taking photos."
                    : "TAPCam could not restore your previous setup. Permissions you already granted are kept."
            )
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if mode == .credentialRecovery {
            Text("Setup recovery is unavailable in this version. Setup cannot continue.")
                .font(.footnote)
                .foregroundStyle(.yellow)
                .fixedSize(horizontal: false, vertical: true)
        } else if coordinator.hasCompletedRequiredStartupChecks {
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
        } else if !coordinator.hasBlockingStartupFailure {
            Text("Camera and photo library access are required. Location and microphone are optional.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.64))
        }
    }
}

struct StartupRequirementRow: View {
    @ScaledMetric(relativeTo: .headline) private var contentHeight: CGFloat = 44

    let iconName: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let status: StartupGateRequirementStatus
    var deniedMessage: LocalizedStringKey? = nil
    var restrictedMessage: LocalizedStringKey? = nil
    let primaryAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                }
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)

                Text(displayMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .frame(height: contentHeight)
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var displayMessage: LocalizedStringKey {
        if status == .restricted, let restrictedMessage {
            return restrictedMessage
        }
        if status == .denied, let deniedMessage {
            return deniedMessage
        }
        return message
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityLabel("Completed")
        case .requesting:
            ProgressView()
                .tint(.white)
                .frame(width: 34, height: 34)
                .accessibilityLabel("Requesting")
        case .denied:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.yellow)
                .accessibilityLabel("Needs Attention")
        case .restricted:
            VStack(spacing: 5) {
                Image(systemName: "lock.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.yellow)
                Text("Restricted")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Restricted by system policy")
        case .idle:
            Button("Continue", action: primaryAction)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
