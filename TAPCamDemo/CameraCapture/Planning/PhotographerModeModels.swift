//
//  PhotographerModeModels.swift
//  TAPCamDemo
//

import Foundation

/// The rear-camera workflow that should be restored after a temporary trip to
/// the front camera.
nonisolated enum PhotographerRearModeIntent: Equatable, Sendable {
    case standard
    case photographer
}

/// Stable mode that remained usable after a configuration attempt.
nonisolated enum PhotographerModeStableMode: Equatable, Sendable {
    case standard
    case photographer
    case unconfigured
}

/// Capability failure that prevents the Release photographer workflow from
/// safely exposing ISO, shutter, and manual focus controls.
nonisolated enum PhotographerModeUnavailableReason: Equatable, Sendable {
    case rearLiDARUnavailable
    case oneXDepthFormatUnavailable
    case photoDepthDeliveryUnavailable
    case customExposureUnavailable
    case manualFocusUnavailable
    case configurationFailed

    var message: String {
        switch self {
        case .rearLiDARUnavailable:
            "Photographer mode requires a rear LiDAR camera."
        case .oneXDepthFormatUnavailable:
            "LiDAR 24mm depth capture is unavailable."
        case .photoDepthDeliveryUnavailable:
            "LiDAR photo depth delivery is unavailable."
        case .customExposureUnavailable:
            "LiDAR ISO and shutter controls are unavailable."
        case .manualFocusUnavailable:
            "LiDAR manual focus is unavailable."
        case .configurationFailed:
            "Unable to configure Photographer mode."
        }
    }
}

/// Hardware eligibility is intentionally independent from the current camera
/// position. A supported phone stays eligible while the front camera is active;
/// the UI can hide its PRO entry until the user returns to the rear camera.
nonisolated enum PhotographerModeAvailability: Equatable, Sendable {
    case available
    case unavailable(PhotographerModeUnavailableReason)

    var isAvailable: Bool {
        self == .available
    }

    var unavailableReason: PhotographerModeUnavailableReason? {
        guard case .unavailable(let reason) = self else {
            return nil
        }
        return reason
    }

    /// Resolves Release eligibility from value-only facts so the contract can
    /// be tested without constructing AVFoundation runtime objects.
    static func resolve(_ facts: PhotographerModeCapabilityFacts) -> PhotographerModeAvailability {
        guard facts.isRearLiDARDevice else {
            return .unavailable(.rearLiDARUnavailable)
        }
        guard facts.hasOneXDepthFormat else {
            return .unavailable(.oneXDepthFormatUnavailable)
        }
        guard facts.supportsPhotoDepthDelivery else {
            return .unavailable(.photoDepthDeliveryUnavailable)
        }
        guard facts.supportsCustomExposure,
              facts.hasAdjustableISORange,
              facts.hasAdjustableShutterRange else {
            return .unavailable(.customExposureUnavailable)
        }
        guard facts.supportsLockedFocus,
              facts.supportsCustomLensPosition else {
            return .unavailable(.manualFocusUnavailable)
        }
        return .available
    }
}

/// Published runtime state. The effective stable mode remains explicit on a
/// failure so UI and capture guards never infer it from button appearance.
nonisolated enum PhotographerModeState: Equatable, Sendable {
    case unavailable(PhotographerModeUnavailableReason)
    case standard
    case activating
    case active
    case deactivating
    case failed(recoveredMode: PhotographerModeStableMode, reason: PhotographerModeUnavailableReason)

    var isTransitioning: Bool {
        switch self {
        case .activating, .deactivating:
            true
        case .unavailable, .standard, .active, .failed:
            false
        }
    }

    var isActive: Bool {
        switch self {
        case .active, .deactivating:
            true
        case .failed(let recoveredMode, _):
            recoveredMode == .photographer
        case .unavailable, .standard, .activating:
            false
        }
    }

    var effectiveMode: PhotographerModeStableMode {
        switch self {
        case .active, .deactivating:
            .photographer
        case .failed(let recoveredMode, _):
            recoveredMode
        case .unavailable, .standard, .activating:
            .standard
        }
    }

    /// No camera path survived the requested transition. The UI must keep the
    /// preview suspended beneath the frost while Runtime rebuilds Standard.
    var requiresStandardRecovery: Bool {
        guard case .failed(let recoveredMode, _) = self else {
            return false
        }
        return recoveredMode == .unconfigured
    }
}

/// Value-only input used by both discovery preflight and post-configuration
/// runtime validation.
nonisolated struct PhotographerModeCapabilityFacts: Equatable, Sendable {
    let isRearLiDARDevice: Bool
    let hasOneXDepthFormat: Bool
    let supportsPhotoDepthDelivery: Bool
    let supportsCustomExposure: Bool
    let hasAdjustableISORange: Bool
    let hasAdjustableShutterRange: Bool
    let supportsLockedFocus: Bool
    let supportsCustomLensPosition: Bool
}

/// Standard selection restored when the user leaves PRO. This stores semantic
/// selection IDs rather than AVFoundation handles.
nonisolated struct StandardCameraSelectionSnapshot: Equatable, Sendable {
    let rgbSourceID: String?
    let focalLengthOptionID: String?
    let zoomID: String?
    let previewCropRectNormalized: CropRectNormalized
}
