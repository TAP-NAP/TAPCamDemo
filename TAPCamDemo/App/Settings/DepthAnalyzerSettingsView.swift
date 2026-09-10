//
//  DepthAnalyzerSettingsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/28.
//

@preconcurrency import AVFoundation
import Combine
import CoreLocation
import Photos
import SwiftUI
import UIKit

enum DepthAnalyzerPreferences {
    static let appleDepthFilteringEnabledKey = "TAPVideoAppleDepthFilteringEnabled"
    static let defaultAppleDepthFilteringEnabled = false
    static let playbackSmoothingEnabledKey = "TAPVideoPlaybackSmoothingEnabled"
    static let defaultPlaybackSmoothingEnabled = false

    static func appleDepthFilteringEnabled(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        defaults.bool(forKey: appleDepthFilteringEnabledKey)
        #else
        false
        #endif
    }

    static func playbackSmoothingEnabled(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        defaults.bool(forKey: playbackSmoothingEnabledKey)
        #else
        false
        #endif
    }

    static let planeGrowthStrictnessKey = "DepthAnalyzerPlaneGrowthStrictness"
    static let defaultPlaneGrowthStrictness = DepthAnalysisPlaneSelectionState.defaultStrictness
}

struct DepthAnalyzerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissionRequester = DepthAnalyzerPermissionRequester()
    @State private var authorizationSnapshot: DepthAnalyzerAuthorizationSnapshot
    private let shutterSoundSuppressionSupported: Bool
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    @AppStorage(AppLanguage.storageKey)
    private var appLanguageRawValue = AppLanguage.defaultValue.rawValue
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var shutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var shutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled
    @AppStorage(CameraOutputFormatPreference.storageKey)
    private var outputFormatRawValue = CameraOutputFormatPreference.defaultValue.rawValue
    @AppStorage(CameraFlashControlMode.startupPolicyKey)
    private var flashStartupPolicyRawValue = CameraFlashControlMode.defaultStartupPolicy.rawValue
    @AppStorage(CameraPhotographerModePreferences.startupPolicyKey)
    private var photographerModeStartupPolicyRawValue = CameraPhotographerModePreferences.defaultStartupPolicy.rawValue
    @AppStorage(CameraGuideOverlayPreference.storageKey)
    private var guideOverlayRawValue = CameraGuideOverlayPreference.defaultValue.rawValue
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue
    @AppStorage(CameraEVPreferences.resetOnAppLaunchKey)
    private var resetEVOnAppLaunch = CameraEVPreferences.defaultResetOnAppLaunch
    #if DEBUG
    @AppStorage(DepthAnalyzerPreferences.appleDepthFilteringEnabledKey)
    private var appleDepthFilteringEnabled = DepthAnalyzerPreferences.defaultAppleDepthFilteringEnabled
    @AppStorage(DepthAnalyzerPreferences.playbackSmoothingEnabledKey)
    private var playbackSmoothingEnabled = DepthAnalyzerPreferences.defaultPlaybackSmoothingEnabled
    @AppStorage(CameraPhotoQualityPreference.storageKey)
    private var photoQualityRawValue = CameraPhotoQualityPreference.defaultValue.rawValue
    @AppStorage(CameraDepthAvailabilityHintPreferences.showsHintsKey)
    private var showsDepthAvailabilityHints = CameraDepthAvailabilityHintPreferences.defaultShowsHints
    @AppStorage(CameraFocusMagnifierPreference.storageKey)
    private var focusMagnifierRawValue = CameraFocusMagnifierPreference.defaultValue.rawValue
    @AppStorage(DepthAnalyzerPreferences.planeGrowthStrictnessKey)
    private var planeGrowthStrictness = DepthAnalyzerPreferences.defaultPlaneGrowthStrictness
    #endif
    @AppStorage(CameraIdleTimerPreferences.keepScreenAwakeKey)
    private var keepScreenAwake = CameraIdleTimerPreferences.defaultKeepScreenAwake
    @AppStorage(CameraLivePhotoPreferences.startupPolicyKey)
    private var livePhotoStartupPolicyRawValue = CameraLivePhotoPreferences.defaultStartupPolicy.rawValue
    @AppStorage(CameraCaptureDataUsePreferences.usesLocationDataKey)
    private var usesLocationData = CameraCaptureDataUsePreferences.defaultUsesLocationData
    @AppStorage(CameraCaptureDataUsePreferences.usesMicrophoneDataKey)
    private var usesMicrophoneData = CameraCaptureDataUsePreferences.defaultUsesMicrophoneData
    @AppStorage(CameraRoutePreferences.returnToCameraOnForegroundKey)
    private var returnToCameraOnForeground = CameraRoutePreferences.defaultReturnToCameraOnForeground

    init(
        snapshot: DepthAnalyzerAuthorizationSnapshot = .current(),
        appAttestController: AppAttestRuntimeController,
        shutterSoundSuppressionSupported: Bool = true
    ) {
        _authorizationSnapshot = State(initialValue: snapshot)
        self.appAttestController = appAttestController
        self.shutterSoundSuppressionSupported = shutterSoundSuppressionSupported
    }

    var body: some View {
        NavigationStack {
            Form {
                languageSettingsSection
                cameraSettingsSection
                interfaceSettingsSection
                dataAndPermissionsSection

                DepthAnalyzerAppAttestSection(
                    readiness: appAttestController.photoIntegrityReadiness,
                    canPrepare: appAttestController.canPreparePhotoIntegrity
                ) {
                    await appAttestController.resetAndPrepareCredential()
                }

                #if DEBUG
                debugCameraControlsSection
                debugAppAttestSections
                #endif

                Section {
                    NavigationLink("Acknowledgements") {
                        AcknowledgementsView()
                    }
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
            .onAppear(perform: refreshAuthorizationSnapshot)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshAuthorizationSnapshot()
            }
        }
    }

    private var languageSettingsSection: some View {
        Section("Language") {
            Picker("App Language", selection: appLanguageSelection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.titleKey)
                        .tag(language.rawValue)
                }
            }
        }
    }

    private var appLanguageSelection: Binding<String> {
        Binding(
            get: {
                AppLanguage.resolved(rawValue: appLanguageRawValue).rawValue
            },
            set: { newValue in
                appLanguageRawValue = AppLanguage.resolved(rawValue: newValue).rawValue
            }
        )
    }

    private var cameraSettingsSection: some View {
        Section("Camera Settings") {
            Picker("Output Format", selection: $outputFormatRawValue) {
                ForEach(CameraOutputFormatPreference.allCases) { format in
                    Text(LocalizedStringKey(format.title)).tag(format.rawValue)
                }
            }

            Picker("Flash Default", selection: $flashStartupPolicyRawValue) {
                ForEach(CameraViewfinderControlDefaultPolicy.allCases) { policy in
                    Text(LocalizedStringKey(policy.title)).tag(policy.rawValue)
                }
            }

            Picker("Live Photo Default", selection: $livePhotoStartupPolicyRawValue) {
                ForEach(CameraViewfinderControlDefaultPolicy.allCases) { policy in
                    Text(LocalizedStringKey(policy.title)).tag(policy.rawValue)
                }
            }

            Picker("Photographer Mode Startup", selection: $photographerModeStartupPolicyRawValue) {
                ForEach(CameraViewfinderControlDefaultPolicy.allCases) { policy in
                    Text(LocalizedStringKey(policy.title)).tag(policy.rawValue)
                }
            }

            Toggle(isOn: $keepScreenAwake) {
                Label("Keep Screen Awake", systemImage: "sun.max")
            }

            Toggle(isOn: $resetEVOnAppLaunch) {
                Label("Reset EV on App Launch", systemImage: "plusminus")
            }

            Toggle(isOn: $returnToCameraOnForeground) {
                Label("Return to Camera After Background", systemImage: "camera.viewfinder")
            }

            Toggle(isOn: $shutterHapticsEnabled) {
                Label("Interaction Haptics", systemImage: "iphone.radiowaves.left.and.right")
            }

            Toggle(isOn: shutterSoundSuppressionBinding) {
                Label("Silent Shutter", systemImage: "speaker.slash")
            }
            .disabled(!shutterSoundSuppressionSupported)

            if !shutterSoundSuppressionSupported {
                Text("Silent shutter is unavailable on this device or in this region.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var interfaceSettingsSection: some View {
        Section("Interface") {
            Picker("Grid", selection: $guideOverlayRawValue) {
                ForEach(CameraGuideOverlayPreference.allCases) { guide in
                    Text(LocalizedStringKey(guide.title)).tag(guide.rawValue)
                }
            }

            Picker("Highlight Color", selection: $viewfinderHighlightRawValue) {
                ForEach(CameraViewfinderHighlightPreference.allCases) { preference in
                    HStack {
                        Circle()
                            .fill(preference.color)
                            .frame(width: 11, height: 11)
                        Text(LocalizedStringKey(preference.title))
                    }
                    .tag(preference.rawValue)
                }
            }

        }
    }

    private var shutterSoundSuppressionBinding: Binding<Bool> {
        Binding(
            get: { !shutterSoundEnabled },
            set: { shutterSoundEnabled = !$0 }
        )
    }

    private var dataAndPermissionsSection: some View {
        Section("Data & Permissions") {
            DepthAnalyzerStatusRow(
                title: "Camera",
                value: authorizationSnapshot.camera,
                systemImage: "camera"
            )
            DepthAnalyzerStatusRow(
                title: "Photos",
                value: authorizationSnapshot.photos,
                systemImage: "photo.on.rectangle"
            )
            DepthAnalyzerDataPermissionRow(
                title: "Location Data",
                subtitle: "Adds capture location to photo metadata.",
                value: authorizationSnapshot.location,
                systemImage: "location",
                actionTitle: authorizationSnapshot.locationPermissionActionTitle,
                isRequesting: permissionRequester.isRequestingLocation,
                dataUseBinding: authorizationSnapshot.isLocationAuthorized ? $usesLocationData : nil,
                action: performLocationPermissionAction
            )

            DepthAnalyzerDataPermissionRow(
                title: "Microphone",
                subtitle: "Records sound for Live Photos and videos.",
                value: authorizationSnapshot.microphone,
                systemImage: "mic",
                actionTitle: authorizationSnapshot.microphonePermissionActionTitle,
                isRequesting: permissionRequester.isRequestingMicrophone,
                dataUseBinding: authorizationSnapshot.isMicrophoneAuthorized ? $usesMicrophoneData : nil,
                action: performMicrophonePermissionAction
            )
        }
    }

    private func refreshAuthorizationSnapshot() {
        let snapshot = DepthAnalyzerAuthorizationSnapshot.current()
        authorizationSnapshot = snapshot

        if snapshot.isMicrophoneAuthorized {
            CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
        }
        usesMicrophoneData = CameraCaptureDataUsePreferences.usesMicrophoneData()
    }

    private func performLocationPermissionAction() {
        switch authorizationSnapshot.locationAuthorizationStatus {
        case .notDetermined:
            Task {
                await permissionRequester.requestLocationAccess()
                refreshAuthorizationSnapshot()
            }
        case .denied, .restricted:
            openAppSettings()
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }
    }

    private func performMicrophonePermissionAction() {
        switch authorizationSnapshot.microphoneAuthorizationStatus {
        case .notDetermined:
            Task {
                let granted = await permissionRequester.requestMicrophoneAccess()
                if granted {
                    CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
                    usesMicrophoneData = CameraCaptureDataUsePreferences.usesMicrophoneData()
                }
                refreshAuthorizationSnapshot()
            }
        case .denied, .restricted:
            openAppSettings()
        case .authorized:
            break
        @unknown default:
            break
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    #if DEBUG
    private var debugCameraControlsSection: some View {
        Section("Debug Camera Controls") {
            Toggle(isOn: $appleDepthFilteringEnabled) {
                VStack(alignment: .leading) {
                    Text("Apple Depth Filtering")
                    Text("Applies to the next TAP Video recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settings.apple-depth-filtering")
            .listRowBackground(Self.debugOnlySettingsBackground)

            Toggle(isOn: $playbackSmoothingEnabled) {
                VStack(alignment: .leading) {
                    Text("3D Playback Smoothing")
                    Text("Changes only the 3D display, never the recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settings.3d-playback-smoothing")
            .listRowBackground(Self.debugOnlySettingsBackground)

            Picker("Capture Prioritization", selection: $photoQualityRawValue) {
                ForEach(CameraPhotoQualityPreference.allCases) { quality in
                    Text(LocalizedStringKey(quality.title)).tag(quality.rawValue)
                }
            }
            .listRowBackground(Self.debugOnlySettingsBackground)

            Toggle(isOn: $showsDepthAvailabilityHints) {
                Label("Depth Warnings", systemImage: "rectangle.and.text.magnifyingglass")
            }
            .listRowBackground(Self.debugOnlySettingsBackground)

            Picker("Focus Magnifier", selection: $focusMagnifierRawValue) {
                ForEach(CameraFocusMagnifierPreference.allCases) { preference in
                    Text(preference.title).tag(preference.rawValue)
                }
            }
            .listRowBackground(Self.debugOnlySettingsBackground)

            VStack(alignment: .leading, spacing: 8) {
                Label("Plane Strictness", systemImage: "scope")

                Slider(
                    value: $planeGrowthStrictness,
                    in: DepthAnalysisPlaneSelectionState.minimumStrictness...DepthAnalysisPlaneSelectionState.maximumStrictness
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Plane Strictness")
            .accessibilityValue("\(Int((planeGrowthStrictness * 100).rounded())) percent")
            .listRowBackground(Self.debugOnlySettingsBackground)
        }
    }

    private var debugAppAttestSections: some View {
        Group {
            // Debug-only App Attest controls are hidden from Release and highlighted here.
            Section("App Attest Backend") {
                LabeledContent("Active", value: appAttestController.runtime.backendPublicSummary)
                    .listRowBackground(Self.debugOnlySettingsBackground)
            }

            Section("App Attest Credential") {
                LabeledContent("Internal Status", value: appAttestController.credentialStatusText)
                    .listRowBackground(Self.debugOnlySettingsBackground)

                LabeledContent("Credential", value: AppAttestRuntimeDefaults.photoCredentialName)
                    .listRowBackground(Self.debugOnlySettingsBackground)

                if let keyID = appAttestController.credentialKeyIDPresentation {
                    LabeledContent("KeyID", value: keyID.displayText)
                        .listRowBackground(Self.debugOnlySettingsBackground)
                }

                Button {
                    Task {
                        await appAttestController.prepareCredentialIfNeeded()
                    }
                } label: {
                    Label("Prepare Credential", systemImage: "checkmark.seal")
                }
                .disabled(appAttestController.isWorking)
                .listRowBackground(Self.debugOnlySettingsBackground)

                Button(role: .destructive) {
                    Task {
                        await appAttestController.resetLocalCredential()
                    }
                } label: {
                    Label("Reset Local Credential", systemImage: "trash")
                }
                .disabled(appAttestController.isWorking)
                .listRowBackground(Self.debugOnlySettingsBackground)
            }
        }
    }

    private static let debugOnlySettingsBackground = Color.yellow.opacity(0.30)
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

            Text(LocalizedStringKey(title))

            Spacer(minLength: 12)

            Text(LocalizedStringKey(value))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DepthAnalyzerDataPermissionRow: View {
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
    let actionTitle: String?
    let isRequesting: Bool
    let dataUseBinding: Binding<Bool>?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))

                Text(LocalizedStringKey(value))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isRequesting {
                ProgressView()
            } else if let actionTitle {
                Button(action: action) {
                    Text(LocalizedStringKey(actionTitle))
                }
                    .buttonStyle(.bordered)
                    .font(.footnote.weight(.semibold))
            } else if let dataUseBinding {
                Toggle("Use When Capturing", isOn: dataUseBinding)
                    .labelsHidden()
                    .accessibilityLabel("Use When Capturing")
            }
        }
    }
}

@MainActor
private final class DepthAnalyzerPermissionRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isRequestingLocation = false
    @Published var isRequestingMicrophone = false

    private let locationManager = CLLocationManager()
    private var locationAuthorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocationAccess() async {
        guard !isRequestingLocation else { return }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .denied, .restricted:
            return
        case .notDetermined:
            isRequestingLocation = true
            _ = await withCheckedContinuation { continuation in
                locationAuthorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
            isRequestingLocation = false
        @unknown default:
            return
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        guard !isRequestingMicrophone else { return false }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            isRequestingMicrophone = true
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            isRequestingMicrophone = false
            return granted
        @unknown default:
            return false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self,
                  let continuation = locationAuthorizationContinuation else {
                return
            }
            locationAuthorizationContinuation = nil
            continuation.resume(returning: manager.authorizationStatus)
        }
    }
}

nonisolated struct DepthAnalyzerAuthorizationSnapshot: Equatable {
    let camera: String
    let photos: String
    let location: String
    let microphone: String
    let locationAuthorizationStatus: CLAuthorizationStatus
    let microphoneAuthorizationStatus: AVAuthorizationStatus

    var locationPermissionActionTitle: String? {
        Self.permissionActionTitle(for: locationAuthorizationStatus)
    }

    var microphonePermissionActionTitle: String? {
        Self.permissionActionTitle(for: microphoneAuthorizationStatus)
    }

    var isLocationAuthorized: Bool {
        locationAuthorizationStatus == .authorizedAlways ||
            locationAuthorizationStatus == .authorizedWhenInUse
    }

    var isMicrophoneAuthorized: Bool {
        microphoneAuthorizationStatus == .authorized
    }

    static func current() -> DepthAnalyzerAuthorizationSnapshot {
        let locationStatus = CLLocationManager().authorizationStatus
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        return DepthAnalyzerAuthorizationSnapshot(
            camera: DepthAnalyzerAuthorizationStatusText.camera(AVCaptureDevice.authorizationStatus(for: .video)),
            photos: DepthAnalyzerAuthorizationStatusText.photos(PHPhotoLibrary.authorizationStatus(for: .readWrite)),
            location: DepthAnalyzerAuthorizationStatusText.location(locationStatus),
            microphone: DepthAnalyzerAuthorizationStatusText.microphone(microphoneStatus),
            locationAuthorizationStatus: locationStatus,
            microphoneAuthorizationStatus: microphoneStatus
        )
    }

    private static func permissionActionTitle(for status: CLAuthorizationStatus) -> String? {
        switch status {
        case .notDetermined:
            "Get Permission"
        case .denied, .restricted:
            "Open Settings"
        case .authorizedAlways, .authorizedWhenInUse:
            nil
        @unknown default:
            nil
        }
    }

    private static func permissionActionTitle(for status: AVAuthorizationStatus) -> String? {
        switch status {
        case .notDetermined:
            "Get Permission"
        case .denied, .restricted:
            "Open Settings"
        case .authorized:
            nil
        @unknown default:
            nil
        }
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

    static func microphone(_ status: AVAuthorizationStatus) -> String {
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
}
