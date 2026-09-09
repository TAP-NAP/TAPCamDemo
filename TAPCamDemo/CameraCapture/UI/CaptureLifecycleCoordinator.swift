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
        case retryPendingCaptures
        case resumeAfterAnalysis
        case prepareVideoMode
        case restoreCameraRoute
        case loadRecentTAPLibraryPreview
    }

    private var didLeaveActiveScene = false

    nonisolated init() {}

    nonisolated enum LibraryReturnResult: Equatable, Sendable {
        case notApplicable
        case cameraReady
        case videoReady
        case failed
    }

    @MainActor
    func warmPendingCaptureSigningCredentialAndRetryIfNeeded(
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        try? await Task.sleep(nanoseconds: Self.startupCredentialWarmupDelayNanoseconds)
        guard !Task.isCancelled else { return }
        guard !viewModel.isBusyForNonCaptureStartupWork else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("credential warmup skipped cameraBusy=true configuring=\(viewModel.isConfiguringSession, privacy: .public) recording=\(viewModel.isVideoRecording, privacy: .public) paused=\(viewModel.isPausedForAnalysis, privacy: .public)")
            #endif
            return
        }
        await appAttestController.warmPendingCaptureSigningCredential()

        try? await Task.sleep(nanoseconds: Self.startupPendingRetryDelayNanoseconds)
        guard !Task.isCancelled else { return }
        await retryPendingCaptures(
            viewModel: viewModel,
            appAttestController: appAttestController
        )
    }

    @MainActor
    func viewDidAppear(chromeOrientation: CameraChromeOrientationController) {
        chromeOrientation.start()
    }

    @MainActor
    func viewDidDisappear(
        chromeOrientation: CameraChromeOrientationController,
        stopCamera: () -> Void
    ) {
        chromeOrientation.stop()
        stopCamera()
    }

    @MainActor
    func depthAlbumPresentationDidChange(
        isPresented: Bool,
        preparesVideoMode: Bool,
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async -> LibraryReturnResult {
        var didPrepareVideoMode = false
        var shouldRetryPendingCaptures = false
        for action in Self.depthAlbumPresentationActions(
            isPresented: isPresented,
            preparesVideoMode: preparesVideoMode
        ) {
            switch action {
            case .resumeAfterAnalysis:
                await viewModel.resumeAfterAnalysis()
            case .prepareVideoMode:
                didPrepareVideoMode = await viewModel.prepareVideoModeIfNeeded()
            case .retryPendingCaptures:
                shouldRetryPendingCaptures = true
            default:
                break
            }
        }
        guard !isPresented else {
            return .notApplicable
        }
        let result: LibraryReturnResult
        if preparesVideoMode {
            result = didPrepareVideoMode ? .videoReady : .failed
        } else {
            result = viewModel.activeSessionConfiguration == nil
                ? .failed : .cameraReady
        }
        if shouldRetryPendingCaptures {
            // Signing/export recovery is independent of camera graph readiness.
            // Do not keep the viewfinder transition blocked on network-backed
            // pending-capture work after the requested camera path is ready.
            Task { @MainActor [weak self] in
                await self?.retryPendingCaptures(
                    viewModel: viewModel,
                    appAttestController: appAttestController
                )
            }
        }
        return result
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

    nonisolated static func depthAlbumPresentationActions(
        isPresented: Bool,
        preparesVideoMode: Bool = false
    ) -> [LifecycleAction] {
        guard !isPresented else {
            return []
        }
        return preparesVideoMode
            ? [.resumeAfterAnalysis, .prepareVideoMode, .retryPendingCaptures]
            : [.resumeAfterAnalysis, .retryPendingCaptures]
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
