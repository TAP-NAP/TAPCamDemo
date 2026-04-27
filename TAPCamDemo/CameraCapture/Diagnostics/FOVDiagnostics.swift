//
//  FOVDiagnostics.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import OSLog

/// Emits the FOV/zoom breadcrumbs needed to diagnose selector and preview drift.
///
/// This logger is intentionally compiled in both Debug and Release. The bug we
/// are hunting lives in the shared Release FOV selector path, so limiting logs to
/// Debug would hide the exact `FocalLengthOption -> CaptureSourcePlan -> session`
/// chain that determines whether a `48mm` tap really applies its resolved raw
/// zoom, which can be `4.0` on a depth-safe virtual-camera format.
nonisolated enum FOVDiagnostics {
    static let isEnabled = true

    private static let logger = Logger(subsystem: "TAPCamDemo", category: "FOVDiagnostics")

    static func logFocalOptions(_ options: [FocalLengthOption]) {
        guard isEnabled else { return }

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
        guard isEnabled else { return }

        logFocalOption(option, event: "selected")
    }

    static func logCapturePlan(_ plan: CaptureSourcePlan) {
        guard isEnabled else { return }

        let zoomFactor = plan.zoom?.rawVideoZoomFactor ?? 1.0
        let depthRanges = plan.zoomCapability.depthSafeZoomRanges
            .map { "\(formatted($0.lowerBound))...\(formatted($0.upperBound))" }
            .joined(separator: ",")
        let depthSource = plan.depthSource?.displayName ?? "nil"
        let focalLabel = plan.requestedFocalLengthLabel
        let format = plan.formatSelection?.videoFormat
        let formatSummary = format.map(formatSummary) ?? "nil"
        mirrorToConsole("plan selectionMode=\(plan.selectionMode.rawValue) label=\(focalLabel.label) zoom=\(formatted(zoomFactor)) depth=\(depthSource) format=\(formatSummary) depthRanges=\(depthRanges) canCapture=\(plan.canCapturePhotoDepth)")

        logger.info("plan selectionMode=\(plan.selectionMode.rawValue, privacy: .public) label=\(focalLabel.label, privacy: .public) labelSource=\(focalLabel.source, privacy: .public) zoom=\(formatted(zoomFactor), privacy: .public) rgbDevice=\(plan.rgbSource.deviceTypeRawValue, privacy: .public) resolvedDevice=\(plan.resolvedCaptureDevice.deviceType.rawValue, privacy: .public) depth=\(depthSource, privacy: .public) format=\(formatSummary, privacy: .public) depthRanges=\(depthRanges, privacy: .public) canCapture=\(plan.canCapturePhotoDepth, privacy: .public)")
    }

    static func logSelectionConfigureStart(generation: Int, plan: CaptureSourcePlan) {
        guard isEnabled else { return }

        mirrorToConsole("selectionConfigure start generation=\(generation) label=\(plan.requestedFocalLengthLabel.label) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0)) device=\(deviceSummary(plan.resolvedCaptureDevice))")
        logger.info("selectionConfigure start generation=\(generation, privacy: .public) label=\(plan.requestedFocalLengthLabel.label, privacy: .public) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0), privacy: .public) device=\(deviceSummary(plan.resolvedCaptureDevice), privacy: .public) depth=\(plan.depthSource?.displayName ?? "nil", privacy: .public) nativeAspect=pending")
    }

    static func logSelectionConfigureResult(
        generation: Int,
        result: SessionConfigurationResult,
        duration: TimeInterval
    ) {
        guard isEnabled else { return }

        mirrorToConsole("selectionConfigure result generation=\(generation) label=\(result.capturePlan.requestedFocalLengthLabel.label) zoom=\(formatted(result.capturePlan.zoom?.rawVideoZoomFactor ?? 1.0)) depthReady=\(result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth) durationMs=\(formatted(duration * 1_000)) device=\(deviceSummary(result.device))")
        logger.info("selectionConfigure result generation=\(generation, privacy: .public) label=\(result.capturePlan.requestedFocalLengthLabel.label, privacy: .public) zoom=\(formatted(result.capturePlan.zoom?.rawVideoZoomFactor ?? 1.0), privacy: .public) depthReady=\(result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth, privacy: .public) nativeAspect=\(formatted(result.nativePreviewAspectRatio), privacy: .public) durationMs=\(formatted(duration * 1_000), privacy: .public) device=\(deviceSummary(result.device), privacy: .public)")
    }

    static func logSelectionConfigureFailure(
        generation: Int,
        plan: CaptureSourcePlan,
        duration: TimeInterval,
        error: Error
    ) {
        guard isEnabled else { return }

        logger.error("selectionConfigure failure generation=\(generation, privacy: .public) label=\(plan.requestedFocalLengthLabel.label, privacy: .public) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0), privacy: .public) durationMs=\(formatted(duration * 1_000), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
    }

    static func logFOVCycleDiagnostic(event: String, targetLabel: String?) {
        guard isEnabled else { return }

        mirrorToConsole("fovCycleDiagnostic event=\(event) target=\(targetLabel ?? "nil")")
        logger.info("fovCycleDiagnostic event=\(event, privacy: .public) target=\(targetLabel ?? "nil", privacy: .public)")
    }

    static func logSessionConfigurePhase(
        _ phase: String,
        plan: CaptureSourcePlan,
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput
    ) {
        guard isEnabled else { return }

        mirrorToConsole("sessionConfigure \(phase) label=\(plan.requestedFocalLengthLabel.label) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0)) inputs=\(session.inputs.count) outputs=\(session.outputs.count) depthEnabled=\(photoOutput.isDepthDataDeliveryEnabled) depthSupported=\(photoOutput.isDepthDataDeliverySupported) running=\(session.isRunning) device=\(deviceSummary(plan.resolvedCaptureDevice))")
        logger.info("sessionConfigure \(phase, privacy: .public) label=\(plan.requestedFocalLengthLabel.label, privacy: .public) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0), privacy: .public) inputs=\(session.inputs.count, privacy: .public) outputs=\(session.outputs.count, privacy: .public) depthEnabled=\(photoOutput.isDepthDataDeliveryEnabled, privacy: .public) depthSupported=\(photoOutput.isDepthDataDeliverySupported, privacy: .public) running=\(session.isRunning, privacy: .public) device=\(deviceSummary(plan.resolvedCaptureDevice), privacy: .public)")
    }

    static func logSessionReuseDecision(
        reuse: Bool,
        reason: String,
        plan: CaptureSourcePlan,
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput
    ) {
        guard isEnabled else { return }

        mirrorToConsole("sessionReuse reuse=\(reuse) reason=\(reason) label=\(plan.requestedFocalLengthLabel.label) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0)) inputs=\(session.inputs.count) outputs=\(session.outputs.count) depthEnabled=\(photoOutput.isDepthDataDeliveryEnabled) depthSupported=\(photoOutput.isDepthDataDeliverySupported) device=\(deviceSummary(plan.resolvedCaptureDevice))")
        logger.info("sessionReuse reuse=\(reuse, privacy: .public) reason=\(reason, privacy: .public) label=\(plan.requestedFocalLengthLabel.label, privacy: .public) zoom=\(formatted(plan.zoom?.rawVideoZoomFactor ?? 1.0), privacy: .public) inputs=\(session.inputs.count, privacy: .public) outputs=\(session.outputs.count, privacy: .public) depthEnabled=\(photoOutput.isDepthDataDeliveryEnabled, privacy: .public) depthSupported=\(photoOutput.isDepthDataDeliverySupported, privacy: .public) device=\(deviceSummary(plan.resolvedCaptureDevice), privacy: .public)")
    }

    static func logDeviceFormatApplied(device: AVCaptureDevice, requestedFormat: AVCaptureDevice.Format?) {
        guard isEnabled else { return }

        let requestedSummary = requestedFormat.map(formatSummary) ?? "nil"
        mirrorToConsole("deviceFormat applied requested=\(requestedSummary) active=\(formatSummary(device.activeFormat)) activeDepth=\(device.activeDepthDataFormat.map(formatSummary) ?? "nil") device=\(deviceSummary(device))")
        logger.info("deviceFormat applied requested=\(requestedSummary, privacy: .public) active=\(formatSummary(device.activeFormat), privacy: .public) activeDepth=\(device.activeDepthDataFormat.map(formatSummary) ?? "nil", privacy: .public) device=\(deviceSummary(device), privacy: .public)")
    }

    static func logAppliedZoom(
        phase: String,
        requestedZoom: Double,
        clampedZoom: CGFloat,
        actualZoom: CGFloat,
        device: AVCaptureDevice
    ) {
        guard isEnabled else { return }

        let activePrimary = device.activePrimaryConstituent.map {
            "\($0.localizedName) [\($0.deviceType.rawValue)]"
        } ?? "nil"
        let formatSummary = formatSummary(device.activeFormat)

        mirrorToConsole("appliedZoom phase=\(phase) requested=\(formatted(requestedZoom)) clamped=\(formatted(Double(clampedZoom))) actual=\(formatted(Double(actualZoom))) device=\(device.localizedName) activePrimary=\(activePrimary) activeFormat=\(formatSummary)")
        logger.info("appliedZoom phase=\(phase, privacy: .public) requested=\(formatted(requestedZoom), privacy: .public) clamped=\(formatted(Double(clampedZoom)), privacy: .public) actual=\(formatted(Double(actualZoom)), privacy: .public) device=\(device.localizedName, privacy: .public) deviceType=\(device.deviceType.rawValue, privacy: .public) activePrimary=\(activePrimary, privacy: .public) activeFormat=\(formatSummary, privacy: .public) minZoom=\(formatted(Double(device.minAvailableVideoZoomFactor)), privacy: .public) maxZoom=\(formatted(Double(device.maxAvailableVideoZoomFactor)), privacy: .public)")
    }

    static func logPreviewCropRect(_ rect: CGRect) {
        guard isEnabled else { return }

        logger.info("previewCrop rect x=\(formatted(Double(rect.origin.x)), privacy: .public) y=\(formatted(Double(rect.origin.y)), privacy: .public) w=\(formatted(Double(rect.width)), privacy: .public) h=\(formatted(Double(rect.height)), privacy: .public)")
    }

    private static func logFocalOption(_ option: FocalLengthOption, event: String) {
        let depthSource = option.depthSource?.displayName ?? "nil"
        let actualZoom = option.zoom.rawVideoZoomFactor
        let format = option.depthSource?.formatSelection?.videoFormat
        let formatSummary = format.map(formatSummary) ?? "nil"
        let depthRanges = format?.supportedVideoZoomRangesForDepthDataDelivery
            .map { "\(formatted(Double($0.lowerBound)))...\(formatted(Double($0.upperBound)))" }
            .joined(separator: ",") ?? "nil"

        mirrorToConsole("FOV \(event) label=\(option.displayName) id=\(option.id) equivMM=\(formatted(option.equivalentFocalLength35mmMillimeters)) rawRequestedZoom=\(formatted(option.zoom.requestedZoomFactor)) rawActualZoom=\(formatted(actualZoom)) depth=\(depthSource) format=\(formatSummary) depthRanges=\(depthRanges) enabled=\(option.isEnabled)")
        logger.info("FOV \(event, privacy: .public) label=\(option.displayName, privacy: .public) id=\(option.id, privacy: .public) source=\(option.labelSource, privacy: .public) equivMM=\(formatted(option.equivalentFocalLength35mmMillimeters), privacy: .public) rawRequestedZoom=\(formatted(option.zoom.requestedZoomFactor), privacy: .public) rawActualZoom=\(formatted(actualZoom), privacy: .public) rgbDevice=\(option.rgbSource.deviceTypeRawValue, privacy: .public) rgbName=\(option.rgbSource.deviceName, privacy: .public) depth=\(depthSource, privacy: .public) format=\(formatSummary, privacy: .public) depthRanges=\(depthRanges, privacy: .public) enabled=\(option.isEnabled, privacy: .public)")
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatSummary(_ format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height) fov=\(formatted(Double(format.videoFieldOfView))) maxZoom=\(formatted(Double(format.videoMaxZoomFactor)))"
    }

    private static func deviceSummary(_ device: AVCaptureDevice) -> String {
        let activePrimary = device.activePrimaryConstituent.map {
            "\($0.localizedName) [\($0.deviceType.rawValue)]"
        } ?? "nil"
        return "\(device.localizedName) [\(device.deviceType.rawValue)] activePrimary=\(activePrimary) zoom=\(formatted(Double(device.videoZoomFactor)))"
    }

    private static func mirrorToConsole(_ message: String) {
        guard ProcessInfo.processInfo.arguments.contains("--tapcam-cycle-fov-diagnostics"),
              let data = "[FOVDiagnostics] \(message)\n".data(using: .utf8) else {
            return
        }

        FileHandle.standardError.write(data)
    }
}
