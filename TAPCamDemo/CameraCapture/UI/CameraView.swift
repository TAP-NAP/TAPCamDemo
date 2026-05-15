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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: CameraViewModel
    @StateObject private var chromeOrientation: CameraChromeOrientationController
    @StateObject private var appAttestController: AppAttestRuntimeController
    @State private var isShowingDepthAlbum = false
    @State private var isShowingSettings = false
    @State private var isShutterTouchActive = false
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var isShutterHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled
    @AppStorage(CameraFeedbackPreferences.shutterSoundEnabledKey)
    private var isShutterSoundEnabled = CameraFeedbackPreferences.defaultShutterSoundEnabled
    #if DEBUG
    @State private var isDepthSelectorExpanded = false
    @State private var isPerformanceExpanded = false
    #endif

    init(
        viewModel: CameraViewModel? = nil,
        appAttestController: AppAttestRuntimeController? = nil,
        startsAutomatically: Bool = true
    ) {
        self.startsAutomatically = startsAutomatically
        if let viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            _viewModel = StateObject(wrappedValue: CameraViewModel())
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
                .navigationDestination(isPresented: $isShowingDepthAlbum) {
                    DepthAlbumPickerView()
                        .toolbar(.visible, for: .navigationBar)
                }
        }
        .sheet(isPresented: $isShowingSettings) {
            DepthAnalyzerSettingsView(
                appAttestController: appAttestController,
                shutterSoundSuppressionSupported: viewModel.isShutterSoundSuppressionSupported
            )
        }
        .task {
            guard startsAutomatically else {
                return
            }
            await viewModel.start()
        }
        .task {
            if startsAutomatically {
                await appAttestController.preparePhotoCredentialAfterFirstInstallLaunch()
            }
            await processPendingCaptures()
        }
        .onAppear {
            chromeOrientation.start()
        }
        .onDisappear {
            chromeOrientation.stop()
            viewModel.stop()
        }
        .onChange(of: isShowingDepthAlbum) { _, isPresented in
            guard !isPresented else { return }
            Task {
                await viewModel.resumeAfterAnalysis()
                await processPendingCaptures()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await viewModel.loadRecentTAPLibraryPreviewIfAvailable()
                await processPendingCaptures()
            }
        }
        .onChange(of: appAttestController.isPreparingCredential) { wasPreparing, isPreparing in
            guard wasPreparing, !isPreparing else {
                return
            }

            Task {
                await processPendingCaptures()
            }
        }
    }

    private var cameraSurface: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                previewStage
                Spacer(minLength: 8)
                cameraSettingsRow
                bottomControls
            }
        }
    }

    private var previewStage: some View {
        GeometryReader { proxy in
            let horizontalInset: CGFloat = 8
            let availableWidth = max(0, proxy.size.width - horizontalInset * 2)
            let availableHeight = proxy.size.height
            let nativeAspectRatio = CGFloat(max(0.01, viewModel.nativePreviewAspectRatio))
            let widthFromHeight = availableHeight * nativeAspectRatio
            let previewWidth = min(availableWidth, widthFromHeight)
            let previewHeight = previewWidth / nativeAspectRatio

            CameraPreviewView(
                session: viewModel.session,
                onCropRectChanged: { rect in
                    viewModel.updatePreviewCropRect(CropRectNormalized(metadataRect: rect))
                }
            )
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                viewfinderControls
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            #if DEBUG
            /*
             Debug overlays are instrumentation, not camera chrome. They stay
             pinned to the portrait-locked preview coordinates so rotation does
             not move them or rotate their text while we are inspecting capture
             devices, zoom ranges, and performance state.
             */
            .overlay(alignment: .bottomLeading) {
                depthSelector
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                debugZoomControl
                    .padding(10)
            }
            .overlay(alignment: .top) {
                debugStatusOverlay
                    .padding(10)
            }
            #endif
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewfinderControls: some View {
        ZStack(alignment: .bottom) {
            if viewModel.shouldShowFocalLengthSelector {
                FocalLengthSelectorView(
                    options: viewModel.focalLengthOptions,
                    selectedID: viewModel.activeFocalLengthOptionID,
                    contentRotation: chromeOrientation.angle,
                    select: { option in
                        Task { await viewModel.selectFocalLengthOption(option) }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .bottom)
    }

    #if DEBUG
    private var debugStatusOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isDepthCaptureReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(viewModel.isDepthCaptureReady ? .green : .yellow)

                Text(viewModel.activeCameraDisplayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        isPerformanceExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            Text(viewModel.statusMessage)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.82))

            if isPerformanceExpanded {
                PerformancePanelView(
                    metrics: viewModel.recentMetrics,
                    pendingJobCount: viewModel.pendingJobCount
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 260, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.50), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var depthSelector: some View {
        DebugDepthPanelView(
            options: viewModel.debugDepthDeviceOptions,
            selectedID: viewModel.debugSelectedDepthDeviceID,
            isExpanded: $isDepthSelectorExpanded,
            select: { option in
                Task {
                    await viewModel.selectDebugDepthDevice(option)
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        isDepthSelectorExpanded = false
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var debugZoomControl: some View {
        if viewModel.isDebugDepthOverrideActive,
           viewModel.debugZoomCapability != nil {
            DebugZoomControlView(
                zoomProfiles: viewModel.debugZoomProfiles,
                selectedZoomID: viewModel.debugSelectedZoomID,
                selectedZoomFactor: viewModel.debugSelectedZoomFactor,
                fovLabel: viewModel.debugFOVLabel,
                sliderRange: viewModel.debugZoomSliderRange,
                isSliderEnabled: viewModel.debugZoomSliderEnabled,
                selectZoom: { zoom in
                    Task { await viewModel.selectDebugZoom(zoom) }
                },
                selectZoomFactor: { zoomFactor in
                    Task { await viewModel.selectDebugZoomFactor(zoomFactor) }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
    #endif

    private var cameraSettingsRow: some View {
        HStack {
            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))

                    Image(systemName: "gearshape")
                        .font(.system(size: 21, weight: .semibold))
                        .rotationEffect(chromeOrientation.angle)
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Open camera and analysis settings.")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
    }

    private var bottomControls: some View {
        HStack {
            recentPhotoButton
                .frame(width: 78, height: 78)
                .rotationEffect(chromeOrientation.angle)

            Spacer()

            shutterControl

            Spacer()

            Button {
                Task { await viewModel.switchCameraPosition() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .rotationEffect(chromeOrientation.angle)
            }
            .accessibilityLabel("Switch front and back camera")
            .frame(width: 78, height: 78)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
    }

    private var shutterControl: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 78, height: 78)

            Circle()
                .fill(viewModel.canCapture ? Color.white : Color.gray)
                .frame(width: 62, height: 62)
        }
        .frame(width: 78, height: 78)
        .scaleEffect(isShutterTouchActive && viewModel.canCapture ? 0.96 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isShutterTouchActive else { return }
                    isShutterTouchActive = true
                    triggerShutter()
                }
                .onEnded { _ in
                    isShutterTouchActive = false
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Capture depth photo")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            triggerShutter()
        }
    }

    private func triggerShutter() {
        guard viewModel.canCapture else {
            return
        }

        performShutterHaptic()
        let appAttestClient = appAttestController.runtime.client
        Task {
            await viewModel.capture(
                appAttestClient: appAttestClient,
                suppressesShutterSound: !isShutterSoundEnabled
            )
        }
    }

    private func processPendingCaptures() async {
        guard !appAttestController.isPreparingCredential else {
            return
        }

        await viewModel.processPendingCaptures(appAttestClient: appAttestController.runtime.client)
    }

    private func performShutterHaptic() {
        guard isShutterHapticsEnabled else {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    @ViewBuilder
    private var recentPhotoButton: some View {
        let isCaptureWriteInProgress = viewModel.isCaptureWriteInProgress

        Button {
            guard !isCaptureWriteInProgress else {
                return
            }
            viewModel.pauseForAnalysis()
            isShowingDepthAlbum = true
        } label: {
            ZStack {
                recentPhotoThumbnail
                    .opacity(isCaptureWriteInProgress ? 0.42 : 1)

                if isCaptureWriteInProgress {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.36))
                        .frame(width: 58, height: 58)

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
        }
        .disabled(isCaptureWriteInProgress)
        .accessibilityLabel(isCaptureWriteInProgress ? "Finishing capture write" : "Open TAPCamDepth album")
        .help(isCaptureWriteInProgress ? "TAP Library will be available after the current capture finishes writing." : "Open TAPCamDepth album.")
        .animation(.easeInOut(duration: 0.18), value: isCaptureWriteInProgress)
    }

    @ViewBuilder
    private var recentPhotoThumbnail: some View {
        if let thumbnail = viewModel.recentThumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.80), lineWidth: 1.5)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.48))
                    .frame(width: 58, height: 58)

                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
