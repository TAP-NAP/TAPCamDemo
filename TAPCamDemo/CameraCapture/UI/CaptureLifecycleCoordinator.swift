//
//  CaptureLifecycleCoordinator.swift
//  TAPCamDemo
//

import SwiftUI

/// Coordinates camera-screen lifecycle side effects.
///
/// `CameraView` owns layout. `CameraRouteStore` owns navigation state.
/// `CameraViewModel` owns capture/session state. This coordinator owns the
/// policy that decides when scene, route, and pending-capture signing
/// transitions should resume the camera, refresh the TAP Library thumbnail, or
/// retry staged pending captures.
nonisolated final class CaptureLifecycleCoordinator {
    nonisolated enum LifecycleAction: Equatable {
        case startCamera
        case warmPendingCaptureSigningCredential
        case retryPendingCaptures
        case resumeAfterAnalysis
        case restoreCameraRoute
        case loadRecentTAPLibraryPreview
        case startChromeOrientation
        case stopChromeOrientation
        case stopCamera
    }

    nonisolated init() {}

    @MainActor
    func startCameraIfNeeded(
        startsAutomatically: Bool,
        viewModel: CameraViewModel
    ) async {
        for action in Self.initialCameraActions(startsAutomatically: startsAutomatically) {
            switch action {
            case .startCamera:
                await viewModel.start()
            default:
                break
            }
        }
    }

    @MainActor
    func warmPendingCaptureSigningCredentialAndRetryIfNeeded(
        startsAutomatically: Bool,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        for action in Self.launchCredentialActions(startsAutomatically: startsAutomatically) {
            switch action {
            case .warmPendingCaptureSigningCredential:
                await appAttestController.warmPendingCaptureSigningCredential()
            case .retryPendingCaptures:
                await retryPendingCaptures(
                    viewModel: viewModel,
                    appAttestController: appAttestController
                )
            default:
                break
            }
        }
    }

    @MainActor
    func viewDidAppear(chromeOrientation: CameraChromeOrientationController) {
        for action in Self.viewDidAppearActions() where action == .startChromeOrientation {
            chromeOrientation.start()
        }
    }

    @MainActor
    func viewDidDisappear(
        viewModel: CameraViewModel,
        chromeOrientation: CameraChromeOrientationController
    ) {
        for action in Self.viewDidDisappearActions() {
            switch action {
            case .stopChromeOrientation:
                chromeOrientation.stop()
            case .stopCamera:
                viewModel.stop()
            default:
                break
            }
        }
    }

    @MainActor
    func depthAlbumPresentationDidChange(
        isPresented: Bool,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        for action in Self.depthAlbumPresentationActions(isPresented: isPresented) {
            switch action {
            case .resumeAfterAnalysis:
                await viewModel.resumeAfterAnalysis()
            case .retryPendingCaptures:
                await retryPendingCaptures(
                    viewModel: viewModel,
                    appAttestController: appAttestController
                )
            default:
                break
            }
        }
    }

    @MainActor
    func scenePhaseDidChange(
        _ phase: ScenePhase,
        shouldForceCameraRouteOnForeground: Bool,
        routeStore: CameraRouteStore,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        for action in Self.scenePhaseActions(
            for: phase,
            shouldForceCameraRouteOnForeground: shouldForceCameraRouteOnForeground
        ) {
            switch action {
            case .restoreCameraRoute:
                routeStore.restoreCameraOnForeground()
            case .loadRecentTAPLibraryPreview:
                await viewModel.loadRecentTAPLibraryPreviewIfAvailable()
            case .retryPendingCaptures:
                await retryPendingCaptures(
                    viewModel: viewModel,
                    appAttestController: appAttestController
                )
            default:
                break
            }
        }
    }

    @MainActor
    func credentialPreparationDidChange(
        wasPreparing: Bool,
        isPreparing: Bool,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        for action in Self.credentialPreparationActions(
            wasPreparing: wasPreparing,
            isPreparing: isPreparing
        ) where action == .retryPendingCaptures {
            await retryPendingCaptures(
                viewModel: viewModel,
                appAttestController: appAttestController
            )
        }
    }

    @MainActor
    func retryPendingCaptures(
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        guard Self.pendingCaptureRetryActions(
            isCredentialPreparationActive: appAttestController.isPreparingCredential
        ).contains(.retryPendingCaptures) else {
            return
        }

        await viewModel.retryPendingCaptures(
            pendingCaptureWorkerClient: appAttestController.runtime.client
        )
    }

    nonisolated static func initialCameraActions(
        startsAutomatically: Bool
    ) -> [LifecycleAction] {
        startsAutomatically ? [.startCamera] : []
    }

    nonisolated static func launchCredentialActions(
        startsAutomatically: Bool
    ) -> [LifecycleAction] {
        startsAutomatically
            ? [.warmPendingCaptureSigningCredential, .retryPendingCaptures]
            : [.retryPendingCaptures]
    }

    nonisolated static func viewDidAppearActions() -> [LifecycleAction] {
        [.startChromeOrientation]
    }

    nonisolated static func viewDidDisappearActions() -> [LifecycleAction] {
        [.stopChromeOrientation, .stopCamera]
    }

    nonisolated static func depthAlbumPresentationActions(
        isPresented: Bool
    ) -> [LifecycleAction] {
        isPresented ? [] : [.resumeAfterAnalysis, .retryPendingCaptures]
    }

    nonisolated static func scenePhaseActions(
        for phase: ScenePhase,
        shouldForceCameraRouteOnForeground: Bool = false
    ) -> [LifecycleAction] {
        guard phase == .active else {
            return []
        }

        var actions: [LifecycleAction] = []
        if shouldForceCameraRouteOnForeground {
            actions.append(.restoreCameraRoute)
        }
        actions.append(contentsOf: [.loadRecentTAPLibraryPreview, .retryPendingCaptures])
        return actions
    }

    nonisolated static func credentialPreparationActions(
        wasPreparing: Bool,
        isPreparing: Bool
    ) -> [LifecycleAction] {
        wasPreparing && !isPreparing ? [.retryPendingCaptures] : []
    }

    nonisolated static func pendingCaptureRetryActions(
        isCredentialPreparationActive: Bool
    ) -> [LifecycleAction] {
        isCredentialPreparationActive ? [] : [.retryPendingCaptures]
    }

    nonisolated static func shouldForceCameraRouteOnForeground(
        isEnabled: Bool,
        backgroundElapsedTime: TimeInterval?
    ) -> Bool {
        guard isEnabled,
              let backgroundElapsedTime else {
            return false
        }
        return backgroundElapsedTime > CameraRoutePreferences.foregroundCameraReturnDelay
    }

    nonisolated static func shouldRestoreCamera(
        for phase: ScenePhase,
        shouldForceCameraRouteOnForeground: Bool = false
    ) -> Bool {
        scenePhaseActions(
            for: phase,
            shouldForceCameraRouteOnForeground: shouldForceCameraRouteOnForeground
        ).contains(.restoreCameraRoute)
    }

    nonisolated static func shouldResumeCameraAfterDepthAlbumPresentationChange(
        isPresented: Bool
    ) -> Bool {
        depthAlbumPresentationActions(isPresented: isPresented).contains(.resumeAfterAnalysis)
    }

    nonisolated static func shouldRetryPendingCaptures(
        isCredentialPreparationActive: Bool
    ) -> Bool {
        pendingCaptureRetryActions(
            isCredentialPreparationActive: isCredentialPreparationActive
        ).contains(.retryPendingCaptures)
    }

    nonisolated static func shouldRetryPendingCapturesAfterCredentialPreparationChange(
        wasPreparing: Bool,
        isPreparing: Bool
    ) -> Bool {
        credentialPreparationActions(
            wasPreparing: wasPreparing,
            isPreparing: isPreparing
        ).contains(.retryPendingCaptures)
    }
}
