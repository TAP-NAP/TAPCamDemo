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
    let onOpenSettings: (StartupGateRequirementKind) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(spacing: 10) {
                        StartupRequirementRow(
                            iconName: "wifi",
                            title: "Network Access",
                            message: "Checks that TAPCam can reach the service before first camera setup.",
                            status: coordinator.securityPreflightStatus,
                            actionTitle: "Allow"
                        ) {
                            Task { await coordinator.requestSecurityPreflight() }
                        }

                        StartupRequirementRow(
                            iconName: "camera",
                            title: "Camera Access",
                            message: "Used to capture photos with depth data.",
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
                            message: "Used to save and read photos.",
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

                        StartupRequirementRow(
                            iconName: "location",
                            title: "Location Access",
                            message: "Optional. Used to write capture location into photo metadata.",
                            status: coordinator.locationStatus,
                            actionTitle: "Allow",
                            secondaryActionTitle: "Skip",
                            deniedMessage: "Location access was denied. You can change it in Settings.",
                            restrictedMessage: "Location access is restricted by system policy.",
                            recoveryActionTitle: "Open Settings"
                        ) {
                            Task { await coordinator.requestLocationAccess() }
                        } secondaryAction: {
                            coordinator.skipLocationAccess()
                        } recoveryAction: {
                            onOpenSettings(.location)
                        }

                        StartupRequirementRow(
                            iconName: "mic",
                            title: "Microphone Access",
                            message: "Optional. Used to record sound for Live Photos and videos.",
                            status: coordinator.microphoneStatus,
                            actionTitle: "Allow",
                            secondaryActionTitle: "Skip",
                            deniedMessage: "Microphone access was denied. You can change it in Settings.",
                            restrictedMessage: "Microphone access is restricted by system policy.",
                            recoveryActionTitle: "Open Settings"
                        ) {
                            Task { await coordinator.requestMicrophoneAccess() }
                        } secondaryAction: {
                            coordinator.skipMicrophoneAccess()
                        } recoveryAction: {
                            onOpenSettings(.microphone)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .initial ? "Welcome to TAPCam" : "Setup Recovery")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            Text(
                mode == .initial
                    ? "First launch needs required setup checks before camera setup can continue."
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
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if coordinator.hasSecurityPreflightFailure {
                    Text("Network access check failed. Check connectivity, then try again.")
                        .font(.footnote)
                        .foregroundStyle(.yellow)

                    Button {
                        Task { await coordinator.requestSecurityPreflight() }
                    } label: {
                        Label("Retry Network Access", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                if !coordinator.hasBlockingStartupFailure {
                    Text("Complete network access, camera, and photo library access first. Location and microphone are optional.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
        }
    }

}

struct StartupRequirementRow: View {
    let iconName: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let status: StartupGateRequirementStatus
    let actionTitle: LocalizedStringKey
    var secondaryActionTitle: LocalizedStringKey? = nil
    var deniedMessage: LocalizedStringKey? = nil
    var restrictedMessage: LocalizedStringKey? = nil
    var recoveryActionTitle: LocalizedStringKey? = nil
    let primaryAction: () -> Void
    var secondaryAction: (() -> Void)? = nil
    var recoveryAction: (() -> Void)? = nil

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

                Text(displayMessage)
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
            VStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Needs Attention")

                if let recoveryActionTitle,
                   let recoveryAction {
                    Button {
                        recoveryAction()
                    } label: {
                        Text(recoveryActionTitle)
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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
            VStack(spacing: 7) {
                Button {
                    primaryAction()
                } label: {
                    Text(actionTitle)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)

                if let secondaryActionTitle,
                   let secondaryAction {
                    Button {
                        secondaryAction()
                    } label: {
                        Text(secondaryActionTitle)
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
