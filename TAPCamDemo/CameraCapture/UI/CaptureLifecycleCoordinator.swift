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

    private static let sceneLogger = Logger(
        subsystem: "TAP-NAP.TAPCamDemo",
        category: "MainCameraSceneLifecycle"
    )

    nonisolated enum LifecycleAction: Equatable, Sendable {
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

    nonisolated struct SceneTransition: Sendable {
        let generation: Int
        let transitionID: String
        let phaseLabel: String
        let actions: [LifecycleAction]
    }

    private var didLeaveActiveScene = false
    private var cameraSceneTransitionGeneration = 0
    private var cameraRequiresRestart = false

    nonisolated init() {}

    @MainActor
    func startCameraIfNeeded(
        startsAutomatically: Bool,
        viewModel: CameraViewModel
    ) async {
        for action in Self.initialCameraActions(startsAutomatically: startsAutomatically) {
            switch action {
            case .startCamera:
                await viewModel.restartAfterSceneTransition()
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
        cameraSceneTransitionGeneration += 1
        cameraRequiresRestart = false
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
    func prepareSceneTransition(
        _ phase: ScenePhase,
        startsAutomatically: Bool,
        shouldReturnToCameraOnForeground: Bool
    ) -> SceneTransition {
        cameraSceneTransitionGeneration += 1
        let generation = cameraSceneTransitionGeneration
        let transitionID = UUID().uuidString
        let phaseLabel = Self.label(for: phase)
        let shouldResumeCamera: Bool

        if phase == .active {
            shouldResumeCamera = startsAutomatically && cameraRequiresRestart
            cameraRequiresRestart = false
        } else {
            cameraRequiresRestart = startsAutomatically
            shouldResumeCamera = false
        }

        Self.sceneLogger.notice(
            "r4d_scene_transition_received transitionID=\(transitionID, privacy: .public) phase=\(phaseLabel, privacy: .public) generation=\(generation, privacy: .public) shouldResumeCamera=\(shouldResumeCamera, privacy: .public)"
        )

        return SceneTransition(
            generation: generation,
            transitionID: transitionID,
            phaseLabel: phaseLabel,
            actions: Self.scenePhaseActions(
                for: phase,
                shouldReturnToCameraOnForeground: shouldReturnToCameraOnForeground,
                shouldResumeCamera: shouldResumeCamera
            )
        )
    }

    @MainActor
    func performSceneTransition(
        _ transition: SceneTransition,
        routeStore: CameraRouteStore,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        for action in transition.actions {
            let generation = transition.generation
            let transitionID = transition.transitionID
            let phaseLabel = transition.phaseLabel

            guard generation == cameraSceneTransitionGeneration else {
                logSupersededTransition(
                    transitionID: transitionID,
                    phaseLabel: phaseLabel,
                    generation: generation,
                    stage: "beforeAction"
                )
                return
            }

            switch action {
            case .startCamera:
                Self.sceneLogger.notice(
                    "r4d_scene_camera_restart_begin transitionID=\(transitionID, privacy: .public) phase=\(phaseLabel, privacy: .public) session=\(viewModel.sessionController.sessionDiagnosticID, privacy: .public) running=\(viewModel.sessionController.isSessionRunning, privacy: .public)"
                )
                await viewModel.restartAfterSceneTransition()
                let isCurrentTransition = generation == cameraSceneTransitionGeneration
                Self.sceneLogger.notice(
                    "r4d_scene_camera_restart_finish transitionID=\(transitionID, privacy: .public) phase=\(phaseLabel, privacy: .public) session=\(viewModel.sessionController.sessionDiagnosticID, privacy: .public) running=\(viewModel.sessionController.isSessionRunning, privacy: .public) current=\(isCurrentTransition, privacy: .public)"
                )
                guard isCurrentTransition else {
                    logSupersededTransition(
                        transitionID: transitionID,
                        phaseLabel: phaseLabel,
                        generation: generation,
                        stage: "afterStart"
                    )
                    return
                }
            case .restoreCameraRoute:
                restoreCameraRouteWithoutAnimation(routeStore: routeStore)
            case .loadRecentTAPLibraryPreview:
                viewModel.scheduleRecentTAPLibraryPreviewRefresh()
            case .retryPendingCaptures:
                await retryPendingCaptures(
                    viewModel: viewModel,
                    appAttestController: appAttestController
                )
            case .stopCamera:
                await viewModel.stopActiveVideoRecordingForLifecycleIfNeeded(
                    pendingCaptureWorkerClient: nil
                )
                guard generation == cameraSceneTransitionGeneration else {
                    logSupersededTransition(
                        transitionID: transitionID,
                        phaseLabel: phaseLabel,
                        generation: generation,
                        stage: "beforeStop"
                    )
                    return
                }
                await viewModel.stopForSceneTransition(
                    transitionID: transitionID,
                    phaseLabel: phaseLabel
                )
            default:
                break
            }
        }
    }

    private func logSupersededTransition(
        transitionID: String,
        phaseLabel: String,
        generation: Int,
        stage: String
    ) {
        Self.sceneLogger.notice(
            "r4d_scene_transition_superseded transitionID=\(transitionID, privacy: .public) phase=\(phaseLabel, privacy: .public) generation=\(generation, privacy: .public) currentGeneration=\(self.cameraSceneTransitionGeneration, privacy: .public) stage=\(stage, privacy: .public)"
        )
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
        shouldReturnToCameraOnForeground: Bool = false,
        shouldResumeCamera: Bool = false
    ) -> [LifecycleAction] {
        guard phase == .active else {
            return [.stopCamera]
        }

        var actions: [LifecycleAction] = []
        if shouldReturnToCameraOnForeground {
            actions.append(.restoreCameraRoute)
        }
        if shouldResumeCamera {
            actions.append(.startCamera)
        }
        actions.append(contentsOf: [.loadRecentTAPLibraryPreview, .retryPendingCaptures])
        return actions
    }

    nonisolated private static func label(for phase: ScenePhase) -> String {
        switch phase {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
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
