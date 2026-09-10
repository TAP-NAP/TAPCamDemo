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
        discover(devices: availableDevices())
    }

    static func availableDevices() -> [AVCaptureDevice] {
        guard !Task.isCancelled else { return [] }
        let rear = discoverDevices(position: .back, deviceTypes: rgbDeviceTypes)
        guard !Task.isCancelled else { return [] }
        return uniqueDevices(rear + discoverDevices(position: .front, deviceTypes: rgbDeviceTypes))
    }

    static func discover(devices: [AVCaptureDevice]) -> CapabilityMatrix {
        var depthCandidates: [DepthDeviceCandidate] = []
        for (kind, device) in depthDevices(in: devices) {
            guard !Task.isCancelled else {
                return CapabilityMatrix(rgbSources: [], depthCandidates: [])
            }
            depthCandidates.append(DepthDeviceCandidate(
                kind: kind,
                device: device,
                formats: prepareDepthFormats(for: device)
            ))
        }
        return matrix(devices: devices, depthCandidates: depthCandidates)
    }

    static func depthDevices(in devices: [AVCaptureDevice]) -> [(kind: DepthProfileKind, device: AVCaptureDevice)] {
        depthCandidateDeviceTypes.compactMap { kind, deviceType, position in
            devices.first { $0.deviceType == deviceType && $0.position == position }.map { (kind, $0) }
        }
    }

    static func matrix(
        devices: [AVCaptureDevice],
        depthCandidates: [DepthDeviceCandidate],
        photographerModeFacts: PhotographerModeCapabilityFacts? = nil
    ) -> CapabilityMatrix {
        guard !Task.isCancelled else {
            return CapabilityMatrix(rgbSources: [], depthCandidates: [])
        }
        let discoveredSources = devices
            .map { makeCameraProfile(device: $0, depthCandidates: depthCandidates) }
            .sorted { lhs, rhs in
                if lhs.fixedOrder == rhs.fixedOrder {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.fixedOrder < rhs.fixedOrder
            }
        let rgbSources = releaseFilteredRGBSources(from: discoveredSources)

        return CapabilityMatrix(
            rgbSources: rgbSources,
            depthCandidates: depthCandidates,
            photographerModeFacts: photographerModeFacts
        )
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

    private static func prepareDepthFormats(for device: AVCaptureDevice) -> [DepthFormatCandidate] {
        var candidates: [DepthFormatCandidate] = []
        for (videoIndex, videoFormat) in device.formats.enumerated() {
            guard !Task.isCancelled else { return [] }
            let depthFormats = videoFormat.supportedDepthDataFormats
            guard let depthFormat = bestDepthFormat(in: depthFormats),
                  let depthIndex = depthFormats.firstIndex(of: depthFormat) else {
                continue
            }
            let selection = PhotoDepthFormatSelection(videoFormat: videoFormat, depthFormat: depthFormat)
            candidates.append(DepthFormatCandidate(
                selection: selection,
                facts: DepthFormatFacts(
                    videoFormatIndex: videoIndex,
                    depthFormatIndex: depthIndex,
                    score: depthFormatSelectionScore(selection),
                    depthSafeZoomRanges: videoFormat.supportedVideoZoomRangesForDepthDataDelivery
                        .map { Double($0.lowerBound)...Double($0.upperBound) }
                )
            ))
        }
        return candidates
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
        cameraProfile(for: device, depthCandidates: depthCandidates)
    }

    /// Builds the same stable profile for an explicitly selected Release
    /// depth-capable device as discovery uses for normal RGB sources.
    ///
    /// LiDAR is commonly removed from the Release RGB list when a higher
    /// priority virtual camera occupies the same 24mm slot. Photographer mode
    /// still needs an explicit LiDAR profile without depending on DEBUG state.
    static func cameraProfile(
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
