//
//  CameraCaptureDataUsePreferences.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum CameraCaptureDataUsePreferences {
    static let usesLocationDataKey = "CameraUsesLocationData"
    static let defaultUsesLocationData = true
    static let usesMicrophoneDataKey = "CameraLivePhotoSoundEnabled"
    static let defaultUsesMicrophoneData = false

    static func usesLocationData(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: usesLocationDataKey) as? Bool ?? defaultUsesLocationData
    }

    static func usesMicrophoneData(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: usesMicrophoneDataKey) as? Bool ?? defaultUsesMicrophoneData
    }
}
