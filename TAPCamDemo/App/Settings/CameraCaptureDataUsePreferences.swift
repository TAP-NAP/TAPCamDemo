//
//  CameraCaptureDataUsePreferences.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum CameraCaptureDataUsePreferences {
    static let usesLocationDataKey = "CameraUsesLocationData"
    static let defaultUsesLocationData = true
    static let usesMicrophoneDataKey = "CameraUsesMicrophoneData"
    static let defaultUsesMicrophoneData = false

    static func usesLocationData(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: usesLocationDataKey) as? Bool ?? defaultUsesLocationData
    }

    static func usesMicrophoneData(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: usesMicrophoneDataKey) as? Bool ?? defaultUsesMicrophoneData
    }

    /// Enables capture-time microphone use after the first successful system
    /// authorization only when the user has never made a choice.
    ///
    /// A current value, including `false`, is authoritative, so later permission
    /// refreshes never re-enable an explicit opt-out.
    @discardableResult
    static func enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
        in userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: usesMicrophoneDataKey) == nil else {
            return false
        }
        userDefaults.set(true, forKey: usesMicrophoneDataKey)
        return true
    }
}
