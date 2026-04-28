//
//  CameraViewModel+Debug.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

#if DEBUG
@preconcurrency import AVFoundation
import Foundation

/// Debug-only override state for exercising depth-capable SingleCam devices.
///
/// This keeps engineering controls separate from Release FOV selection while
/// still producing the same `CaptureSourcePlan` shape used by normal capture.
@MainActor
extension CameraViewModel {
    var debugZoomSliderRange: ClosedRange<Double> {
        let ranges = debugZoomCapability?.depthSafeZoomRanges ?? []
        guard let lower = ranges.map(\.lowerBound).min(),
              let upper = ranges.map(\.upperBound).max(),
              lower < upper else {
            return 1.0...1.0
        }
        return lower...upper
    }

    var debugZoomSliderEnabled: Bool {
        debugZoomCapability?.isContinuous == true && debugZoomSliderRange.lowerBound < debugZoomSliderRange.upperBound
    }

    /// Overrides preview and capture to one depth-capable SingleCam device.
    ///
    /// Debug mode does not pair an arbitrary RGB camera with an arbitrary depth
    /// camera. It switches the whole `AVCaptureSession + AVCapturePhotoOutput`
    /// path to the selected device, then lets engineers explore depth-safe zoom.
    ///
    /// - Tag: SelectDebugDepthDevice
    func selectDebugDepthDevice(_ option: DebugDepthDeviceOption) async {
        guard option.isSelectable,
              let rgbSource = option.rgbSource,
              let device = option.device else {
            statusMessage = option.disabledReason ?? TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        /*
         Picking a Debug depth device is a lens/source switch. It should start at
         that device's native 1x framing instead of inheriting a previous Debug
         or Release zoom. The format selection is therefore resolved against 1x
         before the override plan is built.
         */
        let initialZoomFactor = 1.0
        let initialFormatSelection = CameraCapabilityResolver.bestDepthFormatSelection(
            for: device,
            preferredZoomFactor: initialZoomFactor
        ) ?? option.formatSelection

        guard let initialFormatSelection,
              let depthProfile = option.depthProfile(formatSelection: initialFormatSelection) else {
            statusMessage = option.disabledReason ?? TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        /*
         Debug depth selection is an override of the single-cam capture pipeline,
         not a second device layered on top of the Release FOV selection. The
         selected depth-capable device becomes the source for preview, RGB photo,
         and `AVCapturePhoto.depthData`, which keeps the Apple paired-depth
         guarantees intact while we explore hardware behavior.
         */
        let zoomCapability = ZoomCapabilityResolver.resolve(
            rgbSource: rgbSource,
            depthProfile: depthProfile,
            selectedZoomID: nil,
            selectedZoomFactor: initialZoomFactor
        )
        let preferredZoom = zoomCapability.zoomProfiles.first { $0.isEnabled && $0.matchesRawVideoZoomFactor(initialZoomFactor) }
            ?? zoomCapability.zoomProfiles.first(where: \.isEnabled)

        isDebugDepthOverrideActive = true
        depthSelectionMode = .debugDepthOverride
        selectedRGBSourceID = rgbSource.id
        selectedZoomID = nil
        selectedFocalLengthOptionID = nil
        debugSelectedDepthDeviceID = option.id
        debugSelectedZoomID = preferredZoom?.id
        debugSelectedZoomFactor = preferredZoom?.rawVideoZoomFactor ?? initialZoomFactor
        debugZoomCapability = zoomCapability
        debugZoomProfiles = zoomCapability.zoomProfiles
        await configureCurrentSelection()
    }

    func selectDebugZoom(_ zoom: ZoomProfile) async {
        guard zoom.isEnabled else {
            statusMessage = zoom.disabledReason ?? TAPDepthCaptureError.unsupportedZoomFactor.localizedDescription
            return
        }

        isDebugDepthOverrideActive = true
        let isFixedCandidate = CameraCapabilityResolver.candidateZoomFactors
            .contains { abs($0 - zoom.rawVideoZoomFactor) < 0.001 }
        debugSelectedZoomID = isFixedCandidate ? zoom.id : nil
        debugSelectedZoomFactor = zoom.rawVideoZoomFactor
        await configureCurrentSelection()
    }

    func selectDebugZoomFactor(_ zoomFactor: Double) async {
        guard let capability = debugZoomCapability else {
            statusMessage = TAPDepthCaptureError.unsupportedZoomFactor.localizedDescription
            return
        }

        isDebugDepthOverrideActive = true
        let clamped = depthSafeZoomFactor(zoomFactor, capability: capability)
        debugSelectedZoomID = nil
        debugSelectedZoomFactor = clamped
        await configureCurrentSelection()
    }
    func makeDebugDepthOverridePlan() -> CaptureSourcePlan? {
        guard let option = debugDepthDeviceOptions.first(where: { $0.id == debugSelectedDepthDeviceID }),
              option.isSelectable,
              let rgbSource = option.rgbSource,
              let device = option.device else {
            return nil
        }

        /*
         Depth-safe zoom support belongs to the active video format, not just to
         the device. When the Debug zoom control moves to 2x/3x, re-resolve the
         depth format for that requested factor before building the plan. This
         prevents virtual devices such as Dual Wide/Triple/TrueDepth from briefly
         applying a zoom and then snapping back because the previously selected
         high-resolution format only supported depth at 1x.
         */
        let formatSelection = CameraCapabilityResolver.bestDepthFormatSelection(
            for: device,
            preferredZoomFactor: debugSelectedZoomFactor
        ) ?? option.formatSelection

        guard let formatSelection,
              let depthProfile = option.depthProfile(formatSelection: formatSelection) else {
            return nil
        }

        return CaptureSourcePlan.make(
            rgbSource: rgbSource,
            depthSource: depthProfile,
            selectionMode: .debugDepthOverride,
            selectedZoomID: debugSelectedZoomID,
            selectedZoomFactor: debugSelectedZoomID == nil ? debugSelectedZoomFactor : nil,
            cropRectNormalized: previewCropRectNormalized
        )
    }

    func configureDebugDepthOverride(_ plan: CaptureSourcePlan) async {
        configurationGeneration += 1
        let generation = configurationGeneration
        isDepthCaptureReady = false
        focalLengthOptions = capabilityMatrix.focalLengthOptions()
        debugDepthDeviceOptions = capabilityMatrix.debugDepthDeviceOptions()
        debugZoomCapability = plan.zoomCapability
        debugZoomProfiles = plan.zoomCapability.zoomProfiles
        if debugSelectedZoomID != nil {
            debugSelectedZoomID = plan.zoom?.id
        }
        debugSelectedZoomFactor = plan.zoom?.rawVideoZoomFactor ?? debugSelectedZoomFactor
        debugFOVLabel = debugFOVText(for: plan)
        activeCameraDisplayName = "Debug · \(plan.depthSource?.displayName ?? "No Depth") · \(debugFOVLabel)"
        statusMessage = statusText(for: plan)

        do {
            let result = try await sessionController.configure(SessionConfigurationRequest(capturePlan: plan))

            guard generation == configurationGeneration else {
                return
            }

            activeSessionConfiguration = result
            let actualZoomFactor = Double(result.device.videoZoomFactor)
            debugSelectedZoomFactor = actualZoomFactor
            debugFOVLabel = debugFOVText(for: result.capturePlan, zoomFactor: actualZoomFactor)
            activeCameraDisplayName = "Debug · \(result.capturePlan.depthSource?.displayName ?? "No Depth") · \(debugFOVLabel)"
            nativePreviewAspectRatio = result.nativePreviewAspectRatio
            isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
            statusMessage = statusText(for: result.capturePlan)
        } catch {
            guard generation == configurationGeneration else {
                return
            }

            activeSessionConfiguration = nil
            isDepthCaptureReady = false
            nativePreviewAspectRatio = 3.0 / 4.0
            statusMessage = error.localizedDescription
        }
    }
    func clearDebugDepthOverrideState() {
        isDebugDepthOverrideActive = false
        debugSelectedDepthDeviceID = nil
        debugSelectedZoomID = nil
        debugSelectedZoomFactor = 1.0
        debugZoomProfiles = []
        debugZoomCapability = nil
        debugFOVLabel = "24mm"
        depthSelectionMode = .automatic
    }

    func depthSafeZoomFactor(_ requested: Double, capability: ZoomCapability) -> Double {
        /*
         Apple exposes depth-delivery zoom as runtime format data. Some formats
         allow continuous depth-safe ranges; others only allow discrete zoom
         factors. The Debug slider must therefore clamp to the nearest legal
         value before we ask `CaptureSessionController` to set `videoZoomFactor`.
         */
        let ranges = capability.depthSafeZoomRanges.isEmpty
            ? [capability.minAvailableVideoZoomFactor...capability.maxAvailableVideoZoomFactor]
            : capability.depthSafeZoomRanges

        if ranges.contains(where: { $0.contains(requested) }) {
            return requested
        }

        return ranges
            .flatMap { [$0.lowerBound, $0.upperBound] }
            .min { lhs, rhs in abs(lhs - requested) < abs(rhs - requested) }
            ?? capability.currentZoomFactor
            ?? 1.0
    }

    func debugFOVText(for plan: CaptureSourcePlan, zoomFactor: Double? = nil) -> String {
        let resolvedZoomFactor = zoomFactor
            ?? plan.zoom?.rawVideoZoomFactor
            ?? 1.0
        let equivalentMillimeters = FocalLengthLabelResolver.equivalentMillimeters(
            for: plan.rgbSource,
            rawVideoZoomFactor: resolvedZoomFactor,
            formatSelection: plan.formatSelection
        )
        let label = FocalLengthLabelResolver.label(
            equivalentMillimeters: equivalentMillimeters,
            source: "\(plan.rgbSource.focalLengthLabelSource)+debugRawVideoZoomFactor"
        ).label
        let zoom = formattedZoom(resolvedZoomFactor)
        return "\(label) · \(zoom)"
    }

    func formattedZoom(_ zoom: Double) -> String {
        if abs(zoom.rounded() - zoom) < 0.01 {
            return "\(Int(zoom.rounded()))x"
        }
        return String(format: "%.1fx", zoom)
    }
}
#endif
