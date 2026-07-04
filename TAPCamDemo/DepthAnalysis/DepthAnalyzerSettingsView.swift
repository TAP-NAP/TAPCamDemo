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
    @AppStorage(CameraOutputFormatPreference.storageKey)
    private var outputFormatRawValue = CameraOutputFormatPreference.defaultValue.rawValue
    @AppStorage(CameraPhotoQualityPreference.storageKey)
    private var photoQualityRawValue = CameraPhotoQualityPreference.defaultValue.rawValue
    @AppStorage(CameraFlashControlMode.defaultModeKey)
    private var defaultFlashRawValue = CameraFlashControlMode.defaultValue.rawValue
    @AppStorage(CameraGuideOverlayPreference.storageKey)
    private var guideOverlayRawValue = CameraGuideOverlayPreference.defaultValue.rawValue
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue
    @AppStorage(CameraEVPreferences.resetOnAppLaunchKey)
    private var resetEVOnAppLaunch = CameraEVPreferences.defaultResetOnAppLaunch
    @AppStorage(CameraDepthAvailabilityHintPreferences.showsHintsKey)
    private var showsDepthAvailabilityHints = CameraDepthAvailabilityHintPreferences.defaultShowsHints
    @AppStorage(CameraFocusMagnifierPreference.storageKey)
    private var focusMagnifierRawValue = CameraFocusMagnifierPreference.defaultValue.rawValue
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @AppStorage(CameraManualFocusTapAssistPreferences.isEnabledKey)
    private var isManualFocusTapAssistEnabled = CameraManualFocusTapAssistPreferences.defaultIsEnabled
    #endif
    @AppStorage(CameraIdleTimerPreferences.keepScreenAwakeKey)
    private var keepScreenAwake = CameraIdleTimerPreferences.defaultKeepScreenAwake
    @AppStorage(CameraLiDARFocusAssistPreferences.isEnabledKey)
    private var isLiDARFocusAssistEnabled = CameraLiDARFocusAssistPreferences.defaultIsEnabled
    @AppStorage(CameraLivePhotoPreferences.isEnabledKey)
    private var isLivePhotoEnabled = CameraLivePhotoPreferences.defaultIsEnabled
    @AppStorage(CameraRoutePreferences.returnToCameraOnForegroundKey)
    private var returnToCameraOnForeground = CameraRoutePreferences.defaultReturnToCameraOnForeground

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
                    Picker("Photo Quality", selection: $photoQualityRawValue) {
                        ForEach(CameraPhotoQualityPreference.allCases) { quality in
                            Text(quality.title).tag(quality.rawValue)
                        }
                    }

                    Picker("Output Format", selection: $outputFormatRawValue) {
                        ForEach(CameraOutputFormatPreference.allCases) { format in
                            Text(format.title).tag(format.rawValue)
                        }
                    }

                    Picker("Default Flash", selection: $defaultFlashRawValue) {
                        ForEach(CameraFlashControlMode.allCases) { mode in
                            Text(mode.settingsTitle).tag(mode.rawValue)
                        }
                    }

                    Toggle(isOn: $isLivePhotoEnabled) {
                        Label("Live Photo", systemImage: "livephoto")
                    }

                    Toggle(isOn: $keepScreenAwake) {
                        Label("Keep Screen Awake", systemImage: "sun.max")
                    }
                }

                Section("Viewfinder") {
                    Picker("Grid", selection: $guideOverlayRawValue) {
                        ForEach(CameraGuideOverlayPreference.allCases) { guide in
                            Text(guide.title).tag(guide.rawValue)
                        }
                    }

                    Picker("Highlight Color", selection: $viewfinderHighlightRawValue) {
                        ForEach(CameraViewfinderHighlightPreference.allCases) { preference in
                            HStack {
                                Circle()
                                    .fill(preference.color)
                                    .frame(width: 11, height: 11)
                                Text(preference.title)
                            }
                            .tag(preference.rawValue)
                        }
                    }

                    Picker("Focus Magnifier", selection: $focusMagnifierRawValue) {
                        ForEach(CameraFocusMagnifierPreference.allCases) { preference in
                            Text(preference.title).tag(preference.rawValue)
                        }
                    }

                    Toggle(isOn: $showsDepthAvailabilityHints) {
                        Label("Depth Warnings", systemImage: "rectangle.and.text.magnifyingglass")
                    }
                }

                Section("Focus") {
                    Toggle(isOn: $isLiDARFocusAssistEnabled) {
                        Label("LiDAR Focus Assist", systemImage: "scope")
                    }

                    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
                    Toggle(isOn: $isManualFocusTapAssistEnabled) {
                        Label("Manual Focus Tap Assist", systemImage: "scope")
                    }
                    #endif
                }

                Section("Feedback") {
                    Toggle(isOn: $shutterSoundEnabled) {
                        Label("Shutter Sound", systemImage: "speaker.wave.2")
                    }
                    .disabled(!shutterSoundSuppressionSupported)

                    Toggle(isOn: $shutterHapticsEnabled) {
                        Label("Shutter Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }

                    Toggle(isOn: $resetEVOnAppLaunch) {
                        Label("Reset EV on App Launch", systemImage: "plusminus")
                    }

                    if !shutterSoundSuppressionSupported {
                        Text("Shutter sound cannot be disabled on this device or in this region.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Navigation") {
                    Toggle(isOn: $returnToCameraOnForeground) {
                        Label("Return to Camera After Background", systemImage: "camera.viewfinder")
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

                DepthAnalyzerAppAttestSection(
                    statusText: appAttestController.credentialStatusText,
                    keyID: appAttestController.credentialKeyIDPresentation,
                    isPreparingCredential: appAttestController.isPreparingCredential,
                    canResetAndPrepareCredential: appAttestController.canResetAndPrepareCredential,
                    actionTitle: appAttestController.credentialPreparationActionTitle,
                    showsHelp: showsAnalysisHelp,
                    onPrepare: {
                        await appAttestController.resetAndPrepareCredential()
                    }
                )

                #if DEBUG
                // Debug-only App Attest controls are hidden from Release and highlighted here.
                Section("App Attest Backend") {
                    LabeledContent("Active", value: appAttestController.runtime.backendPublicSummary)
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

    #if DEBUG
    private static let debugOnlyAppAttestBackground = Color.yellow.opacity(0.30)
    #endif
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
