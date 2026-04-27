//
//  FOVDiagnostics.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Emits the FOV/zoom breadcrumbs needed to diagnose selector and preview drift.
///
/// This logger is intentionally compiled in both Debug and Release. The bug we
/// are hunting lives in the shared Release FOV selector path, so limiting logs to
/// Debug would hide the exact `FocalLengthOption -> CaptureSourcePlan -> session`
/// chain that determines whether a `48mm` tap really applies a 2x zoom.
nonisolated enum FOVDiagnostics {
    private static let logger = Logger(subsystem: "TAPCamDemo", category: "FOVDiagnostics")

    static func logFocalOptions(_ options: [FocalLengthOption]) {
        guard !options.isEmpty else {
            logger.info("FOV options rebuilt: empty")
            return
        }

        logger.info("FOV options rebuilt: count=\(options.count, privacy: .public)")
        for option in options {
            logFocalOption(option, event: "option")
        }
    }

    static func logFocalSelection(_ option: FocalLengthOption) {
        logFocalOption(option, event: "selected")
    }

    static func logCapturePlan(_ plan: CaptureSourcePlan) {
        let zoomFactor = plan.zoom?.actualVideoZoomFactor ?? plan.zoom?.requestedZoomFactor ?? 1.0
        let depthRanges = plan.zoomCapability.depthSafeZoomRanges
            .map { "\(formatted($0.lowerBound))...\(formatted($0.upperBound))" }
            .joined(separator: ",")
        let depthSource = plan.depthSource?.displayName ?? "nil"
        let focalLabel = plan.requestedFocalLengthLabel
        let format = plan.formatSelection?.videoFormat
        let formatSummary = format.map(formatSummary) ?? "nil"

        logger.info("plan selectionMode=\(plan.selectionMode.rawValue, privacy: .public) label=\(focalLabel.label, privacy: .public) labelSource=\(focalLabel.source, privacy: .public) zoom=\(formatted(zoomFactor), privacy: .public) rgbDevice=\(plan.rgbSource.deviceTypeRawValue, privacy: .public) resolvedDevice=\(plan.resolvedCaptureDevice.deviceType.rawValue, privacy: .public) depth=\(depthSource, privacy: .public) format=\(formatSummary, privacy: .public) depthRanges=\(depthRanges, privacy: .public) canCapture=\(plan.canCapturePhotoDepth, privacy: .public)")
    }

    static func logAppliedZoom(
        requestedZoom: Double,
        clampedZoom: CGFloat,
        actualZoom: CGFloat,
        device: AVCaptureDevice
    ) {
        let activePrimary = device.activePrimaryConstituent.map {
            "\($0.localizedName) [\($0.deviceType.rawValue)]"
        } ?? "nil"
        let formatSummary = formatSummary(device.activeFormat)

        logger.info("appliedZoom requested=\(formatted(requestedZoom), privacy: .public) clamped=\(formatted(Double(clampedZoom)), privacy: .public) actual=\(formatted(Double(actualZoom)), privacy: .public) device=\(device.localizedName, privacy: .public) deviceType=\(device.deviceType.rawValue, privacy: .public) activePrimary=\(activePrimary, privacy: .public) activeFormat=\(formatSummary, privacy: .public) minZoom=\(formatted(Double(device.minAvailableVideoZoomFactor)), privacy: .public) maxZoom=\(formatted(Double(device.maxAvailableVideoZoomFactor)), privacy: .public)")
    }

    private static func logFocalOption(_ option: FocalLengthOption, event: String) {
        let depthSource = option.depthSource?.displayName ?? "nil"
        let actualZoom = option.zoom.actualVideoZoomFactor ?? option.zoom.requestedZoomFactor
        let format = option.depthSource?.formatSelection?.videoFormat
        let formatSummary = format.map(formatSummary) ?? "nil"
        let depthRanges = format?.supportedVideoZoomRangesForDepthDataDelivery
            .map { "\(formatted(Double($0.lowerBound)))...\(formatted(Double($0.upperBound)))" }
            .joined(separator: ",") ?? "nil"

        logger.info("FOV \(event, privacy: .public) label=\(option.displayName, privacy: .public) id=\(option.id, privacy: .public) source=\(option.labelSource, privacy: .public) equivMM=\(formatted(option.equivalentFocalLength35mmMillimeters), privacy: .public) rawRequestedZoom=\(formatted(option.zoom.requestedZoomFactor), privacy: .public) rawActualZoom=\(formatted(actualZoom), privacy: .public) rgbDevice=\(option.rgbSource.deviceTypeRawValue, privacy: .public) rgbName=\(option.rgbSource.deviceName, privacy: .public) depth=\(depthSource, privacy: .public) format=\(formatSummary, privacy: .public) depthRanges=\(depthRanges, privacy: .public) enabled=\(option.isEnabled, privacy: .public)")
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatSummary(_ format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height) fov=\(formatted(Double(format.videoFieldOfView))) maxZoom=\(formatted(Double(format.videoMaxZoomFactor)))"
    }
}
