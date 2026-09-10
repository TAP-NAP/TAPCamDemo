//
//  CameraViewLifecycleModifier.swift
//  TAPCamDemo
//

import SwiftUI

/// Keeps camera-screen lifecycle event forwarding and screen-awake policy out
/// of the layout body.
///
/// `CaptureLifecycleCoordinator` still owns the policy. This modifier only wires
/// SwiftUI lifecycle events to that coordinator and applies the main-app
/// camera idle-timer gate so `CameraView` can stay focused on object lifetime,
/// navigation, sheet presentation, and visible UI.
struct CameraViewLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var viewModel: CameraViewModel
    @ObservedObject private var routeStore: CameraRouteStore
    @ObservedObject private var chromeOrientation: CameraChromeOrientationController
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    @AppStorage(CameraIdleTimerPreferences.keepScreenAwakeKey)
    private var keepScreenAwake = CameraIdleTimerPreferences.defaultKeepScreenAwake

    private let lifecycleCoordinator: CaptureLifecycleCoordinator
    private let isSettingsPresented: Bool
    private let resumesVideoModeAfterLibrary: Bool
    private let onLibraryReturnCompleted:
        @MainActor (CaptureLifecycleCoordinator.LibraryReturnResult) -> Void

    init(
        lifecycleCoordinator: CaptureLifecycleCoordinator,
        viewModel: CameraViewModel,
        routeStore: CameraRouteStore,
        chromeOrientation: CameraChromeOrientationController,
        appAttestController: AppAttestRuntimeController,
        isSettingsPresented: Bool,
        resumesVideoModeAfterLibrary: Bool,
        onLibraryReturnCompleted: @escaping
            @MainActor (CaptureLifecycleCoordinator.LibraryReturnResult) -> Void
    ) {
        self.lifecycleCoordinator = lifecycleCoordinator
        self.viewModel = viewModel
        self.routeStore = routeStore
        self.chromeOrientation = chromeOrientation
        self.appAttestController = appAttestController
        self.isSettingsPresented = isSettingsPresented
        self.resumesVideoModeAfterLibrary = resumesVideoModeAfterLibrary
        self.onLibraryReturnCompleted = onLibraryReturnCompleted
    }

    func body(content: Content) -> some View {
        content
            .task {
                await viewModel.start()
                await lifecycleCoordinator.warmPendingCaptureSigningCredentialAndRetryIfNeeded(
                    viewModel: viewModel,
                    appAttestController: appAttestController
                )
            }
            .onAppear(perform: viewDidAppear)
            .onDisappear(perform: viewDidDisappear)
            .onChange(of: routeStore.isDepthAlbumPresented) { _, isPresented in
                depthAlbumPresentationDidChange(isPresented)
            }
            .onChange(of: scenePhase) { _, phase in
                scenePhaseDidChange(phase)
            }
            .onChange(of: keepScreenAwake) { _, _ in
                updateIdleTimerForCurrentPresentation()
            }
            .onChange(of: isSettingsPresented) { _, _ in
                updateIdleTimerForCurrentPresentation()
            }
            .onChange(of: appAttestController.isPreparingCredential) { wasPreparing, isPreparing in
                credentialPreparationDidChange(wasPreparing: wasPreparing, isPreparing: isPreparing)
            }
    }

    private func viewDidAppear() {
        lifecycleCoordinator.viewDidAppear(chromeOrientation: chromeOrientation)
        updateIdleTimerForCurrentPresentation()
    }

    private func viewDidDisappear() {
        lifecycleCoordinator.viewDidDisappear(
            chromeOrientation: chromeOrientation,
            stopCamera: viewModel.stop
        )
        CameraIdleTimerController.setCameraScreenIdleTimerDisabled(false)
    }

    private func depthAlbumPresentationDidChange(_ isPresented: Bool) {
        updateIdleTimerForCurrentPresentation()
        Task {
            let result = await lifecycleCoordinator.depthAlbumPresentationDidChange(
                isPresented: isPresented,
                preparesVideoMode: resumesVideoModeAfterLibrary,
                resumeAfterAnalysis: viewModel.resumeAfterAnalysis,
                prepareVideoMode: { await viewModel.prepareVideoModeIfNeeded() },
                isCameraReady: { viewModel.activeSessionConfiguration != nil },
                retryPendingCaptures: { [weak lifecycleCoordinator, viewModel, appAttestController] in
                    await lifecycleCoordinator?.retryPendingCaptures(
                        viewModel: viewModel,
                        appAttestController: appAttestController
                    )
                }
            )
            onLibraryReturnCompleted(result)
        }
    }

    private func scenePhaseDidChange(_ phase: ScenePhase) {
        updateIdleTimerForCurrentPresentation()
        let shouldReturnToCameraOnForeground = lifecycleCoordinator.foregroundRouteRestorePolicy(
            for: phase,
            returnsToCameraOnForeground: CameraRoutePreferences.returnToCameraOnForeground()
        )
        Task {
            await lifecycleCoordinator.scenePhaseDidChange(
                phase,
                shouldReturnToCameraOnForeground: shouldReturnToCameraOnForeground,
                routeStore: routeStore,
                refreshLibraryPreview: { viewModel.scheduleRecentTAPLibraryPreviewRefresh() },
                retryPendingCaptures: retryPendingCaptures
            )
        }
    }

    private func credentialPreparationDidChange(
        wasPreparing: Bool,
        isPreparing: Bool
    ) {
        Task {
            await lifecycleCoordinator.credentialPreparationDidChange(
                wasPreparing: wasPreparing,
                isPreparing: isPreparing,
                retryPendingCaptures: retryPendingCaptures
            )
        }
    }

    private func retryPendingCaptures() async {
        await lifecycleCoordinator.retryPendingCaptures(
            viewModel: viewModel,
            appAttestController: appAttestController
        )
    }

    private func updateIdleTimerForCurrentPresentation() {
        CameraIdleTimerController.setCameraScreenIdleTimerDisabled(
            CameraIdleTimerPolicy.shouldDisableIdleTimer(
                keepScreenAwake: keepScreenAwake,
                isCameraViewVisible: true,
                isActiveScene: scenePhase == .active,
                isSettingsPresented: isSettingsPresented,
                isLibraryPresented: routeStore.isDepthAlbumPresented
            )
        )
    }
}

extension View {
    func cameraScreenLifecycle(
        lifecycleCoordinator: CaptureLifecycleCoordinator,
        viewModel: CameraViewModel,
        routeStore: CameraRouteStore,
        chromeOrientation: CameraChromeOrientationController,
        appAttestController: AppAttestRuntimeController,
        isSettingsPresented: Bool,
        resumesVideoModeAfterLibrary: Bool,
        onLibraryReturnCompleted: @escaping
            @MainActor (CaptureLifecycleCoordinator.LibraryReturnResult) -> Void
    ) -> some View {
        modifier(CameraViewLifecycleModifier(
            lifecycleCoordinator: lifecycleCoordinator,
            viewModel: viewModel,
            routeStore: routeStore,
            chromeOrientation: chromeOrientation,
            appAttestController: appAttestController,
            isSettingsPresented: isSettingsPresented,
            resumesVideoModeAfterLibrary: resumesVideoModeAfterLibrary,
            onLibraryReturnCompleted: onLibraryReturnCompleted
        ))
    }
}
