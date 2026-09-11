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
        #expect(userDefaults.bool(forKey: CameraPhotographerModePreferences.lastPreferredEnabledKey))

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            forKey: CameraPhotographerModePreferences.startupPolicyKey
        )
        #expect(CameraPhotographerModePreferences.resolvedStartupIsEnabled(in: userDefaults))
    }

}
