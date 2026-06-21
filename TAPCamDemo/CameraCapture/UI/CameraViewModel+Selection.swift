//
//  CameraViewModel+Selection.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Foundation

/// Selection planning for the SingleCam screen.
///
/// These methods translate Release FOV chips and camera switching into
/// capability-layer plans before the runtime controller mutates AVFoundation.
@MainActor
extension CameraViewModel {
    /// Applies a Release FOV chip selection to the current SingleCam plan.
    ///
    /// The option already contains the resolved RGB source, Apple-paired depth
    /// source, and raw depth-safe zoom factor produced by Planning.
    ///
    /// - Tag: SelectReleaseFOV
    func selectFocalLengthOption(_ option: FocalLengthOption) async {
        guard option.isEnabled else {
            statusMessage = option.disabledReason ?? CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.noDepthCameraAvailable,
                context: .configuration
            )
            return
        }

        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        depthSelectionMode = .automatic
        selectedRGBSourceID = option.rgbSource.id
        selectedZoomID = option.zoom.id
        selectedFocalLengthOptionID = option.id
        await configureCurrentSelection()
    }

    func switchCameraPosition() async {
        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        let current = capabilityMatrix.rgbSource(id: selectedRGBSourceID)
        let targetPosition: AVCaptureDevice.Position = current?.device.position == .front ? .back : .front

        if targetPosition == .front {
            guard let target = defaultRGBSource(position: .front) else {
                statusMessage = CameraCaptureStatusPresentation.message(
                    for: TAPDepthCaptureError.noDepthCameraAvailable,
                    context: .configuration
                )
                return
            }

            selectedRGBSourceID = target.id
            selectedZoomID = nil
            selectedFocalLengthOptionID = nil
        } else {
            let options = capabilityMatrix.focalLengthOptions()
            let target = capabilityMatrix.bestOption(nearEquivalentMillimeters: 24, in: options)
                ?? capabilityMatrix.defaultFocalLengthOption

            guard let target else {
                statusMessage = CameraCaptureStatusPresentation.message(
                    for: TAPDepthCaptureError.noDepthCameraAvailable,
                    context: .configuration
                )
                return
            }

            selectedRGBSourceID = target.rgbSource.id
            selectedZoomID = target.zoom.id
            selectedFocalLengthOptionID = target.id
        }

        depthSelectionMode = .automatic
        await configureCurrentSelection()
    }

    func configureDefaultSelection() async {
        guard let option = capabilityMatrix.defaultFocalLengthOption else {
            if let frontSource = defaultRGBSource(position: .front) {
                selectedRGBSourceID = frontSource.id
                selectedFocalLengthOptionID = nil
                selectedZoomID = nil
                depthSelectionMode = .automatic
                await configureCurrentSelection()
                return
            }

            isDepthCaptureReady = false
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.noDepthCameraAvailable,
                context: .configuration
            )
            return
        }

        selectedRGBSourceID = option.rgbSource.id
        selectedFocalLengthOptionID = option.id
        selectedZoomID = option.zoom.id
        depthSelectionMode = .automatic
        await configureCurrentSelection()
    }

    /// Rebuilds the active `CaptureSourcePlan` from the current UI state.
    ///
    /// This is where semantic FOV labels become a runtime plan with a preserved
    /// raw `videoZoomFactor`, then the plan is handed to the session controller.
    ///
    /// - Tag: ConfigureCurrentSelection
    func configureCurrentSelection() async {
        guard !isPausedForAnalysis else {
            return
        }

        #if DEBUG
        if isDebugDepthOverrideActive,
           let plan = makeDebugDepthOverridePlan() {
            await configureDebugDepthOverride(plan)
            return
        }
        #endif

        guard let rgbSource = capabilityMatrix.rgbSource(id: selectedRGBSourceID) else {
            await configureDefaultSelection()
            return
        }

        let currentFocalLengthOptions = capabilityMatrix.focalLengthOptions()
        let selectedFocalLengthOption = selectedFocalLengthOptionID.flatMap { selectedID in
            currentFocalLengthOptions.first(where: { $0.id == selectedID })
        }
        let preferredZoomFactor = selectedFocalLengthOption?.zoom.rawVideoZoomFactor
        let depthProfile = selectedFocalLengthOption?.depthSource
            ?? capabilityMatrix.depthProfiles(
                for: rgbSource,
                preferredZoomFactor: preferredZoomFactor
            )
            .first(where: \.isSelectable)
        /*
         Release FOV chips such as 48mm and 77mm are semantic framing choices,
         not always the same as the visible "2x/3x" zoom chips. Some Apple
         virtual depth formats expose their wide baseline at raw video zoom 2.0,
         so the 48mm slot can require raw zoom 4.0. Passing the Double keeps
         that non-standard factor alive when `ZoomCapabilityResolver` builds its
         runtime profile list; passing only `zoom-4x` would be lossy and would
         fall back to the first depth-safe zoom.
         */
        let plan = CaptureSourcePlan.make(
            rgbSource: rgbSource,
            depthSource: depthProfile,
            selectionMode: depthSelectionMode,
            selectedZoomID: selectedZoomID,
            selectedZoomFactor: preferredZoomFactor,
            cropRectNormalized: previewCropRectNormalized
        )

        configurationGeneration += 1
        let generation = configurationGeneration
        isDepthCaptureReady = false
        focalLengthOptions = currentFocalLengthOptions
        #if DEBUG
        debugDepthDeviceOptions = capabilityMatrix.debugDepthDeviceOptions()
        #endif
        selectedRGBSourceID = rgbSource.id
        selectedZoomID = plan.zoom?.id
        selectedFocalLengthOptionID = rgbSource.device.position == .back
            ? focalLengthOptions.first { $0.rgbSource.id == rgbSource.id && $0.zoom.id == plan.zoom?.id }?.id
            : nil
        activeCameraDisplayName = "\(plan.requestedFocalLengthLabel.label) · \(depthProfile?.displayName ?? "No Depth")"
        statusMessage = statusText(for: plan)

        do {
            let result = try await sessionController.configure(SessionConfigurationRequest(capturePlan: plan))

            guard generation == configurationGeneration, !isPausedForAnalysis else {
                sessionController.stop()
                return
            }

            activeSessionConfiguration = result
            activeCameraDisplayName = result.cameraDisplayName
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
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
    }

    func defaultRGBSource(position: AVCaptureDevice.Position) -> CameraProfile? {
        capabilityMatrix.rgbSources
            .filter { $0.isEnabled && $0.device.position == position }
            .max { lhs, rhs in
                CameraCapabilityResolver.automaticPriority(for: lhs.device.deviceType) < CameraCapabilityResolver.automaticPriority(for: rhs.device.deviceType)
            }
    }

    func statusText(for plan: CaptureSourcePlan) -> String {
        if plan.canCapturePhotoDepth {
            return "Ready · \(plan.pairingMode.rawValue) · crop metadata"
        }

        if plan.pairingMode == .requiresMultiCam {
            return CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.multicamRequired,
                context: .configuration
            )
        }

        return plan.compatibilityReason ?? CameraCaptureStatusPresentation.message(
            for: TAPDepthCaptureError.incompatibleRGBDepthPairing,
            context: .configuration
        )
    }

}
