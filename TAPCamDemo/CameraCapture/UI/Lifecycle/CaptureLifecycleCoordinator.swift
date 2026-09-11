//
//  CaptureLifecycleCoordinator.swift
//  TAPCamDemo
//

import Combine
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
    @MainActor @Published private var captureModeChangeTask: Task<Void, Never>?
    @MainActor @Published private var libraryReturnTask: (id: UUID, task: Task<Void, Never>)?

    @MainActor var isChangingCaptureMode: Bool {
        captureModeChangeTask != nil || libraryReturnTask != nil
    }

    nonisolated init() {}

    /// Lock the shutter before publishing the target appearance, then wait for
    /// the actual graph operation. Animation duration never determines readiness.
    @MainActor @discardableResult
    func prepareCaptureMode(
        to mode: CameraCaptureModeOption,
        prepareVideoMode: @escaping @MainActor () async -> Bool,
        restorePhotoMode: @escaping @MainActor () async -> Void,
        completion: @escaping @MainActor (Bool) -> Void,
        settled: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        guard !isChangingCaptureMode else { return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                captureModeChangeTask = nil
                // Presentation cleanup must also run after cancellation, even
                // when SwiftUI coalesces the busy/idle updates into one frame.
                settled()
            }
            let ready: Bool
            switch mode {
            case .photo:
                // The published Photo mode still requires graph cleanup if
                // the view leaves before this task starts.
                await restorePhotoMode()
                ready = true
            case .video:
                guard !Task.isCancelled else { return }
                ready = await prepareVideoMode()
            }
            guard !Task.isCancelled else { return }
            completion(ready)
        }
        captureModeChangeTask = task
        return task
    }

    @MainActor
    func cancelCaptureModeChange() {
        // Keep the gate until any already-started session-queue operation returns.
        captureModeChangeTask?.cancel()
        libraryReturnTask?.task.cancel()
    }

    nonisolated enum LibraryReturnResult: Equatable, Sendable {
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
        cancelCaptureModeChange()
        chromeOrientation.stop()
        stopCamera()
    }

    @MainActor @discardableResult
    func depthAlbumPresentationDidChange(
        isPresented: Bool,
        preparesVideoMode: Bool,
        canResumeCamera: @escaping @MainActor () -> Bool,
        resumeAfterAnalysis: @escaping @MainActor () async -> Void,
        prepareVideoMode: @escaping @MainActor () async -> Bool,
        isCameraReady: @escaping @MainActor () -> Bool,
        retryPendingCaptures: @escaping @MainActor () async -> Void,
        completion: @escaping @MainActor (LibraryReturnResult) -> Void
    ) -> Task<Void, Never>? {
        let previousModeTask = captureModeChangeTask
        let previousReturnTask = libraryReturnTask?.task
        cancelCaptureModeChange()
        guard !isPresented else { return nil }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if libraryReturnTask?.id == id {
                    libraryReturnTask = nil
                }
            }
            // Cancellation retires publication, but already-started graph work
            // must finish before the next return or mode change can begin.
            await previousModeTask?.value
            await previousReturnTask?.value
            guard !Task.isCancelled, canResumeCamera() else { return }
            await resumeAfterAnalysis()
            guard !Task.isCancelled, canResumeCamera() else { return }

            let result: LibraryReturnResult
            if preparesVideoMode {
                let ready = await prepareVideoMode()
                guard !Task.isCancelled, canResumeCamera() else { return }
                result = ready ? .videoReady : .failed
            } else {
                result = isCameraReady() ? .cameraReady : .failed
            }
            completion(result)
            // Recovery must not hold the viewfinder transition on network work.
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                await retryPendingCaptures()
            }
        }
        libraryReturnTask = (id, task)
        return task
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
