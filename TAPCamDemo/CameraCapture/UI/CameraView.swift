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

nonisolated enum CameraFeedbackPreferences {
    static let shutterHapticsEnabledKey = "CameraShutterHapticsEnabled"
    static let defaultShutterHapticsEnabled = true
    static let shutterSoundEnabledKey = "CameraShutterSoundEnabled"
    static let defaultShutterSoundEnabled = true

    static func shouldSuppressShutterSound(
        storedIsEnabled: Bool,
        suppressionSupported: Bool
    ) -> Bool {
        suppressionSupported && !storedIsEnabled
    }
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
    private let libraryStore: LibraryMediaStore
    private let initialReadinessGate: CameraInitialReadinessGate
    private let onViewfinderInteractive: () -> Void
    private let viewfinderFrameBarrier = CameraViewfinderFrameBarrier()
    @StateObject private var lifecycleCoordinator: CaptureLifecycleCoordinator
    @StateObject private var viewModel: CameraViewModel
    @StateObject private var routeStore: CameraRouteStore
    @StateObject private var chromeOrientation: CameraChromeOrientationController
    @StateObject private var appAttestController: AppAttestRuntimeController
    @StateObject private var hapticFeedbackController: CameraHapticFeedbackController
    private let intentHandoffStore: TAPCamIntentHandoffStore
    @State private var didCompleteInitialReadinessGate = false
    @State private var didFailInitialReadinessMarkerCommit = false
    @State private var resourceInitializationMarkerCommitTask: Task<Void, Never>?
    @State private var didPublishViewfinderInteractive = false
    @State private var viewfinderInteractivePublicationTask: Task<Void, Never>?
    #if DEBUG
    @State private var resourceInitializationDiagnosticTask: Task<Void, Never>?
    #endif
    @State private var isShowingSettings = false
    @State private var selectedMode: CameraCaptureModeOption = .photo
    @State private var flashMode: CameraFlashControlMode
    @State private var isLivePhotoEnabled: Bool
    @State private var focusMode = CameraFocusControlMode.auto
    @State private var activeAdjustmentControl: CameraAdjustmentControl?
    @State private var exposureControlState: CameraExposureControlState?
    @State private var latestExposureControlDebugState: CameraExposureControlDebugState?
    @State private var isBasicEVStripVisible = false
    @State private var globalEVBias: Double
    @State private var globalEVApplyTask: Task<Void, Never>?
    @State private var temporaryFocusEVOffset = 0.0
    @State private var temporaryFocusEVApplyTask: Task<Void, Never>?
    @State private var adjustmentDraft = CameraAdjustmentControlDraft.fallback
    @State private var adjustmentDraftMemory = CameraAdjustmentControlDraftMemory()
    @State private var exposureApplyTask: Task<Void, Never>?
    @State private var exposureReadbackTask: Task<Void, Never>?
    @State private var manualFocusAssistToken: UUID?
    @State private var manualFocusModeEntryToken: UUID?
    @State private var manualFocusDraftRevision: UInt64 = 0
    @State private var focusLoupePulseID: UUID?
    @State private var lastFocusMeteringAt = Date.distantPast
    @State private var viewfinderHint: String?
    @State private var cameraPathTransitionPresentation = CameraViewfinderTransitionPresentation.hidden
    @State private var cameraPathTransitionToken: UUID?
    @State private var cameraPathTransitionRuntimeCompleted = false
    @State private var previewController = CameraPreviewController()
    @State private var isPreviewLayerPreviewing = false
    @State private var previewReadinessGeneration = 0
    @State private var cameraPathPreviewWatchdogTask: Task<Void, Never>?
    @State private var pendingPhotographerModePreference: Bool?
    @State private var settingsSessionReconfigurationPolicy =
        CameraSettingsSessionReconfigurationPolicy()
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
    @AppStorage(CameraPhotographerModePreferences.startupPolicyKey)
    private var photographerModeStartupPolicyRawValue = CameraPhotographerModePreferences.defaultStartupPolicy.rawValue
    @AppStorage(CameraPhotographerModePreferences.lastPreferredEnabledKey)
    private var lastPhotographerModePreferredEnabled = CameraPhotographerModePreferences.defaultLastPreferredEnabled
    @AppStorage(CameraGuideOverlayPreference.storageKey)
    private var guideOverlayRawValue = CameraGuideOverlayPreference.defaultValue.rawValue
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue
    @AppStorage(CameraDepthAvailabilityHintPreferences.showsHintsKey)
    private var showsDepthAvailabilityHints = CameraDepthAvailabilityHintPreferences.defaultShowsHints
    @AppStorage(CameraFocusMagnifierPreference.storageKey)
    private var focusMagnifierRawValue = CameraFocusMagnifierPreference.defaultValue.rawValue
    @AppStorage(CameraLivePhotoPreferences.startupPolicyKey)
    private var livePhotoStartupPolicyRawValue = CameraLivePhotoPreferences.defaultStartupPolicy.rawValue
    @AppStorage(CameraLivePhotoPreferences.lastEnabledKey)
    private var lastLivePhotoEnabled = CameraLivePhotoPreferences.defaultLastEnabled
    @AppStorage(CameraCaptureDataUsePreferences.usesMicrophoneDataKey)
    private var usesMicrophoneData = CameraCaptureDataUsePreferences.defaultUsesMicrophoneData

    init(
        libraryStore: LibraryMediaStore,
        capabilityMatrix: CapabilityMatrix,
        libraryMediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        viewModel: CameraViewModel? = nil,
        routeStore: CameraRouteStore? = nil,
        appAttestController: AppAttestRuntimeController? = nil,
        lifecycleCoordinator: CaptureLifecycleCoordinator = CaptureLifecycleCoordinator(),
        hapticFeedbackController: CameraHapticFeedbackController = CameraHapticFeedbackController(),
        intentHandoffStore: TAPCamIntentHandoffStore = TAPCamIntentHandoffStore(),
        initialReadinessGate: CameraInitialReadinessGate = .disabled,
        onViewfinderInteractive: @escaping () -> Void = {}
    ) {
        let initialGlobalEVBias = CameraEVPreferences.resolvedLaunchBias()
        let initialFlashMode = CameraFlashControlMode.resolvedStartupMode()
        let initialLivePhotoEnabled = CameraLivePhotoPreferences.resolvedStartupIsEnabled()
        let initialPhotographerModeEnabled = CameraPhotographerModePreferences.resolvedStartupIsEnabled()
        self.initialReadinessGate = initialReadinessGate
        self.onViewfinderInteractive = onViewfinderInteractive
        self.intentHandoffStore = intentHandoffStore
        _lifecycleCoordinator = StateObject(wrappedValue: lifecycleCoordinator)
        _hapticFeedbackController = StateObject(wrappedValue: hapticFeedbackController)
        let resolvedLibraryStore = viewModel?.libraryStore ?? libraryStore
        self.libraryStore = resolvedLibraryStore
        if let viewModel {
            viewModel.requestedGlobalAutoExposureBias = initialGlobalEVBias
            viewModel.requestedPhotographerModeOnStart = initialPhotographerModeEnabled
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            // Keep construction inside StateObject's autoclosure. Parent route
            // updates (I commit and t5 release) can re-evaluate this View value
            // without eagerly discovering capabilities or discarding a second
            // capture-session graph.
            _viewModel = StateObject(wrappedValue: {
                let created = CameraViewModel(
                    capabilityMatrix: capabilityMatrix,
                    libraryStore: resolvedLibraryStore,
                    libraryMediaFetcher: libraryMediaFetcher
                )
                created.requestedGlobalAutoExposureBias = initialGlobalEVBias
                created.requestedPhotographerModeOnStart =
                    initialPhotographerModeEnabled
                return created
            }())
        }
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
        cameraReadinessObservers
    }

    private var cameraRootView: some View {
        NavigationStack {
            cameraSurface
                .allowsHitTesting(!viewModel.isFocusDistanceCalibrating)
                .accessibilityHidden(viewModel.isFocusDistanceCalibrating)
                .navigationTitle("Camera")
                .environment(\.locale, AppLanguage.english.locale)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: depthAlbumPresentedBinding) {
                    DepthAlbumPickerView(
                        routeStore: routeStore,
                        libraryStore: libraryStore,
                        mediaFetcher: viewModel.libraryMediaFetcher
                    )
                }
        }
        .disabled(initialReadinessState.blocksInteraction)
        .accessibilityHidden(initialReadinessState.blocksInteraction)
        .statusBarHidden(true)
        .environment(\.cameraHapticFeedbackController, hapticFeedbackController)
        .sheet(isPresented: $isShowingSettings) {
            DepthAnalyzerSettingsView(
                appAttestController: appAttestController,
                cameraViewModel: viewModel,
                shutterSoundSuppressionSupported: viewModel.isShutterSoundSuppressionSupported
            )
        }
        .cameraScreenLifecycle(
            lifecycleCoordinator: lifecycleCoordinator,
            viewModel: viewModel,
            routeStore: routeStore,
            chromeOrientation: chromeOrientation,
            appAttestController: appAttestController,
            isSettingsPresented: isShowingSettings,
            resumesVideoModeAfterLibrary: selectedMode == .video,
            onLibraryReturnCompleted: handleLibraryReturnCompleted
        )
        .overlay {
            if initialReadinessState.blocksInteraction {
                CameraInitialReadinessOverlayView(
                    state: initialReadinessState,
                    isCameraReady: startupCameraInteractionIsReady,
                    isLibraryReady: libraryStore.hasUsableSnapshot
                )
                .transition(.opacity)
            }
        }
    }

    private var cameraLifecycleObservers: some View {
        cameraRootView
        .onAppear(perform: cameraViewDidAppear)
        .onReceive(NotificationCenter.default.publisher(for: .tapCamIntentHandoffDidChange)) { _ in
            applyPendingIntentHandoff()
        }
        .onDisappear {
            lifecycleCoordinator.cancelCaptureModeChange()
            persistRememberedViewfinderControlStateIfNeeded()
            isBasicEVStripVisible = false
            activeAdjustmentControl = nil
            manualFocusModeEntryToken = nil
            viewModel.cancelManualFocusRuntime()
            cancelCameraPathTransitionPresentation()
            #if DEBUG
            resourceInitializationDiagnosticTask?.cancel()
            resourceInitializationDiagnosticTask = nil
            #endif
            resourceInitializationMarkerCommitTask?.cancel()
            resourceInitializationMarkerCommitTask = nil
            viewfinderInteractivePublicationTask?.cancel()
            viewfinderInteractivePublicationTask = nil
        }
        .onChange(of: isShowingSettings) { _, isPresented in
            if isPresented {
                persistRememberedViewfinderControlStateIfNeeded()
                isBasicEVStripVisible = false
                activeAdjustmentControl = nil
                let shouldRestoreAutoFocus = focusMode == .manual
                if shouldRestoreAutoFocus {
                    focusMode = .auto
                    manualFocusDraftRevision &+= 1
                    focusLoupePulseID = nil
                }
                manualFocusAssistToken = nil
                manualFocusModeEntryToken = nil
                viewModel.cancelManualFocusRuntime()
                if shouldRestoreAutoFocus {
                    Task {
                        await viewModel.restoreAutoFocus()
                    }
                }
            } else {
                applyPendingSettingsSessionReconfiguration()
            }
        }
        .onChange(of: outputFormatRawValue) { _, _ in
            captureSessionPreferenceDidChange()
        }
        .onChange(of: photoQualityRawValue) { _, _ in
            captureSessionPreferenceDidChange()
        }
    }

    private var cameraPreferenceAndSceneObservers: some View {
        cameraLifecycleObservers
        .onChange(of: flashStartupPolicyRawValue) { _, rawValue in
            applyFlashStartupPolicy(rawValue)
        }
        .onChange(of: livePhotoStartupPolicyRawValue) { _, rawValue in
            applyLivePhotoStartupPolicy(rawValue)
        }
        .onChange(of: photographerModeStartupPolicyRawValue) { _, rawValue in
            applyPhotographerModeStartupPolicy(rawValue)
        }
        .onChange(of: isShutterHapticsEnabled) { _, isEnabled in
            hapticFeedbackController.setEnabled(isEnabled)
        }
        .onChange(of: usesMicrophoneData) { _, _ in
            captureSessionPreferenceDidChange()
        }
        .onChange(of: routeStore.isDepthAlbumPresented) { _, isPresented in
            if isPresented {
                persistRememberedViewfinderControlStateIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.sessionController.setSceneActive(phase == .active)
            if phase != .active {
                cameraPathPreviewWatchdogTask?.cancel()
                cameraPathPreviewWatchdogTask = nil
                resourceInitializationMarkerCommitTask?.cancel()
                resourceInitializationMarkerCommitTask = nil
                viewfinderInteractivePublicationTask?.cancel()
                viewfinderInteractivePublicationTask = nil
                persistRememberedViewfinderControlStateIfNeeded()
                let shouldRestoreAutoFocus = focusMode == .manual
                if shouldRestoreAutoFocus {
                    focusMode = .auto
                    if activeAdjustmentControl == .focus {
                        activeAdjustmentControl = nil
                    }
                    manualFocusDraftRevision &+= 1
                    focusLoupePulseID = nil
                }
                manualFocusAssistToken = nil
                manualFocusModeEntryToken = nil
                viewModel.cancelManualFocusRuntime()
                Task {
                    if shouldRestoreAutoFocus {
                        await viewModel.restoreAutoFocus()
                    }
                    await viewModel.stopActiveVideoRecordingForLifecycleIfNeeded(
                        pendingCaptureWorkerClient: appAttestController.runtime.client
                    )
                }
            } else {
                hapticFeedbackController.prepareForCameraInteraction()
                evaluateStartupReadiness()
                prepareSelectedVideoModeIfNeeded()
                if let token = cameraPathTransitionToken {
                    beginCameraPathPreviewWatchdog(token: token)
                    releaseCameraPathTransitionIfPreviewResumed()
                }
            }
        }
        .onChange(of: viewModel.videoPreparationState) { _, state in
            if state == .needsPreparation {
                prepareSelectedVideoModeIfNeeded()
            }
        }
        .onChange(of: lifecycleCoordinator.isChangingCaptureMode) { _, isChanging in
            if !isChanging {
                prepareSelectedVideoModeIfNeeded()
            }
        }
    }

    private var cameraControlObservers: some View {
        cameraPreferenceAndSceneObservers
        .onChange(of: viewModel.latestCaptureDepthHint) { _, hint in
            guard let hint else {
                return
            }
            if runtimeShowsDepthAvailabilityHints {
                showViewfinderHint(hint.message)
            }
        }
        .onChange(of: activeAdjustmentControlKey) { _, _ in
            if viewModel.isPhotographerModeActive {
                alignVisibleAdjustmentControlsIfNeeded()
            }
        }
        .onChange(of: viewModel.activeControlCapabilities) { _, _ in
            if viewModel.isPhotographerModeActive {
                alignVisibleAdjustmentControlsIfNeeded()
            }
        }
        .onChange(of: viewModel.photographerModeState) { previousState, state in
            handlePhotographerModeStateChange(from: previousState, to: state)
        }
        .onChange(of: viewModel.isFocusDistanceCalibrating) { _, isCalibrating in
            if isCalibrating {
                globalEVApplyTask?.cancel()
                temporaryFocusEVApplyTask?.cancel()
                exposureApplyTask?.cancel()
                exposureReadbackTask?.cancel()
                return
            }
            alignVisibleAdjustmentControlsIfNeeded()
            if !isShowingSettings, !applyPendingSettingsSessionReconfiguration() {
                prepareSelectedVideoModeIfNeeded()
            }
        }
        .onChange(of: viewModel.exposureRuntimeEvent) { _, event in
            guard !viewModel.isFocusDistanceCalibrating,
                  viewModel.isPhotographerModeActive,
                  event?.kind == .exposureSettled else {
                return
            }
            scheduleManualControlReadback(reason: .exposureSettled, delay: .milliseconds(0))
        }
        .onChange(of: viewModel.focusRuntimeEvent) { _, event in
            guard !viewModel.isFocusDistanceCalibrating,
                  viewModel.isPhotographerModeActive,
                  event?.kind == .focusSettled else {
                return
            }
            handleFocusSettledMeteringTrigger()
        }
    }

    private var cameraReadinessObservers: some View {
        cameraControlObservers
        .onChange(of: runtimeShowsDepthAvailabilityHints) { _, isEnabled in
            if !isEnabled {
                viewfinderHint = nil
            }
        }
        .onChange(of: viewModel.isDepthCaptureReady) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: viewModel.isConfiguringSession) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: viewModel.activeSessionConfiguration != nil) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: isPreviewLayerPreviewing) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: startupPrimaryControlsAreSafe) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: hapticFeedbackController.hasPreparedCameraInteraction) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: libraryStore.hasUsableSnapshot) { _, _ in
            evaluateStartupReadiness()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            evaluateStartupReadiness()
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

    private var resourceInitializationInputsState: CameraInteractiveReadinessState {
        CameraInteractiveReadinessState.resolve(
            isGateEnabled: initialReadinessGate.isEnabled,
            didCompleteGate: didCompleteInitialReadinessGate,
            cameraAuthorizationStatus: AVCaptureDevice.authorizationStatus(for: .video),
            isConfiguringSession: viewModel.isConfiguringSession,
            hasActiveSessionConfiguration: viewModel.activeSessionConfiguration != nil,
            isDepthCaptureReady: viewModel.isDepthCaptureReady,
            hasPresentedFirstPreview: isPreviewLayerPreviewing,
            hasSafePrimaryControls: startupPrimaryControlsAreSafe,
            hasPreparedHaptics: hapticFeedbackController.hasPreparedCameraInteraction,
            hasUsableLibraryCatalog: libraryStore.hasUsableSnapshot,
            isSceneActive: scenePhase == .active
        )
    }

    private var initialReadinessState: CameraInteractiveReadinessState {
        if resourceInitializationMarkerCommitTask != nil,
           resourceInitializationInputsState == .ready {
            return .preparing(.markerCommit)
        }
        if didFailInitialReadinessMarkerCommit,
           resourceInitializationInputsState == .ready {
            return .preparing(.markerCommit)
        }
        return resourceInitializationInputsState
    }

    private var startupCameraInteractionIsReady: Bool {
        scenePhase == .active
            && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && !viewModel.isConfiguringSession
            && viewModel.activeSessionConfiguration != nil
            && viewModel.isDepthCaptureReady
            && isPreviewLayerPreviewing
            && startupPrimaryControlsAreSafe
            && hapticFeedbackController.hasPreparedCameraInteraction
    }

    private var startupPrimaryControlsAreSafe: Bool {
        !viewModel.isConfiguringSession
            && viewModel.activeSessionConfiguration != nil
            && !isCameraPathTransitioning
            && manualFocusAssistToken == nil
            && shutterIsEnabled
    }

    private func cameraViewDidAppear() {
        viewModel.sessionController.setSceneActive(scenePhase == .active)
        hapticFeedbackController.setEnabled(isShutterHapticsEnabled)
        hapticFeedbackController.prepareForCameraInteraction()
        applyPendingIntentHandoff()
        #if DEBUG
        scheduleResourceInitializationDiagnosticIfNeeded()
        #endif
        evaluateStartupReadiness()
    }

    private func evaluateStartupReadiness() {
        if initialReadinessGate.isEnabled,
           !didCompleteInitialReadinessGate,
           resourceInitializationMarkerCommitTask == nil,
           resourceInitializationInputsState == .ready {
            resourceInitializationMarkerCommitTask = Task { @MainActor in
                let preparedCommit = await initialReadinessGate.prepareCommit()
                guard !Task.isCancelled else {
                    preparedCommit?.discard()
                    return
                }
                guard resourceInitializationInputsState == .ready,
                      let preparedCommit else {
                    preparedCommit?.discard()
                    resourceInitializationMarkerCommitTask = nil
                    return
                }
                // No suspension is allowed between this atomic rename and the
                // matching t4 state publication below.
                let didCommit = preparedCommit.commit()
                resourceInitializationMarkerCommitTask = nil
                if didCommit {
                    didFailInitialReadinessMarkerCommit = false
                    didCompleteInitialReadinessGate = true
                    #if DEBUG
                    resourceInitializationDiagnosticTask?.cancel()
                    resourceInitializationDiagnosticTask = nil
                    #endif
                } else {
                    didFailInitialReadinessMarkerCommit = true
                    #if DEBUG
                    TAPDiagnostics.cameraCapture.error(
                        "resource_initialization_marker_commit failed"
                    )
                    #endif
                }
                scheduleViewfinderInteractivePublicationIfReady()
            }
        }

        scheduleViewfinderInteractivePublicationIfReady()
    }

    private func scheduleViewfinderInteractivePublicationIfReady() {
        guard !didPublishViewfinderInteractive,
              viewfinderInteractivePublicationTask == nil,
              startupCameraInteractionIsReady,
              !initialReadinessGate.isEnabled || didCompleteInitialReadinessGate else {
            return
        }

        viewfinderInteractivePublicationTask = Task { @MainActor in
            await viewfinderFrameBarrier.waitForCommittedViewfinderFrame()
            guard !Task.isCancelled else { return }
            viewfinderInteractivePublicationTask = nil
            guard !didPublishViewfinderInteractive,
                  startupCameraInteractionIsReady,
                  !initialReadinessGate.isEnabled || didCompleteInitialReadinessGate else {
                return
            }
            didPublishViewfinderInteractive = true
            viewModel.releaseDeferredLibraryCoverWork()
            onViewfinderInteractive()
            applyPendingIntentHandoff()
        }
    }

    #if DEBUG
    private func scheduleResourceInitializationDiagnosticIfNeeded() {
        guard initialReadinessGate.isEnabled,
              resourceInitializationDiagnosticTask == nil else {
            return
        }
        resourceInitializationDiagnosticTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard !didCompleteInitialReadinessGate else { return }
            let checkpoint = initialReadinessState.pendingCheckpoint
                ?? .markerCommit
            TAPDiagnostics.cameraCapture.error(
                "resource_initialization_incomplete checkpoint=\(checkpoint.rawValue, privacy: .public)"
            )
        }
    }
    #endif

    private var viewfinderHighlightColor: Color {
        CameraViewfinderHighlightPreference.resolved(rawValue: viewfinderHighlightRawValue).color
    }

    private var isCameraPathTransitioning: Bool {
        viewModel.photographerModeState.isTransitioning
            || viewModel.photographerModeState.requiresStandardRecovery
            || cameraPathTransitionPresentation.isPresented
    }

    private var effectiveCameraPathTransitionPresentation: CameraViewfinderTransitionPresentation {
        if viewModel.photographerModeState.requiresStandardRecovery {
            if viewModel.isSessionControllerSuspectedWedged {
                return .failed(message: "Camera service is not responding. Reopen TAP-NAP if it does not recover.")
            }
            return viewModel.canRetryUnconfiguredCameraRecovery
                ? .failed(message: "Unable to restore the camera.")
                : .presented(message: "Restoring standard camera…")
        }
        if cameraPathTransitionPresentation.isPresented {
            return cameraPathTransitionPresentation
        }
        switch viewModel.photographerModeState {
        case .activating:
            return .activatingProMode
        case .deactivating:
            return .deactivatingProMode
        case .unavailable, .standard, .active, .failed:
            return .hidden
        }
    }

    private var cameraPathRecoveryActionTitle: String? {
        viewModel.canRetryUnconfiguredCameraRecovery ? "Retry" : nil
    }

    private var cameraPathRecoveryAction: (() -> Void)? {
        guard viewModel.canRetryUnconfiguredCameraRecovery else {
            return nil
        }
        return {
            retryUnconfiguredCameraRecovery()
        }
    }

    private var proModeChromeState: CameraProModeChromeState {
        guard viewModel.photographerModeAvailability.isAvailable,
              viewModel.isRearCameraActive else {
            return .unavailable
        }

        switch viewModel.photographerModeState {
        case .activating, .deactivating:
            return .transitioning
        case .active:
            return .active
        case .failed(let recoveredMode, _):
            return recoveredMode == .photographer ? .active : .standard
        case .standard:
            return .standard
        case .unavailable:
            return .unavailable
        }
    }

    @ViewBuilder
    private func viewfinderChrome(topSafeAreaInset: CGFloat) -> some View {
        CameraViewfinderChromeView(
            state: CameraViewfinderChromeState(
                flashMode: flashMode,
                isFlashAvailable: viewModel.isFlashAvailable,
                isLivePhotoAvailable: selectedMode == .photo
                    && viewModel.isLivePhotoCaptureSupported,
                isLivePhotoEnabled: isLivePhotoEnabled,
                proModeState: proModeChromeState,
                basicEVState: basicEVControlState,
                videoRecordingTimecode: viewModel.videoRecordingStartedAt.map {
                    CameraVideoRecordingTimecodeState(
                        startedAt: $0,
                        maximumDuration: TAPVideoRecordingRequest.defaultMaximumDuration
                    )
                },
                contentRotation: chromeOrientation.angle
            ),
            highlightColor: viewfinderHighlightColor,
            topSafeAreaInset: topSafeAreaInset,
            onToggleBasicEV: toggleBasicEVStrip,
            onOpenSettings: {
                isShowingSettings = true
            },
            onCycleFlash: cycleFlashMode,
            onToggleLivePhoto: toggleLivePhoto,
            onToggleProMode: togglePhotographerMode
        )
        .allowsHitTesting(!isCameraPathTransitioning && !viewModel.isConfiguringSession)
        .accessibilityHidden(isCameraPathTransitioning || viewModel.isConfiguringSession)
    }

    @ViewBuilder
    private var captureControls: some View {
        CameraCaptureControlsView(
            state: CameraCaptureControlsState(
                isShutterEnabled: shutterIsEnabled,
                isLibraryWriteInProgress: viewModel.isCaptureWriteInProgress,
                selectedMode: selectedMode,
                isRecordingMovie: viewModel.isVideoRecording,
                isPreparingCaptureMode: viewModel.isPreparingVideoMode
                    || viewModel.videoPreparationState == .needsPreparation
                    || lifecycleCoordinator.isChangingCaptureMode,
                showsProfessionalControls: viewModel.isPhotographerModeActive
                    && (cameraPathTransitionPresentation == .hidden
                        || cameraPathTransitionPresentation == .switchingCaptureMode),
                isInteractionLocked: isCameraPathTransitioning || viewModel.isConfiguringSession,
                adjustmentControlState: adjustmentControlState,
                basicEVControlState: basicEVControlState,
                contentRotation: chromeOrientation.angle
            ),
            highlightColor: viewfinderHighlightColor,
            recentThumbnail: viewModel.recentThumbnail,
            recentLibraryPresentation: viewModel.recentLibraryPresentation,
            onOpenTAPLibrary: openTAPLibrary,
            onCapture: triggerShutter,
            onSwitchCamera: switchCameraPosition,
            onSelectMode: selectCaptureMode,
            onSelectAdjustmentControl: selectAdjustmentControl,
            onAdjustEV: adjustGlobalEVBias,
            onAdjustISO: adjustISO,
            onAdjustShutterPosition: adjustShutterPosition,
            onAdjustLensPosition: adjustLensPosition,
            onRestoreAutomaticMode: restoreAutomaticMode,
            onBeginAdjustment: beginAdjustmentInteraction,
            onEndAdjustment: endAdjustmentInteraction
        )
    }

    private var depthAlbumPresentedBinding: Binding<Bool> {
        Binding(
            get: { routeStore.isDepthAlbumPresented },
            set: { routeStore.setDepthAlbumPresented($0) }
        )
    }

    private var shutterIsEnabled: Bool {
        guard scenePhase == .active,
              !viewModel.isFocusDistanceCalibrating,
              isPreviewLayerPreviewing || viewModel.isVideoRecording,
              !isCameraPathTransitioning,
              !lifecycleCoordinator.isChangingCaptureMode,
              manualFocusAssistToken == nil else {
            return false
        }
        switch selectedMode {
        case .photo:
            return viewModel.canCapture
        case .video:
            return viewModel.canUseVideoShutter
        }
    }

    private func applyPendingIntentHandoff() {
        // Programmatic handoffs cannot bypass Resource Initialization. Leaving
        // the record in the store lets the first committed interactive frame
        // consume it exactly once at t5.
        guard didPublishViewfinderInteractive else { return }
        guard let handoff = intentHandoffStore.loadAndClearHandoff() else {
            return
        }

        switch handoff.destination {
        case .camera:
            routeStore.returnToCamera()
        case .tapLibrary:
            presentTAPLibrary()
        }
    }

    private var cameraPreviewStage: some View {
        #if DEBUG
        CameraPreviewStageView(
            session: viewModel.session,
            manualFocusPreviewStream: viewModel.manualFocusPreviewStream,
            previewController: previewController,
            state: previewStageState,
            highlightColor: viewfinderHighlightColor,
            recoveryActionTitle: cameraPathRecoveryActionTitle,
            onRecoveryAction: cameraPathRecoveryAction,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onPreviewingChanged: previewLayerPreviewingDidChange,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
            onTapFocusPoint: handleFocusTapAtPreviewPoint,
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
            manualFocusPreviewStream: viewModel.manualFocusPreviewStream,
            previewController: previewController,
            state: previewStageState,
            highlightColor: viewfinderHighlightColor,
            recoveryActionTitle: cameraPathRecoveryActionTitle,
            onRecoveryAction: cameraPathRecoveryAction,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onPreviewingChanged: previewLayerPreviewingDidChange,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
            onTapFocusPoint: handleFocusTapAtPreviewPoint,
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
            shouldShowFocalLengthSelector: viewModel.shouldShowFocalLengthSelector
                && effectiveCameraPathTransitionPresentation.keepsFocalLengthSelector,
            guideOverlayPreference: CameraGuideOverlayPreference.resolved(rawValue: guideOverlayRawValue),
            temporaryFocusEVOffset: temporaryFocusEVOffset,
            focusMode: focusMode,
            focusRuntimeEvent: viewModel.focusRuntimeEvent,
            focusMagnifierPreference: CameraFocusMagnifierPreference.resolved(rawValue: focusMagnifierRawValue),
            focusLoupePulseID: previewFocusLoupePulseID,
            viewfinderEdgeToastMessage: viewfinderHint,
            contentRotation: chromeOrientation.angle,
            transitionPresentation: effectiveCameraPathTransitionPresentation,
            previewReadinessGeneration: previewReadinessGeneration
        )
    }

    private var previewFocusLoupePulseID: UUID? {
        viewModel.isPhotographerModeActive ? focusLoupePulseID : nil
    }

    private var basicEVControlState: CameraBasicEVControlState {
        CameraBasicEVControlState(
            bias: globalEVBias,
            isStripVisible: isBasicEVStripVisible
        )
    }

    private func toggleBasicEVStrip() {
        guard !viewModel.isPhotographerModeActive,
              !viewModel.photographerModeState.isTransitioning else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            isBasicEVStripVisible.toggle()
        }
    }

    private var activeAdjustmentControlKey: String? {
        viewModel.activeSessionConfiguration?.controlCapabilities.deviceID
    }

    private var adjustmentControlState: CameraAdjustmentControlState? {
        guard viewModel.isPhotographerModeActive,
              let capability = viewModel.activeControlCapabilities else {
            return nil
        }
        let exposureState = resolvedExposureControlState(for: capability)
        let exposureDisplay = exposureState.currentDisplayState
        let displayedLensPosition: Double
        if focusMode == .auto {
            if let readback = viewModel.latestManualControlReadback,
               readback.deviceID == capability.deviceID,
               readback.generation == viewModel.configurationGeneration {
                displayedLensPosition = readback.lensPosition
            } else {
                displayedLensPosition = capability.focus.currentLensPosition
            }
        } else {
            displayedLensPosition = adjustmentDraft.lensPosition
        }
        let exposureDraft = CameraAdjustmentControlDraft(
            iso: exposureDisplay.iso,
            shutterDurationSeconds: exposureDisplay.shutterDurationSeconds,
            lensPosition: displayedLensPosition
        )
        return CameraAdjustmentControlState(
            capability: capability,
            activeControl: activeAdjustmentControl,
            exposureMode: adjustmentExposureMode(from: exposureDisplay),
            focusMode: focusMode,
            draft: exposureDraft,
            exposureRiskRanges: exposureRiskRanges(from: exposureState),
            allowsManualFocusControl: viewModel.isManualFocusControlAvailable,
            estimatedFocusDistanceMeters: viewModel.estimatedFocusDistanceMeters(at: displayedLensPosition)
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

    private func prepareSelectedVideoModeIfNeeded() {
        guard scenePhase == .active, selectedMode == .video,
              !viewModel.isFocusDistanceCalibrating,
              !viewModel.isPausedForAnalysis,
              !isCameraPathTransitioning, !viewModel.isConfiguringSession,
              viewModel.videoPreparationState == .idle || viewModel.videoPreparationState == .needsPreparation else {
            return
        }
        lifecycleCoordinator.prepareCaptureMode(
            to: .video,
            prepareVideoMode: prepareVideoModeForCurrentSelection,
            restorePhotoMode: {}
        )
    }

    private func prepareVideoModeForCurrentSelection() async -> Bool {
        let generation = viewModel.configurationGeneration
        let ready = await viewModel.prepareVideoModeIfNeeded()
        guard !Task.isCancelled, generation == viewModel.configurationGeneration,
              scenePhase == .active, !viewModel.isPausedForAnalysis,
              selectedMode == .video else { return false }
        if !ready {
            selectedMode = .photo
            showViewfinderHint("Video mode unavailable")
        }
        return ready
    }

    private func selectCaptureMode(_ mode: CameraCaptureModeOption) {
        guard mode != selectedMode,
              !isCameraPathTransitioning, !viewModel.isConfiguringSession else {
            return
        }
        guard !viewModel.isVideoRecording,
              !viewModel.isPreparingVideoMode else {
            return
        }
        let transitionToken = UUID()
        guard lifecycleCoordinator.prepareCaptureMode(
            to: mode,
            prepareVideoMode: prepareVideoModeForCurrentSelection,
            restorePhotoMode: { await viewModel.teardownPreparedVideoModeIfNeeded() },
            settled: {
                guard cameraPathTransitionToken == transitionToken else { return }
                if scenePhase == .active && !viewModel.isPausedForAnalysis {
                    completeCameraPathRuntimeTransition()
                } else {
                    cancelCameraPathTransitionPresentation()
                }
            }
        ) != nil else { return }
        beginCameraPathTransition(.switchingCaptureMode, token: transitionToken)
        selectedMode = mode
    }

    private func cycleFlashMode() {
        guard viewModel.isFlashAvailable else {
            showViewfinderHint("Flash unavailable")
            return
        }
        flashMode = flashMode.next
    }

    private func toggleLivePhoto() {
        guard selectedMode == .photo, !isCameraPathTransitioning else {
            return
        }
        isLivePhotoEnabled.toggle()
    }

    private func togglePhotographerMode() {
        guard !isCameraPathTransitioning,
              !lifecycleCoordinator.isChangingCaptureMode,
              !viewModel.isVideoRecording,
              !viewModel.isPreparingVideoMode else {
            return
        }
        guard viewModel.photographerModeAvailability.isAvailable else {
            if let reason = viewModel.photographerModeAvailability.unavailableReason {
                showViewfinderHint(reason.message)
            }
            return
        }
        guard viewModel.canTogglePhotographerMode else {
            return
        }

        let shouldEnable = !viewModel.isPhotographerModeActive
        resetModeSpecificControlsForCameraPathChange()
        let transitionToken = beginCameraPathTransition(shouldEnable
            ? .activatingProMode
            : .deactivatingProMode)
        pendingPhotographerModePreference = shouldEnable

        Task { @MainActor in
            defer { completeCameraPathRuntimeTransition(token: transitionToken) }
            if selectedMode == .video {
                await viewModel.teardownPreparedVideoModeIfNeeded()
            }
            guard cameraPathTransitionToken == transitionToken else { return }
            await viewModel.setPhotographerModeEnabled(shouldEnable)
            guard cameraPathTransitionToken == transitionToken else { return }

            let didReachRequestedStableMode: Bool
            if shouldEnable {
                didReachRequestedStableMode = viewModel.photographerModeState == .active
            } else {
                didReachRequestedStableMode = viewModel.photographerModeState == .standard
            }
            guard didReachRequestedStableMode else {
                if case .failed(_, let reason) = viewModel.photographerModeState {
                    showViewfinderHint(reason.message)
                }
                return
            }

            if selectedMode == .video {
                guard await prepareVideoModeForCurrentSelection() else { return }
            }

            if shouldEnable {
                alignVisibleAdjustmentControlsIfNeeded()
            } else {
                scheduleGlobalEVBiasApply(globalEVBias)
            }
        }
    }

    private func handlePhotographerModeStateChange(
        from previousState: PhotographerModeState,
        to state: PhotographerModeState
    ) {
        guard !viewModel.isFocusDistanceCalibrating else { return }
        switch state {
        case .active:
            if selectedMode != .video {
                completeCameraPathRuntimeTransition()
            }
            isBasicEVStripVisible = false
            alignVisibleAdjustmentControlsIfNeeded()
        case .standard, .unavailable:
            if selectedMode != .video,
               previousState.isTransitioning || previousState.requiresStandardRecovery {
                completeCameraPathRuntimeTransition()
            }
            activeAdjustmentControl = nil
            focusMode = .auto
        case .failed(let recoveredMode, let reason):
            if recoveredMode != .unconfigured {
                completeCameraPathRuntimeTransition()
            }
            if recoveredMode == .photographer {
                alignVisibleAdjustmentControlsIfNeeded()
            } else {
                activeAdjustmentControl = nil
                focusMode = .auto
            }
            showViewfinderHint(reason.message)
        case .activating:
            if !cameraPathTransitionPresentation.isPresented {
                beginCameraPathTransition(.activatingProMode)
            }
            resetModeSpecificControlsForCameraPathChange()
        case .deactivating:
            if !cameraPathTransitionPresentation.isPresented {
                beginCameraPathTransition(.deactivatingProMode)
            }
            resetModeSpecificControlsForCameraPathChange()
        }
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

    private func applyPhotographerModeStartupPolicy(_ rawValue: String) {
        viewModel.requestedPhotographerModeOnStart = CameraPhotographerModePreferences.resolvedStartupIsEnabled(
            policyRawValue: rawValue,
            lastPreferredEnabled: lastPhotographerModePreferredEnabled
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

    private var isPhotographerModePreferredForRearCamera: Bool {
        viewModel.isPhotographerModeActive
            || viewModel.suspendedRearModeIntent == .photographer
    }

    private func persistPhotographerModePreferenceAfterSuccessfulToggle(_ isEnabled: Bool) {
        guard CameraViewfinderControlDefaultPolicy.resolved(
            rawValue: photographerModeStartupPolicyRawValue,
            fallback: CameraPhotographerModePreferences.defaultStartupPolicy
        ) == .rememberLastState else {
            return
        }
        lastPhotographerModePreferredEnabled = isEnabled
    }

    /// Visual preferences such as the viewfinder highlight color must never
    /// rebuild the AVFoundation graph. Capture-format and microphone changes
    /// are the only Settings values observed here; coalesce them while the
    /// sheet is open so dismissal performs at most one session reconfiguration.
    private func captureSessionPreferenceDidChange() {
        guard settingsSessionReconfigurationPolicy.capturePreferenceDidChange(
            isSettingsPresented: isShowingSettings || viewModel.isFocusDistanceCalibrating
        ) else {
            return
        }
        reconfigureSessionForCapturePreferenceChange()
    }

    @discardableResult
    private func applyPendingSettingsSessionReconfiguration() -> Bool {
        guard !viewModel.isFocusDistanceCalibrating,
              settingsSessionReconfigurationPolicy.settingsDidDismiss() else {
            return false
        }
        reconfigureSessionForCapturePreferenceChange()
        return true
    }

    private func reconfigureSessionForCapturePreferenceChange() {
        Task { @MainActor in
            await viewModel.configureCurrentSelection()
            if selectedMode == .video {
                _ = await prepareVideoModeForCurrentSelection()
            }
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

        guard viewModel.isPhotographerModeActive else {
            scheduleGlobalEVBiasApply(nextBias)
            return
        }
        guard let capability = viewModel.activeControlCapabilities else {
            return
        }
        let result = resolvedExposureControlState(for: capability).setEVBias(nextBias)
        applyExposureControlResult(result, delay: .milliseconds(70))
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
        let exposureMode = viewModel.isPhotographerModeActive
            ? (exposureControlState?.mode ?? .auto)
            : .auto
        Task {
            if exposureMode == .auto {
                await viewModel.restoreAutoCameraControls(globalExposureBias: globalEVBias)
            } else {
                await viewModel.restoreAutoFocus()
            }
        }
    }

    private func selectAdjustmentControl(_ control: CameraAdjustmentControl) {
        guard viewModel.isPhotographerModeActive else {
            return
        }
        guard let state = adjustmentControlState else {
            showViewfinderHint("Camera controls unavailable")
            return
        }

        switch control {
        case .ev:
            activeAdjustmentControl = activeAdjustmentControl == .ev ? nil : .ev
        case .iso:
            guard state.exposure.isAvailable,
                  state.exposure.isoScale.isAdjustable else {
                showViewfinderHint("ISO unavailable")
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .iso ? nil : .iso
        case .shutter:
            guard state.exposure.isAvailable,
                  state.exposure.shutterScale.isAdjustable else {
                showViewfinderHint("Shutter unavailable")
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .shutter ? nil : .shutter
        case .focus:
            guard state.focus.isAvailable else {
                showViewfinderHint("Focus unavailable")
                return
            }
            activeAdjustmentControl = activeAdjustmentControl == .focus ? nil : .focus
        }
    }

    private func restoreAutomaticMode(_ control: CameraAdjustmentControl) {
        switch control {
        case .iso:
            guard let exposureControlState,
                  !exposureControlState.mode.isISOAutomatic else {
                return
            }
            applyExposureControlResult(exposureControlState.makeISOAutomatic())
            activeAdjustmentControl = .iso
        case .shutter:
            guard let exposureControlState,
                  !exposureControlState.mode.isShutterAutomatic else {
                return
            }
            applyExposureControlResult(exposureControlState.makeShutterAutomatic())
            activeAdjustmentControl = .shutter
        case .focus:
            restoreAutoFocusFromStrip()
        case .ev:
            break
        }
    }

    private func beginAdjustmentInteraction(_ control: CameraAdjustmentControl) async -> Double? {
        guard !Task.isCancelled, let state = adjustmentControlState else {
            return nil
        }
        if control == .focus {
            guard state.focus.isAvailable,
                  manualFocusModeEntryToken == nil else {
                return nil
            }
            guard focusMode == .auto else {
                return state.focus.lensPosition
            }

            let entryToken = UUID()
            manualFocusModeEntryToken = entryToken
            focusMode = .manual
            activeAdjustmentControl = .focus
            let snapshot = await viewModel.lockManualFocusAtCurrentLensPosition()
            guard manualFocusModeEntryToken == entryToken,
                  focusMode == .manual else {
                return nil
            }
            guard let snapshot,
                  snapshot.focusMode == .locked else {
                manualFocusModeEntryToken = nil
                focusMode = .auto
                viewModel.cancelManualFocusRuntime()
                showViewfinderHint("Manual focus unavailable")
                await viewModel.restoreAutoFocus()
                return nil
            }
            manualFocusModeEntryToken = nil
            storeAdjustmentDraft(
                adjustmentDraft.replacingLensPosition(snapshot.lensPosition),
                state: state
            )
            return adjustmentDraft.lensPosition
        }

        guard let exposureInteraction = exposureInteraction(for: control),
              let capability = viewModel.activeControlCapabilities else {
            return nil
        }
        let result = resolvedExposureControlState(for: capability).beginInteraction(exposureInteraction)
        exposureControlState = result.nextState
        latestExposureControlDebugState = result.debugState
        switch control {
        case .ev:
            return result.displayState.evBias
        case .iso:
            if state.exposure.isoAutomationState == .automatic {
                adjustISO(result.displayState.iso)
            }
            return result.displayState.iso
        case .shutter:
            let duration = result.displayState.shutterDurationSeconds
            if state.exposure.shutterAutomationState == .automatic {
                adjustShutterPosition(state.exposure.shutterPosition(for: duration))
            }
            return duration
        case .focus:
            return nil
        }
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

        storeAdjustmentDraft(
            adjustmentDraft.replacingISO(value),
            state: state
        )
        let result = resolvedExposureControlState(for: capability).setISO(value)
        applyExposureControlResult(result)
    }

    private func adjustShutterPosition(_ position: Double) {
        guard let capability = viewModel.activeControlCapabilities,
              let state = adjustmentControlState else {
            return
        }

        let shutterDuration = state.exposure.shutterDuration(forPosition: position)
        storeAdjustmentDraft(
            adjustmentDraft.replacingShutterDuration(shutterDuration),
            state: state
        )
        let result = resolvedExposureControlState(for: capability).setShutterDuration(shutterDuration)
        applyExposureControlResult(result)
    }

    private func adjustLensPosition(_ value: Double) {
        guard focusMode == .manual,
              manualFocusModeEntryToken == nil,
              let state = adjustmentControlState else {
            return
        }

        manualFocusDraftRevision &+= 1
        focusLoupePulseID = UUID()
        storeAdjustmentDraft(
            adjustmentDraft.replacingLensPosition(value),
            state: state
        )
        viewModel.queueManualFocus(lensPosition: value)
    }

    private func restoreAutoFocusFromStrip() {
        guard focusMode == .manual else {
            return
        }
        manualFocusAssistToken = nil
        manualFocusModeEntryToken = nil
        viewModel.cancelManualFocusRuntime()
        focusMode = .auto
        activeAdjustmentControl = .focus
        Task { @MainActor in
            guard focusMode == .auto,
                  manualFocusModeEntryToken == nil else {
                return
            }
            await viewModel.restoreAutoFocus()
        }
    }

    private func alignVisibleAdjustmentControlsIfNeeded() {
        guard !viewModel.isFocusDistanceCalibrating else { return }
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
            manualFocusModeEntryToken = nil
            viewModel.cancelManualFocusRuntime()
            exposureApplyTask?.cancel()
            Task {
                await viewModel.restoreAutoCameraControls(globalExposureBias: globalEVBias)
            }
            scheduleManualControlReadback(reason: .initialBaseline)
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
        guard !viewModel.isFocusDistanceCalibrating,
              let capability = viewModel.activeControlCapabilities else {
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

    private func focusAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        let exposureMode = viewModel.isPhotographerModeActive
            ? (exposureControlState?.mode ?? .auto)
            : .auto
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
    }

    /// The preview stage can briefly render one frame behind the parent while
    /// AF/MF state changes. Resolve the interaction from CameraView's current
    /// state so the first tap after entering MF cannot be routed through the
    /// stale AF callback.
    private func handleFocusTapAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        if viewModel.isPhotographerModeActive, focusMode == .manual {
            manualFocusTapAssistAtPreviewPoint(point)
        } else {
            focusAtPreviewPoint(point)
        }
    }

    private func manualFocusTapAssistAtPreviewPoint(_ point: CameraPreviewFocusPoint) {
        guard viewModel.isPhotographerModeActive,
              focusMode == .manual else {
            return
        }
        temporaryFocusEVOffset = 0
        temporaryFocusEVApplyTask?.cancel()
        let assistToken = UUID()
        let draftRevisionAtAssist = manualFocusDraftRevision
        manualFocusModeEntryToken = nil
        manualFocusAssistToken = assistToken
        focusLoupePulseID = UUID()
        Task { @MainActor in
            let outcome = await viewModel.performManualFocusTapAssist(at: point)
            guard manualFocusAssistToken == assistToken,
                  focusMode == .manual else {
                return
            }
            manualFocusAssistToken = nil

            switch outcome {
            case .focused(let snapshot):
                if manualFocusDraftRevision == draftRevisionAtAssist,
                   let state = adjustmentControlState {
                    storeAdjustmentDraft(
                        adjustmentDraft.replacingLensPosition(snapshot.lensPosition),
                        state: state
                    )
                }
            case .failedButRecovered(let snapshot):
                if manualFocusDraftRevision == draftRevisionAtAssist,
                   let state = adjustmentControlState {
                    storeAdjustmentDraft(
                        adjustmentDraft.replacingLensPosition(snapshot.lensPosition),
                        state: state
                    )
                }
                showViewfinderHint("Focus assist unavailable")
            case .unavailable:
                showViewfinderHint("Focus assist unavailable")
            case .manualFocusLost:
                focusMode = .auto
                if activeAdjustmentControl == .focus {
                    activeAdjustmentControl = nil
                }
                manualFocusDraftRevision &+= 1
                focusLoupePulseID = nil
                viewModel.cancelManualFocusRuntime()
                showViewfinderHint("Manual focus unavailable")
                await viewModel.restoreAutoFocus()
            case .cancelled:
                break
            }
        }
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
        viewModel.isPhotographerModeActive ? debugManualControlLines : []
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
        guard (!option.isSelected || viewModel.activeSessionConfiguration == nil),
              !isCameraPathTransitioning,
              !lifecycleCoordinator.isChangingCaptureMode,
              let index = focalLengthOptionIndex(for: option.selectionToken),
              viewModel.focalLengthOptions.indices.contains(index) else {
            return
        }
        let sourceOption = viewModel.focalLengthOptions[index]
        Task { @MainActor in
            let transitionToken = UUID()
            let expectedGeneration = viewModel.configurationGeneration + 1
            await viewModel.selectFocalLengthOption(
                sourceOption,
                transitionDuration: CameraViewfinderTransitionPresentation.duration
            ) {
                beginCameraPathTransition(.switchingFocalLength, token: transitionToken)
            }
            guard viewModel.configurationGeneration == expectedGeneration else { return }
            if scenePhase == .active, !viewModel.isPausedForAnalysis {
                if selectedMode == .video, viewModel.activeSessionConfiguration != nil {
                    _ = await prepareVideoModeForCurrentSelection()
                    guard viewModel.configurationGeneration == expectedGeneration else { return }
                    guard scenePhase == .active, !viewModel.isPausedForAnalysis else {
                        if cameraPathTransitionToken == transitionToken {
                            cancelCameraPathTransitionPresentation()
                        }
                        return
                    }
                }
                if cameraPathTransitionToken == transitionToken {
                    completeCameraPathRuntimeTransition()
                }
            } else if cameraPathTransitionToken == transitionToken {
                cancelCameraPathTransitionPresentation()
            }
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
                    suppressesShutterSound: CameraFeedbackPreferences.shouldSuppressShutterSound(
                        storedIsEnabled: isShutterSoundEnabled,
                        suppressionSupported: viewModel.isShutterSoundSuppressionSupported
                    ),
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

    private var runtimeShowsDepthAvailabilityHints: Bool {
        CameraDepthAvailabilityHintPreferences.resolvedShowsHints(
            storedValue: showsDepthAvailabilityHints
        )
    }

    private func openTAPLibrary() {
        guard !viewModel.isCaptureWriteInProgress,
              !viewModel.isVideoRecording else {
            return
        }

        presentTAPLibrary()
    }

    private func presentTAPLibrary() {
        guard !routeStore.isDepthAlbumPresented else {
            return
        }

        isBasicEVStripVisible = false
        activeAdjustmentControl = nil
        focusMode = .auto
        manualFocusAssistToken = nil
        manualFocusModeEntryToken = nil
        manualFocusDraftRevision &+= 1
        focusLoupePulseID = nil

        lifecycleCoordinator.cancelCaptureModeChange()
        beginCameraPathTransition(.resumingPreview)
        viewModel.pauseForAnalysis()
        routeStore.presentDepthAlbum()
    }

    private func handleLibraryReturnCompleted(
        _ result: CaptureLifecycleCoordinator.LibraryReturnResult
    ) {
        switch result {
        case .cameraReady:
            completeCameraPathRuntimeTransition()
        case .videoReady:
            completeCameraPathRuntimeTransition()
            if viewModel.isPhotographerModeActive {
                alignVisibleAdjustmentControlsIfNeeded()
            }
        case .failed:
            if selectedMode == .video {
                selectedMode = .photo
                showViewfinderHint("Video mode unavailable")
            }
            completeCameraPathRuntimeTransition()
        }
    }

    private func switchCameraPosition() {
        guard !isCameraPathTransitioning,
              !viewModel.isConfiguringSession,
              !lifecycleCoordinator.isChangingCaptureMode,
              !viewModel.isVideoRecording,
              !viewModel.isPreparingVideoMode else {
            return
        }

        let isSwitchingFromRear = viewModel.isRearCameraActive
        let involvesPhotographerMode = isPhotographerModePreferredForRearCamera
        resetModeSpecificControlsForCameraPathChange()

        let transitionToken = beginCameraPathTransition(isSwitchingFromRear
            ? .switchingToFrontCamera
            : (involvesPhotographerMode ? .restoringProMode : .switchingToRearCamera))

        Task { @MainActor in
            defer { completeCameraPathRuntimeTransition(token: transitionToken) }
            if selectedMode == .video {
                await viewModel.teardownPreparedVideoModeIfNeeded()
            }
            guard cameraPathTransitionToken == transitionToken else { return }
            await viewModel.switchCameraPosition()
            guard cameraPathTransitionToken == transitionToken else { return }
            if viewModel.isPhotographerModeActive {
                alignVisibleAdjustmentControlsIfNeeded()
            }
            if selectedMode == .video {
                _ = await prepareVideoModeForCurrentSelection()
            }
        }
    }

    private func retryUnconfiguredCameraRecovery() {
        guard viewModel.canRetryUnconfiguredCameraRecovery else {
            return
        }
        resetModeSpecificControlsForCameraPathChange()
        let transitionToken = beginCameraPathTransition(.presented(message: "Restoring standard camera…"))
        Task { @MainActor in
            await viewModel.configureCurrentSelection()
            completeCameraPathRuntimeTransition(token: transitionToken)
        }
    }

    private func resetModeSpecificControlsForCameraPathChange() {
        isBasicEVStripVisible = false
        activeAdjustmentControl = nil
        focusMode = .auto
        temporaryFocusEVOffset = 0
        manualFocusAssistToken = nil
        manualFocusModeEntryToken = nil
        focusLoupePulseID = nil
        viewModel.cancelManualFocusRuntime()
        globalEVApplyTask?.cancel()
        temporaryFocusEVApplyTask?.cancel()
        exposureApplyTask?.cancel()
        exposureReadbackTask?.cancel()
    }

    @discardableResult
    private func beginCameraPathTransition(
        _ presentation: CameraViewfinderTransitionPresentation,
        token: UUID = UUID()
    ) -> UUID {
        cameraPathPreviewWatchdogTask?.cancel()
        cameraPathPreviewWatchdogTask = nil
        pendingPhotographerModePreference = nil
        previewController.retainCurrentAppearance()
        cameraPathTransitionToken = token
        cameraPathTransitionRuntimeCompleted = false
        cameraPathTransitionPresentation = presentation
        return token
    }

    private func completeCameraPathRuntimeTransition(token: UUID? = nil) {
        if let token, cameraPathTransitionToken != token { return }
        guard cameraPathTransitionPresentation.isPresented,
              !viewModel.isPausedForAnalysis else {
            return
        }
        let needsPostRuntimePreviewConfirmation = !cameraPathTransitionRuntimeCompleted
        if needsPostRuntimePreviewConfirmation {
            // Require one current-value report from PreviewLayer after Runtime
            // reaches a stable state. This is not a synthetic stop event.
            isPreviewLayerPreviewing = false
            previewReadinessGeneration &+= 1
        }
        cameraPathTransitionRuntimeCompleted = true
        if needsPostRuntimePreviewConfirmation,
           let token = cameraPathTransitionToken {
            beginCameraPathPreviewWatchdog(token: token)
        }
        releaseCameraPathTransitionIfPreviewResumed()
    }

    private func beginCameraPathPreviewWatchdog(token: UUID) {
        cameraPathPreviewWatchdogTask?.cancel()
        cameraPathPreviewWatchdogTask = nil
        // System interruptions suspend preview. Give the current transition a
        // fresh preview deadline only once the scene is active again.
        guard scenePhase == .active,
              cameraPathTransitionToken == token,
              cameraPathTransitionRuntimeCompleted,
              !isPreviewLayerPreviewing else {
            return
        }
        cameraPathPreviewWatchdogTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  scenePhase == .active,
                  cameraPathTransitionToken == token,
                  cameraPathTransitionRuntimeCompleted,
                  !isPreviewLayerPreviewing,
                  !viewModel.photographerModeState.isTransitioning else {
                return
            }
            viewModel.failCameraPathAfterPreviewTimeout()
            cancelCameraPathTransitionPresentation()
        }
    }

    private func previewLayerPreviewingDidChange(_ isPreviewing: Bool, generation: Int) {
        guard generation == previewReadinessGeneration else { return }
        isPreviewLayerPreviewing = isPreviewing
        evaluateStartupReadiness()
        guard cameraPathTransitionToken != nil else {
            return
        }
        releaseCameraPathTransitionIfPreviewResumed()
    }

    private func releaseCameraPathTransitionIfPreviewResumed() {
        guard scenePhase == .active,
              !viewModel.isPausedForAnalysis,
              cameraPathTransitionToken != nil,
              cameraPathTransitionRuntimeCompleted,
              isPreviewLayerPreviewing,
              !viewModel.photographerModeState.isTransitioning else {
            return
        }

        releaseCameraPathTransitionPresentation()
    }

    private func releaseCameraPathTransitionPresentation() {
        if let pendingPhotographerModePreference {
            let didReachRequestedStableMode = pendingPhotographerModePreference
                ? viewModel.photographerModeState == .active
                : viewModel.photographerModeState == .standard
            if didReachRequestedStableMode {
                persistPhotographerModePreferenceAfterSuccessfulToggle(
                    pendingPhotographerModePreference
                )
            }
        }
        cancelCameraPathTransitionPresentation()
        prepareSelectedVideoModeIfNeeded()
    }

    private func cancelCameraPathTransitionPresentation() {
        cameraPathPreviewWatchdogTask?.cancel()
        cameraPathPreviewWatchdogTask = nil
        cameraPathTransitionToken = nil
        cameraPathTransitionRuntimeCompleted = false
        pendingPhotographerModePreference = nil
        cameraPathTransitionPresentation = .hidden
        previewController.releaseRetainedAppearance()
    }

    private func performShutterHaptic() {
        hapticFeedbackController.shutterAccepted()
    }
}
