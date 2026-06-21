//
//  CameraView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

enum CameraFeedbackPreferences {
    static let shutterHapticsEnabledKey = "CameraShutterHapticsEnabled"
    static let defaultShutterHapticsEnabled = true
    static let shutterSoundEnabledKey = "CameraShutterSoundEnabled"
    static let defaultShutterSoundEnabled = true
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
    private let startsAutomatically: Bool
    private let lifecycleCoordinator: CaptureLifecycleCoordinator
    @StateObject private var viewModel: CameraViewModel
    @StateObject private var routeStore: CameraRouteStore
    @StateObject private var chromeOrientation: CameraChromeOrientationController
    @StateObject private var appAttestController: AppAttestRuntimeController
    @State private var isShowingSettings = false
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var isShutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var isShutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled

    init(
        viewModel: CameraViewModel? = nil,
        routeStore: CameraRouteStore? = nil,
        appAttestController: AppAttestRuntimeController? = nil,
        lifecycleCoordinator: CaptureLifecycleCoordinator = CaptureLifecycleCoordinator(),
        startsAutomatically: Bool = true
    ) {
        self.startsAutomatically = startsAutomatically
        self.lifecycleCoordinator = lifecycleCoordinator
        if let viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            _viewModel = StateObject(wrappedValue: CameraViewModel())
        }
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
        NavigationStack {
            cameraSurface
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: depthAlbumPresentedBinding) {
                    DepthAlbumPickerView(routeStore: routeStore)
                        .toolbar(.visible, for: .navigationBar)
                }
        }
        .sheet(isPresented: $isShowingSettings) {
            DepthAnalyzerSettingsView(
                appAttestController: appAttestController,
                shutterSoundSuppressionSupported: viewModel.isShutterSoundSuppressionSupported
            )
        }
        .cameraScreenLifecycle(
            startsAutomatically: startsAutomatically,
            lifecycleCoordinator: lifecycleCoordinator,
            viewModel: viewModel,
            routeStore: routeStore,
            chromeOrientation: chromeOrientation,
            appAttestController: appAttestController
        )
    }

    private var cameraSurface: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                cameraPreviewStage
                Spacer(minLength: 8)
                CameraCaptureControlsView(
                    state: CameraCaptureControlsState(
                        isShutterEnabled: viewModel.canCapture,
                        isLibraryWriteInProgress: viewModel.isCaptureWriteInProgress,
                        contentRotation: chromeOrientation.angle
                    ),
                    recentThumbnail: viewModel.recentThumbnail,
                    onOpenSettings: {
                        isShowingSettings = true
                    },
                    onOpenTAPLibrary: openTAPLibrary,
                    onCapture: triggerShutter,
                    onSwitchCamera: switchCameraPosition
                )
            }
        }
    }

    private var depthAlbumPresentedBinding: Binding<Bool> {
        Binding(
            get: { routeStore.isDepthAlbumPresented },
            set: { routeStore.setDepthAlbumPresented($0) }
        )
    }

    private var cameraPreviewStage: some View {
        #if DEBUG
        CameraPreviewStageView(
            session: viewModel.session,
            state: previewStageState,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption,
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
                isSliderEnabled: viewModel.debugZoomSliderEnabled
            ),
            onSelectDebugDepthOption: selectDebugDepthDisplayOption,
            onSelectDebugZoomOption: selectDebugZoomDisplayOption,
            onSelectDebugZoomFactor: selectDebugZoomFactor
        )
        #else
        CameraPreviewStageView(
            session: viewModel.session,
            state: previewStageState,
            onPreviewCropChange: viewModel.updatePreviewCropRect,
            onSelectFocalLengthOption: selectFocalLengthDisplayOption
        )
        #endif
    }

    private var previewStageState: CameraPreviewStageState {
        CameraPreviewStageState(
            nativePreviewAspectRatio: viewModel.nativePreviewAspectRatio,
            focalLengthOptions: focalLengthDisplayOptions,
            shouldShowFocalLengthSelector: viewModel.shouldShowFocalLengthSelector,
            contentRotation: chromeOrientation.angle
        )
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
        guard let index = focalLengthOptionIndex(for: option.selectionToken),
              viewModel.focalLengthOptions.indices.contains(index) else {
            return
        }
        let sourceOption = viewModel.focalLengthOptions[index]
        Task {
            await viewModel.selectFocalLengthOption(sourceOption)
        }
    }

    private func focalLengthOptionIndex(for token: String) -> Int? {
        guard token.hasPrefix("fov-") else {
            return nil
        }
        return Int(token.dropFirst(4))
    }

    private func triggerShutter() {
        guard viewModel.canCapture else {
            return
        }

        performShutterHaptic()
        let pendingCaptureWorkerClient = appAttestController.runtime.client
        Task {
            await viewModel.capture(
                pendingCaptureWorkerClient: pendingCaptureWorkerClient,
                suppressesShutterSound: !isShutterSoundEnabled
            )
        }
    }

    private func openTAPLibrary() {
        guard !viewModel.isCaptureWriteInProgress else {
            return
        }

        viewModel.pauseForAnalysis()
        routeStore.presentDepthAlbum()
    }

    private func switchCameraPosition() {
        Task { await viewModel.switchCameraPosition() }
    }

    private func performShutterHaptic() {
        guard isShutterHapticsEnabled else {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
