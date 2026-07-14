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

    private let startsAutomatically: Bool
    private let lifecycleCoordinator: CaptureLifecycleCoordinator
    private let isSettingsPresented: Bool

    init(
        startsAutomatically: Bool,
        lifecycleCoordinator: CaptureLifecycleCoordinator,
        viewModel: CameraViewModel,
        routeStore: CameraRouteStore,
        chromeOrientation: CameraChromeOrientationController,
        appAttestController: AppAttestRuntimeController,
        isSettingsPresented: Bool
    ) {
        self.startsAutomatically = startsAutomatically
        self.lifecycleCoordinator = lifecycleCoordinator
        self.viewModel = viewModel
        self.routeStore = routeStore
        self.chromeOrientation = chromeOrientation
        self.appAttestController = appAttestController
        self.isSettingsPresented = isSettingsPresented
    }

    func body(content: Content) -> some View {
        content
            .task {
                await lifecycleCoordinator.startCameraIfNeeded(
                    startsAutomatically: startsAutomatically,
                    viewModel: viewModel
                )
                await lifecycleCoordinator.warmPendingCaptureSigningCredentialAndRetryIfNeeded(
                    startsAutomatically: startsAutomatically,
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
            viewModel: viewModel,
            chromeOrientation: chromeOrientation
        )
        CameraIdleTimerController.setCameraScreenIdleTimerDisabled(false)
    }

    private func depthAlbumPresentationDidChange(_ isPresented: Bool) {
        updateIdleTimerForCurrentPresentation()
        Task {
            await lifecycleCoordinator.depthAlbumPresentationDidChange(
                isPresented: isPresented,
                viewModel: viewModel,
                appAttestController: appAttestController
            )
        }
    }

    private func scenePhaseDidChange(_ phase: ScenePhase) {
        updateIdleTimerForCurrentPresentation()
        let shouldReturnToCameraOnForeground = lifecycleCoordinator.foregroundRouteRestorePolicy(
            for: phase,
            returnsToCameraOnForeground: CameraRoutePreferences.returnToCameraOnForeground()
        )
        let transition = lifecycleCoordinator.prepareSceneTransition(
            phase,
            startsAutomatically: startsAutomatically,
            shouldReturnToCameraOnForeground: shouldReturnToCameraOnForeground
        )
        Task {
            await lifecycleCoordinator.performSceneTransition(
                transition,
                routeStore: routeStore,
                viewModel: viewModel,
                appAttestController: appAttestController
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
                viewModel: viewModel,
                appAttestController: appAttestController
            )
        }
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
        startsAutomatically: Bool,
        lifecycleCoordinator: CaptureLifecycleCoordinator,
        viewModel: CameraViewModel,
        routeStore: CameraRouteStore,
        chromeOrientation: CameraChromeOrientationController,
        appAttestController: AppAttestRuntimeController,
        isSettingsPresented: Bool
    ) -> some View {
        modifier(CameraViewLifecycleModifier(
            startsAutomatically: startsAutomatically,
            lifecycleCoordinator: lifecycleCoordinator,
            viewModel: viewModel,
            routeStore: routeStore,
            chromeOrientation: chromeOrientation,
            appAttestController: appAttestController,
            isSettingsPresented: isSettingsPresented
        ))
    }
}
