//
//  CaptureLifecycleCoordinator.swift
//  TAPCamDemo
//

import Combine
import OSLog
import SwiftUI

/// Coordinates camera-screen lifecycle side effects.
///
/// `CameraView` owns layout. `CameraRouteStore` owns navigation state.
/// `CameraViewModel` owns capture/session state. This coordinator owns the
/// policy that decides when scene, route, and pending-capture signing
/// transitions should resume the camera, refresh the TAP Library thumbnail, or
/// retry staged pending captures.
final class CaptureLifecycleCoordinator: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    nonisolated static let startupCredentialWarmupDelayNanoseconds: UInt64 = 1_500_000_000
    nonisolated static let startupPendingRetryDelayNanoseconds: UInt64 = 1_500_000_000

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

    private var didLeaveActiveScene = false

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
                if startsAutomatically {
                    try? await Task.sleep(nanoseconds: Self.startupCredentialWarmupDelayNanoseconds)
                    guard !Task.isCancelled else {
                        return
                    }
                }
                guard !viewModel.isBusyForNonCaptureStartupWork else {
                    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                    TAPDiagnostics.pendingCapture.info("credential warmup skipped cameraBusy=true configuring=\(viewModel.isConfiguringSession, privacy: .public) recording=\(viewModel.isVideoRecording, privacy: .public) paused=\(viewModel.isPausedForAnalysis, privacy: .public)")
                    #endif
                    return
                }
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

        if startsAutomatically {
            try? await Task.sleep(nanoseconds: Self.startupPendingRetryDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await retryPendingCaptures(
                viewModel: viewModel,
                appAttestController: appAttestController
            )
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
        shouldReturnToCameraOnForeground: Bool,
        routeStore: CameraRouteStore,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        for action in Self.scenePhaseActions(
            for: phase,
            shouldReturnToCameraOnForeground: shouldReturnToCameraOnForeground
        ) {
            switch action {
            case .restoreCameraRoute:
                restoreCameraRouteWithoutAnimation(routeStore: routeStore)
            case .loadRecentTAPLibraryPreview:
                viewModel.scheduleRecentTAPLibraryPreviewRefresh()
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
    private func restoreCameraRouteWithoutAnimation(routeStore: CameraRouteStore) {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            routeStore.restoreCameraOnForeground()
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
        let isCameraBusy = viewModel.isBusyForNonCaptureStartupWork
        guard Self.pendingCaptureRetryActions(
            isCredentialPreparationActive: appAttestController.isPreparingCredential,
            isCameraBusy: isCameraBusy
        ).contains(.retryPendingCaptures) else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("retryPendingCaptures skipped credentialPreparing=\(appAttestController.isPreparingCredential, privacy: .public) cameraBusy=\(isCameraBusy, privacy: .public) configuring=\(viewModel.isConfiguringSession, privacy: .public) recording=\(viewModel.isVideoRecording, privacy: .public) paused=\(viewModel.isPausedForAnalysis, privacy: .public)")
            #endif
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
            ? [.warmPendingCaptureSigningCredential]
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
        shouldReturnToCameraOnForeground: Bool = false
    ) -> [LifecycleAction] {
        guard phase == .active else {
            return []
        }

        var actions: [LifecycleAction] = []
        if shouldReturnToCameraOnForeground {
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
        isCredentialPreparationActive: Bool,
        isCameraBusy: Bool = false
    ) -> [LifecycleAction] {
        isCredentialPreparationActive || isCameraBusy ? [] : [.retryPendingCaptures]
    }

    nonisolated static func shouldRestoreCamera(
        for phase: ScenePhase,
        shouldReturnToCameraOnForeground: Bool = false
    ) -> Bool {
        scenePhaseActions(
            for: phase,
            shouldReturnToCameraOnForeground: shouldReturnToCameraOnForeground
        ).contains(.restoreCameraRoute)
    }

    @MainActor
    func foregroundRouteRestorePolicy(
        for phase: ScenePhase,
        returnsToCameraOnForeground: Bool
    ) -> Bool {
        switch phase {
        case .active:
            defer {
                didLeaveActiveScene = false
            }
            return returnsToCameraOnForeground && didLeaveActiveScene
        case .inactive, .background:
            didLeaveActiveScene = true
            return false
        @unknown default:
            return false
        }
    }

    nonisolated static func shouldResumeCameraAfterDepthAlbumPresentationChange(
        isPresented: Bool
    ) -> Bool {
        depthAlbumPresentationActions(isPresented: isPresented).contains(.resumeAfterAnalysis)
    }

    nonisolated static func shouldRetryPendingCaptures(
        isCredentialPreparationActive: Bool,
        isCameraBusy: Bool = false
    ) -> Bool {
        pendingCaptureRetryActions(
            isCredentialPreparationActive: isCredentialPreparationActive,
            isCameraBusy: isCameraBusy
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
