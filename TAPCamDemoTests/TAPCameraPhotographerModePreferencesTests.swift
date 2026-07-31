//
//  TAPCameraPhotographerModePreferencesTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraPhotographerModePreferencesTests {
    @Test func startupPolicyResolvesPhotographerModeIntent() {
        #expect(!CameraPhotographerModePreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOff.rawValue,
            lastPreferredEnabled: true
        ))
        #expect(CameraPhotographerModePreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOn.rawValue,
            lastPreferredEnabled: false
        ))
        #expect(CameraPhotographerModePreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            lastPreferredEnabled: true
        ))
        #expect(!CameraPhotographerModePreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            lastPreferredEnabled: false
        ))
        #expect(!CameraPhotographerModePreferences.resolvedStartupIsEnabled(
            policyRawValue: "unexpected",
            lastPreferredEnabled: true
        ))
    }

    @Test func persistedStartupPolicyDefaultsOffAndRemembersUserIntent() throws {
        let suiteName = "TAPCameraPhotographerModePreferencesTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraPhotographerModePreferences.defaultStartupPolicy == .defaultOff)
        #expect(!CameraPhotographerModePreferences.defaultLastPreferredEnabled)
        #expect(!CameraPhotographerModePreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.defaultOn.rawValue,
            forKey: CameraPhotographerModePreferences.startupPolicyKey
        )
        #expect(CameraPhotographerModePreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            forKey: CameraPhotographerModePreferences.startupPolicyKey
        )
        #expect(!CameraPhotographerModePreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.set(true, forKey: CameraPhotographerModePreferences.lastPreferredEnabledKey)
        #expect(CameraPhotographerModePreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.defaultOff.rawValue,
            forKey: CameraPhotographerModePreferences.startupPolicyKey
        )
        #expect(!CameraPhotographerModePreferences.resolvedStartupIsEnabled(in: userDefaults))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func photographerModeStartupPickerIsUserVisibleAndKeepsOnlyFunctionalDebugFocusControls() throws {
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let cameraSettingsStart = try #require(settingsSource.range(of: "private var cameraSettingsSection"))
        let interfaceSettingsStart = try #require(settingsSource.range(of: "private var interfaceSettingsSection"))
        let cameraSettingsSection = String(
            settingsSource[cameraSettingsStart.lowerBound..<interfaceSettingsStart.lowerBound]
        )

        #expect(settingsSource.contains("@AppStorage(CameraPhotographerModePreferences.startupPolicyKey)"))
        #expect(cameraSettingsSection.contains(#"Section("Camera Settings")"#))
        #expect(cameraSettingsSection.contains(#"Picker("Photographer Mode Startup", selection: $photographerModeStartupPolicyRawValue)"#))
        #expect(cameraSettingsSection.contains("CameraViewfinderControlDefaultPolicy.allCases"))
        #expect(!cameraSettingsSection.contains("requires a rear LiDAR camera"))
        #expect(!cameraSettingsSection.contains("Unsupported devices fall back to Standard mode at runtime"))
        #expect(settingsSource.contains(#"Section("Debug Camera Controls")"#))
        #expect(settingsSource.contains("Focus Magnifier"))
        #expect(!settingsSource.contains("LiDAR Focus Assist"))
        #expect(!settingsSource.contains("CameraLiDARFocusAssistPreferences"))
        #expect(!settingsSource.contains("Manual Focus Tap Assist"))
        #expect(!settingsSource.contains("TAP_ENABLE_PRO_CAMERA_CONTROLS"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func rememberedPhotographerPreferenceOnlyChangesAfterASuccessfulExplicitToggle() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )

        #expect(source.contains("pendingPhotographerModePreference = shouldEnable"))
        #expect(source.contains("releaseCameraPathTransitionPresentation"))
        #expect(source.contains("persistPhotographerModePreferenceAfterSuccessfulToggle("))
        #expect(source.contains("viewModel.photographerModeState == .active"))
        #expect(source.contains("viewModel.photographerModeState == .standard"))
        #expect(source.contains("lastPhotographerModePreferredEnabled = isEnabled"))
        #expect(!source.contains("lastPhotographerModePreferredEnabled = isPhotographerModePreferredForRearCamera"))
        #expect(!source.contains("persistPhotographerModePreferenceIfNeeded()"))
    }
}
