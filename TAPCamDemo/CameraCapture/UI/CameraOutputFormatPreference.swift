//
//  CameraOutputFormatPreference.swift
//  TAPCamDemo
//

import Foundation

/// User preference for the reviewed TAP photo-depth output format.
///
/// Settings stores only this small UI value. Runtime still receives a
/// `CaptureOutputProfile` selected through `CaptureOutputProfileCatalog`, so
/// adding a new visible format must also add a reviewed output profile.
nonisolated enum CameraOutputFormatPreference: String, CaseIterable, Identifiable, Sendable {
    case heic
    case jpeg

    static let storageKey = "CameraOutputFormatPreference"
    static let defaultValue = CameraOutputFormatPreference.heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heic:
            "HEIC"
        case .jpeg:
            "JPG"
        }
    }

    var selectionIntent: CaptureOutputProfileSelectionIntent {
        switch self {
        case .heic:
            CaptureOutputProfileSelectionIntent(request: .profile(id: CaptureOutputProfile.releasePhotoDepthHEIC.id))
        case .jpeg:
            CaptureOutputProfileSelectionIntent(request: .profile(id: CaptureOutputProfile.releasePhotoDepthJPEG.id))
        }
    }

    static func resolved(rawValue: String) -> CameraOutputFormatPreference {
        CameraOutputFormatPreference(rawValue: rawValue) ?? defaultValue
    }
}

nonisolated enum CameraPhotoQualityPreference: String, CaseIterable, Identifiable, Sendable {
    case speed
    case balanced
    case quality

    static let storageKey = "CameraPhotoQualityPreference"
    static let defaultValue = CameraPhotoQualityPreference.quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed:
            "Speed"
        case .balanced:
            "Balanced"
        case .quality:
            "Quality"
        }
    }

    var captureQualityLevel: CapturePhotoQualityLevel {
        switch self {
        case .speed:
            .speed
        case .balanced:
            .balanced
        case .quality:
            .quality
        }
    }

    var photoQualityPolicy: CapturePhotoQualityPolicy {
        .release(requested: captureQualityLevel)
    }

    func applied(to profile: CaptureOutputProfile) -> CaptureOutputProfile {
        profile.withPhotoQualityPolicy(photoQualityPolicy)
    }

    static func resolved(rawValue: String) -> CameraPhotoQualityPreference {
        CameraPhotoQualityPreference(rawValue: rawValue) ?? defaultValue
    }

    /// Resolves the capture-prioritization policy that runtime is allowed to use.
    ///
    /// Release builds deliberately ignore any legacy `speed` or `balanced`
    /// preference because capture prioritization is not a supported customer
    /// control. Debug builds can still exercise every AVFoundation policy.
    static func resolvedForRuntime(
        rawValue: String,
        allowsDebugOverride: Bool = _isDebugAssertConfiguration()
    ) -> CameraPhotoQualityPreference {
        guard allowsDebugOverride else {
            return .quality
        }
        return resolved(rawValue: rawValue)
    }
}
