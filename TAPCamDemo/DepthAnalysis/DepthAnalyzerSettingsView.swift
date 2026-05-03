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
}

struct DepthAnalyzerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let snapshot: DepthAnalyzerAuthorizationSnapshot
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    @AppStorage(DepthAnalyzerPreferences.showsAnalysisHelpKey)
    private var showsAnalysisHelp = DepthAnalyzerPreferences.defaultShowsAnalysisHelp
    @State private var attestationObjectDocument: AppAttestCBORDocument?
    @State private var isAttestationExporterPresented = false

    init(
        snapshot: DepthAnalyzerAuthorizationSnapshot = .current(),
        appAttestController: AppAttestRuntimeController
    ) {
        self.snapshot = snapshot
        self.appAttestController = appAttestController
    }

    var body: some View {
        NavigationStack {
            List {
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

                Section("App Attest Backend") {
                    LabeledContent("Active", value: appAttestController.runtime.backendDescription)
                }

                Section("App Attest Credential") {
                    LabeledContent("Credential", value: AppAttestRuntimeDefaults.photoCredentialName)

                    Button {
                        Task {
                            await appAttestController.prepareCredential()
                        }
                    } label: {
                        Label("Prepare Credential", systemImage: "checkmark.seal")
                    }
                    .disabled(appAttestController.isWorking)

                    Button(role: .destructive) {
                        Task {
                            await appAttestController.resetLocalCredential()
                        }
                    } label: {
                        Label("Reset Local Credential", systemImage: "trash")
                    }
                    .disabled(appAttestController.isWorking)

                    Button {
                        exportAttestationCBOR()
                    } label: {
                        Label("Export Attestation CBOR", systemImage: "square.and.arrow.down")
                    }
                    .disabled(appAttestController.isWorking)

                    LabeledContent("Status", value: appAttestController.credentialStatusText)
                }
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
        .fileExporter(
            isPresented: $isAttestationExporterPresented,
            document: attestationObjectDocument,
            contentType: .data,
            defaultFilename: "attestationObject.cbor"
        ) { result in
            appAttestController.handleAttestationExportResult(result)
        }
    }

    private func exportAttestationCBOR() {
        Task {
            guard let data = await appAttestController.attestationObjectForExport() else {
                return
            }
            attestationObjectDocument = AppAttestCBORDocument(data: data)
            isAttestationExporterPresented = true
        }
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
