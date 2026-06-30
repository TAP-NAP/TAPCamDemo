//
//  CameraView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
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
    private let startsAutomatically: Bool
    @StateObject private var lifecycleCoordinator: CaptureLifecycleCoordinator
    @StateObject private var viewModel: CameraViewModel
    @StateObject private var routeStore: CameraRouteStore
    @StateObject private var chromeOrientation: CameraChromeOrientationController
    @StateObject private var appAttestController: AppAttestRuntimeController
    private let intentHandoffStore: TAPCamIntentHandoffStore
    @State private var isShowingSettings = false
    @State private var selectedMode: CameraCaptureModeOption = .photo
    @State private var flashMode = CameraFlashControlMode.defaultValue
    @State private var focusMode = CameraFocusControlMode.auto
    @State private var activeAdjustmentControl: CameraAdjustmentControl?
    @State private var isCustomExposure = false
    @State private var exposureMeterOffset = 0.0
    @State private var globalEVBias: Double
    @State private var globalEVApplyTask: Task<Void, Never>?
    @State private var temporaryFocusEVOffset = 0.0
    @State private var temporaryFocusEVApplyTask: Task<Void, Never>?
    @State private var adjustmentDraft = CameraAdjustmentControlDraft.fallback
    @State private var adjustmentDraftMemory = CameraAdjustmentControlDraftMemory()
    @State private var adjustmentApplyTask: Task<Void, Never>?
    @State private var viewfinderHint: String?
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var isShutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var isShutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled
    @AppStorage(CameraOutputFormatPreference.storageKey)
    private var outputFormatRawValue = CameraOutputFormatPreference.defaultValue.rawValue
    @AppStorage(CameraPhotoQualityPreference.storageKey)
    private var photoQualityRawValue = CameraPhotoQualityPreference.defaultValue.rawValue
    @AppStorage(CameraGuideOverlayPreference.storageKey)
    private var guideOverlayRawValue = CameraGuideOverlayPreference.defaultValue.rawValue
    @AppStorage(CameraDepthAvailabilityHintPreferences.showsHintsKey)
    private var showsDepthAvailabilityHints = CameraDepthAvailabilityHintPreferences.defaultShowsHints
    @AppStorage(CameraFocusMagnifierPreferences.isEnabledKey)
    private var isFocusMagnifierEnabled = CameraFocusMagnifierPreferences.defaultIsEnabled
    @AppStorage(CameraManualFocusTapAssistPreferences.isEnabledKey)
    private var isManualFocusTapAssistEnabled = CameraManualFocusTapAssistPreferences.defaultIsEnabled
    @AppStorage(CameraLivePhotoPreferences.isEnabledKey)
    private var isLivePhotoEnabled = CameraLivePhotoPreferences.defaultIsEnabled

    init(
        viewModel: CameraViewModel? = nil,
        routeStore: CameraRouteStore? = nil,
        appAttestController: AppAttestRuntimeController? = nil,
        lifecycleCoordinator: CaptureLifecycleCoordinator = CaptureLifecycleCoordinator(),
        intentHandoffStore: TAPCamIntentHandoffStore = TAPCamIntentHandoffStore(),
        startsAutomatically: Bool = true
    ) {
        let initialGlobalEVBias = CameraEVPreferences.resolvedLaunchBias()
        self.startsAutomatically = startsAutomatically
        self.intentHandoffStore = intentHandoffStore
        _lifecycleCoordinator = StateObject(wrappedValue: lifecycleCoordinator)
        let resolvedViewModel = viewModel ?? CameraViewModel()
        resolvedViewModel.requestedGlobalAutoExposureBias = initialGlobalEVBias
        _viewModel = StateObject(wrappedValue: resolvedViewModel)
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
        .onAppear(perform: applyPendingIntentHandoff)
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
        .onChange(of: viewModel.latestCaptureDepthHint) { _, hint in
            guard let hint else {
                return
            }
            if showsDepthAvailabilityHints {
                showViewfinderHint(hint.message)
            }
        }
        .onChange(of: activeAdjustmentControlKey) { _, _ in
            alignVisibleAdjustmentControlsIfNeeded()
        }
        .onChange(of: viewModel.activeControlCapabilities) { _, _ in
            alignVisibleAdjustmentControlsIfNeeded()
        }
        .onChange(of: showsDepthAvailabilityHints) { _, isEnabled in
            if !isEnabled {
                viewfinderHint = nil
            }
        }
    }

    private var cameraSurface: some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                CameraViewfinderChromeView(
                    state: CameraViewfinderChromeState(
                        flashMode: flashMode,
                        isFlashAvailable: viewModel.isFlashAvailable,
                        isLivePhotoAvailable: false,
                        isLivePhotoEnabled: isLivePhotoEnabled,
                        contentRotation: chromeOrientation.angle
                    ),
                    topSafeAreaInset: proxy.safeAreaInsets.top,
                    onOpenSettings: {
                        isShowingSettings = true
                    },
                    onCycleFlash: cycleFlashMode,
                    onToggleLivePhoto: {
                        showViewfinderHint("Coming soon")
                    }
                )

                cameraPreviewStage
                Spacer(minLength: 8)
                CameraCaptureControlsView(
                    state: CameraCaptureControlsState(
                        isShutterEnabled: viewModel.canCapture,
                        isLibraryWriteInProgress: viewModel.isCaptureWriteInProgress,
                        selectedMode: selectedMode,
                        adjustmentControlState: adjustmentControlState,
                        contentRotation: chromeOrientation.angle
                    ),
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
                    onAdjustLensPosition: adjustLensPosition
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }

    private var depthAlbumPresentedBinding: Binding<Bool> {
        Binding(
            get: { routeStore.isDepthAlbumPresented },
            set: { routeStore.setDepthAlbumPresented($0) }
        )
    }

    private func applyPendingIntentHandoff() {
        guard let handoff = intentHandoffStore.loadAndClearHandoff() else {
            return
        }

        switch handoff.destination {
        case .camera:
            routeStore.returnToCamera()
        case .tapLibrary:
            routeStore.presentDepthAlbum()
        }
    }

    private var cameraPreviewStage: some View {
        #if DEBUG
        CameraPreviewStageView(
            session: viewModel.session,
            state: previewStageState,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
            onTapFocusPoint: focusAtPreviewPoint,
            onManualFocusTapAssist: manualFocusTapAssistAtPreviewPoint,
            onAdjustTemporaryFocusEV: adjustTemporaryFocusEVOffset,
            onLockFocusAndExposure: { point in
                lockFocusAndExposure(at: point)
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
                isSliderEnabled: viewModel.debugZoomSliderEnabled
            ),
            onSelectDebugDepthOption: selectDebugDepthDisplayOption,
            onSelectDebugZoomOption: selectDebugZoomDisplayOption,
            onSelectDebugZoomFactor: selectDebugZoomFactor
        )
        #else
        CameraPreviewStageView(
            session: viewModel.session,
            state: previewStageState,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
            onTapFocusPoint: focusAtPreviewPoint,
            onManualFocusTapAssist: manualFocusTapAssistAtPreviewPoint,
            onAdjustTemporaryFocusEV: adjustTemporaryFocusEVOffset,
            onLockFocusAndExposure: { point in
                lockFocusAndExposure(at: point)
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
            isFocusMagnifierEnabled: isFocusMagnifierEnabled,
            isManualFocusTapAssistEnabled: isManualFocusTapAssistEnabled,
            viewfinderEdgeToastMessage: viewfinderHint,
            contentRotation: chromeOrientation.angle
        )
    }

    private var activeAdjustmentControlKey: String? {
        viewModel.activeSessionConfiguration?.controlCapabilities.deviceID
    }

    private var adjustmentControlState: CameraAdjustmentControlState? {
        guard let capability = viewModel.activeControlCapabilities else {
            return nil
        }
        return CameraAdjustmentControlState(
            capability: capability,
            activeControl: activeAdjustmentControl,
            exposureMode: isCustomExposure
                ? .custom(meterOffset: exposureMeterOffset)
                : .auto(globalBias: globalEVBias),
            focusMode: focusMode,
            draft: adjustmentDraft
        )
    }

    private func selectCaptureMode(_ mode: CameraCaptureModeOption) {
        guard mode.isAvailableInStageOne else {
            showViewfinderHint("Coming soon")
            return
        }
        selectedMode = mode
    }

    private func cycleFlashMode() {
        guard viewModel.isFlashAvailable else {
            showViewfinderHint("Flash unavailable")
            return
        }
        flashMode = flashMode.next
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
        globalEVApplyTask?.cancel()
        globalEVApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.setGlobalAutoExposureBias(
                nextBias,
                effectiveExposureBias: effectiveAutoExposureBias
            )
        }
    }

    private var effectiveAutoExposureBias: Double {
        CameraEVPreferences.clampedBias(globalEVBias + temporaryFocusEVOffset)
    }

    private func adjustTemporaryFocusEVOffset(_ offset: Double) {
        temporaryFocusEVOffset = CameraTemporaryFocusEVPreferences.clampedOffset(offset)
        temporaryFocusEVApplyTask?.cancel()
        temporaryFocusEVApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.applyEffectiveAutoExposureBiasToActiveConfiguration(effectiveAutoExposureBias)
        }
    }

    private func selectAdjustmentControl(_ control: CameraAdjustmentControl) {
        guard let state = adjustmentControlState else {
            showViewfinderHint("Camera controls unavailable")
            return
        }

        switch control {
        case .ev:
            if state.exposure.isCustom {
                restoreAutoExposureFromMeter()
            } else {
                activeAdjustmentControl = activeAdjustmentControl == .ev ? nil : .ev
            }
        case .iso:
            guard state.exposure.isAvailable else {
                showViewfinderHint("ISO unavailable")
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .iso ? nil : .iso
        case .shutter:
            guard state.exposure.isAvailable else {
                showViewfinderHint("Shutter unavailable")
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .shutter ? nil : .shutter
        case .focus:
            toggleFocusMode()
        }
    }

    private func adjustISO(_ value: Double) {
        guard let state = adjustmentControlState else {
            return
        }

        isCustomExposure = true
        exposureMeterOffset = currentExposureMeterOffset
        activeAdjustmentControl = .iso
        storeAdjustmentDraft(
            adjustmentDraft.replacingISO(value),
            state: state
        )
        scheduleCustomExposureApply()
    }

    private func adjustShutterPosition(_ position: Double) {
        guard let state = adjustmentControlState else {
            return
        }

        isCustomExposure = true
        exposureMeterOffset = currentExposureMeterOffset
        activeAdjustmentControl = .shutter
        storeAdjustmentDraft(
            adjustmentDraft.replacingShutterDuration(
                state.exposure.shutterDuration(forNormalizedPosition: position)
            ),
            state: state
        )
        scheduleCustomExposureApply()
    }

    private func adjustLensPosition(_ value: Double) {
        guard let state = adjustmentControlState else {
            return
        }

        focusMode = .manual
        activeAdjustmentControl = .focus
        storeAdjustmentDraft(
            adjustmentDraft.replacingLensPosition(value),
            state: state
        )
        scheduleManualFocusApply()
    }

    private var currentExposureMeterOffset: Double {
        viewModel.activeControlCapabilities?.exposure.currentExposureTargetOffset ?? exposureMeterOffset
    }

    private func restoreAutoExposureFromMeter() {
        isCustomExposure = false
        exposureMeterOffset = 0
        activeAdjustmentControl = nil
        adjustmentApplyTask?.cancel()
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
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: activeAdjustmentControl,
            exposureMode: isCustomExposure
                ? .custom(meterOffset: exposureMeterOffset)
                : .auto(globalBias: globalEVBias),
            focusMode: focusMode,
            draft: fallback
        )
        adjustmentDraft = adjustmentDraftMemory.draft(
            for: activeAdjustmentControlKey,
            state: state,
            fallback: fallback
        )
        if !isCustomExposure {
            exposureMeterOffset = capability.exposure.currentExposureTargetOffset
        }
        if isCustomExposure {
            scheduleCustomExposureApply()
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

    private func scheduleCustomExposureApply() {
        adjustmentApplyTask?.cancel()
        adjustmentApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.applyCustomExposure(
                iso: adjustmentDraft.iso,
                shutterDurationSeconds: adjustmentDraft.shutterDurationSeconds
            )
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

    private func focusAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        Task {
            await viewModel.focusAtPreviewPoint(
                point,
                globalExposureBias: globalEVBias
            )
        }
    }

    private func manualFocusTapAssistAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        Task {
            await viewModel.focusAtPreviewPoint(
                point,
                globalExposureBias: globalEVBias
            )
            await viewModel.applyManualFocus(lensPosition: adjustmentDraft.lensPosition)
        }
    }

    private func lockFocusAndExposure(at point: CameraPreviewFocusPoint) {
        temporaryFocusEVApplyTask?.cancel()
        showViewfinderHint("AE/AF LOCK")
        Task {
            await viewModel.lockFocusAndExposure(at: point)
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
        guard viewModel.canCapture else {
            return
        }

        performShutterHaptic()
        let pendingCaptureWorkerClient = appAttestController.runtime.client
        Task {
            await viewModel.capture(
                pendingCaptureWorkerClient: pendingCaptureWorkerClient,
                suppressesShutterSound: !isShutterSoundEnabled,
                flashMode: flashMode.captureFlashMode
            )
        }
    }

    private func openTAPLibrary() {
        guard !viewModel.isCaptureWriteInProgress else {
            return
        }

        viewModel.pauseForAnalysis()
        routeStore.presentDepthAlbum()
    }

    private func switchCameraPosition() {
        Task { await viewModel.switchCameraPosition() }
    }

    private func performShutterHaptic() {
        guard isShutterHapticsEnabled else {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
