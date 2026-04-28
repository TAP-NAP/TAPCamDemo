//
//  FocalLengthLabelResolver.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

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

    static func displayZoomFactor(
        for profile: CameraProfile,
        rawVideoZoomFactor: Double,
        formatSelection: PhotoDepthFormatSelection?
    ) -> Double {
        displayZoomFactor(
            rawVideoZoomFactor: rawVideoZoomFactor,
            wideReferenceZoomFactor: wideReferenceZoomFactor(for: profile, formatSelection: formatSelection)
        )
    }

    static func displayZoomFactor(rawVideoZoomFactor: Double, wideReferenceZoomFactor: Double) -> Double {
        /*
         User-facing zoom is relative to the 24mm Wide FOV baseline. On some
         virtual photo-depth formats, AVFoundation's depth-safe Wide baseline is
         raw 2.0, so raw 2.0 must display as 1x rather than 2x.
         */
        max(0.01, rawVideoZoomFactor) / max(0.01, wideReferenceZoomFactor)
    }

    static func rawVideoZoomFactor(
        for profile: CameraProfile,
        displayZoomFactor: Double,
        formatSelection: PhotoDepthFormatSelection?
    ) -> Double {
        wideReferenceZoomFactor(for: profile, formatSelection: formatSelection) * max(0.01, displayZoomFactor)
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
