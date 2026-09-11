import SwiftUI

/// An independent point-cloud viewfinder with the shared album entry, shutter, camera switch and settings.
/// Entering it does not change the ordinary camera's persisted controls or output bytes.
struct GeekModeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CameraIdleTimerPreferences.keepScreenAwakeKey)
    private var keepScreenAwake = CameraIdleTimerPreferences.defaultKeepScreenAwake
    @StateObject private var capture: GeekModeCaptureController
    @ObservedObject var appAttestController: AppAttestRuntimeController
    @State private var selectedCamera = GeekModeCamera.rear
    @Binding private var isShowingSettings: Bool
    @Binding private var isShowingLibrary: Bool
    let recentLibraryPresentation: RecentLibraryPresentation
    let isEnabled: Bool
    @State private var isExiting = false
    let beforeStart: @MainActor () async -> Void
    let onExit: @MainActor () -> Void

    init(
        capabilities: CapabilityMatrix,
        appAttestController: AppAttestRuntimeController,
        isShowingSettings: Binding<Bool>,
        isShowingLibrary: Binding<Bool>,
        recentLibraryPresentation: RecentLibraryPresentation,
        isEnabled: Bool,
        beforeStart: @escaping @MainActor () async -> Void,
        onExit: @escaping @MainActor () -> Void
    ) {
        _capture = StateObject(wrappedValue: GeekModeCaptureController(capabilities: capabilities))
        self.appAttestController = appAttestController
        _isShowingSettings = isShowingSettings
        _isShowingLibrary = isShowingLibrary
        self.recentLibraryPresentation = recentLibraryPresentation
        self.isEnabled = isEnabled
        self.beforeStart = beforeStart
        self.onExit = onExit
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("geek.settings")
                .disabled(capture.isCapturing || isExiting)
            }
            .padding(.horizontal, 12)

            ZStack {
                GeekModePointCloudPreview(
                    store: capture.pointCloudStore,
                    frozen: !capture.hasPointCloud || capture.isCapturing || isShowingSettings || isShowingLibrary || scenePhase != .active,
                    sourceID: String(capture.sourceRevision)
                )
                .accessibilityIdentifier("geek.preview")

                if capture.isPreparing || (!capture.hasPointCloud && capture.message == nil) {
                    VStack(spacing: 8) {
                        LibraryMediaLoadingRing(isLoading: true)
                        Text(verbatim: capture.isPreparing ? "Preparing camera…" : "Waiting for depth…")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .allowsHitTesting(false)
                } else if capture.hasPointCloud, !capture.depthAvailable, capture.isReady {
                    Text("Depth unavailable · Last frame held")
                        .font(.callout)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(capture.previewAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottom) {
                if let message = capture.isCapturing ? "Capturing…" : capture.message {
                    HStack(spacing: 8) {
                        if capture.isCapturing {
                            LibraryMediaLoadingRing(isLoading: true)
                        }
                        Text(verbatim: message)
                    }
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("geek.status")
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)

            HStack {
                CameraLibraryButton(
                    recentThumbnail: recentLibraryPresentation.poster?.image,
                    recentLibraryPresentation: recentLibraryPresentation,
                    isWriteInProgress: capture.isCapturing,
                    isEnabled: !capture.isCapturing && !isExiting,
                    thumbnailOpacity: capture.isCapturing ? 0.42 : 1,
                    accessibilityLabel: capture.isCapturing ? "Finishing capture write" : "Open TAPCamDepth album",
                    helpText: capture.isCapturing
                        ? "TAP Library will be available after the current capture finishes writing."
                        : "Open TAPCamDepth album.",
                    onOpen: {
                        capture.suspend()
                        isShowingLibrary = true
                    }
                )
                .frame(width: 78, height: 78)

                Spacer()

                Button {
                    Task { await capture.capture(client: appAttestController.runtime.client) }
                } label: {
                    Circle()
                        .fill(.white)
                        .padding(8)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .frame(width: 78, height: 78)
                        .opacity(capture.canCapture ? 1 : 0.4)
                        .contentShape(Circle())
                }
                .disabled(!capture.canCapture || isExiting)
                .accessibilityLabel("Take photo")
                .accessibilityIdentifier("geek.shutter")

                Spacer()

                Button {
                    capture.suspend()
                    selectedCamera = selectedCamera == .rear ? .front : .rear
                } label: {
                    CenterAnchoredChromeRotation(rotation: .zero, width: 58, height: 58) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 27, weight: .semibold))
                    }
                }
                .frame(width: 78, height: 78)
                .disabled(capture.isPreparing || capture.isCapturing || isExiting || !capture.hasFrontCamera)
                .accessibilityLabel("Switch front and back camera")
                .accessibilityValue(Text(verbatim: selectedCamera.title))
                .accessibilityIdentifier("geek.switch-camera")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .foregroundStyle(.white)
        .background(.black)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, AppLanguage.english.locale)
        .statusBarHidden(true)
        .onChange(of: shouldKeepScreenAwake) { _, value in
            CameraIdleTimerController.setCameraScreenIdleTimerDisabled(value)
        }
        .task(id: sessionRequest) {
            switch sessionRequest {
            case .inactive, .library:
                capture.suspend()
            case .settings:
                capture.pointCloudStream.setFrozen(true)
            case .exit:
                isExiting = true
                await capture.stop()
                guard !Task.isCancelled else { return }
                onExit()
            case .preview(let camera):
                isExiting = false
                await beforeStart()
                guard !Task.isCancelled else { return }
                CameraIdleTimerController.setCameraScreenIdleTimerDisabled(shouldKeepScreenAwake)
                capture.pointCloudStream.setFrozen(false)
                // Re-read capture preferences after closing the shared Settings page.
                await capture.prepare(camera)
            }
        }
        .onDisappear {
            CameraIdleTimerController.setCameraScreenIdleTimerDisabled(false)
            capture.suspend()
        }
    }

    private var shouldKeepScreenAwake: Bool {
        CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: keepScreenAwake, isCameraViewVisible: true,
            isActiveScene: scenePhase == .active,
            isSettingsPresented: isShowingSettings, isLibraryPresented: isShowingLibrary
        )
    }

    private enum SessionRequest: Hashable {
        case inactive, settings, library, exit
        case preview(GeekModeCamera)
    }

    private var sessionRequest: SessionRequest {
        guard scenePhase == .active else { return .inactive }
        if isShowingLibrary { return .library }
        if isShowingSettings { return .settings }
        if !isEnabled { return .exit }
        return .preview(selectedCamera)
    }
}
