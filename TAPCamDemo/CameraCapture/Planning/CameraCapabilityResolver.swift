//
//  CameraCapabilityResolver.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Produces the app's capability matrix from AVFoundation discovery.
///
/// This is the single boundary where raw device types, formats, and depth
/// formats become the stable model that UI and capture planning consume.
nonisolated enum CameraCapabilityResolver {
    static let candidateZoomFactors: [Double] = [0.5, 1.0, 2.0, 3.0]

    /// Discovers camera devices and depth-capable formats for the app.
    ///
    /// This is the only place raw AVFoundation device discovery is converted
    /// into the stable `CapabilityMatrix` that UI and planning read.
    ///
    /// - Tag: DiscoverCameraCapabilities
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
        displayZoomFactor: Double? = nil,
        minimumZoom: Double,
        maximumZoom: Double,
        depthDeliveryRanges: [ClosedRange<Double>],
        allowsZoomOutsideDepthDeliveryRanges: Bool,
        requiresDepthSafeZoom: Bool = true
    ) -> ZoomProfile {
        guard zoom >= minimumZoom, zoom <= maximumZoom else {
            return .disabled(zoom, displayZoomFactor: displayZoomFactor, reason: "Outside camera zoom range")
        }

        guard requiresDepthSafeZoom else {
            return .enabled(zoom, displayZoomFactor: displayZoomFactor)
        }

        if depthDeliveryRanges.isEmpty {
            /*
             Debug and Release depth captures should not present arbitrary zoom
             as safe when AVFoundation exposes no depth-delivery zoom ranges for
             the chosen format. 1x remains the conservative preview/capture
             baseline; higher factors need an explicit runtime range.
             */
            return abs(zoom - 1.0) < 0.001
                ? .enabled(zoom, displayZoomFactor: displayZoomFactor)
                : .disabled(zoom, displayZoomFactor: displayZoomFactor, reason: "No depth-safe zoom range")
        }

        guard depthDeliveryRanges.contains(where: { $0.contains(zoom) }) else {
            return .disabled(
                zoom,
                displayZoomFactor: displayZoomFactor,
                reason: allowsZoomOutsideDepthDeliveryRanges
                    ? "Zoom would drop depth delivery"
                    : "Outside depth zoom range"
            )
        }

        return .enabled(zoom, displayZoomFactor: displayZoomFactor)
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
