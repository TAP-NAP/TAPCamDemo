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
import UniformTypeIdentifiers

enum DepthAnalyzerPreferences {
    static let showsAnalysisHelpKey = "DepthAnalyzerShowsAnalysisHelp"
    static let defaultShowsAnalysisHelp = true

    static func showsAnalysisHelp(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: showsAnalysisHelpKey) != nil else {
            return defaultShowsAnalysisHelp
        }
        return userDefaults.bool(forKey: showsAnalysisHelpKey)
    }
}

struct DepthAnalyzerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    @State private var snapshot: DepthAnalyzerAuthorizationSnapshot
    @State private var showsAnalysisHelp: Bool
    @State private var helpPreferenceWriteTask: Task<Void, Never>?
    private let userDefaults: UserDefaults
    #if DEBUG
    @State private var attestationObjectDocument: AppAttestCBORDocument?
    @State private var isAttestationExporterPresented = false
    #endif

    init(
        snapshot: DepthAnalyzerAuthorizationSnapshot? = nil,
        appAttestController: AppAttestRuntimeController,
        userDefaults: UserDefaults = .standard
    ) {
        self.appAttestController = appAttestController
        self.userDefaults = userDefaults
        _snapshot = State(initialValue: snapshot ?? .checking)
        _showsAnalysisHelp = State(initialValue: DepthAnalyzerPreferences.showsAnalysisHelp(userDefaults: userDefaults))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Analysis") {
                    Toggle(isOn: showsAnalysisHelpBinding) {
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
                            await appAttestController.prepareCredential()
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

                    Button {
                        exportAttestationCBOR()
                    } label: {
                        Label("Export Attestation CBOR", systemImage: "square.and.arrow.down")
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
            .task {
                await refreshAuthorizationSnapshotIfNeeded()
            }
            .onDisappear {
                helpPreferenceWriteTask?.cancel()
                userDefaults.set(showsAnalysisHelp, forKey: DepthAnalyzerPreferences.showsAnalysisHelpKey)
            }
        }
        #if DEBUG
        .fileExporter(
            isPresented: $isAttestationExporterPresented,
            document: attestationObjectDocument,
            contentType: .data,
            defaultFilename: "attestationObject.cbor"
        ) { result in
            appAttestController.handleAttestationExportResult(result)
        }
        #endif
    }

    private var showsAnalysisHelpBinding: Binding<Bool> {
        Binding(
            get: { showsAnalysisHelp },
            set: { newValue in
                showsAnalysisHelp = newValue
                scheduleHelpPreferenceWrite(newValue)
            }
        )
    }

    private func scheduleHelpPreferenceWrite(_ newValue: Bool) {
        helpPreferenceWriteTask?.cancel()
        helpPreferenceWriteTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }
            userDefaults.set(newValue, forKey: DepthAnalyzerPreferences.showsAnalysisHelpKey)
        }
    }

    private func refreshAuthorizationSnapshotIfNeeded() async {
        guard snapshot == .checking else {
            return
        }

        await Task.yield()
        snapshot = .current()
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
            Button {
                Task {
                    await appAttestController.resetAndPrepareCredential()
                }
            } label: {
                Text(appAttestController.credentialStatusText)
                    .multilineTextAlignment(.trailing)
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Resets and prepares the App Attest credential.")
        } else {
            Text(appAttestController.credentialStatusText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let keyIDHelpText = "KeyID identifies the App Attest key that this app prepared on this device. " +
        "The app uses that key to generate request assertions, and the backend uses the KeyID to find the registered credential for verification."

    #if DEBUG
    private func exportAttestationCBOR() {
        Task {
            guard let data = await appAttestController.attestationObjectForExport() else {
                return
            }
            attestationObjectDocument = AppAttestCBORDocument(data: data)
            isAttestationExporterPresented = true
        }
    }

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

    static let checking = DepthAnalyzerAuthorizationSnapshot(
        camera: "Checking...",
        photos: "Checking...",
        location: "Checking..."
    )

    @MainActor
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
