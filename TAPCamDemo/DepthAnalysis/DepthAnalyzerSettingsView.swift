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
    static let showsAnalysisHelpKey = "DepthAnalyzerShowsAnalysisHelp"
    static let defaultShowsAnalysisHelp = true
    static let planeGridAnimationEnabledKey = "DepthAnalyzerPlaneGridAnimationEnabled"
    static let defaultPlaneGridAnimationEnabled = true
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
    @AppStorage(DepthAnalyzerPreferences.showsAnalysisHelpKey)
    private var showsAnalysisHelp = DepthAnalyzerPreferences.defaultShowsAnalysisHelp
    @AppStorage(DepthAnalyzerPreferences.planeGridAnimationEnabledKey)
    private var isPlaneGridAnimationEnabled = DepthAnalyzerPreferences.defaultPlaneGridAnimationEnabled
    @AppStorage(DepthAnalyzerPreferences.planeGrowthStrictnessKey)
    private var planeGrowthStrictness = DepthAnalyzerPreferences.defaultPlaneGrowthStrictness
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var shutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var shutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled
    @AppStorage(CameraOutputFormatPreference.storageKey)
    private var outputFormatRawValue = CameraOutputFormatPreference.defaultValue.rawValue
    @AppStorage(CameraPhotoQualityPreference.storageKey)
    private var photoQualityRawValue = CameraPhotoQualityPreference.defaultValue.rawValue
    @AppStorage(CameraFlashControlMode.startupPolicyKey)
    private var flashStartupPolicyRawValue = CameraFlashControlMode.defaultStartupPolicy.rawValue
    @AppStorage(CameraGuideOverlayPreference.storageKey)
    private var guideOverlayRawValue = CameraGuideOverlayPreference.defaultValue.rawValue
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue
    @AppStorage(CameraEVPreferences.resetOnAppLaunchKey)
    private var resetEVOnAppLaunch = CameraEVPreferences.defaultResetOnAppLaunch
    @AppStorage(CameraDepthAvailabilityHintPreferences.showsHintsKey)
    private var showsDepthAvailabilityHints = CameraDepthAvailabilityHintPreferences.defaultShowsHints
    #if DEBUG
    @AppStorage(CameraFocusMagnifierPreference.storageKey)
    private var focusMagnifierRawValue = CameraFocusMagnifierPreference.defaultValue.rawValue
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @AppStorage(CameraManualFocusTapAssistPreferences.isEnabledKey)
    private var isManualFocusTapAssistEnabled = CameraManualFocusTapAssistPreferences.defaultIsEnabled
    #endif
    @AppStorage(CameraLiDARFocusAssistPreferences.isEnabledKey)
    private var isLiDARFocusAssistEnabled = CameraLiDARFocusAssistPreferences.defaultIsEnabled
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
                captureSettingsSection
                viewfinderSettingsSection
                cameraBehaviorSection
                feedbackSettingsSection
                analysisSettingsSection
                permissionsSection

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
                debugCameraControlsSection
                debugAppAttestSections
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
            .onAppear(perform: refreshAuthorizationSnapshot)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshAuthorizationSnapshot()
            }
        }
    }

    private var captureSettingsSection: some View {
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

            Picker("Flash Default", selection: $flashStartupPolicyRawValue) {
                ForEach(CameraViewfinderControlDefaultPolicy.allCases) { policy in
                    Text(policy.title).tag(policy.rawValue)
                }
            }

            Picker("Live Photo Default", selection: $livePhotoStartupPolicyRawValue) {
                ForEach(CameraViewfinderControlDefaultPolicy.allCases) { policy in
                    Text(policy.title).tag(policy.rawValue)
                }
            }
        }
    }

    private var viewfinderSettingsSection: some View {
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

            Toggle(isOn: $showsDepthAvailabilityHints) {
                Label("Depth Warnings", systemImage: "rectangle.and.text.magnifyingglass")
            }
        }
    }

    private var cameraBehaviorSection: some View {
        Section("Camera Behavior") {
            Toggle(isOn: $keepScreenAwake) {
                Label("Keep Screen Awake", systemImage: "sun.max")
            }

            Toggle(isOn: $resetEVOnAppLaunch) {
                Label("Reset EV on App Launch", systemImage: "plusminus")
            }

            Toggle(isOn: $returnToCameraOnForeground) {
                Label("Return to Camera After Background", systemImage: "camera.viewfinder")
            }
        }
    }

    private var feedbackSettingsSection: some View {
        Section("Feedback") {
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
    }

    private var analysisSettingsSection: some View {
        Section("Analysis") {
            Toggle(isOn: $showsAnalysisHelp) {
                Label("Help", systemImage: "questionmark.circle")
            }

            Toggle(isOn: $isPlaneGridAnimationEnabled) {
                Label("Grid Growth Animation", systemImage: "square.grid.3x3")
            }

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
        }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
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
            DepthAnalyzerPermissionControlRow(
                title: "Location",
                value: authorizationSnapshot.location,
                systemImage: "location",
                actionTitle: authorizationSnapshot.locationPermissionActionTitle,
                isRequesting: permissionRequester.isRequestingLocation,
                action: performLocationPermissionAction
            )

            Toggle(isOn: $usesLocationData) {
                Label("Use Location Data", systemImage: "location.fill")
            }

            DepthAnalyzerPermissionControlRow(
                title: "Microphone",
                value: authorizationSnapshot.microphone,
                systemImage: "mic",
                actionTitle: authorizationSnapshot.microphonePermissionActionTitle,
                isRequesting: permissionRequester.isRequestingMicrophone,
                action: performMicrophonePermissionAction
            )

            Toggle(isOn: $usesMicrophoneData) {
                Label("Use Microphone Data", systemImage: "mic.fill")
            }

            Text("Capture uses location or microphone data only when system authorization and the app data-use switch are both enabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshAuthorizationSnapshot() {
        authorizationSnapshot = .current()
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
                await permissionRequester.requestMicrophoneAccess()
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
            Picker("Focus Magnifier", selection: $focusMagnifierRawValue) {
                ForEach(CameraFocusMagnifierPreference.allCases) { preference in
                    Text(preference.title).tag(preference.rawValue)
                }
            }
            .listRowBackground(Self.debugOnlySettingsBackground)

            Toggle(isOn: $isLiDARFocusAssistEnabled) {
                Label("LiDAR Focus Assist", systemImage: "scope")
            }
            .listRowBackground(Self.debugOnlySettingsBackground)

            #if TAP_ENABLE_PRO_CAMERA_CONTROLS
            Toggle(isOn: $isManualFocusTapAssistEnabled) {
                Label("Manual Focus Tap Assist", systemImage: "scope")
            }
            .listRowBackground(Self.debugOnlySettingsBackground)
            #endif
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
                LabeledContent("Credential", value: AppAttestRuntimeDefaults.photoCredentialName)
                    .listRowBackground(Self.debugOnlySettingsBackground)

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

            Text(title)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DepthAnalyzerPermissionControlRow: View {
    let title: String
    let value: String
    let systemImage: String
    let actionTitle: String?
    let isRequesting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isRequesting {
                ProgressView()
            } else if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .font(.footnote.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
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

    func requestMicrophoneAccess() async {
        guard !isRequestingMicrophone else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized, .denied, .restricted:
            return
        case .notDetermined:
            isRequestingMicrophone = true
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            isRequestingMicrophone = false
        @unknown default:
            return
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
