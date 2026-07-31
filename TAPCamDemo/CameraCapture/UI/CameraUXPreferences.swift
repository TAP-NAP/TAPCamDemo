//
//  CameraUXPreferences.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI
import UIKit

nonisolated enum CameraGuideOverlayPreference: String, CaseIterable, Identifiable, Sendable {
    case off
    case ruleOfThirds
    case centerCross

    static let storageKey = "CameraGuideOverlayPreference"
    static let defaultValue = CameraGuideOverlayPreference.off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .ruleOfThirds:
            "Rule of Thirds"
        case .centerCross:
            "Center Cross"
        }
    }

    static func resolved(rawValue: String) -> CameraGuideOverlayPreference {
        CameraGuideOverlayPreference(rawValue: rawValue) ?? defaultValue
    }
}

nonisolated enum CameraViewfinderHighlightPreference: String, CaseIterable, Identifiable, Sendable {
    case yellow
    case titian

    static let storageKey = "CameraViewfinderHighlightPreference"
    static let defaultValue = CameraViewfinderHighlightPreference.yellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow:
            "Yellow"
        case .titian:
            "Titian"
        }
    }

    var color: Color {
        switch self {
        case .yellow:
            .yellow
        case .titian:
            Color(red: 183.0 / 255.0, green: 40.0 / 255.0, blue: 46.0 / 255.0)
        }
    }

    static func resolved(rawValue: String) -> CameraViewfinderHighlightPreference {
        CameraViewfinderHighlightPreference(rawValue: rawValue) ?? defaultValue
    }
}

nonisolated enum CameraEVPreferences {
    static let resetOnAppLaunchKey = "CameraResetEVOnAppLaunch"
    static let defaultResetOnAppLaunch = true
    static let globalBiasKey = "CameraGlobalEVBias"
    static let launchResetProcessIDKey = "CameraGlobalEVLaunchResetProcessID"
    static let defaultGlobalBias = 0.0
    static let minimumGlobalBias = -2.0
    static let maximumGlobalBias = 2.0
    static let adjustmentStep = 0.1

    static func clampedBias(_ value: Double) -> Double {
        guard value.isFinite else {
            return defaultGlobalBias
        }
        return min(max(value, minimumGlobalBias), maximumGlobalBias)
    }

    static func resolvedLaunchBias(in userDefaults: UserDefaults = .standard) -> Double {
        let shouldResetOnLaunch = userDefaults.object(forKey: resetOnAppLaunchKey) as? Bool
            ?? defaultResetOnAppLaunch
        let currentProcessID = Int(ProcessInfo.processInfo.processIdentifier)
        if shouldResetOnLaunch,
           userDefaults.integer(forKey: launchResetProcessIDKey) != currentProcessID {
            userDefaults.set(currentProcessID, forKey: launchResetProcessIDKey)
            userDefaults.set(defaultGlobalBias, forKey: globalBiasKey)
            return defaultGlobalBias
        }

        return clampedBias(userDefaults.object(forKey: globalBiasKey) as? Double ?? defaultGlobalBias)
    }

    static func persistGlobalBias(_ value: Double, in userDefaults: UserDefaults = .standard) {
        userDefaults.set(clampedBias(value), forKey: globalBiasKey)
    }
}

nonisolated enum CameraTemporaryFocusEVPreferences {
    static let minimumOffset = -2.0
    static let maximumOffset = 2.0
    static let adjustmentStep = 0.1

    static func clampedOffset(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, minimumOffset), maximumOffset)
    }
}

nonisolated enum CameraDepthAvailabilityHintPreferences {
    static let showsHintsKey = "CameraDepthAvailabilityHintsEnabled"
    static let defaultShowsHints = true

    /// Depth availability remains an always-on product hint in Release.
    /// Debug builds retain the stored switch for diagnostics.
    static func resolvedShowsHints(
        storedValue: Bool,
        allowsDebugOverride: Bool = _isDebugAssertConfiguration()
    ) -> Bool {
        allowsDebugOverride ? storedValue : defaultShowsHints
    }
}

nonisolated enum CameraFocusMagnifierPreference: String, CaseIterable, Identifiable, Sendable {
    case off
    case brief
    case standard
    case extended

    static let storageKey = "CameraFocusMagnifierPreference"
    static let defaultValue = CameraFocusMagnifierPreference.brief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .brief:
            "1.5s"
        case .standard:
            "3s"
        case .extended:
            "5s"
        }
    }

    var duration: Duration? {
        switch self {
        case .off:
            nil
        case .brief:
            .milliseconds(1_500)
        case .standard:
            .seconds(3)
        case .extended:
            .seconds(5)
        }
    }

    static func resolved(rawValue: String) -> CameraFocusMagnifierPreference {
        CameraFocusMagnifierPreference(rawValue: rawValue) ?? defaultValue
    }
}

nonisolated enum CameraViewfinderControlDefaultPolicy: String, CaseIterable, Identifiable, Sendable {
    case defaultOff
    case defaultOn
    case rememberLastState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultOff:
            "Default Off"
        case .defaultOn:
            "Default On"
        case .rememberLastState:
            "Remember Last State"
        }
    }

    static func resolved(
        rawValue: String,
        fallback: CameraViewfinderControlDefaultPolicy
    ) -> CameraViewfinderControlDefaultPolicy {
        CameraViewfinderControlDefaultPolicy(rawValue: rawValue) ?? fallback
    }
}

nonisolated enum CameraPhotographerModePreferences {
    static let startupPolicyKey = "CameraPhotographerModeStartupPolicy"
    static let defaultStartupPolicy = CameraViewfinderControlDefaultPolicy.defaultOff
    static let lastPreferredEnabledKey = "CameraPhotographerModeLastPreferredEnabled"
    static let defaultLastPreferredEnabled = false

    static func resolvedStartupIsEnabled(
        policyRawValue: String,
        lastPreferredEnabled: Bool
    ) -> Bool {
        switch CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: policyRawValue,
            fallback: defaultStartupPolicy
        ) {
        case .defaultOff:
            return false
        case .defaultOn:
            return true
        case .rememberLastState:
            return lastPreferredEnabled
        }
    }

    static func resolvedStartupIsEnabled(in userDefaults: UserDefaults = .standard) -> Bool {
        let policyRawValue = userDefaults.string(forKey: startupPolicyKey) ?? defaultStartupPolicy.rawValue
        let lastPreferredEnabled = userDefaults.object(forKey: lastPreferredEnabledKey) as? Bool
            ?? defaultLastPreferredEnabled
        return resolvedStartupIsEnabled(
            policyRawValue: policyRawValue,
            lastPreferredEnabled: lastPreferredEnabled
        )
    }
}

nonisolated enum CameraLivePhotoPreferences {
    static let startupPolicyKey = "CameraLivePhotoStartupPolicy"
    static let defaultStartupPolicy = CameraViewfinderControlDefaultPolicy.rememberLastState
    static let lastEnabledKey = "CameraLivePhotoLastEnabled"
    static let defaultLastEnabled = false
    static let legacyIsEnabledKey = "CameraLivePhotoEnabled"
    static let soundEnabledKey = "CameraLivePhotoSoundEnabled"
    static let defaultSoundEnabled = false

    static func resolvedStartupIsEnabled(
        policyRawValue: String,
        lastIsEnabled: Bool
    ) -> Bool {
        switch CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: policyRawValue,
            fallback: defaultStartupPolicy
        ) {
        case .defaultOff:
            return false
        case .defaultOn:
            return true
        case .rememberLastState:
            return lastIsEnabled
        }
    }

    static func resolvedStartupIsEnabled(in userDefaults: UserDefaults = .standard) -> Bool {
        let policyRawValue = userDefaults.string(forKey: startupPolicyKey) ?? defaultStartupPolicy.rawValue
        let lastIsEnabled = userDefaults.object(forKey: lastEnabledKey) as? Bool
            ?? userDefaults.object(forKey: legacyIsEnabledKey) as? Bool
            ?? defaultLastEnabled
        return resolvedStartupIsEnabled(
            policyRawValue: policyRawValue,
            lastIsEnabled: lastIsEnabled
        )
    }
}

nonisolated enum CameraIdleTimerPreferences {
    static let keepScreenAwakeKey = "CameraKeepScreenAwake"
    static let defaultKeepScreenAwake = true
}

nonisolated struct CameraPreviewFocusPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = Self.clampedUnitValue(x)
        self.y = Self.clampedUnitValue(y)
    }

    func mappedThroughVisibleCrop(_ crop: CropRectNormalized) -> CameraPreviewFocusPoint {
        CameraPreviewFocusPoint(
            x: crop.x + x * crop.width,
            y: crop.y + y * crop.height
        )
    }

    private static func clampedUnitValue(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0.5
        }
        return min(max(value, 0), 1)
    }
}

nonisolated enum CameraFocusLockRequest: Equatable, Sendable {
    case lockCurrent(displayPoint: CameraPreviewFocusPoint)
    case refocusAndLock(displayPoint: CameraPreviewFocusPoint, capturePoint: CameraPreviewFocusPoint)

    var displayPoint: CameraPreviewFocusPoint {
        switch self {
        case .lockCurrent(let displayPoint),
             .refocusAndLock(let displayPoint, _):
            displayPoint
        }
    }

    var capturePoint: CameraPreviewFocusPoint? {
        switch self {
        case .lockCurrent:
            nil
        case .refocusAndLock(_, let capturePoint):
            capturePoint
        }
    }
}

nonisolated enum CameraFocusTargetOverlayPhase: Equatable, Sendable {
    case focusing
    case focused
    case locked
}

nonisolated struct CameraFocusRuntimeEvent: Equatable, Identifiable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case focusStarted
        case focusSettled
        case subjectAreaChanged
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

nonisolated struct CameraExposureRuntimeEvent: Equatable, Identifiable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case exposureStarted
        case exposureSettled
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

nonisolated struct CameraFocusTargetOverlay: Equatable, Identifiable, Sendable {
    let id: UUID
    let point: CameraPreviewFocusPoint
    let phase: CameraFocusTargetOverlayPhase

    init(
        id: UUID = UUID(),
        point: CameraPreviewFocusPoint,
        phase: CameraFocusTargetOverlayPhase
    ) {
        self.id = id
        self.point = point
        self.phase = phase
    }

    static func focusing(at point: CameraPreviewFocusPoint) -> CameraFocusTargetOverlay {
        CameraFocusTargetOverlay(point: point, phase: .focusing)
    }

    var isLocked: Bool {
        phase == .locked
    }

    func lockedOverlay(at point: CameraPreviewFocusPoint? = nil) -> CameraFocusTargetOverlay {
        let lockedPoint = point ?? self.point
        if lockedPoint == self.point {
            return CameraFocusTargetOverlay(id: id, point: lockedPoint, phase: .locked)
        }
        return CameraFocusTargetOverlay(point: lockedPoint, phase: .locked)
    }

    func contains(
        _ point: CameraPreviewFocusPoint,
        previewSize: CGSize,
        sideLength: CGFloat
    ) -> Bool {
        let halfSide = max(sideLength, 0) / 2
        let horizontalDistance = abs(CGFloat(point.x - self.point.x) * max(previewSize.width, 1))
        let verticalDistance = abs(CGFloat(point.y - self.point.y) * max(previewSize.height, 1))
        return horizontalDistance <= halfSide && verticalDistance <= halfSide
    }

    func applyingRuntimeEvent(_ event: CameraFocusRuntimeEvent.Kind) -> CameraFocusTargetOverlay? {
        guard !isLocked else {
            return self
        }

        switch (phase, event) {
        case (.focusing, .focusStarted):
            return self
        case (.focusing, .focusSettled), (.focused, .focusSettled):
            return CameraFocusTargetOverlay(id: id, point: point, phase: .focused)
        case (.focusing, .subjectAreaChanged),
             (.focused, .subjectAreaChanged),
             (.focused, .focusStarted):
            return nil
        case (.locked, _):
            return self
        }
    }
}

nonisolated enum CameraIdleTimerPolicy {
    static func shouldDisableIdleTimer(
        keepScreenAwake: Bool,
        isCameraViewVisible: Bool,
        isActiveScene: Bool,
        isSettingsPresented: Bool,
        isLibraryPresented: Bool
    ) -> Bool {
        keepScreenAwake
            && isCameraViewVisible
            && isActiveScene
            && !isSettingsPresented
            && !isLibraryPresented
    }
}

/// Coalesces capture-session preference changes while Settings is presented.
///
/// Presentation-only preferences never enter this gate. Callers feed it only
/// changes that alter the AVFoundation graph or capture output configuration.
nonisolated struct CameraSettingsSessionReconfigurationPolicy: Equatable, Sendable {
    private(set) var hasPendingReconfiguration = false

    mutating func capturePreferenceDidChange(isSettingsPresented: Bool) -> Bool {
        guard isSettingsPresented else {
            return true
        }
        hasPendingReconfiguration = true
        return false
    }

    mutating func settingsDidDismiss() -> Bool {
        guard hasPendingReconfiguration else {
            return false
        }
        hasPendingReconfiguration = false
        return true
    }
}

@MainActor
enum CameraIdleTimerController {
    static func setCameraScreenIdleTimerDisabled(_ isDisabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isDisabled
    }
}

nonisolated enum CameraFocusControlMode: String, Equatable, Sendable {
    case auto
    case manual

    var title: String {
        switch self {
        case .auto:
            "AF"
        case .manual:
            "MF"
        }
    }

    var toggled: CameraFocusControlMode {
        switch self {
        case .auto:
            .manual
        case .manual:
            .auto
        }
    }
}

nonisolated enum CameraAdjustmentControl: String, Equatable, Identifiable, Sendable {
    case ev
    case iso
    case shutter
    case focus

    var id: String { rawValue }
}

nonisolated enum CameraFlashControlMode: String, CaseIterable, Equatable, Identifiable, Sendable {
    case auto
    case on
    case off

    static let allCases: [CameraFlashControlMode] = [.off, .auto, .on]
    static let defaultModeKey = "CameraDefaultFlashMode"
    static let defaultValue = CameraFlashControlMode.auto
    static let startupPolicyKey = "CameraFlashStartupPolicy"
    static let defaultStartupPolicy = CameraViewfinderControlDefaultPolicy.defaultOn
    static let lastModeKey = "CameraLastFlashMode"
    static let defaultLastMode = CameraFlashControlMode.auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "Auto"
        case .on:
            "On"
        case .off:
            "Off"
        }
    }

    var settingsTitle: String {
        switch self {
        case .auto:
            "Auto"
        case .on:
            "Always On"
        case .off:
            "Off"
        }
    }

    var systemImage: String {
        switch self {
        case .auto:
            "bolt.badge.automatic"
        case .on:
            "bolt.fill"
        case .off:
            "bolt.slash"
        }
    }

    var next: CameraFlashControlMode {
        switch self {
        case .auto:
            .on
        case .on:
            .off
        case .off:
            .auto
        }
    }

    static func resolved(rawValue: String) -> CameraFlashControlMode {
        CameraFlashControlMode(rawValue: rawValue) ?? defaultValue
    }

    static func resolvedDefault(in userDefaults: UserDefaults = .standard) -> CameraFlashControlMode {
        let rawValue = userDefaults.string(forKey: defaultModeKey) ?? defaultValue.rawValue
        return resolved(rawValue: rawValue)
    }

    static func resolvedStartupMode(
        policyRawValue: String,
        lastModeRawValue: String
    ) -> CameraFlashControlMode {
        switch CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: policyRawValue,
            fallback: defaultStartupPolicy
        ) {
        case .defaultOff:
            return .off
        case .defaultOn:
            return .auto
        case .rememberLastState:
            return resolved(rawValue: lastModeRawValue)
        }
    }

    static func resolvedStartupMode(in userDefaults: UserDefaults = .standard) -> CameraFlashControlMode {
        let policyRawValue = userDefaults.string(forKey: startupPolicyKey) ?? defaultStartupPolicy.rawValue
        let lastModeRawValue = userDefaults.string(forKey: lastModeKey)
            ?? userDefaults.string(forKey: defaultModeKey)
            ?? defaultLastMode.rawValue
        return resolvedStartupMode(
            policyRawValue: policyRawValue,
            lastModeRawValue: lastModeRawValue
        )
    }

    var captureFlashMode: CaptureFlashMode {
        switch self {
        case .auto:
            .auto
        case .on:
            .on
        case .off:
            .off
        }
    }
}

nonisolated enum CameraCaptureModeOption: String, CaseIterable, Identifiable, Sendable {
    case photo
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo:
            "PHOTO"
        case .video:
            "VIDEO"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .photo:
            "Photo mode"
        case .video:
            "Video mode"
        }
    }

    var comingSoonAccessibilityLabel: String {
        switch self {
        case .photo:
            "Photo mode coming soon"
        case .video:
            "Video mode coming soon"
        }
    }

    var isAvailableInStageOne: Bool {
        true
    }
}
