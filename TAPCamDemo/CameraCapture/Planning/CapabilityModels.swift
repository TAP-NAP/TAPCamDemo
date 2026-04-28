//
//  CapabilityModels.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Capture-session family used by the SingleCam demo.
///
/// The current implementation runs only still photo + depth through
/// `.singleCam`: one AVFoundation capture pipeline produces the visible photo
/// and Apple's paired `AVCapturePhoto.depthData`.
nonisolated enum CaptureSessionMode: String, Codable, Sendable {
    case singleCam
}

/// User-facing RGB source category.
///
/// A profile may be a physical camera or an Apple virtual camera. UI presents
/// these as sources for the visual RGB image, while pairing logic decides which
/// of them can be represented by a legal photo-depth capture pipeline.
nonisolated enum RGBSourceKind: String, Codable, Sendable {
    case physical
    case virtual
    case depthVirtual
}

/// Stable UI profile for a discoverable RGB source.
///
/// This is the only RGB camera type SwiftUI reads. It intentionally carries
/// display and identity fields beside the underlying `AVCaptureDevice`, because
/// the UI should not inspect AVFoundation directly while the session controller
/// still needs the device object to configure preview/capture.
nonisolated struct CameraProfile: Identifiable, @unchecked Sendable {
    let id: String
    let displayName: String
    let focalLengthLabelSource: String
    let equivalentFocalLength35mmMillimeters: Double?
    let deviceTypeRawValue: String
    let deviceName: String
    let positionDescription: String
    let sourceKind: RGBSourceKind
    let fixedOrder: Int
    let isEnabled: Bool
    let disabledReason: String?
    let referenceZoomFactor: Double
    let device: AVCaptureDevice
}

/// Fixed depth rows shown by the Debug selector.
///
/// Rows are capability concepts, not a sorted list of currently available
/// devices. They stay in this order as RGB source, zoom, or hardware changes
/// only update enabled/disabled state.
nonisolated enum DepthProfileKind: String, Codable, CaseIterable, Sendable {
    case lidarDepth
    case trueDepth
    case dualCameraDisparity
    case dualWideDisparity
    case portraitSemanticDepth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lidarDepth:
            "LiDAR Depth"
        case .trueDepth:
            "TrueDepth"
        case .dualCameraDisparity:
            "Dual Camera Disparity"
        case .dualWideDisparity:
            "Dual Wide Disparity"
        case .portraitSemanticDepth:
            "Portrait / Semantic Depth"
        }
    }

    var fixedOrder: Int {
        switch self {
        case .lidarDepth:
            0
        case .trueDepth:
            1
        case .dualCameraDisparity:
            2
        case .dualWideDisparity:
            3
        case .portraitSemanticDepth:
            4
        }
    }

    var iconName: String {
        switch self {
        case .lidarDepth:
            "dot.radiowaves.left.and.right"
        case .trueDepth:
            "faceid"
        case .dualCameraDisparity, .dualWideDisparity:
            "camera.metering.matrix"
        case .portraitSemanticDepth:
            "viewfinder"
        }
    }
}

/// Availability of a depth row before RGB pairing is considered.
nonisolated enum DepthProfileAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unsupportedFormat
}

/// Result of validating a selected RGB source against a depth row.
///
/// Values are intentionally more specific than a boolean so UI and metrics can
/// explain why a row is grey without re-implementing AVFoundation rules.
nonisolated enum RGBDepthCompatibilityStatus: String, Codable, Equatable, Sendable {
    case compatible
    case requiresMultiCam
    case unsupportedFormat
    case unsupportedZoom
    case releasePackagingUnsupported
    case unavailable
}

/// A video/depth format pair that can produce `AVCapturePhoto.depthData`.
///
/// The capability layer chooses a pair; the session controller applies it on
/// the serial session queue. Keeping the pair as data prevents UI or capture code
/// from mutating `activeFormat` directly.
nonisolated struct PhotoDepthFormatSelection: @unchecked Sendable {
    let videoFormat: AVCaptureDevice.Format
    let depthFormat: AVCaptureDevice.Format
}

/// Candidate AVFoundation device behind one fixed depth row.
nonisolated struct DepthDeviceCandidate: @unchecked Sendable {
    let kind: DepthProfileKind
    let device: AVCaptureDevice
    let formatSelection: PhotoDepthFormatSelection?
}

/// UI-safe depth profile for the current selected RGB source.
///
/// `resolvedDevice` is the device the session would use if this row is selected.
/// For Apple-paired still photo + depth, that device must either be the selected
/// RGB source itself or a virtual device that contains the selected RGB source
/// as a constituent.
nonisolated struct DepthProfile: Identifiable, @unchecked Sendable {
    let id: String
    let kind: DepthProfileKind
    let displayName: String
    let iconName: String
    let fixedOrder: Int
    let availability: DepthProfileAvailability
    let compatibility: RGBDepthCompatibilityStatus
    let disabledReason: String?
    let resolvedDevice: AVCaptureDevice?
    let formatSelection: PhotoDepthFormatSelection?

    var isSelectable: Bool {
        availability == .available && compatibility == .compatible
    }
}

/// Debug-only depth device row independent from Release FOV pairing.
///
/// The Release UI asks for a visual FOV and lets the capability layer resolve an
/// Apple-paired depth pipeline. Debug exploration needs a different surface: it
/// lists the depth-capable devices themselves, then lets the engineer override
/// the whole single-cam preview/capture pipeline to that device. This type
/// intentionally does not encode compatibility with the current Release FOV.
nonisolated struct DebugDepthDeviceOption: Identifiable, @unchecked Sendable {
    let id: String
    let kind: DepthProfileKind
    let displayName: String
    let iconName: String
    let fixedOrder: Int
    let availability: DepthProfileAvailability
    let disabledReason: String?
    let deviceName: String?
    let deviceTypeRawValue: String?
    let device: AVCaptureDevice?
    let rgbSource: CameraProfile?
    let formatSelection: PhotoDepthFormatSelection?

    var isSelectable: Bool {
        availability == .available
            && device != nil
            && rgbSource != nil
            && formatSelection != nil
    }

    func depthProfile(formatSelection: PhotoDepthFormatSelection) -> DepthProfile? {
        guard isSelectable,
              let device else {
            return nil
        }

        return DepthProfile(
            id: id,
            kind: kind,
            displayName: displayName,
            iconName: iconName,
            fixedOrder: fixedOrder,
            availability: availability,
            compatibility: .compatible,
            disabledReason: nil,
            resolvedDevice: device,
            formatSelection: formatSelection
        )
    }
}

/// A raw zoom choice for the active RGB-depth pairing.
///
/// Debug presents some of these as compact `0.5x/1x/2x/3x` chips. Release uses
/// the same value type behind semantic FOV labels, so the important invariant is
/// that `rawVideoZoomFactor` reaches `CaptureSessionController` unchanged.
nonisolated struct ZoomProfile: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let rawVideoZoomFactor: Double
    let isEnabled: Bool
    let disabledReason: String?

    /// Raw zoom value requested from `AVCaptureDevice.videoZoomFactor`.
    ///
    /// Release FOV labels are semantic (`24mm`, `48mm`, `77mm`); this value is
    /// the lower-level zoom number that must survive planning and reach the
    /// session controller. On some depth-capable virtual formats, `48mm` is raw
    /// `4.0` rather than the visually familiar `2x`.
    var requestedZoomFactor: Double {
        rawVideoZoomFactor
    }

    func matchesRawVideoZoomFactor(_ zoomFactor: Double) -> Bool {
        abs(rawVideoZoomFactor - zoomFactor) < 0.001
    }

    nonisolated static func enabled(_ zoom: Double, displayZoomFactor: Double? = nil) -> ZoomProfile {
        ZoomProfile(
            id: id(for: zoom),
            displayName: displayName(for: displayZoomFactor ?? zoom),
            rawVideoZoomFactor: zoom,
            isEnabled: true,
            disabledReason: nil
        )
    }

    nonisolated static func disabled(_ zoom: Double, displayZoomFactor: Double? = nil, reason: String) -> ZoomProfile {
        ZoomProfile(
            id: id(for: zoom),
            displayName: displayName(for: displayZoomFactor ?? zoom),
            rawVideoZoomFactor: zoom,
            isEnabled: false,
            disabledReason: reason
        )
    }

    private nonisolated static func id(for zoom: Double) -> String {
        /*
         IDs intentionally stay tied to the raw `videoZoomFactor`. Display names
         can be semantic, such as raw 2.0 showing as 1x when that raw value is
         the 24mm baseline for a virtual depth format.
         */
        let safeValue = displayName(for: zoom).replacingOccurrences(of: ".", with: "_")
        return "zoom-\(safeValue)"
    }

    private nonisolated static func displayName(for zoom: Double) -> String {
        if abs(zoom.rounded() - zoom) < 0.01 {
            return "\(Int(zoom.rounded()))x"
        }
        return String(format: "%.1fx", zoom)
    }
}

/// Snapshot of runtime zoom support for a resolved capture plan.
///
/// This type reads from `AVCaptureDevice.Format` and produces the depth-safe
/// range used by UI and capture planning. It does not mutate the session.
nonisolated struct ZoomCapability: Equatable, Sendable {
    let available: Bool
    let currentZoomFactor: Double?
    let videoMaxZoomFactor: Double
    let minAvailableVideoZoomFactor: Double
    let maxAvailableVideoZoomFactor: Double
    let systemRecommendedVideoZoomRange: ClosedRange<Double>?
    let supportedVideoZoomRangesForDepthDataDelivery: [ClosedRange<Double>]
    let zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported: Bool
    let virtualDeviceSwitchOverVideoZoomFactors: [Double]
    let depthSafeZoomRanges: [ClosedRange<Double>]
    let isContinuous: Bool
    let isDiscrete: Bool
    let zoomProfiles: [ZoomProfile]
}

/// One user-facing field-of-view choice in the camera UI.
///
/// Release presents these options instead of separate "camera source" and
/// "zoom" controls. Each option already resolves to a concrete RGB source,
/// automatic Apple-paired depth source, and depth-safe `videoZoomFactor`.
/// Debug can keep disabled options visible for hardware exploration; Release
/// filters them out.
nonisolated struct FocalLengthOption: Identifiable, @unchecked Sendable {
    let id: String
    let displayName: String
    let numericLabel: String
    let unitLabel: String
    let equivalentFocalLength35mmMillimeters: Double
    let labelSource: String
    let rgbSource: CameraProfile
    let depthSource: DepthProfile?
    let zoom: ZoomProfile
    let isEnabled: Bool
    let disabledReason: String?
}
