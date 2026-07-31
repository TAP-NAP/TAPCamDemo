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
        guard !photographerModeState.isTransitioning, !isConfiguringSession else {
            return
        }
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
        guard !isSessionControllerSuspectedWedged,
              !photographerModeState.isTransitioning,
              !isConfiguringSession else {
            return
        }
        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        let current = capabilityMatrix.rgbSource(id: selectedRGBSourceID)
        let targetPosition: AVCaptureDevice.Position = current?.device.position == .front ? .back : .front

        if targetPosition == .front, photographerModeState.isActive {
            suspendedRearModeIntent = .photographer
            await transitionFromPhotographerModeToFrontCamera()
            return
        }

        if targetPosition == .back, suspendedRearModeIntent == .photographer {
            await transitionFromFrontCameraToPhotographerMode()
            return
        }

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
        guard !isSessionControllerSuspectedWedged else {
            statusMessage = "Camera service is still recovering."
            return
        }
        if !hasConsumedPhotographerModeStartupRequest {
            hasConsumedPhotographerModeStartupRequest = true
            if requestedPhotographerModeOnStart,
               photographerModeAvailability.isAvailable {
                let configured = await configurePhotographerMode(
                    recovery: .previous(runtimeSelectionSnapshot())
                )
                if configured {
                    return
                }
            }
        }

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

    /// Switches between the standard automatic path and the fixed LiDAR 1x
    /// Photographer path. UI should call this only for rear PHOTO, but Runtime
    /// repeats the safety gates so a stale or duplicated tap cannot expose an
    /// incompletely configured manual-control surface.
    func setPhotographerModeEnabled(_ isEnabled: Bool) async {
        guard !photographerModeState.isTransitioning,
              !isConfiguringSession,
              !isSessionControllerSuspectedWedged,
              !isVideoRecording,
              !isPreparingVideoMode,
              !isPausedForAnalysis else {
            return
        }

        guard photographerModeAvailability.isAvailable else {
            let reason = photographerModeAvailability.unavailableReason ?? .rearLiDARUnavailable
            photographerModeState = .unavailable(reason)
            statusMessage = reason.message
            return
        }

        guard isRearCameraActive else {
            statusMessage = "Photographer mode is available on the rear camera."
            return
        }

        if isEnabled {
            guard !photographerModeState.isActive else {
                return
            }
            #if DEBUG
            clearDebugDepthOverrideState()
            #endif
            standardRearSelectionBeforePhotographerMode = currentStandardSelectionSnapshot()
            _ = await configurePhotographerMode(
                recovery: .previous(runtimeSelectionSnapshot())
            )
        } else {
            guard photographerModeState.isActive else {
                suspendedRearModeIntent = .standard
                return
            }
            await transitionFromPhotographerModeToStandardRearCamera()
        }
    }

    private func reconfigureActivePhotographerMode() async {
        _ = await configurePhotographerMode(
            recovery: .previous(runtimeSelectionSnapshot())
        )
    }

    private func configurePhotographerMode(
        recovery: PhotographerModeRecovery
    ) async -> Bool {
        guard photographerModeAvailability.isAvailable,
              let plan = capabilityMatrix.photographerModeCapturePlan() else {
            let reason = photographerModeAvailability.unavailableReason ?? .oneXDepthFormatUnavailable
            photographerModeState = .unavailable(reason)
            suspendedRearModeIntent = .standard
            statusMessage = reason.message
            return false
        }

        cancelManualFocusRuntime()
        configurationGeneration += 1
        let generation = configurationGeneration
        photographerModeState = .activating
        isConfiguringSession = true
        isDepthCaptureReady = false
        armCameraPathConfigurationWatchdog(generation: generation)
        defer {
            finishSelectionConfiguration(generation: generation)
        }

        do {
            guard let request = makeSessionConfigurationRequest(
                for: plan,
                auxiliaryPreviewPolicy: .manualFocusLoupe
            ) else {
                throw PhotographerModeTransitionError(reason: .configurationFailed)
            }
            let result = try await sessionController.configure(request)
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return false
            }

            let runtimeAvailability = photographerModeRuntimeAvailability(for: result)
            guard runtimeAvailability.isAvailable else {
                throw PhotographerModeTransitionError(
                    reason: runtimeAvailability.unavailableReason ?? .configurationFailed
                )
            }

            applyPhotographerModeConfiguration(result)
            await applyRequestedGlobalAutoExposureBiasToActiveConfiguration()
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return false
            }
            photographerModeState = .active
            suspendedRearModeIntent = .photographer
            return true
        } catch {
            guard generation == configurationGeneration else {
                return false
            }
            let reason = (error as? PhotographerModeTransitionError)?.reason ?? .configurationFailed
            let recoveredMode = await recoverPhotographerModeTransition(
                recovery,
                generation: generation
            )
            guard generation == configurationGeneration else {
                return false
            }
            photographerModeState = .failed(recoveredMode: recoveredMode, reason: reason)
            suspendedRearModeIntent = recoveredMode == .photographer
                ? .photographer
                : .standard
            if recoveredMode == .unconfigured {
                hasPendingSelectionReconfiguration = true
            }
            statusMessage = reason.message
            return false
        }
    }

    private func transitionFromPhotographerModeToStandardRearCamera() async {
        guard let target = standardTargetSelection(
            position: .back,
            preferred: standardRearSelectionBeforePhotographerMode
        ) else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.noDepthCameraAvailable,
                context: .configuration
            )
            return
        }

        let previous = runtimeSelectionSnapshot()
        cancelManualFocusRuntime()
        configurationGeneration += 1
        let generation = configurationGeneration
        photographerModeState = .deactivating
        isConfiguringSession = true
        isDepthCaptureReady = false
        armCameraPathConfigurationWatchdog(generation: generation)
        defer {
            finishSelectionConfiguration(generation: generation)
        }

        do {
            let result = try await configureStandardTarget(target)
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return
            }
            applyStandardConfiguration(result, target: target)
            await applyRequestedGlobalAutoExposureBiasToActiveConfiguration()
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return
            }
            photographerModeState = .standard
            suspendedRearModeIntent = .standard
            standardRearSelectionBeforePhotographerMode = nil
        } catch {
            guard generation == configurationGeneration else {
                return
            }
            let recoveredMode = await recoverPhotographerModeTransition(
                .previous(previous),
                generation: generation
            )
            guard generation == configurationGeneration else {
                return
            }
            photographerModeState = .failed(
                recoveredMode: recoveredMode,
                reason: .configurationFailed
            )
            suspendedRearModeIntent = recoveredMode == .photographer
                ? .photographer
                : .standard
            if recoveredMode == .unconfigured {
                hasPendingSelectionReconfiguration = true
            }
            statusMessage = PhotographerModeUnavailableReason.configurationFailed.message
        }
    }

    private func transitionFromPhotographerModeToFrontCamera() async {
        guard let target = standardTargetSelection(position: .front, preferred: nil) else {
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.noDepthCameraAvailable,
                context: .configuration
            )
            return
        }

        let previous = runtimeSelectionSnapshot()
        cancelManualFocusRuntime()
        configurationGeneration += 1
        let generation = configurationGeneration
        photographerModeState = .deactivating
        isConfiguringSession = true
        isDepthCaptureReady = false
        armCameraPathConfigurationWatchdog(generation: generation)
        defer {
            finishSelectionConfiguration(generation: generation)
        }

        do {
            let result = try await configureStandardTarget(target)
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return
            }
            applyStandardConfiguration(result, target: target)
            await applyRequestedGlobalAutoExposureBiasToActiveConfiguration()
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return
            }
            photographerModeState = .standard
        } catch {
            guard generation == configurationGeneration else {
                return
            }
            let recoveredMode = await recoverPhotographerModeTransition(
                .previous(previous),
                generation: generation
            )
            guard generation == configurationGeneration else {
                return
            }
            photographerModeState = .failed(
                recoveredMode: recoveredMode,
                reason: .configurationFailed
            )
            suspendedRearModeIntent = recoveredMode == .photographer
                ? .photographer
                : .standard
            if recoveredMode == .unconfigured {
                hasPendingSelectionReconfiguration = true
            }
            statusMessage = PhotographerModeUnavailableReason.configurationFailed.message
        }
    }

    private func transitionFromFrontCameraToPhotographerMode() async {
        let previous = runtimeSelectionSnapshot()
        _ = await configurePhotographerMode(
            recovery: .standardRearOrPrevious(
                preferred: standardRearSelectionBeforePhotographerMode,
                previous: previous
            )
        )
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

        guard !isSessionControllerSuspectedWedged else {
            statusMessage = "Camera service is still recovering."
            return
        }

        guard !isConfiguringSession,
              !photographerModeState.isTransitioning else {
            hasPendingSelectionReconfiguration = true
            return
        }
        hasPendingSelectionReconfiguration = false

        if photographerModeState.effectiveMode == .photographer,
           !photographerModeState.isTransitioning {
            await reconfigureActivePhotographerMode()
            return
        }

        #if DEBUG
        if isDebugDepthOverrideActive,
           let plan = makeDebugDepthOverridePlan() {
            await configureDebugDepthOverride(plan)
            return
        }
        #endif

        guard let rgbSource = capabilityMatrix.standardRGBSource(id: selectedRGBSourceID) else {
            await configureDefaultSelection()
            return
        }

        let currentFocalLengthOptions = capabilityMatrix.focalLengthOptions()
        let selectedFocalLengthOption = selectedFocalLengthOptionID.flatMap { selectedID in
            currentFocalLengthOptions.first(where: { $0.id == selectedID })
        }
        let preferredZoomFactor = selectedFocalLengthOption?.zoom.rawVideoZoomFactor
        let depthProfile = selectedFocalLengthOption?.depthSource
            ?? capabilityMatrix.standardDepthProfiles(
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

        let isRecoveringUnconfiguredCamera = photographerModeState.requiresStandardRecovery
        cancelManualFocusRuntime()
        configurationGeneration += 1
        let generation = configurationGeneration
        isConfiguringSession = true
        if isRecoveringUnconfiguredCamera {
            armCameraPathConfigurationWatchdog(generation: generation)
        }
        defer {
            finishSelectionConfiguration(generation: generation)
        }
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
            guard let request = makeSessionConfigurationRequest(for: plan) else {
                activeSessionConfiguration = nil
                isDepthCaptureReady = false
                nativePreviewAspectRatio = 3.0 / 4.0
                return
            }
            let result = try await sessionController.configure(request)

            guard generation == configurationGeneration, !isPausedForAnalysis else {
                sessionController.stop()
                return
            }

            activeSessionConfiguration = result
            activeCameraDisplayName = result.cameraDisplayName
            nativePreviewAspectRatio = result.nativePreviewAspectRatio
            isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
            statusMessage = statusText(for: result.capturePlan)
            await applyRequestedGlobalAutoExposureBiasToActiveConfiguration()
            guard generation == configurationGeneration, !isPausedForAnalysis else {
                return
            }
            if photographerModeState.effectiveMode != .photographer {
                photographerModeState = .standard
                if result.device.position == .back {
                    suspendedRearModeIntent = .standard
                }
            }
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
            .filter {
                $0.isEnabled
                    && $0.device.position == position
                    && $0.device.deviceType != .builtInLiDARDepthCamera
            }
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

    private func makeSessionConfigurationRequest(
        for plan: CaptureSourcePlan,
        auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy = .none
    ) -> SessionConfigurationRequest? {
        let outputFormatPreference = CameraOutputFormatPreference.resolved(
            rawValue: UserDefaults.standard.string(forKey: CameraOutputFormatPreference.storageKey)
                ?? CameraOutputFormatPreference.defaultValue.rawValue
        )
        let photoQualityPreference = CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: UserDefaults.standard.string(forKey: CameraPhotoQualityPreference.storageKey)
                ?? CameraPhotoQualityPreference.defaultValue.rawValue
        )
        let outputResolution = outputFormatPreference.selectionIntent.resolved()
        guard let selectedProfile = outputResolution.selectedProfile,
              outputResolution.isExecutable else {
            let presentation = CaptureOutputProfileSelectionPresentation(resolution: outputResolution)
            statusMessage = "\(presentation.title) · \(presentation.detail)"
            return nil
        }
        return SessionConfigurationRequest(
            capturePlan: plan,
            outputProfile: photoQualityPreference.applied(to: selectedProfile),
            auxiliaryPreviewPolicy: auxiliaryPreviewPolicy
        )
    }

    private func currentStandardSelectionSnapshot() -> StandardCameraSelectionSnapshot {
        StandardCameraSelectionSnapshot(
            rgbSourceID: selectedRGBSourceID,
            focalLengthOptionID: selectedFocalLengthOptionID,
            zoomID: selectedZoomID,
            previewCropRectNormalized: previewCropRectNormalized
        )
    }

    private func standardTargetSelection(
        position: AVCaptureDevice.Position,
        preferred: StandardCameraSelectionSnapshot?
    ) -> StandardTargetSelection? {
        let options = capabilityMatrix.focalLengthOptions()

        if position == .front {
            guard let rgbSource = defaultRGBSource(position: .front) else {
                return nil
            }
            let depthProfile = capabilityMatrix.standardDepthProfiles(for: rgbSource)
                .first(where: \.isSelectable)
            let plan = CaptureSourcePlan.make(
                rgbSource: rgbSource,
                depthSource: depthProfile,
                selectionMode: .automatic,
                selectedZoomID: nil,
                cropRectNormalized: .fullFrame
            )
            guard plan.canCapturePhotoDepth else {
                return nil
            }
            return StandardTargetSelection(
                plan: plan,
                focalLengthOptions: options,
                selectedRGBSourceID: rgbSource.id,
                selectedFocalLengthOptionID: nil,
                selectedZoomID: plan.zoom?.id,
                previewCropRectNormalized: .fullFrame
            )
        }

        let preferredOption = preferred?.focalLengthOptionID.flatMap { preferredID in
            options.first(where: { $0.id == preferredID && $0.isEnabled })
        } ?? preferred.flatMap { snapshot in
            options.first {
                $0.isEnabled
                    && $0.rgbSource.id == snapshot.rgbSourceID
                    && $0.zoom.id == snapshot.zoomID
            }
        }
        guard let option = preferredOption
            ?? capabilityMatrix.bestOption(nearEquivalentMillimeters: 24, in: options)
            ?? capabilityMatrix.defaultFocalLengthOption else {
            return nil
        }
        let cropRect = preferred?.previewCropRectNormalized ?? .fullFrame
        let plan = CaptureSourcePlan.make(
            rgbSource: option.rgbSource,
            depthSource: option.depthSource,
            selectionMode: .automatic,
            selectedZoomID: option.zoom.id,
            selectedZoomFactor: option.zoom.rawVideoZoomFactor,
            cropRectNormalized: cropRect
        )
        guard plan.canCapturePhotoDepth else {
            return nil
        }
        return StandardTargetSelection(
            plan: plan,
            focalLengthOptions: options,
            selectedRGBSourceID: option.rgbSource.id,
            selectedFocalLengthOptionID: option.id,
            selectedZoomID: plan.zoom?.id,
            previewCropRectNormalized: cropRect
        )
    }

    private func configureStandardTarget(
        _ target: StandardTargetSelection
    ) async throws -> SessionConfigurationResult {
        guard let request = makeSessionConfigurationRequest(for: target.plan) else {
            throw PhotographerModeTransitionError(reason: .configurationFailed)
        }
        return try await sessionController.configure(request)
    }

    private func applyStandardConfiguration(
        _ result: SessionConfigurationResult,
        target: StandardTargetSelection
    ) {
        activeSessionConfiguration = result
        focalLengthOptions = target.focalLengthOptions
        selectedRGBSourceID = target.selectedRGBSourceID
        selectedFocalLengthOptionID = target.selectedFocalLengthOptionID
        selectedZoomID = target.selectedZoomID
        previewCropRectNormalized = target.previewCropRectNormalized
        depthSelectionMode = .automatic
        activeCameraDisplayName = result.cameraDisplayName
        nativePreviewAspectRatio = result.nativePreviewAspectRatio
        isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
        statusMessage = statusText(for: result.capturePlan)
    }

    private func applyPhotographerModeConfiguration(
        _ result: SessionConfigurationResult
    ) {
        activeSessionConfiguration = result
        focalLengthOptions = capabilityMatrix.focalLengthOptions()
        selectedRGBSourceID = result.capturePlan.rgbSource.id
        selectedFocalLengthOptionID = nil
        selectedZoomID = result.capturePlan.zoom?.id
        previewCropRectNormalized = .fullFrame
        depthSelectionMode = .manual
        activeCameraDisplayName = result.cameraDisplayName
        nativePreviewAspectRatio = result.nativePreviewAspectRatio
        isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
        statusMessage = statusText(for: result.capturePlan)
    }

    private func photographerModeRuntimeAvailability(
        for result: SessionConfigurationResult
    ) -> PhotographerModeAvailability {
        let capability = result.controlCapabilities
        let plan = result.capturePlan
        let plannedAtOneX = plan.zoom?.matchesRawVideoZoomFactor(1.0) == true
            && plan.formatSelection != nil
        let runtimeAtOneX = abs(Double(result.device.videoZoomFactor) - 1.0) < 0.001
        return PhotographerModeAvailability.resolve(
            PhotographerModeCapabilityFacts(
                isRearLiDARDevice: result.device.deviceType == .builtInLiDARDepthCamera
                    && result.device.position == .back,
                hasOneXDepthFormat: plannedAtOneX && runtimeAtOneX,
                supportsPhotoDepthDelivery: result.depthDeliverySupported
                    && plan.canCapturePhotoDepth,
                supportsCustomExposure: capability.exposure.supportsCustomExposure,
                hasAdjustableISORange: capability.exposure.isoRange.isAdjustable,
                hasAdjustableShutterRange: capability.exposure.shutterDurationRangeSeconds.isAdjustable,
                supportsLockedFocus: capability.focus.supportsLockedFocus,
                supportsCustomLensPosition: capability.focus.supportsCustomLensPosition
            )
        )
    }

    private func runtimeSelectionSnapshot() -> RuntimeSelectionSnapshot {
        RuntimeSelectionSnapshot(
            activeSessionConfiguration: activeSessionConfiguration,
            focalLengthOptions: focalLengthOptions,
            selectedRGBSourceID: selectedRGBSourceID,
            selectedFocalLengthOptionID: selectedFocalLengthOptionID,
            selectedZoomID: selectedZoomID,
            previewCropRectNormalized: previewCropRectNormalized,
            depthSelectionMode: depthSelectionMode,
            photographerMode: photographerModeState.effectiveMode,
            nativePreviewAspectRatio: nativePreviewAspectRatio
        )
    }

    private func restoreRuntimeSelection(
        _ snapshot: RuntimeSelectionSnapshot,
        generation: Int
    ) async -> Bool {
        guard generation == configurationGeneration else {
            return false
        }

        guard let previousConfiguration = snapshot.activeSessionConfiguration else {
            activeSessionConfiguration = nil
            focalLengthOptions = snapshot.focalLengthOptions
            selectedRGBSourceID = snapshot.selectedRGBSourceID
            selectedFocalLengthOptionID = snapshot.selectedFocalLengthOptionID
            selectedZoomID = snapshot.selectedZoomID
            previewCropRectNormalized = snapshot.previewCropRectNormalized
            depthSelectionMode = snapshot.depthSelectionMode
            nativePreviewAspectRatio = snapshot.nativePreviewAspectRatio
            isDepthCaptureReady = false
            return false
        }

        do {
            let result = try await sessionController.configure(
                SessionConfigurationRequest(
                    capturePlan: previousConfiguration.capturePlan,
                    outputProfile: previousConfiguration.outputProfile,
                    auxiliaryPreviewPolicy: previousConfiguration.auxiliaryPreviewPolicy
                )
            )
            guard generation == configurationGeneration else {
                return false
            }
            activeSessionConfiguration = result
            focalLengthOptions = snapshot.focalLengthOptions
            selectedRGBSourceID = snapshot.selectedRGBSourceID
            selectedFocalLengthOptionID = snapshot.selectedFocalLengthOptionID
            selectedZoomID = snapshot.selectedZoomID
            previewCropRectNormalized = snapshot.previewCropRectNormalized
            depthSelectionMode = snapshot.depthSelectionMode
            activeCameraDisplayName = result.cameraDisplayName
            nativePreviewAspectRatio = result.nativePreviewAspectRatio
            isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
            await applyRequestedGlobalAutoExposureBiasToActiveConfiguration()
            return isDepthCaptureReady
        } catch {
            guard generation == configurationGeneration else {
                return false
            }
            activeSessionConfiguration = nil
            isDepthCaptureReady = false
            nativePreviewAspectRatio = 3.0 / 4.0
            return false
        }
    }

    private func recoverPhotographerModeTransition(
        _ recovery: PhotographerModeRecovery,
        generation: Int
    ) async -> PhotographerModeStableMode {
        switch recovery {
        case .previous(let snapshot):
            let didRestore = await restoreRuntimeSelection(snapshot, generation: generation)
            return didRestore ? snapshot.photographerMode : .unconfigured

        case .standardRearOrPrevious(let preferred, let previous):
            if let target = standardTargetSelection(position: .back, preferred: preferred),
               let result = try? await configureStandardTarget(target),
               generation == configurationGeneration {
                applyStandardConfiguration(result, target: target)
                await applyRequestedGlobalAutoExposureBiasToActiveConfiguration()
                if isDepthCaptureReady {
                    return .standard
                }
            }
            let didRestore = await restoreRuntimeSelection(previous, generation: generation)
            return didRestore ? previous.photographerMode : .unconfigured
        }
    }

    private func finishSelectionConfiguration(generation: Int) {
        guard generation == configurationGeneration else {
            return
        }
        cancelCameraPathConfigurationWatchdog(generation: generation)
        isConfiguringSession = false
        guard hasPendingSelectionReconfiguration else {
            return
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.hasPendingSelectionReconfiguration,
                  !self.isPausedForAnalysis else {
                return
            }
            await self.configureCurrentSelection()
        }
    }

}

private struct StandardTargetSelection {
    let plan: CaptureSourcePlan
    let focalLengthOptions: [FocalLengthOption]
    let selectedRGBSourceID: String?
    let selectedFocalLengthOptionID: String?
    let selectedZoomID: String?
    let previewCropRectNormalized: CropRectNormalized
}

private struct RuntimeSelectionSnapshot {
    let activeSessionConfiguration: SessionConfigurationResult?
    let focalLengthOptions: [FocalLengthOption]
    let selectedRGBSourceID: String?
    let selectedFocalLengthOptionID: String?
    let selectedZoomID: String?
    let previewCropRectNormalized: CropRectNormalized
    let depthSelectionMode: DepthSelectionMode
    let photographerMode: PhotographerModeStableMode
    let nativePreviewAspectRatio: Double
}

private enum PhotographerModeRecovery {
    case previous(RuntimeSelectionSnapshot)
    case standardRearOrPrevious(
        preferred: StandardCameraSelectionSnapshot?,
        previous: RuntimeSelectionSnapshot
    )
}

private struct PhotographerModeTransitionError: Error {
    let reason: PhotographerModeUnavailableReason
}
