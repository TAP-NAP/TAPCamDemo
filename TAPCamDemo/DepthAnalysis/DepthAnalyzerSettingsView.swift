//
//  DepthAnalyzerSettingsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/28.
//

@preconcurrency import AVFoundation
import CoreLocation
import Photos
import SwiftUI

enum DepthAnalyzerPreferences {
    static let showsAnalysisHelpKey = "DepthAnalyzerShowsAnalysisHelp"
    static let defaultShowsAnalysisHelp = true
}

struct DepthAnalyzerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let snapshot: DepthAnalyzerAuthorizationSnapshot
    private let shutterSoundSuppressionSupported: Bool
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    @AppStorage(DepthAnalyzerPreferences.showsAnalysisHelpKey)
    private var showsAnalysisHelp = DepthAnalyzerPreferences.defaultShowsAnalysisHelp
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var shutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var shutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled

    init(
        snapshot: DepthAnalyzerAuthorizationSnapshot = .current(),
        appAttestController: AppAttestRuntimeController,
        shutterSoundSuppressionSupported: Bool = true
    ) {
        self.snapshot = snapshot
        self.appAttestController = appAttestController
        self.shutterSoundSuppressionSupported = shutterSoundSuppressionSupported
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    Toggle(isOn: $shutterSoundEnabled) {
                        Label("Shutter Sound", systemImage: "speaker.wave.2")
                    }
                    .disabled(!shutterSoundSuppressionSupported)

                    Toggle(isOn: $shutterHapticsEnabled) {
                        Label("Shutter Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }

                    if !shutterSoundSuppressionSupported {
                        Text("Shutter sound cannot be disabled on this device or in this region.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Analysis") {
                    Toggle(isOn: $showsAnalysisHelp) {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }

                Section("Permissions") {
                    DepthAnalyzerStatusRow(
                        title: "Camera",
                        value: snapshot.camera,
                        systemImage: "camera"
                    )
                    DepthAnalyzerStatusRow(
                        title: "Photos",
                        value: snapshot.photos,
                        systemImage: "photo.on.rectangle"
                    )
                    DepthAnalyzerStatusRow(
                        title: "Location",
                        value: snapshot.location,
                        systemImage: "location"
                    )
                }

                Section("App Attest") {
                    appAttestStatusRow
                    if showsAnalysisHelp {
                        AppAttestKeyIDHelpView(message: Self.keyIDHelpText)
                    }
                    if let keyID = appAttestController.credentialKeyIdText {
                        AppAttestKeyIDInfoView(keyID: keyID)
                    }
                }

                #if DEBUG
                // Debug-only App Attest controls are hidden from Release and highlighted here.
                Section("App Attest Backend") {
                    LabeledContent("Active", value: appAttestController.runtime.backendDescription)
                        .listRowBackground(Self.debugOnlyAppAttestBackground)
                }

                Section("App Attest Credential") {
                    LabeledContent("Credential", value: AppAttestRuntimeDefaults.photoCredentialName)
                        .listRowBackground(Self.debugOnlyAppAttestBackground)

                    Button {
                        Task {
                            await appAttestController.prepareCredentialIfNeeded()
                        }
                    } label: {
                        Label("Prepare Credential", systemImage: "checkmark.seal")
                    }
                    .disabled(appAttestController.isWorking)
                    .listRowBackground(Self.debugOnlyAppAttestBackground)

                    Button(role: .destructive) {
                        Task {
                            await appAttestController.resetLocalCredential()
                        }
                    } label: {
                        Label("Reset Local Credential", systemImage: "trash")
                    }
                    .disabled(appAttestController.isWorking)
                    .listRowBackground(Self.debugOnlyAppAttestBackground)

                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appAttestStatusRow: some View {
        LabeledContent {
            appAttestStatusValue
        } label: {
            Text("Status")
        }
    }

    @ViewBuilder
    private var appAttestStatusValue: some View {
        if appAttestController.isPreparingCredential {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Preparing App Attest credential")
        } else if appAttestController.canResetAndPrepareCredential {
            VStack(alignment: .trailing, spacing: 6) {
                Text(appAttestController.credentialStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                Button {
                    Task {
                        await appAttestController.resetAndPrepareCredential()
                    }
                } label: {
                    Text(appAttestController.credentialPreparationActionTitle)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Resets and prepares the App Attest credential.")
            }
        } else {
            Text(appAttestController.credentialStatusText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let keyIDHelpText = "KeyID identifies the App Attest key that this app prepared on this device. " +
        "The app uses that key to generate request assertions, and the backend uses the KeyID to find the registered credential for verification."

    #if DEBUG
    private static let debugOnlyAppAttestBackground = Color.yellow.opacity(0.30)
    #endif
}

// Help stays inline under Status so Release users can read it in context.
private struct AppAttestKeyIDHelpView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("KeyID help. \(message)")
    }
}

// Keep this detail row to the keyId only; status belongs in the row above.
private struct AppAttestKeyIDInfoView: View {
    let keyID: String

    var body: some View {
        Text(keyID)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .accessibilityLabel("KeyID \(keyID)")
    }
}

private struct DepthAnalyzerStatusRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

nonisolated struct DepthAnalyzerAuthorizationSnapshot: Equatable {
    let camera: String
    let photos: String
    let location: String

    static func current() -> DepthAnalyzerAuthorizationSnapshot {
        DepthAnalyzerAuthorizationSnapshot(
            camera: DepthAnalyzerAuthorizationStatusText.camera(AVCaptureDevice.authorizationStatus(for: .video)),
            photos: DepthAnalyzerAuthorizationStatusText.photos(PHPhotoLibrary.authorizationStatus(for: .readWrite)),
            location: DepthAnalyzerAuthorizationStatusText.location(CLLocationManager().authorizationStatus)
        )
    }
}

nonisolated enum DepthAnalyzerAuthorizationStatusText {
    static func camera(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "Authorized"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }

    static func photos(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "Authorized"
        case .limited:
            "Limited"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }

    static func location(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways:
            "Always allowed"
        case .authorizedWhenInUse:
            "While using app"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }
}
