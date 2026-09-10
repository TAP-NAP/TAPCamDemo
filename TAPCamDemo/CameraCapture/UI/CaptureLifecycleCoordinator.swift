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
        resumeAfterAnalysis: () async -> Void,
        prepareVideoMode: () async -> Bool,
        isCameraReady: () -> Bool,
        retryPendingCaptures: @escaping @MainActor () async -> Void
    ) async -> LibraryReturnResult {
        guard !isPresented else { return .notApplicable }
        await resumeAfterAnalysis()
        let result: LibraryReturnResult
        if preparesVideoMode {
            result = await prepareVideoMode() ? .videoReady : .failed
        } else {
            result = isCameraReady() ? .cameraReady : .failed
        }
        // Recovery must not hold the viewfinder transition on network work.
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            await retryPendingCaptures()
        }
        return result
    }

    @MainActor
    func scenePhaseDidChange(
        _ phase: ScenePhase,
        shouldReturnToCameraOnForeground: Bool,
        routeStore: CameraRouteStore,
        refreshLibraryPreview: () -> Void,
        retryPendingCaptures: () async -> Void
    ) async {
        guard phase == .active else { return }
        if shouldReturnToCameraOnForeground {
            restoreCameraRouteWithoutAnimation(routeStore: routeStore)
        }
        refreshLibraryPreview()
        await retryPendingCaptures()
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
        retryPendingCaptures: () async -> Void
    ) async {
        guard wasPreparing && !isPreparing else { return }
        await retryPendingCaptures()
    }

    @MainActor
    func retryPendingCaptures(
        viewModel: CameraViewModel,
        appAttestController: AppAttestRuntimeController
    ) async {
        let isCameraBusy = viewModel.isBusyForNonCaptureStartupWork
        guard Self.shouldRetryPendingCaptures(
            isCredentialPreparationActive: appAttestController.isPreparingCredential,
            isCameraBusy: isCameraBusy
        ) else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("retryPendingCaptures skipped credentialPreparing=\(appAttestController.isPreparingCredential, privacy: .public) cameraBusy=\(isCameraBusy, privacy: .public) configuring=\(viewModel.isConfiguringSession, privacy: .public) recording=\(viewModel.isVideoRecording, privacy: .public) paused=\(viewModel.isPausedForAnalysis, privacy: .public)")
            #endif
            return
        }

        await viewModel.retryPendingCaptures(
            pendingCaptureWorkerClient: appAttestController.runtime.client
        )
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

    nonisolated static func shouldRetryPendingCaptures(
        isCredentialPreparationActive: Bool,
        isCameraBusy: Bool = false
    ) -> Bool {
        !isCredentialPreparationActive && !isCameraBusy
    }
}
