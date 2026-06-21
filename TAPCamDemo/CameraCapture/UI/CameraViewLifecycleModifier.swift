//
//  CameraViewLifecycleModifier.swift
//  TAPCamDemo
//

import SwiftUI

/// Keeps camera-screen lifecycle event forwarding out of the layout body.
///
/// `CaptureLifecycleCoordinator` still owns the policy. This modifier only wires
/// SwiftUI lifecycle events to that coordinator so `CameraView` can stay focused
/// on object lifetime, navigation, sheet presentation, and visible UI.
struct CameraViewLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var viewModel: CameraViewModel
    @ObservedObject private var routeStore: CameraRouteStore
    @ObservedObject private var chromeOrientation: CameraChromeOrientationController
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    @AppStorage(CameraRoutePreferences.forceCameraOnForegroundAfterDelayKey)
    private var forceCameraOnForegroundAfterDelay = CameraRoutePreferences.defaultForceCameraOnForegroundAfterDelay
    @State private var backgroundedAt: Date?

    private let startsAutomatically: Bool
    private let lifecycleCoordinator: CaptureLifecycleCoordinator

    init(
        startsAutomatically: Bool,
        lifecycleCoordinator: CaptureLifecycleCoordinator,
        viewModel: CameraViewModel,
        routeStore: CameraRouteStore,
        chromeOrientation: CameraChromeOrientationController,
        appAttestController: AppAttestRuntimeController
    ) {
        self.startsAutomatically = startsAutomatically
        self.lifecycleCoordinator = lifecycleCoordinator
        self.viewModel = viewModel
        self.routeStore = routeStore
        self.chromeOrientation = chromeOrientation
        self.appAttestController = appAttestController
    }

    func body(content: Content) -> some View {
        content
            .task {
                await lifecycleCoordinator.startCameraIfNeeded(
                    startsAutomatically: startsAutomatically,
                    viewModel: viewModel
                )
            }
            .task {
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
            .onChange(of: appAttestController.isPreparingCredential) { wasPreparing, isPreparing in
                credentialPreparationDidChange(wasPreparing: wasPreparing, isPreparing: isPreparing)
            }
    }

    private func viewDidAppear() {
        lifecycleCoordinator.viewDidAppear(chromeOrientation: chromeOrientation)
    }

    private func viewDidDisappear() {
        lifecycleCoordinator.viewDidDisappear(
            viewModel: viewModel,
            chromeOrientation: chromeOrientation
        )
    }

    private func depthAlbumPresentationDidChange(_ isPresented: Bool) {
        Task {
            await lifecycleCoordinator.depthAlbumPresentationDidChange(
                isPresented: isPresented,
                viewModel: viewModel,
                appAttestController: appAttestController
            )
        }
    }

    private func scenePhaseDidChange(_ phase: ScenePhase) {
        let shouldForceCameraRouteOnForeground = foregroundRouteRestorePolicy(for: phase)
        Task {
            await lifecycleCoordinator.scenePhaseDidChange(
                phase,
                shouldForceCameraRouteOnForeground: shouldForceCameraRouteOnForeground,
                routeStore: routeStore,
                viewModel: viewModel,
                appAttestController: appAttestController
            )
        }
    }

    private func foregroundRouteRestorePolicy(for phase: ScenePhase) -> Bool {
        switch phase {
        case .active:
            defer {
                backgroundedAt = nil
            }
            let elapsedTime = backgroundedAt.map { Date().timeIntervalSince($0) }
            return CaptureLifecycleCoordinator.shouldForceCameraRouteOnForeground(
                isEnabled: forceCameraOnForegroundAfterDelay,
                backgroundElapsedTime: elapsedTime
            )
        case .inactive, .background:
            if backgroundedAt == nil {
                backgroundedAt = Date()
            }
            return false
        @unknown default:
            return false
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
}

extension View {
    func cameraScreenLifecycle(
        startsAutomatically: Bool,
        lifecycleCoordinator: CaptureLifecycleCoordinator,
        viewModel: CameraViewModel,
        routeStore: CameraRouteStore,
        chromeOrientation: CameraChromeOrientationController,
        appAttestController: AppAttestRuntimeController
    ) -> some View {
        modifier(CameraViewLifecycleModifier(
            startsAutomatically: startsAutomatically,
            lifecycleCoordinator: lifecycleCoordinator,
            viewModel: viewModel,
            routeStore: routeStore,
            chromeOrientation: chromeOrientation,
            appAttestController: appAttestController
        ))
    }
}
