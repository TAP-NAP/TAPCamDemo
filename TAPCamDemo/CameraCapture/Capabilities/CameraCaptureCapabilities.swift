//
//  CameraCaptureCapabilities.swift
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
/// Values are intentionally more specific than a boolean so UI, diagnostics,
/// and diagnostics can explain why a row is grey without re-implementing
/// AVFoundation rules in the presentation layer.
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

    nonisolated static func enabled(_ zoom: Double) -> ZoomProfile {
        ZoomProfile(
            id: id(for: zoom),
            displayName: displayName(for: zoom),
            rawVideoZoomFactor: zoom,
            isEnabled: true,
            disabledReason: nil
        )
    }

    nonisolated static func disabled(_ zoom: Double, reason: String) -> ZoomProfile {
        ZoomProfile(
            id: id(for: zoom),
            displayName: displayName(for: zoom),
            rawVideoZoomFactor: zoom,
            isEnabled: false,
            disabledReason: reason
        )
    }

    private nonisolated static func id(for zoom: Double) -> String {
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

/// Normalized metadata rectangle describing what the preview showed.
///
/// Values are in the metadata-output coordinate space used by
/// `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`.
/// Release records this only as metadata; it does not destructively crop
/// the RGB image or the depth map.
nonisolated struct CropRectNormalized: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static let fullFrame = CropRectNormalized(x: 0, y: 0, width: 1, height: 1)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(metadataRect rect: CGRect) {
        let standardized = rect.standardized
        self.x = Double(min(max(standardized.origin.x, 0), 1))
        self.y = Double(min(max(standardized.origin.y, 0), 1))
        self.width = Double(min(max(standardized.width, 0), 1))
        self.height = Double(min(max(standardized.height, 0), 1))
    }
}

/// Complete capability surface consumed by `CameraViewModel`.
///
/// The matrix is rebuilt from AVFoundation discovery at launch, then queried as
/// value data when the selected RGB source, depth row, zoom, or crop metadata
/// changes. SwiftUI never makes direct `AVCaptureDevice` decisions.
nonisolated struct CapabilityMatrix: @unchecked Sendable {
    let rgbSources: [CameraProfile]
    let depthCandidates: [DepthDeviceCandidate]

    var defaultRGBSource: CameraProfile? {
        rgbSources
            .filter(\.isEnabled)
            .max { lhs, rhs in
                CameraCapabilityResolver.automaticPriority(for: lhs.device.deviceType) < CameraCapabilityResolver.automaticPriority(for: rhs.device.deviceType)
            }
    }

    func rgbSource(id: String?) -> CameraProfile? {
        guard let id else {
            return defaultRGBSource
        }
        return rgbSources.first(where: { $0.id == id })
    }

    func depthProfiles(
        for rgbSource: CameraProfile,
        preferredZoomFactor: Double? = nil
    ) -> [DepthProfile] {
        DepthProfileKind.allCases.map { kind in
            let candidate = depthCandidates.first(where: { $0.kind == kind })
            let availability = availability(for: kind, candidate: candidate)
            let pairing = RGBDepthCompatibilityMatrix.evaluate(
                rgbSource: rgbSource,
                depthKind: kind,
                candidate: candidate,
                preferredZoomFactor: preferredZoomFactor
            )

            return DepthProfile(
                id: kind.id,
                kind: kind,
                displayName: kind.displayName,
                iconName: kind.iconName,
                fixedOrder: kind.fixedOrder,
                availability: availability,
                compatibility: pairing.status,
                disabledReason: pairing.reason,
                resolvedDevice: pairing.resolvedDevice,
                formatSelection: pairing.formatSelection
            )
        }
        .sorted { $0.fixedOrder < $1.fixedOrder }
    }

    func bestCompatibleDepthProfile(for rgbSource: CameraProfile) -> DepthProfile? {
        depthProfiles(for: rgbSource)
            .first(where: \.isSelectable)
    }

    func bestCompatibleDepthProfile(for rgbSource: CameraProfile, preferredZoomFactor: Double) -> DepthProfile? {
        depthProfiles(
            for: rgbSource,
            preferredZoomFactor: preferredZoomFactor
        )
        .first(where: \.isSelectable)
    }

    func debugDepthDeviceOptions() -> [DebugDepthDeviceOption] {
        DepthProfileKind.allCases
            .map { kind in
            let candidate = depthCandidates.first(where: { $0.kind == kind })
            let availability = availability(for: kind, candidate: candidate)
            let rgbSource = candidate.map { candidate in
                rgbSources.first(where: { $0.id == candidate.device.uniqueID })
                    ?? CameraCapabilityResolver.debugCameraProfile(for: candidate.device, depthCandidates: depthCandidates)
            }

            return DebugDepthDeviceOption(
                id: kind.id,
                kind: kind,
                displayName: kind.displayName,
                iconName: kind.iconName,
                fixedOrder: kind.fixedOrder,
                availability: availability,
                disabledReason: debugDepthDeviceDisabledReason(
                    availability: availability,
                    rgbSource: rgbSource
                ),
                deviceName: candidate?.device.localizedName,
                deviceTypeRawValue: candidate?.device.deviceType.rawValue,
                device: candidate?.device,
                rgbSource: rgbSource,
                formatSelection: candidate?.formatSelection
            )
        }
        .sorted { $0.fixedOrder < $1.fixedOrder }
    }

    func focalLengthOptions() -> [FocalLengthOption] {
        var bestBySlot: [String: FocalLengthOption] = [:]

        for rgbSource in rgbSources {
            /*
             FOV buttons are a rear-camera composition control. Front capture is
             entered through the dedicated camera-switch button so the selector
             does not mix "front camera" with rear 35mm-equivalent focal slots.
             */
            guard rgbSource.device.position == .back else {
                continue
            }

            for targetFOV in FocalLengthLabelResolver.releaseFOVTargets() {
                /*
                 Depth support is format-specific. A virtual device may expose
                 one active format whose depth delivery is safe only at 2x/3x
                 and another format that works at 1x. Release FOV options must
                 therefore resolve the Apple-paired depth source for each target
                 FOV instead of reusing the single "best" depth format selected
                 during discovery. Otherwise the 24mm slot can be incorrectly
                 filled by LiDAR while Triple/Dual Wide are marked unavailable
                 at 1x, making 24mm and 48mm look visually too similar.
                 */
                let seedDepthSource = bestCompatibleDepthProfile(for: rgbSource)
                let requestedZoomFactor = FocalLengthLabelResolver.releaseVideoZoomFactor(
                    for: rgbSource,
                    targetEquivalentMillimeters: targetFOV,
                    formatSelection: seedDepthSource?.formatSelection
                )
                let depthSource = bestCompatibleDepthProfile(
                    for: rgbSource,
                    preferredZoomFactor: requestedZoomFactor
                )
                let zoomCapability = ZoomCapabilityResolver.resolve(
                    rgbSource: rgbSource,
                    depthProfile: depthSource,
                    selectedZoomID: nil,
                    selectedZoomFactor: requestedZoomFactor
                )
                guard let zoom = zoomCapability.zoomProfiles.first(where: { $0.matchesRawVideoZoomFactor(requestedZoomFactor) }) else {
                    continue
                }
                let label = FocalLengthLabelResolver.label(
                    equivalentMillimeters: targetFOV,
                    source: "\(rgbSource.focalLengthLabelSource)+releaseFOVTarget"
                )
                let isEnabled = rgbSource.isEnabled && depthSource?.isSelectable == true && zoom.isEnabled
                let option = FocalLengthOption(
                    id: "\(rgbSource.id)-\(zoom.id)-\(label.label)",
                    displayName: label.label,
                    numericLabel: label.numericLabel,
                    unitLabel: label.unitLabel,
                    equivalentFocalLength35mmMillimeters: label.equivalentMillimeters ?? 0,
                    labelSource: label.source,
                    rgbSource: rgbSource,
                    depthSource: depthSource,
                    zoom: zoom,
                    isEnabled: isEnabled,
                    disabledReason: isEnabled
                        ? nil
                        : zoom.disabledReason ?? depthSource?.disabledReason ?? rgbSource.disabledReason ?? "Depth capture unavailable"
                )

                #if !DEBUG
                guard option.isEnabled else {
                    continue
                }
                #endif

                let slotKey = "\(rgbSource.positionDescription)-\(option.displayName)"
                if let existing = bestBySlot[slotKey],
                   focalOptionPriority(existing) >= focalOptionPriority(option) {
                    continue
                }
                bestBySlot[slotKey] = option
            }
        }

        let options = bestBySlot.values.sorted { lhs, rhs in
            if lhs.rgbSource.device.position != rhs.rgbSource.device.position {
                return lhs.rgbSource.device.position == .back
            }
            if lhs.equivalentFocalLength35mmMillimeters == rhs.equivalentFocalLength35mmMillimeters {
                return focalOptionPriority(lhs) > focalOptionPriority(rhs)
            }
            return lhs.equivalentFocalLength35mmMillimeters < rhs.equivalentFocalLength35mmMillimeters
        }
        FOVDiagnostics.logFocalOptions(options)
        return options
    }

    var defaultFocalLengthOption: FocalLengthOption? {
        let options = focalLengthOptions()
        return bestOption(nearEquivalentMillimeters: 24, in: options)
            ?? options.first(where: \.isEnabled)
    }

    func bestOption(nearEquivalentMillimeters target: Double, in options: [FocalLengthOption]? = nil) -> FocalLengthOption? {
        let candidates = (options ?? focalLengthOptions()).filter(\.isEnabled)
        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs.equivalentFocalLength35mmMillimeters - target)
            let rhsDistance = abs(rhs.equivalentFocalLength35mmMillimeters - target)
            if abs(lhsDistance - rhsDistance) > 0.001 {
                return lhsDistance < rhsDistance
            }
            return focalOptionPriority(lhs) > focalOptionPriority(rhs)
        }
    }

    private func focalOptionPriority(_ option: FocalLengthOption) -> Int {
        let enabledScore = option.isEnabled ? 10_000 : 0
        let sourceScore = CameraCapabilityResolver.releaseDisplayPriority(for: option.rgbSource)
        return enabledScore + sourceScore
    }

    private func availability(for kind: DepthProfileKind, candidate: DepthDeviceCandidate?) -> DepthProfileAvailability {
        guard let candidate else {
            return .unavailable
        }
        return candidate.formatSelection == nil ? .unsupportedFormat : .available
    }

    private func debugDepthDeviceDisabledReason(
        availability: DepthProfileAvailability,
        rgbSource: CameraProfile?
    ) -> String? {
        switch availability {
        case .available where rgbSource == nil:
            return "Debug RGB source unavailable"
        case .available:
            return nil
        case .unavailable:
            return "Depth device unavailable"
        case .unsupportedFormat:
            return "No depth-capable format"
        }
    }
}

/// Produces the app's capability matrix from AVFoundation discovery.
///
/// This is the single boundary where raw device types, formats, and depth
/// formats become the stable model that UI and capture planning consume.
nonisolated enum CameraCapabilityResolver {
    static let candidateZoomFactors: [Double] = [0.5, 1.0, 2.0, 3.0]

    static func discover() -> CapabilityMatrix {
        let allDevices = uniqueDevices(
            discoverDevices(position: .back, deviceTypes: rgbDeviceTypes)
            + discoverDevices(position: .front, deviceTypes: rgbDeviceTypes)
        )

        let depthCandidates = depthCandidateDeviceTypes.compactMap { kind, deviceType, position -> DepthDeviceCandidate? in
            discoverDevices(position: position, deviceTypes: [deviceType]).first.map { device in
                DepthDeviceCandidate(
                    kind: kind,
                    device: device,
                    formatSelection: bestDepthFormatSelection(for: device)
                )
            }
        }

        let discoveredSources = allDevices
            .map { makeCameraProfile(device: $0, depthCandidates: depthCandidates) }
            .sorted { lhs, rhs in
                if lhs.fixedOrder == rhs.fixedOrder {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.fixedOrder < rhs.fixedOrder
            }
        let rgbSources = releaseFilteredRGBSources(from: discoveredSources)

        return CapabilityMatrix(rgbSources: rgbSources, depthCandidates: depthCandidates)
    }

    static func makeZoomProfiles(
        candidateZooms: [Double] = candidateZoomFactors,
        minimumZoom: Double,
        maximumZoom: Double,
        depthDeliveryRanges: [ClosedRange<Double>],
        allowsZoomOutsideDepthDeliveryRanges: Bool,
        requiresDepthSafeZoom: Bool = true
    ) -> [ZoomProfile] {
        candidateZooms.map { zoom in
            makeZoomProfile(
                zoom: zoom,
                minimumZoom: minimumZoom,
                maximumZoom: maximumZoom,
                depthDeliveryRanges: depthDeliveryRanges,
                allowsZoomOutsideDepthDeliveryRanges: allowsZoomOutsideDepthDeliveryRanges,
                requiresDepthSafeZoom: requiresDepthSafeZoom
            )
        }
    }

    static func makeZoomProfile(
        zoom: Double,
        minimumZoom: Double,
        maximumZoom: Double,
        depthDeliveryRanges: [ClosedRange<Double>],
        allowsZoomOutsideDepthDeliveryRanges: Bool,
        requiresDepthSafeZoom: Bool = true
    ) -> ZoomProfile {
        guard zoom >= minimumZoom, zoom <= maximumZoom else {
            return .disabled(zoom, reason: "Outside camera zoom range")
        }

        guard requiresDepthSafeZoom else {
            return .enabled(zoom)
        }

        if depthDeliveryRanges.isEmpty {
            /*
             Debug and Release depth captures should not present arbitrary zoom
             as safe when AVFoundation exposes no depth-delivery zoom ranges for
             the chosen format. 1x remains the conservative preview/capture
             baseline; higher factors need an explicit runtime range.
             */
            return abs(zoom - 1.0) < 0.001
                ? .enabled(zoom)
                : .disabled(zoom, reason: "No depth-safe zoom range")
        }

        guard depthDeliveryRanges.contains(where: { $0.contains(zoom) }) else {
            return .disabled(
                zoom,
                reason: allowsZoomOutsideDepthDeliveryRanges
                    ? "Zoom would drop depth delivery"
                    : "Outside depth zoom range"
            )
        }

        return .enabled(zoom)
    }

    static func displayName(for device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            "Ultra Wide"
        case .builtInWideAngleCamera:
            "Wide"
        case .builtInTelephotoCamera:
            "Telephoto"
        case .builtInTripleCamera:
            "Triple"
        case .builtInDualWideCamera:
            "Dual Wide"
        case .builtInDualCamera:
            "Dual"
        case .builtInLiDARDepthCamera:
            "LiDAR"
        case .builtInTrueDepthCamera:
            "TrueDepth"
        default:
            device.localizedName
        }
    }

    static func fixedOrder(for deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position = .back) -> Int {
        let positionOffset = position == .front ? 100 : 0
        let order: Int
        switch deviceType {
        case .builtInUltraWideCamera:
            order = 0
        case .builtInWideAngleCamera:
            order = 1
        case .builtInTelephotoCamera:
            order = 2
        case .builtInTripleCamera:
            order = 3
        case .builtInDualWideCamera:
            order = 4
        case .builtInDualCamera:
            order = 5
        case .builtInLiDARDepthCamera:
            order = 6
        case .builtInTrueDepthCamera:
            order = 7
        default:
            order = 99
        }
        return positionOffset + order
    }

    static func automaticPriority(for deviceType: AVCaptureDevice.DeviceType) -> Int {
        switch deviceType {
        case .builtInTripleCamera:
            1_000
        case .builtInDualWideCamera:
            950
        case .builtInDualCamera:
            900
        case .builtInWideAngleCamera:
            850
        case .builtInUltraWideCamera:
            800
        case .builtInTelephotoCamera:
            760
        case .builtInLiDARDepthCamera:
            740
        case .builtInTrueDepthCamera:
            700
        default:
            0
        }
    }

    static func depthFormatSelections(for device: AVCaptureDevice) -> [PhotoDepthFormatSelection] {
        device.formats.compactMap { videoFormat -> PhotoDepthFormatSelection? in
            guard let depthFormat = bestDepthFormat(in: videoFormat.supportedDepthDataFormats) else {
                return nil
            }
            return PhotoDepthFormatSelection(videoFormat: videoFormat, depthFormat: depthFormat)
        }
    }

    static func bestDepthFormatSelection(
        for device: AVCaptureDevice,
        preferredZoomFactor: Double? = nil,
        requiresPreferredZoomSupport: Bool = false
    ) -> PhotoDepthFormatSelection? {
        let selections = depthFormatSelections(for: device)
        let zoomCompatibleSelections = preferredZoomFactor.map { zoom in
            selections.filter { selection in
                depthFormatSelection(selection, supportsDepthSafeZoom: zoom)
            }
        } ?? []

        guard !zoomCompatibleSelections.isEmpty || !requiresPreferredZoomSupport else {
            return nil
        }

        let selectable = zoomCompatibleSelections.isEmpty ? selections : zoomCompatibleSelections

        /*
         The previous implementation chose the largest video format. That made
         still photo depth work, but it could pick a format whose depth-delivery
         zoom range was only 1x; selecting 2x/3x then caused the preview to jump
         briefly and settle back. Zoom support is format-specific, so Debug
         override prefers formats with broader depth-safe zoom first, then uses
         resolution/depth precision as tie breakers.
         */
        return selectable.max { lhs, rhs in
            depthFormatSelectionScore(lhs) < depthFormatSelectionScore(rhs)
        }
    }

    static func depthFormatSelection(
        _ selection: PhotoDepthFormatSelection,
        supportsDepthSafeZoom zoom: Double
    ) -> Bool {
        let ranges = selection.videoFormat.supportedVideoZoomRangesForDepthDataDelivery
            .map { Double($0.lowerBound)...Double($0.upperBound) }
        guard !ranges.isEmpty else {
            return abs(zoom - 1.0) < 0.001
        }
        return ranges.contains { $0.contains(zoom) }
    }

    private static func depthFormatSelectionScore(_ selection: PhotoDepthFormatSelection) -> Double {
        let videoFormat = selection.videoFormat
        let ranges = videoFormat.supportedVideoZoomRangesForDepthDataDelivery
            .map { Double($0.lowerBound)...Double($0.upperBound) }
        let maximumDepthSafeZoom = ranges.map(\.upperBound).max() ?? 1.0
        let totalDepthSafeSpan = ranges.reduce(0) { partial, range in
            partial + max(0, range.upperBound - range.lowerBound)
        }
        let hasContinuousDepthZoom = ranges.contains { $0.upperBound > $0.lowerBound }
        let dimensions = CMVideoFormatDescriptionGetDimensions(videoFormat.formatDescription)
        let resolutionScore = Double(Int(dimensions.width) * Int(dimensions.height)) / 1_000_000.0

        return (hasContinuousDepthZoom ? 1_000_000 : 0)
            + maximumDepthSafeZoom * 100_000
            + totalDepthSafeSpan * 10_000
            + Double(depthFormatScore(selection.depthFormat)) * 1_000
            + resolutionScore
    }

    static func debugCameraProfile(
        for device: AVCaptureDevice,
        depthCandidates: [DepthDeviceCandidate]
    ) -> CameraProfile {
        makeCameraProfile(device: device, depthCandidates: depthCandidates)
    }

    private static func makeCameraProfile(
        device: AVCaptureDevice,
        depthCandidates: [DepthDeviceCandidate]
    ) -> CameraProfile {
        let focalLabel = FocalLengthLabelResolver.label(for: device)
        let hasDepthCapture = hasCompatibleApplePairedDepthCapture(for: device, depthCandidates: depthCandidates)
        return CameraProfile(
            id: device.uniqueID,
            displayName: focalLabel.label,
            focalLengthLabelSource: focalLabel.source,
            equivalentFocalLength35mmMillimeters: focalLabel.equivalentMillimeters,
            deviceTypeRawValue: device.deviceType.rawValue,
            deviceName: device.localizedName,
            positionDescription: device.position.tapDescription,
            sourceKind: sourceKind(for: device),
            fixedOrder: fixedOrder(for: device.deviceType, position: device.position),
            isEnabled: hasDepthCapture,
            disabledReason: hasDepthCapture ? nil : "No Apple paired depth capture",
            referenceZoomFactor: referenceZoomFactor(for: device.deviceType),
            device: device
        )
    }

    private static func hasCompatibleApplePairedDepthCapture(
        for device: AVCaptureDevice,
        depthCandidates: [DepthDeviceCandidate]
    ) -> Bool {
        let source = CameraProfile(
            id: device.uniqueID,
            displayName: displayName(for: device),
            focalLengthLabelSource: "internalCompatibilityProbe",
            equivalentFocalLength35mmMillimeters: nil,
            deviceTypeRawValue: device.deviceType.rawValue,
            deviceName: device.localizedName,
            positionDescription: device.position.tapDescription,
            sourceKind: sourceKind(for: device),
            fixedOrder: fixedOrder(for: device.deviceType, position: device.position),
            isEnabled: true,
            disabledReason: nil,
            referenceZoomFactor: referenceZoomFactor(for: device.deviceType),
            device: device
        )

        return DepthProfileKind.allCases.contains { kind in
            guard let candidate = depthCandidates.first(where: { $0.kind == kind }) else {
                return false
            }

            return RGBDepthCompatibilityMatrix.evaluate(
                rgbSource: source,
                depthKind: kind,
                candidate: candidate
            ).status == .compatible
        }
    }

    private static func releaseFilteredRGBSources(from profiles: [CameraProfile]) -> [CameraProfile] {
        #if DEBUG
        /*
         Debug deliberately keeps every discovered source so hardware exploration
         can reveal "seen by AVFoundation but not depth-capturable" cases. Those
         rows are disabled by `isEnabled`; Release removes them entirely.
         */
        return profiles
        #else
        var bestByFocalSlot: [String: CameraProfile] = [:]
        for profile in profiles where profile.isEnabled {
            let key = "\(profile.positionDescription)-\(profile.displayName)"
            if let existing = bestByFocalSlot[key],
               releaseDisplayPriority(for: existing) >= releaseDisplayPriority(for: profile) {
                continue
            }
            bestByFocalSlot[key] = profile
        }

        return bestByFocalSlot.values.sorted { lhs, rhs in
            if lhs.fixedOrder == rhs.fixedOrder {
                return lhs.displayName < rhs.displayName
            }
            return lhs.fixedOrder < rhs.fixedOrder
        }
        #endif
    }

    static func releaseDisplayPriority(for profile: CameraProfile) -> Int {
        switch profile.sourceKind {
        case .virtual:
            300
        case .depthVirtual:
            200
        case .physical:
            100
        }
    }

    private static func sourceKind(for device: AVCaptureDevice) -> RGBSourceKind {
        switch device.deviceType {
        case .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera:
            .virtual
        case .builtInLiDARDepthCamera, .builtInTrueDepthCamera:
            .depthVirtual
        default:
            .physical
        }
    }

    private static func referenceZoomFactor(for deviceType: AVCaptureDevice.DeviceType) -> Double {
        switch deviceType {
        case .builtInUltraWideCamera:
            1.0
        case .builtInWideAngleCamera:
            1.0
        case .builtInTelephotoCamera:
            2.0
        default:
            1.0
        }
    }

    private static func bestDepthFormat(in formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        formats.max { lhs, rhs in
            let lhsScore = depthFormatScore(lhs)
            let rhsScore = depthFormatScore(rhs)
            if lhsScore == rhsScore {
                let lhsDimensions = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
                let rhsDimensions = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
                return Int(lhsDimensions.width) * Int(lhsDimensions.height) < Int(rhsDimensions.width) * Int(rhsDimensions.height)
            }
            return lhsScore < rhsScore
        }
    }

    private static func depthFormatScore(_ format: AVCaptureDevice.Format) -> Int {
        switch CMFormatDescriptionGetMediaSubType(format.formatDescription) {
        case kCVPixelFormatType_DepthFloat32:
            4
        case kCVPixelFormatType_DepthFloat16:
            3
        case kCVPixelFormatType_DisparityFloat32:
            2
        case kCVPixelFormatType_DisparityFloat16:
            1
        default:
            0
        }
    }

    private static func discoverDevices(
        position: AVCaptureDevice.Position,
        deviceTypes: [AVCaptureDevice.DeviceType]
    ) -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        ).devices
    }

    private static func uniqueDevices(_ devices: [AVCaptureDevice]) -> [AVCaptureDevice] {
        var seen = Set<String>()
        return devices.filter { device in
            guard !seen.contains(device.uniqueID) else { return false }
            seen.insert(device.uniqueID)
            return true
        }
    }

    private static var rgbDeviceTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInLiDARDepthCamera,
            .builtInTrueDepthCamera
        ]
    }

    private static var depthCandidateDeviceTypes: [(DepthProfileKind, AVCaptureDevice.DeviceType, AVCaptureDevice.Position)] {
        [
            (.lidarDepth, .builtInLiDARDepthCamera, .back),
            (.trueDepth, .builtInTrueDepthCamera, .front),
            (.dualCameraDisparity, .builtInDualCamera, .back),
            (.dualWideDisparity, .builtInDualWideCamera, .back),
            (.portraitSemanticDepth, .builtInTripleCamera, .back)
        ]
    }
}

/// Validates whether an RGB source and a depth row can form a legal SingleCam plan.
///
/// This matrix is deliberately conservative. It only reports `.compatible` for
/// Apple-paired single-pipeline configurations the app can actually run today.
/// Other plausible hardware combinations are surfaced as unsupported states so
/// the UI can grey them and diagnostics can explain the boundary.
nonisolated enum RGBDepthCompatibilityMatrix {
    nonisolated struct Result: @unchecked Sendable {
        let status: RGBDepthCompatibilityStatus
        let reason: String?
        let resolvedDevice: AVCaptureDevice?
        let formatSelection: PhotoDepthFormatSelection?
    }

    static func evaluate(
        rgbSource: CameraProfile,
        depthKind: DepthProfileKind,
        candidate: DepthDeviceCandidate?,
        preferredZoomFactor: Double? = nil
    ) -> Result {
        guard let candidate else {
            return Result(
                status: .unavailable,
                reason: "Depth source unavailable",
                resolvedDevice: nil,
                formatSelection: nil
            )
        }

        let formatSelection: PhotoDepthFormatSelection?
        if let preferredZoomFactor {
            formatSelection = CameraCapabilityResolver.bestDepthFormatSelection(
                for: candidate.device,
                preferredZoomFactor: preferredZoomFactor,
                requiresPreferredZoomSupport: true
            )
        } else {
            formatSelection = candidate.formatSelection
        }

        guard let formatSelection else {
            return Result(
                status: .unsupportedFormat,
                reason: "No depth-capable format",
                resolvedDevice: candidate.device,
                formatSelection: nil
            )
        }

        if candidate.device.uniqueID == rgbSource.device.uniqueID || candidate.device.containsConstituent(rgbSource.device) {
            return Result(
                status: .compatible,
                reason: nil,
                resolvedDevice: candidate.device,
                formatSelection: formatSelection
            )
        }

        return Result(
            status: .requiresMultiCam,
            reason: "Requires multiple independent camera inputs",
            resolvedDevice: candidate.device,
            formatSelection: formatSelection
        )
    }
}

/// Resolves zoom support for the current RGB-depth pairing.
///
/// The resolver consumes the active candidate format and returns profiles for
/// UI. It never calls `lockForConfiguration` or changes `videoZoomFactor`; those
/// mutations remain in `CaptureSessionController`.
nonisolated enum ZoomCapabilityResolver {
    static func resolve(
        rgbSource: CameraProfile,
        depthProfile: DepthProfile?,
        selectedZoomID: String?,
        selectedZoomFactor: Double? = nil
    ) -> ZoomCapability {
        let resolvedDevice = depthProfile?.resolvedDevice ?? rgbSource.device
        let videoFormat = depthProfile?.formatSelection?.videoFormat ?? resolvedDevice.activeFormat
        let depthRanges = depthProfile?.compatibility == .compatible
            ? videoFormat.supportedVideoZoomRangesForDepthDataDelivery.map { Double($0.lowerBound)...Double($0.upperBound) }
            : []
        let allowsOutsideDepthRanges = depthProfile?.compatibility == .compatible
            ? videoFormat.zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported
            : true
        let requiresDepthSafeZoom = depthProfile?.compatibility == .compatible
        let minimumZoom = Double(resolvedDevice.minAvailableVideoZoomFactor)
        let maximumZoom = Double(min(resolvedDevice.maxAvailableVideoZoomFactor, videoFormat.videoMaxZoomFactor))
        var profiles = CameraCapabilityResolver.makeZoomProfiles(
            minimumZoom: minimumZoom,
            maximumZoom: maximumZoom,
            depthDeliveryRanges: depthRanges,
            allowsZoomOutsideDepthDeliveryRanges: allowsOutsideDepthRanges,
            requiresDepthSafeZoom: requiresDepthSafeZoom
        )
        /*
         The fixed Debug zoom chips are 0.5/1/2/3x, but Release FOV labels may
         need a raw value outside that list. For example, if a depth-capable
         virtual format exposes 24mm at raw 2.0, then the semantic 48mm slot
         needs raw 4.0. Appending the selected factor here lets the plan carry
         the exact value through validation and into `CaptureSessionController`.
         */
        if let selectedZoomFactor,
           profiles.contains(where: { $0.matchesRawVideoZoomFactor(selectedZoomFactor) }) == false {
            profiles.append(
                CameraCapabilityResolver.makeZoomProfile(
                    zoom: selectedZoomFactor,
                    minimumZoom: minimumZoom,
                    maximumZoom: maximumZoom,
                    depthDeliveryRanges: depthRanges,
                    allowsZoomOutsideDepthDeliveryRanges: allowsOutsideDepthRanges,
                    requiresDepthSafeZoom: requiresDepthSafeZoom
                )
            )
            profiles.sort { $0.requestedZoomFactor < $1.requestedZoomFactor }
        }
        let selected = selectedZoomID.flatMap { id in profiles.first(where: { $0.id == id && $0.isEnabled }) }
            ?? selectedZoomFactor.flatMap { zoom in profiles.first(where: { $0.matchesRawVideoZoomFactor(zoom) && $0.isEnabled }) }
            ?? profiles.first(where: \.isEnabled)
        let recommendedRange = videoFormat.systemRecommendedVideoZoomRange.map { Double($0.lowerBound)...Double($0.upperBound) }
        let isContinuous = depthRanges.contains { $0.lowerBound != $0.upperBound }
        let isDiscrete = !depthRanges.isEmpty && depthRanges.allSatisfy { $0.lowerBound == $0.upperBound }

        return ZoomCapability(
            available: profiles.contains(where: \.isEnabled),
            currentZoomFactor: selected?.rawVideoZoomFactor,
            videoMaxZoomFactor: Double(videoFormat.videoMaxZoomFactor),
            minAvailableVideoZoomFactor: minimumZoom,
            maxAvailableVideoZoomFactor: maximumZoom,
            systemRecommendedVideoZoomRange: recommendedRange,
            supportedVideoZoomRangesForDepthDataDelivery: depthRanges,
            zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported: allowsOutsideDepthRanges,
            virtualDeviceSwitchOverVideoZoomFactors: resolvedDevice.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue),
            depthSafeZoomRanges: depthRanges,
            isContinuous: isContinuous,
            isDiscrete: isDiscrete,
            zoomProfiles: profiles
        )
    }
}

/// Produces user-facing 35mm-equivalent focal labels for capture choices.
///
/// iOS 26+ uses `AVCaptureDevice.nominalFocalLengthIn35mmFilm`. Earlier iOS
/// versions use a small model-aware catalog for common iPhone Pro devices, then
/// a conservative fallback by camera type. The label is computed in the
/// capability layer so Release UI, Debug UI, and manifests all describe the same
/// selected focal slot.
nonisolated enum FocalLengthLabelResolver {
    nonisolated struct Label: Equatable, Sendable {
        let label: String
        let numericLabel: String
        let unitLabel: String
        let equivalentMillimeters: Double?
        let source: String
    }

    static func label(for device: AVCaptureDevice) -> Label {
        if let runtimeValue = device.tapNominalFocalLengthIn35mmFilm {
            let millimeters = Double(runtimeValue)
            return Label(
                label: formattedLabel(millimeters),
                numericLabel: formattedNumericLabel(millimeters),
                unitLabel: "mm",
                equivalentMillimeters: millimeters,
                source: "AVCaptureDevice.nominalFocalLengthIn35mmFilm"
            )
        }

        if let catalogValue = catalogValue(for: device) {
            let millimeters = Double(catalogValue)
            return Label(
                label: formattedLabel(millimeters),
                numericLabel: formattedNumericLabel(millimeters),
                unitLabel: "mm",
                equivalentMillimeters: millimeters,
                source: "deviceModelCatalog"
            )
        }

        let fallback = fallbackValue(for: device)
        return Label(
            label: formattedLabel(Double(fallback)),
            numericLabel: formattedNumericLabel(Double(fallback)),
            unitLabel: "mm",
            equivalentMillimeters: Double(fallback),
            source: "deviceTypeFallback"
        )
    }

    static func label(for profile: CameraProfile, zoomFactor: Double) -> Label {
        let millimeters = resolvedEquivalentMillimeters(for: profile, zoomFactor: zoomFactor)
        return label(
            equivalentMillimeters: millimeters,
            source: "\(fovBaseLabelSource(for: profile))+depthSafeZoom"
        )
    }

    static func label(equivalentMillimeters millimeters: Double, source: String) -> Label {
        return Label(
            label: formattedLabel(millimeters),
            numericLabel: formattedNumericLabel(millimeters),
            unitLabel: "mm",
            equivalentMillimeters: millimeters,
            source: source
        )
    }

    static func debugZoomLabel(for profile: CameraProfile, zoomFactor: Double) -> Label {
        let baseMillimeters = fovBaseEquivalentMillimeters(for: profile)
        let millimeters = equivalentMillimeters(
            baseMillimeters: baseMillimeters,
            zoomFactor: zoomFactor
        )
        return Label(
            label: formattedLabel(millimeters),
            numericLabel: formattedNumericLabel(millimeters),
            unitLabel: "mm",
            equivalentMillimeters: millimeters,
            source: "\(fovBaseLabelSource(for: profile))+videoZoomFactor"
        )
    }

    static func debugEquivalentMillimeters(baseMillimeters: Double, zoomFactor: Double) -> Double {
        equivalentMillimeters(baseMillimeters: baseMillimeters, zoomFactor: zoomFactor)
    }

    static func equivalentMillimeters(baseMillimeters: Double, zoomFactor: Double) -> Double {
        max(1, baseMillimeters) * max(0.01, zoomFactor)
    }

    static func releaseFOVTargets() -> [Double] {
        let model = DeviceModelIdentifier.current
        let wideType = AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue
        let teleType = AVCaptureDevice.DeviceType.builtInTelephotoCamera.rawValue
        let wide = Double(modelCatalog[model]?[wideType] ?? 24)
        let tele = Double(modelCatalog[model]?[teleType] ?? 77)
        return uniqueSorted([13, wide, wide * 2, tele])
    }

    static func releaseVideoZoomFactor(
        for profile: CameraProfile,
        targetEquivalentMillimeters: Double,
        formatSelection: PhotoDepthFormatSelection?
    ) -> Double {
        /*
         Release FOV math starts from the Wide-equivalent baseline, then converts
         the requested 35mm label into the raw `videoZoomFactor` that AVFoundation
         expects for the resolved format. The baseline may be the lower bound of
         the depth-safe range rather than 1.0 on virtual photo-depth devices.
         */
        let wideMillimeters = virtualWideEquivalentMillimeters(for: profile.device)
        let wideRawZoom = wideReferenceZoomFactor(for: profile, formatSelection: formatSelection)
        return max(0.01, wideRawZoom * targetEquivalentMillimeters / max(1, wideMillimeters))
    }

    static func equivalentMillimeters(
        for profile: CameraProfile,
        rawVideoZoomFactor: Double,
        formatSelection: PhotoDepthFormatSelection?
    ) -> Double {
        let wideMillimeters = virtualWideEquivalentMillimeters(for: profile.device)
        let wideRawZoom = wideReferenceZoomFactor(for: profile, formatSelection: formatSelection)
        return max(1, wideMillimeters) * max(0.01, rawVideoZoomFactor) / max(0.01, wideRawZoom)
    }

    static func usesWideBaselineForVirtualFOV(deviceTypeRawValue: String) -> Bool {
        [
            AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue,
            AVCaptureDevice.DeviceType.builtInDualWideCamera.rawValue,
            AVCaptureDevice.DeviceType.builtInDualCamera.rawValue,
            AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue
        ].contains(deviceTypeRawValue)
    }

    static func semanticZoomScore(equivalentMillimeters: Double, zoomFactor: Double) -> Int {
        isSemanticFOVSlot(equivalentMillimeters: equivalentMillimeters, zoomFactor: zoomFactor) ? 1_000 : 0
    }

    static func isSemanticFOVSlot(equivalentMillimeters: Double, zoomFactor: Double) -> Bool {
        let expectedZoom: Double
        switch equivalentMillimeters {
        case ..<18:
            return zoomFactor <= 1.0
        case 18..<36:
            expectedZoom = 1.0
        case 36..<62:
            expectedZoom = 2.0
        default:
            expectedZoom = 3.0
        }

        return abs(zoomFactor - expectedZoom) < 0.01
    }

    private static func fovBaseEquivalentMillimeters(for profile: CameraProfile) -> Double {
        /*
         Release and Debug both expose human-facing FOV slots, not raw
         `AVCaptureDevice` focal metadata. For Apple virtual depth pipelines
         such as Dual, Dual Wide, Triple/Portrait, and LiDAR, the 1x FOV is the
         Wide baseline on current iPhones. On iOS 26,
         `nominalFocalLengthIn35mmFilm` may report an active-constituent or
         format-specific value such as 48mm for a virtual device, which must not
         make the Release `48mm` button point at the 1x preview. These pipelines
         therefore share the same Wide baseline helper used by Debug zoom labels.
         */
        if usesWideBaselineForVirtualFOV(deviceTypeRawValue: profile.deviceTypeRawValue) {
            return virtualWideEquivalentMillimeters(for: profile.device)
        }

        switch profile.device.deviceType {
        case .builtInTrueDepthCamera:
            return Double(catalogValue(for: profile.device) ?? fallbackValue(for: profile.device))
        default:
            return profile.equivalentFocalLength35mmMillimeters
                ?? label(for: profile.device).equivalentMillimeters
                ?? Double(fallbackValue(for: profile.device))
        }
    }

    private static func fovBaseLabelSource(for profile: CameraProfile) -> String {
        usesWideBaselineForVirtualFOV(deviceTypeRawValue: profile.deviceTypeRawValue)
            ? "virtualWideBaseline"
            : profile.focalLengthLabelSource
    }

    private static func wideReferenceZoomFactor(
        for profile: CameraProfile,
        formatSelection: PhotoDepthFormatSelection?
    ) -> Double {
        guard usesWideBaselineForVirtualFOV(deviceTypeRawValue: profile.deviceTypeRawValue),
              let formatSelection else {
            return 1.0
        }

        let lowerDepthSafeBound = formatSelection.videoFormat.supportedVideoZoomRangesForDepthDataDelivery
            .map { Double($0.lowerBound) }
            .min() ?? 1.0
        /*
         Treat the lower depth-safe bound as the raw zoom where the Wide FOV
         begins for this format. This is the core distinction between semantic
         FOV labels and `AVCaptureDevice.videoZoomFactor`.
         */
        return max(1.0, lowerDepthSafeBound)
    }

    private static func resolvedEquivalentMillimeters(for profile: CameraProfile, zoomFactor: Double) -> Double {
        if profile.device.position == .front {
            return profile.equivalentFocalLength35mmMillimeters ?? 23
        }

        let baseMillimeters = fovBaseEquivalentMillimeters(for: profile)

        if zoomFactor <= 0.75 {
            return 13
        }

        if abs(zoomFactor - 1.0) < 0.01 {
            return baseMillimeters
        }

        if abs(zoomFactor - 2.0) < 0.01 {
            return equivalentMillimeters(baseMillimeters: baseMillimeters, zoomFactor: 2.0)
        }

        if abs(zoomFactor - 3.0) < 0.01 {
            return teleEquivalentMillimeters(for: profile)
                ?? equivalentMillimeters(baseMillimeters: baseMillimeters, zoomFactor: 3.0)
        }

        return equivalentMillimeters(baseMillimeters: baseMillimeters, zoomFactor: zoomFactor)
    }

    private static func teleEquivalentMillimeters(for profile: CameraProfile) -> Double? {
        let model = DeviceModelIdentifier.current
        let teleType = AVCaptureDevice.DeviceType.builtInTelephotoCamera.rawValue
        if let value = modelCatalog[model]?[teleType] {
            return Double(value)
        }
        return nil
    }

    private static func catalogValue(for device: AVCaptureDevice) -> Int? {
        let model = DeviceModelIdentifier.current
        let deviceType = device.deviceType.rawValue
        if let value = modelCatalog[model]?[deviceType] {
            return value
        }
        return nil
    }

    private static func virtualWideEquivalentMillimeters(for device: AVCaptureDevice) -> Double {
        let model = DeviceModelIdentifier.current
        if let virtualValue = catalogValue(for: device) {
            return Double(virtualValue)
        }
        if let wideValue = modelCatalog[model]?[AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue] {
            return Double(wideValue)
        }
        return Double(fallbackValue(for: device))
    }

    private static func uniqueSorted(_ values: [Double]) -> [Double] {
        values.reduce(into: [Double]()) { result, value in
            guard !result.contains(where: { abs($0 - value) < 0.001 }) else {
                return
            }
            result.append(value)
        }
        .sorted()
    }

    private static func fallbackValue(for device: AVCaptureDevice) -> Int {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return 13
        case .builtInTrueDepthCamera:
            return 23
        case .builtInTelephotoCamera:
            return 77
        case .builtInWideAngleCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInLiDARDepthCamera:
            return 24
        default:
            return 24
        }
    }

    private static func formattedLabel(_ millimeters: Double) -> String {
        "\(formattedNumericLabel(millimeters))mm"
    }

    private static func formattedNumericLabel(_ millimeters: Double) -> String {
        "\(Int(millimeters.rounded()))"
    }

    private static let modelCatalog: [String: [String: Int]] = [
        "iPhone13,3": proLabels(wide: 26, tele: 52),
        "iPhone13,4": proLabels(wide: 26, tele: 65),
        "iPhone14,2": proLabels(wide: 26, tele: 77),
        "iPhone14,3": proLabels(wide: 26, tele: 77),
        "iPhone15,2": proLabels(wide: 24, tele: 77),
        "iPhone15,3": proLabels(wide: 24, tele: 77),
        "iPhone16,1": proLabels(wide: 24, tele: 77),
        "iPhone16,2": proLabels(wide: 24, tele: 120),
        "iPhone17,1": proLabels(wide: 24, tele: 120),
        "iPhone17,2": proLabels(wide: 24, tele: 120)
    ]

    private static func proLabels(wide: Int, tele: Int) -> [String: Int] {
        [
            AVCaptureDevice.DeviceType.builtInUltraWideCamera.rawValue: 13,
            AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue: wide,
            AVCaptureDevice.DeviceType.builtInTelephotoCamera.rawValue: tele,
            AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue: wide,
            AVCaptureDevice.DeviceType.builtInDualWideCamera.rawValue: wide,
            AVCaptureDevice.DeviceType.builtInDualCamera.rawValue: wide,
            AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue: wide,
            AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue: 23
        ]
    }
}

nonisolated enum DeviceModelIdentifier {
    static let current: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { charPointer in
                String(validatingUTF8: charPointer) ?? "unknown"
            }
        }
    }()
}

extension AVCaptureDevice {
    nonisolated func containsConstituent(_ source: AVCaptureDevice) -> Bool {
        constituentDevices.contains { $0.uniqueID == source.uniqueID }
    }
}
