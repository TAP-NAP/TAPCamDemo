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

struct DepthAnalyzerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let snapshot: DepthAnalyzerAuthorizationSnapshot
    @Binding private var appAttestBackendSelection: AppAttestBackendSelection
    @Binding private var appAttestHTTPBaseURL: String
    private let appAttestBackendDescription: String
    private let onApplyAppAttestBackend: () -> Void

    init(
        snapshot: DepthAnalyzerAuthorizationSnapshot = .current(),
        appAttestBackendSelection: Binding<AppAttestBackendSelection>,
        appAttestHTTPBaseURL: Binding<String>,
        appAttestBackendDescription: String,
        onApplyAppAttestBackend: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self._appAttestBackendSelection = appAttestBackendSelection
        self._appAttestHTTPBaseURL = appAttestHTTPBaseURL
        self.appAttestBackendDescription = appAttestBackendDescription
        self.onApplyAppAttestBackend = onApplyAppAttestBackend
    }

    var body: some View {
        NavigationStack {
            List {
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
                    Picker("Backend", selection: $appAttestBackendSelection) {
                        ForEach(AppAttestBackendSelection.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if appAttestBackendSelection.showsHTTPSettings {
                        TextField("Base URL", text: $appAttestHTTPBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    Button {
                        onApplyAppAttestBackend()
                    } label: {
                        Label("Use Selected Backend", systemImage: "arrow.triangle.2.circlepath")
                    }

                    LabeledContent("Active", value: appAttestBackendDescription)
                }
            }
            .navigationTitle("Analyzer Settings")
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
