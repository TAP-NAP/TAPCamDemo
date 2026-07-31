//
//  CameraCaptureDataUsePreferences.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum CameraCaptureDataUsePreferences {
    static let usesLocationDataKey = "CameraUsesLocationData"
    static let defaultUsesLocationData = true
    static let usesMicrophoneDataKey = "CameraUsesMicrophoneData"
    static let legacyUsesMicrophoneDataKey = "CameraLivePhotoSoundEnabled"
    static let defaultUsesMicrophoneData = false

    static func usesLocationData(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: usesLocationDataKey) as? Bool ?? defaultUsesLocationData
    }

    static func usesMicrophoneData(in userDefaults: UserDefaults = .standard) -> Bool {
        migrateLegacyMicrophonePreferenceIfNeeded(in: userDefaults)
        return userDefaults.object(forKey: usesMicrophoneDataKey) as? Bool ?? defaultUsesMicrophoneData
    }

    /// Copies the former Live Photo-specific preference into the neutral
    /// capture-data preference without changing the user's existing choice.
    @discardableResult
    static func migrateLegacyMicrophonePreferenceIfNeeded(
        in userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: usesMicrophoneDataKey) == nil,
              let legacyValue = userDefaults.object(forKey: legacyUsesMicrophoneDataKey) as? Bool else {
            return false
        }

        userDefaults.set(legacyValue, forKey: usesMicrophoneDataKey)
        return true
    }

    /// Enables capture-time microphone use after the first successful system
    /// authorization only when the user has never made a choice.
    ///
    /// A new-key value (including `false`) or a legacy value is authoritative,
    /// so upgrades and later permission refreshes never re-enable an explicit
    /// opt-out.
    @discardableResult
    static func enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
        in userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: usesMicrophoneDataKey) == nil else {
            return false
        }
        if migrateLegacyMicrophonePreferenceIfNeeded(in: userDefaults) {
            return false
        }

        userDefaults.set(true, forKey: usesMicrophoneDataKey)
        return true
    }
}
