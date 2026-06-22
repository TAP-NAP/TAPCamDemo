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
