//
//  CameraView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Combine
import OSLog
import SwiftUI
import UIKit

enum CameraFeedbackPreferences {
    static let shutterHapticsEnabledKey = "CameraShutterHapticsEnabled"
    static let defaultShutterHapticsEnabled = true
    static let shutterSoundEnabledKey = "CameraShutterSoundEnabled"
    static let defaultShutterSoundEnabled = true
}

/// Main SingleCam photo-depth capture screen.
///
/// The view is intentionally thin: it renders FOV options, Debug depth override
/// controls, Debug zoom profiles, and metrics supplied by `CameraViewModel`.
/// AVFoundation details stay below the capability/session layers, which keeps
/// the UI from re-implementing device compatibility rules.
///
/// - Tag: CameraCaptureRootView
struct CameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private let startsAutomatically: Bool
    private let initialReadinessGate: CameraInitialReadinessGate
    @StateObject private var lifecycleCoordinator: CaptureLifecycleCoordinator
    @StateObject private var viewModel: CameraViewModel
    @StateObject private var routeStore: CameraRouteStore
    @StateObject private var chromeOrientation: CameraChromeOrientationController
    @StateObject private var appAttestController: AppAttestRuntimeController
    @StateObject private var hapticFeedbackController: CameraHapticFeedbackController
    private let intentHandoffStore: TAPCamIntentHandoffStore
    @State private var didCompleteInitialReadinessGate = false
    @State private var isShowingSettings = false
    @State private var selectedMode: CameraCaptureModeOption = .photo
    @State private var flashMode: CameraFlashControlMode
    @State private var isLivePhotoEnabled: Bool
    @State private var focusMode = CameraFocusControlMode.auto
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @State private var activeAdjustmentControl: CameraAdjustmentControl?
    @State private var exposureControlState: CameraExposureControlState?
    @State private var latestExposureControlDebugState: CameraExposureControlDebugState?
    #else
    @State private var isBasicEVStripVisible = false
    #endif
    @State private var globalEVBias: Double
    @State private var globalEVApplyTask: Task<Void, Never>?
    @State private var temporaryFocusEVOffset = 0.0
    @State private var temporaryFocusEVApplyTask: Task<Void, Never>?
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @State private var adjustmentDraft = CameraAdjustmentControlDraft.fallback
    @State private var adjustmentDraftMemory = CameraAdjustmentControlDraftMemory()
    @State private var adjustmentApplyTask: Task<Void, Never>?
    @State private var exposureApplyTask: Task<Void, Never>?
    @State private var exposureReadbackTask: Task<Void, Never>?
    @State private var manualFocusAssistToken: UUID?
    @State private var focusLoupePulseID: UUID?
    @State private var lastFocusMeteringAt = Date.distantPast
    #endif
    @State private var viewfinderHint: String?
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var isShutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var isShutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled
    @AppStorage(CameraOutputFormatPreference.storageKey)
    private var outputFormatRawValue = CameraOutputFormatPreference.defaultValue.rawValue
    @AppStorage(CameraPhotoQualityPreference.storageKey)
    private var photoQualityRawValue = CameraPhotoQualityPreference.defaultValue.rawValue
    @AppStorage(CameraFlashControlMode.startupPolicyKey)
    private var flashStartupPolicyRawValue = CameraFlashControlMode.defaultStartupPolicy.rawValue
    @AppStorage(CameraFlashControlMode.lastModeKey)
    private var lastFlashModeRawValue = CameraFlashControlMode.defaultLastMode.rawValue
    @AppStorage(CameraGuideOverlayPreference.storageKey)
    private var guideOverlayRawValue = CameraGuideOverlayPreference.defaultValue.rawValue
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue
    @AppStorage(CameraDepthAvailabilityHintPreferences.showsHintsKey)
    private var showsDepthAvailabilityHints = CameraDepthAvailabilityHintPreferences.defaultShowsHints
    @AppStorage(CameraFocusMagnifierPreference.storageKey)
    private var focusMagnifierRawValue = CameraFocusMagnifierPreference.defaultValue.rawValue
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @AppStorage(CameraManualFocusTapAssistPreferences.isEnabledKey)
    private var isManualFocusTapAssistEnabled = CameraManualFocusTapAssistPreferences.defaultIsEnabled
    #endif
    @AppStorage(CameraLivePhotoPreferences.startupPolicyKey)
    private var livePhotoStartupPolicyRawValue = CameraLivePhotoPreferences.defaultStartupPolicy.rawValue
    @AppStorage(CameraLivePhotoPreferences.lastEnabledKey)
    private var lastLivePhotoEnabled = CameraLivePhotoPreferences.defaultLastEnabled
    @AppStorage(CameraCaptureDataUsePreferences.usesMicrophoneDataKey)
    private var usesMicrophoneData = CameraCaptureDataUsePreferences.defaultUsesMicrophoneData

    init(
        viewModel: CameraViewModel? = nil,
        routeStore: CameraRouteStore? = nil,
        appAttestController: AppAttestRuntimeController? = nil,
        lifecycleCoordinator: CaptureLifecycleCoordinator = CaptureLifecycleCoordinator(),
        hapticFeedbackController: CameraHapticFeedbackController = CameraHapticFeedbackController(),
        intentHandoffStore: TAPCamIntentHandoffStore = TAPCamIntentHandoffStore(),
        initialReadinessGate: CameraInitialReadinessGate = .disabled,
        startsAutomatically: Bool = true
    ) {
        let initialGlobalEVBias = CameraEVPreferences.resolvedLaunchBias()
        let initialFlashMode = CameraFlashControlMode.resolvedStartupMode()
        let initialLivePhotoEnabled = CameraLivePhotoPreferences.resolvedStartupIsEnabled()
        self.startsAutomatically = startsAutomatically
        self.initialReadinessGate = initialReadinessGate
        self.intentHandoffStore = intentHandoffStore
        _lifecycleCoordinator = StateObject(wrappedValue: lifecycleCoordinator)
        _hapticFeedbackController = StateObject(wrappedValue: hapticFeedbackController)
        let resolvedViewModel = viewModel ?? CameraViewModel()
        resolvedViewModel.requestedGlobalAutoExposureBias = initialGlobalEVBias
        _viewModel = StateObject(wrappedValue: resolvedViewModel)
        _flashMode = State(initialValue: initialFlashMode)
        _isLivePhotoEnabled = State(initialValue: initialLivePhotoEnabled)
        _globalEVBias = State(initialValue: initialGlobalEVBias)
        if let routeStore {
            _routeStore = StateObject(wrappedValue: routeStore)
        } else {
            _routeStore = StateObject(wrappedValue: CameraRouteStore())
        }
        _chromeOrientation = StateObject(wrappedValue: CameraChromeOrientationController())
        if let appAttestController {
            _appAttestController = StateObject(wrappedValue: appAttestController)
        } else {
            _appAttestController = StateObject(wrappedValue: AppAttestRuntimeController())
        }
    }

    var body: some View {
        NavigationStack {
            cameraSurface
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: depthAlbumPresentedBinding) {
                    DepthAlbumPickerView(routeStore: routeStore)
                        .toolbar(.visible, for: .navigationBar)
                }
        }
        .statusBarHidden(true)
        .environment(\.cameraHapticFeedbackController, hapticFeedbackController)
        .sheet(isPresented: $isShowingSettings) {
            DepthAnalyzerSettingsView(
                appAttestController: appAttestController,
                shutterSoundSuppressionSupported: viewModel.isShutterSoundSuppressionSupported
            )
        }
        .cameraScreenLifecycle(
            startsAutomatically: startsAutomatically,
            lifecycleCoordinator: lifecycleCoordinator,
            viewModel: viewModel,
            routeStore: routeStore,
            chromeOrientation: chromeOrientation,
            appAttestController: appAttestController,
            isSettingsPresented: isShowingSettings
        )
        .overlay {
            if initialReadinessState.blocksInteraction {
                CameraInitialReadinessOverlayView(
                    state: initialReadinessState,
                    onRetry: retryInitialCameraReadiness,
                    onOpenSettings: openAppSettings
                )
                .transition(.opacity)
            }
        }
        .onAppear(perform: cameraViewDidAppear)
        .onReceive(NotificationCenter.default.publisher(for: .tapCamIntentHandoffDidChange)) { _ in
            applyPendingIntentHandoff()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapCamLockedCaptureImportDidAddPendingCaptures).receive(on: RunLoop.main)) { _ in
            retryPendingCapturesAfterLockedImport()
        }
        #if !TAP_ENABLE_PRO_CAMERA_CONTROLS
        .onDisappear {
            persistRememberedViewfinderControlStateIfNeeded()
            isBasicEVStripVisible = false
        }
        .onChange(of: isShowingSettings) { _, isPresented in
            if isPresented {
                persistRememberedViewfinderControlStateIfNeeded()
                isBasicEVStripVisible = false
            } else {
                refreshCaptureDataUsePolicyAfterSettingsDismissal()
            }
        }
        #else
        .onDisappear {
            persistRememberedViewfinderControlStateIfNeeded()
        }
        .onChange(of: isShowingSettings) { _, isPresented in
            if isPresented {
                persistRememberedViewfinderControlStateIfNeeded()
            } else {
                refreshCaptureDataUsePolicyAfterSettingsDismissal()
            }
        }
        #endif
        .onChange(of: outputFormatRawValue) { _, _ in
            Task {
                await viewModel.configureCurrentSelection()
            }
        }
        .onChange(of: photoQualityRawValue) { _, _ in
            Task {
                await viewModel.configureCurrentSelection()
            }
        }
        .onChange(of: flashStartupPolicyRawValue) { _, rawValue in
            applyFlashStartupPolicy(rawValue)
        }
        .onChange(of: livePhotoStartupPolicyRawValue) { _, rawValue in
            applyLivePhotoStartupPolicy(rawValue)
        }
        .onChange(of: usesMicrophoneData) { _, _ in
            Task {
                await viewModel.configureCurrentSelection()
            }
        }
        .onChange(of: routeStore.isDepthAlbumPresented) { _, isPresented in
            if isPresented {
                persistRememberedViewfinderControlStateIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persistRememberedViewfinderControlStateIfNeeded()
                Task {
                    await viewModel.stopActiveVideoRecordingForLifecycleIfNeeded(
                        pendingCaptureWorkerClient: appAttestController.runtime.client
                    )
                }
            } else {
                hapticFeedbackController.prepareForCameraInteraction()
                completeInitialReadinessGateIfReady()
            }
        }
        .onChange(of: viewModel.latestCaptureDepthHint) { _, hint in
            guard let hint else {
                return
            }
            if showsDepthAvailabilityHints {
                showViewfinderHint(hint.message)
            }
        }
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        .onChange(of: activeAdjustmentControlKey) { _, _ in
            alignVisibleAdjustmentControlsIfNeeded()
        }
        .onChange(of: viewModel.activeControlCapabilities) { _, _ in
            alignVisibleAdjustmentControlsIfNeeded()
        }
        .onChange(of: viewModel.exposureRuntimeEvent) { _, event in
            guard event?.kind == .exposureSettled else {
                return
            }
            scheduleManualControlReadback(reason: .exposureSettled, delay: .milliseconds(0))
        }
        .onChange(of: viewModel.focusRuntimeEvent) { _, event in
            guard event?.kind == .focusSettled else {
                return
            }
            handleFocusSettledMeteringTrigger()
        }
        #endif
        .onChange(of: showsDepthAvailabilityHints) { _, isEnabled in
            if !isEnabled {
                viewfinderHint = nil
            }
        }
        .onChange(of: viewModel.isDepthCaptureReady) { _, _ in
            completeInitialReadinessGateIfReady()
        }
        .onChange(of: viewModel.isConfiguringSession) { _, _ in
            completeInitialReadinessGateIfReady()
        }
        .onChange(of: hapticFeedbackController.hasPreparedCameraInteraction) { _, _ in
            completeInitialReadinessGateIfReady()
        }
    }

    private var cameraSurface: some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                viewfinderChrome(topSafeAreaInset: proxy.safeAreaInsets.top)

                cameraPreviewStage
                Spacer(minLength: 8)
                captureControls
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }

    private var initialReadinessState: CameraInteractiveReadinessState {
        CameraInteractiveReadinessState.resolve(
            isGateEnabled: initialReadinessGate.isEnabled,
            didCompleteGate: didCompleteInitialReadinessGate,
            cameraAuthorizationStatus: AVCaptureDevice.authorizationStatus(for: .video),
            isConfiguringSession: viewModel.isConfiguringSession,
            hasActiveSessionConfiguration: viewModel.activeSessionConfiguration != nil,
            isDepthCaptureReady: viewModel.isDepthCaptureReady,
            hasPreparedHaptics: hapticFeedbackController.hasPreparedCameraInteraction,
            statusMessage: viewModel.statusMessage
        )
    }

    private func cameraViewDidAppear() {
        hapticFeedbackController.prepareForCameraInteraction()
        applyPendingIntentHandoff()
        completeInitialReadinessGateIfReady()
    }

    private func completeInitialReadinessGateIfReady() {
        guard initialReadinessGate.isEnabled,
              !didCompleteInitialReadinessGate,
              initialReadinessState == .ready else {
            return
        }

        didCompleteInitialReadinessGate = true
        initialReadinessGate.onReady()
    }

    private func retryInitialCameraReadiness() {
        hapticFeedbackController.prepareForCameraInteraction()
        Task {
            await viewModel.start()
            completeInitialReadinessGateIfReady()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private var viewfinderHighlightColor: Color {
        CameraViewfinderHighlightPreference.resolved(rawValue: viewfinderHighlightRawValue).color
    }

    @ViewBuilder
    private func viewfinderChrome(topSafeAreaInset: CGFloat) -> some View {
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        CameraViewfinderChromeView(
            state: CameraViewfinderChromeState(
                flashMode: flashMode,
                isFlashAvailable: viewModel.isFlashAvailable,
                isLivePhotoAvailable: viewModel.isLivePhotoCaptureSupported,
                isLivePhotoEnabled: isLivePhotoEnabled,
                contentRotation: chromeOrientation.angle
            ),
            highlightColor: viewfinderHighlightColor,
            topSafeAreaInset: topSafeAreaInset,
            onOpenSettings: {
                isShowingSettings = true
            },
            onCycleFlash: cycleFlashMode,
            onToggleLivePhoto: toggleLivePhoto
        )
        #else
        CameraViewfinderChromeView(
            state: CameraViewfinderChromeState(
                flashMode: flashMode,
                isFlashAvailable: viewModel.isFlashAvailable,
                isLivePhotoAvailable: viewModel.isLivePhotoCaptureSupported,
                isLivePhotoEnabled: isLivePhotoEnabled,
                basicEVState: basicEVControlState,
                contentRotation: chromeOrientation.angle
            ),
            highlightColor: viewfinderHighlightColor,
            topSafeAreaInset: topSafeAreaInset,
            onToggleBasicEV: toggleBasicEVStrip,
            onOpenSettings: {
                isShowingSettings = true
            },
            onCycleFlash: cycleFlashMode,
            onToggleLivePhoto: toggleLivePhoto
        )
        #endif
    }

    @ViewBuilder
    private var captureControls: some View {
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        CameraCaptureControlsView(
            state: CameraCaptureControlsState(
                isShutterEnabled: shutterIsEnabled,
                isLibraryWriteInProgress: viewModel.isCaptureWriteInProgress || viewModel.isVideoRecording || viewModel.isPreparingVideoMode,
                selectedMode: selectedMode,
                isRecordingMovie: viewModel.isVideoRecording,
                isPreparingMovie: viewModel.isPreparingVideoMode,
                adjustmentControlState: adjustmentControlState,
                contentRotation: chromeOrientation.angle
            ),
            highlightColor: viewfinderHighlightColor,
            recentThumbnail: viewModel.recentThumbnail,
            onOpenTAPLibrary: openTAPLibrary,
            onCapture: triggerShutter,
            onSwitchCamera: switchCameraPosition,
            onSelectMode: selectCaptureMode,
            onSelectAdjustmentControl: selectAdjustmentControl,
            onToggleFocusMode: toggleFocusMode,
            onAdjustEV: adjustGlobalEVBias,
            onAdjustISO: adjustISO,
            onAdjustShutterPosition: adjustShutterPosition,
            onAdjustLensPosition: adjustLensPosition,
            onBeginAdjustment: beginAdjustmentInteraction,
            onEndAdjustment: endAdjustmentInteraction
        )
        #else
        CameraCaptureControlsView(
            state: CameraCaptureControlsState(
                isShutterEnabled: shutterIsEnabled,
                isLibraryWriteInProgress: viewModel.isCaptureWriteInProgress || viewModel.isVideoRecording || viewModel.isPreparingVideoMode,
                selectedMode: selectedMode,
                isRecordingMovie: viewModel.isVideoRecording,
                isPreparingMovie: viewModel.isPreparingVideoMode,
                basicEVControlState: basicEVControlState,
                contentRotation: chromeOrientation.angle
            ),
            highlightColor: viewfinderHighlightColor,
            recentThumbnail: viewModel.recentThumbnail,
            onOpenTAPLibrary: openTAPLibrary,
            onCapture: triggerShutter,
            onSwitchCamera: switchCameraPosition,
            onSelectMode: selectCaptureMode,
            onAdjustEV: adjustGlobalEVBias
        )
        #endif
    }

    private var depthAlbumPresentedBinding: Binding<Bool> {
        Binding(
            get: { routeStore.isDepthAlbumPresented },
            set: { routeStore.setDepthAlbumPresented($0) }
        )
    }

    private var shutterIsEnabled: Bool {
        switch selectedMode {
        case .photo:
            return viewModel.canCapture
        case .video:
            return viewModel.canUseVideoShutter
        }
    }

    private func applyPendingIntentHandoff() {
        guard let handoff = intentHandoffStore.loadAndClearHandoff() else {
            return
        }
        LockedCameraDiagnostics.logger.info(
            "locked_camera_handoff_apply destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public) routeDepthAlbumPresented=\(routeStore.isDepthAlbumPresented, privacy: .public) routeAwaitingImport=\(routeStore.isAwaitingLockedCaptureImport, privacy: .public)"
        )

        switch handoff.destination {
        case .camera:
            routeStore.returnToCamera()
        case .tapLibrary:
            presentTAPLibrary()
        case .tapLibraryAwaitingLockedImport:
            presentTAPLibrary(awaitingLockedCaptureImport: true)
        case .lockedImportNeutral:
            routeStore.returnToCamera()
        }
    }

    private var cameraPreviewStage: some View {
        #if DEBUG
        CameraPreviewStageView(
            session: viewModel.session,
            state: previewStageState,
            highlightColor: viewfinderHighlightColor,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
            onTapFocusPoint: focusAtPreviewPoint,
            onManualFocusTapAssist: manualFocusTapAssistAtPreviewPoint,
            onAdjustTemporaryFocusEV: adjustTemporaryFocusEVOffset,
            onFinishTemporaryFocusEVAdjustment: finishTemporaryFocusEVAdjustment,
            onClearFocusSession: clearFocusSession,
            onLockFocusAndExposure: { request in
                lockFocusAndExposure(request)
            },
            debugState: CameraPreviewDebugState(
                isDepthReady: viewModel.isDepthCaptureReady,
                activeCameraDisplayName: viewModel.activeCameraDisplayName,
                statusMessage: viewModel.statusMessage,
                recentMetrics: viewModel.recentMetrics,
                queuedJobCount: viewModel.pendingJobCount,
                depthOptions: debugDepthDisplayOptions,
                showsZoomControl: viewModel.isDebugDepthOverrideActive && viewModel.debugZoomCapability != nil,
                zoomOptions: debugZoomDisplayOptions,
                selectedZoomFactor: viewModel.debugSelectedZoomFactor,
                fovLabel: viewModel.debugFOVLabel,
                sliderRange: viewModel.debugZoomSliderRange,
                isSliderEnabled: viewModel.debugZoomSliderEnabled,
                manualControlLines: previewDebugManualControlLines
            ),
            onSelectDebugDepthOption: selectDebugDepthDisplayOption,
            onSelectDebugZoomOption: selectDebugZoomDisplayOption,
            onSelectDebugZoomFactor: selectDebugZoomFactor
        )
        #else
        CameraPreviewStageView(
            session: viewModel.session,
            state: previewStageState,
            highlightColor: viewfinderHighlightColor,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
            onTapFocusPoint: focusAtPreviewPoint,
            onManualFocusTapAssist: manualFocusTapAssistAtPreviewPoint,
            onAdjustTemporaryFocusEV: adjustTemporaryFocusEVOffset,
            onFinishTemporaryFocusEVAdjustment: finishTemporaryFocusEVAdjustment,
            onClearFocusSession: clearFocusSession,
            onLockFocusAndExposure: { request in
                lockFocusAndExposure(request)
            }
        )
        #endif
    }

    private var previewStageState: CameraPreviewStageState {
        CameraPreviewStageState(
            nativePreviewAspectRatio: viewModel.nativePreviewAspectRatio,
            focalLengthOptions: focalLengthDisplayOptions,
            shouldShowFocalLengthSelector: viewModel.shouldShowFocalLengthSelector,
            guideOverlayPreference: CameraGuideOverlayPreference.resolved(rawValue: guideOverlayRawValue),
            previewCropRectNormalized: viewModel.previewCropRectNormalized,
            temporaryFocusEVOffset: temporaryFocusEVOffset,
            focusMode: focusMode,
            focusRuntimeEvent: viewModel.focusRuntimeEvent,
            focusMagnifierPreference: CameraFocusMagnifierPreference.resolved(rawValue: focusMagnifierRawValue),
            focusLoupePulseID: previewFocusLoupePulseID,
            isManualFocusTapAssistEnabled: previewManualFocusTapAssistEnabled,
            viewfinderEdgeToastMessage: viewfinderHint,
            contentRotation: chromeOrientation.angle
        )
    }

    private var previewFocusLoupePulseID: UUID? {
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        focusLoupePulseID
        #else
        nil
        #endif
    }

    private var previewManualFocusTapAssistEnabled: Bool {
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        isManualFocusTapAssistEnabled
        #else
        false
        #endif
    }

    #if !TAP_ENABLE_PRO_CAMERA_CONTROLS
    private var basicEVControlState: CameraBasicEVControlState {
        CameraBasicEVControlState(
            bias: globalEVBias,
            isStripVisible: isBasicEVStripVisible
        )
    }

    private func toggleBasicEVStrip() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isBasicEVStripVisible.toggle()
        }
    }
    #endif

    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    private var activeAdjustmentControlKey: String? {
        viewModel.activeSessionConfiguration?.controlCapabilities.deviceID
    }

    private var adjustmentControlState: CameraAdjustmentControlState? {
        guard let capability = viewModel.activeControlCapabilities else {
            return nil
        }
        let exposureState = resolvedExposureControlState(for: capability)
        let exposureDisplay = exposureState.currentDisplayState
        let exposureDraft = CameraAdjustmentControlDraft(
            iso: exposureDisplay.iso,
            shutterDurationSeconds: exposureDisplay.shutterDurationSeconds,
            lensPosition: adjustmentDraft.lensPosition
        )
        return CameraAdjustmentControlState(
            capability: capability,
            activeControl: activeAdjustmentControl,
            exposureMode: adjustmentExposureMode(from: exposureDisplay),
            focusMode: focusMode,
            draft: exposureDraft,
            exposureRiskRanges: exposureRiskRanges(from: exposureState),
            allowsManualFocusControl: viewModel.isManualFocusControlAvailable
        )
    }

    private func resolvedExposureControlState(
        for capability: CameraControlCapabilitySnapshot
    ) -> CameraExposureControlState {
        if let exposureControlState,
           exposureControlState.deviceID == capability.deviceID,
           exposureControlState.controlSurfaceSignature == CameraManualControlCommandPlan.ControlSurfaceSignature(capability: capability),
           exposureControlState.generation == viewModel.configurationGeneration {
            return exposureControlState
        }
        return CameraExposureControlState(
            capability: capability,
            generation: viewModel.configurationGeneration,
            evBias: globalEVBias
        )
    }

    private func adjustmentExposureMode(
        from display: CameraExposureControlDisplayState
    ) -> CameraAdjustmentControlState.ExposureMode {
        switch display.mode {
        case .auto:
            return .auto(globalBias: display.evBias)
        case .isoPriority:
            return .isoPriority(globalBias: display.evBias)
        case .shutterPriority:
            return .shutterPriority(globalBias: display.evBias)
        case .manual:
            return .custom(meterOffset: display.meterDeltaEV ?? 0)
        }
    }

    private func exposureRiskRanges(
        from state: CameraExposureControlState
    ) -> CameraAdjustmentControlState.ExposureRiskRanges {
        CameraAdjustmentControlState.ExposureRiskRanges(
            iso: state.riskRangeForISO(),
            shutterDurationSeconds: state.riskRangeForShutterDuration()
        )
    }
    #endif

    private func selectCaptureMode(_ mode: CameraCaptureModeOption) {
        guard mode.isAvailableInStageOne else {
            showViewfinderHint("Coming soon")
            return
        }
        guard !viewModel.isVideoRecording else {
            return
        }
        selectedMode = mode
        Task {
            switch mode {
            case .photo:
                await viewModel.teardownPreparedVideoModeIfNeeded()
            case .video:
                await viewModel.prepareVideoModeIfNeeded()
            }
        }
    }

    private func cycleFlashMode() {
        guard viewModel.isFlashAvailable else {
            showViewfinderHint("Flash unavailable")
            return
        }
        flashMode = flashMode.next
    }

    private func toggleLivePhoto() {
        isLivePhotoEnabled.toggle()
    }

    private func applyFlashStartupPolicy(_ rawValue: String) {
        let policy = CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: rawValue,
            fallback: CameraFlashControlMode.defaultStartupPolicy
        )
        let lastModeRawValue: String
        if policy == .rememberLastState {
            lastModeRawValue = flashMode.rawValue
            lastFlashModeRawValue = lastModeRawValue
        } else {
            lastModeRawValue = lastFlashModeRawValue
        }
        flashMode = CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: rawValue,
            lastModeRawValue: lastModeRawValue
        )
    }

    private func applyLivePhotoStartupPolicy(_ rawValue: String) {
        let policy = CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: rawValue,
            fallback: CameraLivePhotoPreferences.defaultStartupPolicy
        )
        let lastIsEnabled: Bool
        if policy == .rememberLastState {
            lastIsEnabled = isLivePhotoEnabled
            lastLivePhotoEnabled = lastIsEnabled
        } else {
            lastIsEnabled = lastLivePhotoEnabled
        }
        isLivePhotoEnabled = CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: rawValue,
            lastIsEnabled: lastIsEnabled
        )
    }

    private func persistRememberedViewfinderControlStateIfNeeded() {
        if CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: flashStartupPolicyRawValue,
            fallback: CameraFlashControlMode.defaultStartupPolicy
        ) == .rememberLastState {
            lastFlashModeRawValue = flashMode.rawValue
        }

        if CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: livePhotoStartupPolicyRawValue,
            fallback: CameraLivePhotoPreferences.defaultStartupPolicy
        ) == .rememberLastState {
            lastLivePhotoEnabled = isLivePhotoEnabled
        }
    }

    private func refreshCaptureDataUsePolicyAfterSettingsDismissal() {
        Task {
            await viewModel.configureCurrentSelection()
        }
    }

    private func showViewfinderHint(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            viewfinderHint = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard viewfinderHint == message else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                viewfinderHint = nil
            }
        }
    }

    private func adjustGlobalEVBias(_ value: Double) {
        let nextBias = CameraEVPreferences.clampedBias(value)
        globalEVBias = nextBias
        CameraEVPreferences.persistGlobalBias(nextBias)

        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        guard let capability = viewModel.activeControlCapabilities else {
            scheduleGlobalEVBiasApply(nextBias)
            return
        }
        let result = resolvedExposureControlState(for: capability).setEVBias(nextBias)
        applyExposureControlResult(result, delay: .milliseconds(70))
        #else
        scheduleGlobalEVBiasApply(nextBias)
        #endif
    }

    private func scheduleGlobalEVBiasApply(_ requestedBias: Double) {
        globalEVApplyTask?.cancel()
        globalEVApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.setGlobalAutoExposureBias(
                requestedBias,
                effectiveExposureBias: effectiveAutoExposureBias
            )
        }
    }

    private var effectiveAutoExposureBias: Double {
        CameraEVPreferences.clampedBias(globalEVBias + temporaryFocusEVOffset)
    }

    private func adjustTemporaryFocusEVOffset(_ offset: Double) {
        let clampedOffset = CameraTemporaryFocusEVPreferences.clampedOffset(offset)
        guard clampedOffset != temporaryFocusEVOffset else {
            return
        }
        temporaryFocusEVOffset = clampedOffset
        temporaryFocusEVApplyTask?.cancel()
        temporaryFocusEVApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.applyEffectiveAutoExposureBiasToActiveConfiguration(effectiveAutoExposureBias)
        }
    }

    private func finishTemporaryFocusEVAdjustment() {
        temporaryFocusEVApplyTask?.cancel()
        temporaryFocusEVApplyTask = nil
        Task {
            await viewModel.applyEffectiveAutoExposureBiasToActiveConfiguration(effectiveAutoExposureBias)
        }
    }

    private func clearFocusSession() {
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        temporaryFocusEVApplyTask = nil
        guard focusMode == .auto else {
            return
        }
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        let exposureMode = exposureControlState?.mode ?? .auto
        Task {
            if exposureMode == .auto {
                await viewModel.restoreAutoCameraControls(globalExposureBias: globalEVBias)
            } else {
                await viewModel.restoreAutoFocus()
            }
        }
        #else
        Task {
            await viewModel.restoreAutoCameraControls(globalExposureBias: globalEVBias)
        }
        #endif
    }

    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    private func selectAdjustmentControl(_ control: CameraAdjustmentControl) {
        guard let state = adjustmentControlState else {
            showViewfinderHint("Camera controls unavailable")
            return
        }

        switch control {
        case .ev:
            activeAdjustmentControl = activeAdjustmentControl == .ev ? nil : .ev
        case .iso:
            guard state.exposure.isAvailable else {
                showViewfinderHint("ISO unavailable")
                return
            }
            if activeAdjustmentControl == .iso,
               let exposureControlState,
               !exposureControlState.mode.isISOAutomatic {
                applyExposureControlResult(exposureControlState.makeISOAutomatic())
                activeAdjustmentControl = nil
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .iso ? nil : .iso
        case .shutter:
            guard state.exposure.isAvailable else {
                showViewfinderHint("Shutter unavailable")
                return
            }
            if activeAdjustmentControl == .shutter,
               let exposureControlState,
               !exposureControlState.mode.isShutterAutomatic {
                applyExposureControlResult(exposureControlState.makeShutterAutomatic())
                activeAdjustmentControl = nil
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .shutter ? nil : .shutter
        case .focus:
            toggleFocusMode()
        }
    }

    private func beginAdjustmentInteraction(_ control: CameraAdjustmentControl) {
        guard let exposureInteraction = exposureInteraction(for: control),
              let capability = viewModel.activeControlCapabilities else {
            return
        }
        let result = resolvedExposureControlState(for: capability).beginInteraction(exposureInteraction)
        exposureControlState = result.nextState
        latestExposureControlDebugState = result.debugState
    }

    private func endAdjustmentInteraction(_ control: CameraAdjustmentControl) {
        guard exposureInteraction(for: control) != nil,
              let exposureControlState else {
            return
        }
        applyExposureControlResult(exposureControlState.endInteraction())
    }

    private func exposureInteraction(
        for control: CameraAdjustmentControl
    ) -> CameraExposureControlInteraction? {
        switch control {
        case .ev:
            .ev
        case .iso:
            .iso
        case .shutter:
            .shutter
        case .focus:
            nil
        }
    }

    private func adjustISO(_ value: Double) {
        guard let capability = viewModel.activeControlCapabilities,
              let state = adjustmentControlState else {
            return
        }

        activeAdjustmentControl = .iso
        storeAdjustmentDraft(
            adjustmentDraft.replacingISO(value),
            state: state
        )
        let result = resolvedExposureControlState(for: capability).setISO(value)
        applyExposureControlResult(result, delay: .milliseconds(80))
    }

    private func adjustShutterPosition(_ position: Double) {
        guard let capability = viewModel.activeControlCapabilities,
              let state = adjustmentControlState else {
            return
        }

        activeAdjustmentControl = .shutter
        let shutterDuration = state.exposure.shutterDuration(forNormalizedPosition: position)
        storeAdjustmentDraft(
            adjustmentDraft.replacingShutterDuration(shutterDuration),
            state: state
        )
        let result = resolvedExposureControlState(for: capability).setShutterDuration(shutterDuration)
        applyExposureControlResult(result, delay: .milliseconds(80))
    }

    private func adjustLensPosition(_ value: Double) {
        guard let state = adjustmentControlState else {
            return
        }

        manualFocusAssistToken = nil
        focusLoupePulseID = UUID()
        focusMode = .manual
        activeAdjustmentControl = .focus
        storeAdjustmentDraft(
            adjustmentDraft.replacingLensPosition(value),
            state: state
        )
        scheduleManualFocusApply()
    }

    private func restoreAutoExposureFromMeter() {
        guard let capability = viewModel.activeControlCapabilities else {
            return
        }
        exposureControlState = CameraExposureControlState(
            capability: capability,
            generation: viewModel.configurationGeneration,
            evBias: globalEVBias
        )
        activeAdjustmentControl = nil
        exposureApplyTask?.cancel()
        showViewfinderHint("Auto exposure restored")
        Task {
            await viewModel.restoreAutoExposure(globalExposureBias: globalEVBias)
        }
    }

    private func toggleFocusMode() {
        guard let state = adjustmentControlState else {
            showViewfinderHint("Focus unavailable")
            return
        }

        switch focusMode {
        case .auto:
            guard state.focus.isAvailable else {
                showViewfinderHint("Manual focus unavailable")
                return
            }
            focusMode = .manual
            activeAdjustmentControl = .focus
            scheduleManualFocusApply()
        case .manual:
            focusMode = .auto
            if activeAdjustmentControl == .focus {
                activeAdjustmentControl = nil
            }
            adjustmentApplyTask?.cancel()
            Task {
                await viewModel.restoreAutoFocus()
            }
        }
    }

    private func alignVisibleAdjustmentControlsIfNeeded() {
        guard let capability = viewModel.activeControlCapabilities else {
            return
        }

        let fallback = CameraAdjustmentControlState.defaultDraft(from: capability)
        let currentExposureState = resolvedExposureControlState(for: capability)
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: activeAdjustmentControl,
            exposureMode: adjustmentExposureMode(from: currentExposureState.currentDisplayState),
            focusMode: focusMode,
            draft: fallback,
            exposureRiskRanges: exposureRiskRanges(from: currentExposureState),
            allowsManualFocusControl: viewModel.isManualFocusControlAvailable
        )
        adjustmentDraft = adjustmentDraftMemory.draft(
            for: activeAdjustmentControlKey,
            state: state,
            fallback: fallback
        )
        let expectedSignature = CameraManualControlCommandPlan.ControlSurfaceSignature(capability: capability)
        if exposureControlState?.deviceID != capability.deviceID
            || exposureControlState?.controlSurfaceSignature != expectedSignature
            || exposureControlState?.generation != viewModel.configurationGeneration {
            let result = CameraExposureControlState.configurationChanged(
                capability: capability,
                generation: viewModel.configurationGeneration,
                evBias: globalEVBias
            )
            exposureControlState = result.nextState
            latestExposureControlDebugState = result.debugState
            activeAdjustmentControl = nil
            focusMode = .auto
            manualFocusAssistToken = nil
            adjustmentApplyTask?.cancel()
            exposureApplyTask?.cancel()
            Task {
                await viewModel.restoreAutoCameraControls(globalExposureBias: globalEVBias)
            }
            scheduleManualControlReadback(reason: .initialBaseline)
        }
        if focusMode == .manual {
            scheduleManualFocusApply()
        }
    }

    private func storeAdjustmentDraft(
        _ draft: CameraAdjustmentControlDraft,
        state: CameraAdjustmentControlState
    ) {
        adjustmentDraft = adjustmentDraftMemory.store(
            draft,
            for: activeAdjustmentControlKey,
            state: state
        )
    }

    private func applyExposureControlResult(
        _ result: CameraExposureControlResult,
        delay: Duration = .milliseconds(0)
    ) {
        exposureControlState = result.nextState
        latestExposureControlDebugState = result.debugState
        if let state = adjustmentControlState {
            storeAdjustmentDraft(
                CameraAdjustmentControlDraft(
                    iso: result.displayState.iso,
                    shutterDurationSeconds: result.displayState.shutterDurationSeconds,
                    lensPosition: adjustmentDraft.lensPosition
                ),
                state: state
            )
        }

        guard let intent = result.manualControlIntent else {
            if result.shouldReadback, let reason = result.readbackReason {
                scheduleManualControlReadback(reason: reason)
            }
            return
        }

        exposureApplyTask?.cancel()
        exposureApplyTask = Task { @MainActor in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else {
                return
            }
            if result.nextState.mode == .auto,
               case .continuousAuto? = intent.exposure {
                await viewModel.restoreAutoExposure(globalExposureBias: result.nextState.evBias)
            } else {
                await viewModel.applyManualControlIntent(intent)
            }
            if result.shouldReadback, let reason = result.readbackReason {
                scheduleManualControlReadback(reason: reason)
            } else if result.nextState.mode != .auto {
                scheduleManualControlReadback(reason: .userInteractionEnded)
            }
        }
    }

    private func scheduleManualControlReadback(
        reason: CameraManualControlReadbackReason,
        delay: Duration = .milliseconds(300)
    ) {
        exposureReadbackTask?.cancel()
        exposureReadbackTask = Task { @MainActor in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else {
                return
            }
            guard let snapshot = await viewModel.readManualControlSnapshot(reason: reason) else {
                return
            }
            applyMeterSample(snapshot.meterSample)
        }
    }

    private func applyMeterSample(_ sample: CameraExposureMeterSample) {
        guard let capability = viewModel.activeControlCapabilities else {
            return
        }
        let state = exposureControlState ?? CameraExposureControlState(
            capability: capability,
            generation: viewModel.configurationGeneration,
            evBias: globalEVBias
        )
        let result = state.receiveMeterSample(sample)
        exposureControlState = result.nextState
        latestExposureControlDebugState = result.debugState
        if let adjustmentState = adjustmentControlState {
            storeAdjustmentDraft(
                CameraAdjustmentControlDraft(
                    iso: result.displayState.iso,
                    shutterDurationSeconds: result.displayState.shutterDurationSeconds,
                    lensPosition: adjustmentDraft.lensPosition
                ),
                state: adjustmentState
            )
        }
        guard let intent = result.manualControlIntent,
              result.nextState.mode != .auto else {
            return
        }
        exposureApplyTask?.cancel()
        exposureApplyTask = Task { @MainActor in
            await viewModel.applyManualControlIntent(intent)
        }
    }

    private func handleFocusSettledMeteringTrigger() {
        let now = Date()
        guard now.timeIntervalSince(lastFocusMeteringAt) >= 0.5 else {
            return
        }
        lastFocusMeteringAt = now
        guard let exposureControlState else {
            scheduleManualControlReadback(reason: .focusMetering, delay: .milliseconds(0))
            return
        }
        switch exposureControlState.mode {
        case .auto, .isoPriority, .shutterPriority, .manual:
            scheduleManualControlReadback(reason: .focusMetering, delay: .milliseconds(0))
        }
    }

    private func scheduleManualFocusApply() {
        adjustmentApplyTask?.cancel()
        adjustmentApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.applyManualFocus(lensPosition: adjustmentDraft.lensPosition)
        }
    }
    #endif

    private func focusAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        let exposureMode = exposureControlState?.mode ?? .auto
        Task {
            if exposureMode == .auto {
                await viewModel.focusAtPreviewPoint(
                    point,
                    globalExposureBias: globalEVBias
                )
            } else {
                await viewModel.focusOnlyAtPreviewPoint(point)
            }
        }
        #else
        Task {
            await viewModel.focusAtPreviewPoint(
                point,
                globalExposureBias: globalEVBias
            )
        }
        #endif
    }

    private func manualFocusTapAssistAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        let assistToken = UUID()
        manualFocusAssistToken = assistToken
        focusLoupePulseID = UUID()
        Task {
            await viewModel.focusOnlyAtPreviewPoint(point)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled,
                  manualFocusAssistToken == assistToken,
                  focusMode == .manual,
                  let snapshot = await viewModel.readManualControlSnapshot(reason: .focusMetering),
                  let state = adjustmentControlState else {
                return
            }
            storeAdjustmentDraft(
                adjustmentDraft.replacingLensPosition(snapshot.lensPosition),
                state: state
            )
            await viewModel.applyManualFocus(lensPosition: snapshot.lensPosition)
        }
        #endif
    }

    private func lockFocusAndExposure(_ request: CameraFocusLockRequest) {
        temporaryFocusEVApplyTask?.cancel()
        Task {
            switch request {
            case .lockCurrent:
                await viewModel.lockFocusAndExposure()
            case .refocusAndLock(_, let capturePoint):
                await viewModel.lockFocusAndExposure(at: capturePoint)
            }
        }
    }

    private var focalLengthDisplayOptions: [CameraFocalLengthDisplayOption] {
        viewModel.focalLengthOptions.enumerated().map { index, option in
            CameraFocalLengthDisplayOption(
                selectionToken: "fov-\(index)",
                displayName: option.displayName,
                numericLabel: option.numericLabel,
                unitLabel: option.unitLabel,
                isSelected: option.id == viewModel.activeFocalLengthOptionID,
                isEnabled: option.isEnabled
            )
        }
    }

    #if DEBUG
    private var previewDebugManualControlLines: [String] {
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        debugManualControlLines
        #else
        []
        #endif
    }

    private var debugDepthDisplayOptions: [CameraDebugDepthDisplayOption] {
        viewModel.debugDepthDeviceOptions.enumerated().map { index, option in
            CameraDebugDepthDisplayOption(
                selectionToken: "debug-depth-\(index)",
                displayName: option.displayName,
                iconName: option.iconName,
                isSelected: option.id == viewModel.debugSelectedDepthDeviceID,
                isEnabled: option.isSelectable
            )
        }
    }

    private var debugZoomDisplayOptions: [CameraDebugZoomDisplayOption] {
        viewModel.debugZoomProfiles.enumerated().map { index, zoom in
            CameraDebugZoomDisplayOption(
                selectionToken: "debug-zoom-\(index)",
                displayName: zoom.displayName,
                isSelected: isDebugZoomSelected(zoom),
                isEnabled: zoom.isEnabled
            )
        }
    }

    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    private var debugManualControlLines: [String] {
        var lines: [String] = []
        if let debugState = latestExposureControlDebugState {
            lines.append("EXP \(debugState.mode) gen \(debugState.generation) settled \(debugState.baselineSettled)")
            if let equivalentExposure = debugState.equivalentExposure {
                lines.append(String(format: "eq %.5f target %.5f", equivalentExposure, debugState.targetExposure ?? 0))
            }
            if let meterDeltaEV = debugState.meterDeltaEV {
                lines.append(String(format: "meter %+0.2f EV", meterDeltaEV))
            }
            if let lastReadbackReason = debugState.lastReadbackReason {
                lines.append("read \(lastReadbackReason.rawValue)")
            }
        }
        if let readback = viewModel.latestManualControlReadback {
            lines.append(String(
                format: "rb ISO %.0f S %.5f off %+0.2f",
                readback.iso,
                readback.shutterDurationSeconds,
                readback.exposureTargetOffset
            ))
        }
        return lines
    }
    #endif

    private func selectDebugDepthDisplayOption(_ option: CameraDebugDepthDisplayOption) {
        guard let index = debugDepthOptionIndex(for: option.selectionToken),
              viewModel.debugDepthDeviceOptions.indices.contains(index) else {
            return
        }
        let sourceOption = viewModel.debugDepthDeviceOptions[index]
        Task {
            await viewModel.selectDebugDepthDevice(sourceOption)
        }
    }

    private func selectDebugZoomDisplayOption(_ option: CameraDebugZoomDisplayOption) {
        guard let index = debugZoomOptionIndex(for: option.selectionToken),
              viewModel.debugZoomProfiles.indices.contains(index) else {
            return
        }
        let sourceZoom = viewModel.debugZoomProfiles[index]
        Task {
            await viewModel.selectDebugZoom(sourceZoom)
        }
    }

    private func selectDebugZoomFactor(_ zoomFactor: Double) {
        Task {
            await viewModel.selectDebugZoomFactor(zoomFactor)
        }
    }

    private func debugDepthOptionIndex(for token: String) -> Int? {
        guard token.hasPrefix("debug-depth-") else {
            return nil
        }
        return Int(token.dropFirst("debug-depth-".count))
    }

    private func debugZoomOptionIndex(for token: String) -> Int? {
        guard token.hasPrefix("debug-zoom-") else {
            return nil
        }
        return Int(token.dropFirst("debug-zoom-".count))
    }

    private func isDebugZoomSelected(_ zoom: ZoomProfile) -> Bool {
        if let selectedZoomID = viewModel.debugSelectedZoomID {
            return zoom.id == selectedZoomID
        }
        return zoom.matchesRawVideoZoomFactor(viewModel.debugSelectedZoomFactor)
    }
    #endif

    private func selectFocalLengthDisplayOption(_ option: CameraFocalLengthDisplayOption) {
        guard let index = focalLengthOptionIndex(for: option.selectionToken),
              viewModel.focalLengthOptions.indices.contains(index) else {
            return
        }
        let sourceOption = viewModel.focalLengthOptions[index]
        Task {
            await viewModel.selectFocalLengthOption(sourceOption)
        }
    }

    private func focalLengthOptionIndex(for token: String) -> Int? {
        guard token.hasPrefix("fov-") else {
            return nil
        }
        return Int(token.dropFirst(4))
    }

    private func triggerShutter() {
        guard shutterIsEnabled else {
            return
        }

        performShutterHaptic()
        let pendingCaptureWorkerClient = appAttestController.runtime.client
        Task {
            switch selectedMode {
            case .photo:
                await viewModel.capture(
                    pendingCaptureWorkerClient: pendingCaptureWorkerClient,
                    suppressesShutterSound: !isShutterSoundEnabled,
                    flashMode: flashMode.captureFlashMode,
                    livePhotoRequest: CaptureLivePhotoRequest(
                        isEnabled: isLivePhotoEnabled && viewModel.isLivePhotoCaptureSupported,
                        capturesAudio: shouldCaptureLivePhotoAudio
                    )
                )
            case .video:
                await viewModel.toggleVideoRecording(
                    pendingCaptureWorkerClient: pendingCaptureWorkerClient
                )
            }
        }
    }

    private var shouldCaptureLivePhotoAudio: Bool {
        isLivePhotoEnabled
            && viewModel.isLivePhotoCaptureSupported
            && usesMicrophoneData
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && viewModel.activeSessionConfiguration?.livePhotoAudioInputConfigured == true
    }

    private func openTAPLibrary() {
        guard !viewModel.isCaptureWriteInProgress,
              !viewModel.isVideoRecording,
              !viewModel.isPreparingVideoMode else {
            return
        }

        presentTAPLibrary()
    }

    private func presentTAPLibrary(
        lockedImportReason: String? = nil,
        awaitingLockedCaptureImport: Bool = false
    ) {
        LockedCameraDiagnostics.logger.info(
            "tap_library_present requestedLockedImportReason=\(lockedImportReason ?? "none", privacy: .public) awaitingLockedCaptureImport=\(awaitingLockedCaptureImport, privacy: .public)"
        )
        #if !TAP_ENABLE_PRO_CAMERA_CONTROLS
        isBasicEVStripVisible = false
        #endif

        viewModel.pauseForAnalysis()
        routeStore.presentDepthAlbum(
            lockedImportReason: lockedImportReason,
            awaitingLockedCaptureImport: awaitingLockedCaptureImport
        )
    }

    private func retryPendingCapturesAfterLockedImport() {
        LockedCameraDiagnostics.logger.info(
            "locked_camera_import_notification_received routeDepthAlbumPresented=\(routeStore.isDepthAlbumPresented, privacy: .public) routeAwaitingImport=\(routeStore.isAwaitingLockedCaptureImport, privacy: .public)"
        )
        routeStore.finishAwaitingLockedCaptureImport()
        Task {
            await lifecycleCoordinator.retryPendingCaptures(
                viewModel: viewModel,
                appAttestController: appAttestController
            )
        }
    }

    private func switchCameraPosition() {
        Task { await viewModel.switchCameraPosition() }
    }

    private func performShutterHaptic() {
        guard isShutterHapticsEnabled else {
            return
        }

        hapticFeedbackController.shutterAccepted()
    }
}
