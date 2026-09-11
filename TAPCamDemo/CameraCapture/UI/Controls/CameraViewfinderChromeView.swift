//
//  CameraViewfinderChromeView.swift
//  TAPCamDemo
//

import SwiftUI

nonisolated enum CameraProModeChromeState: Equatable, Sendable {
    case unavailable
    case standard
    case transitioning
    case active

    var isVisible: Bool {
        self != .unavailable
    }

    var isInteractive: Bool {
        self == .standard || self == .active
    }

    var isTransitioning: Bool {
        self == .transitioning
    }

    var isActive: Bool {
        self == .active
    }

    var accessibilityLabel: String {
        switch self {
        case .unavailable:
            "Pro mode unavailable"
        case .standard:
            "Turn on Pro mode"
        case .transitioning:
            "Switching Pro mode"
        case .active:
            "Turn off Pro mode"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case .standard:
            "Off"
        case .transitioning:
            "Switching"
        case .active:
            "On"
        }
    }
}

struct CameraViewfinderChromeState: Equatable {
    let flashMode: CameraFlashControlMode
    let isFlashAvailable: Bool
    let isLivePhotoAvailable: Bool
    let isLivePhotoEnabled: Bool
    let proModeState: CameraProModeChromeState
    let basicEVState: CameraBasicEVControlState
    let videoRecordingTimecode: CameraVideoRecordingTimecodeState?
    let contentRotation: Angle

    var shouldShowBasicEV: Bool {
        !proModeState.isActive && !proModeState.isTransitioning
    }

    init(
        flashMode: CameraFlashControlMode,
        isFlashAvailable: Bool,
        isLivePhotoAvailable: Bool,
        isLivePhotoEnabled: Bool,
        proModeState: CameraProModeChromeState = .unavailable,
        basicEVState: CameraBasicEVControlState = CameraBasicEVControlState(
            bias: 0,
            isStripVisible: false
        ),
        videoRecordingTimecode: CameraVideoRecordingTimecodeState? = nil,
        contentRotation: Angle
    ) {
        self.flashMode = flashMode
        self.isFlashAvailable = isFlashAvailable
        self.isLivePhotoAvailable = isLivePhotoAvailable
        self.isLivePhotoEnabled = isLivePhotoEnabled
        self.proModeState = proModeState
        self.basicEVState = basicEVState
        self.videoRecordingTimecode = videoRecordingTimecode
        self.contentRotation = contentRotation
    }
}

struct CameraViewfinderChromeView: View {
    let state: CameraViewfinderChromeState
    let highlightColor: Color
    let topSafeAreaInset: CGFloat
    let onToggleBasicEV: () -> Void
    let onOpenSettings: () -> Void
    let onCycleFlash: () -> Void
    let onToggleLivePhoto: () -> Void
    let onToggleProMode: () -> Void

    init(
        state: CameraViewfinderChromeState,
        highlightColor: Color,
        topSafeAreaInset: CGFloat,
        onToggleBasicEV: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void,
        onCycleFlash: @escaping () -> Void,
        onToggleLivePhoto: @escaping () -> Void,
        onToggleProMode: @escaping () -> Void = {}
    ) {
        self.state = state
        self.highlightColor = highlightColor
        self.topSafeAreaInset = topSafeAreaInset
        self.onToggleBasicEV = onToggleBasicEV
        self.onOpenSettings = onOpenSettings
        self.onCycleFlash = onCycleFlash
        self.onToggleLivePhoto = onToggleLivePhoto
        self.onToggleProMode = onToggleProMode
    }

    var body: some View {
        VStack(spacing: 10) {
            shoulderRow
                .frame(height: shoulderHeight, alignment: .bottom)
            topToolbar
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }

    private var shoulderHeight: CGFloat {
        max(topSafeAreaInset, Metrics.minimumShoulderHeight)
    }

    private var shoulderRow: some View {
        HStack(alignment: .center) {
            CameraBasicEVButton(
                state: state.basicEVState,
                highlightColor: highlightColor,
                contentRotation: state.contentRotation,
                onToggle: onToggleBasicEV
            )
            .animation(.easeInOut(duration: 0.2)) { content in
                content.opacity(state.shouldShowBasicEV ? 1 : 0)
            }
            .allowsHitTesting(state.shouldShowBasicEV)
            .accessibilityHidden(!state.shouldShowBasicEV)

            Spacer(minLength: Metrics.dynamicIslandClearance)

            Button(action: onOpenSettings) {
                CenterAnchoredChromeRotation(
                    rotation: state.contentRotation,
                    width: Metrics.viewfinderButtonSize,
                    height: Metrics.viewfinderButtonSize
                ) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                }
                .background(.black.opacity(0.42), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("camera.chrome.settings")
            .help("Open camera and analysis settings.")
        }
    }

    private var topToolbar: some View {
        ZStack {
            HStack(spacing: 10) {
                flashButton
                livePhotoButton
                    .animation(.easeInOut(duration: 0.2)) { content in
                        content.opacity(state.isLivePhotoAvailable ? 1 : 0)
                    }
                    .allowsHitTesting(state.isLivePhotoAvailable)
                    .accessibilityHidden(!state.isLivePhotoAvailable)
                Spacer(minLength: 0)
                proModeButton
            }

            if let videoRecordingTimecode = state.videoRecordingTimecode {
                CenterAnchoredChromeRotation(
                    rotation: state.contentRotation,
                    width: Metrics.timecodeWidth,
                    height: Metrics.viewfinderButtonSize
                ) {
                    CameraVideoRecordingTimecodeView(state: videoRecordingTimecode)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.videoRecordingTimecode != nil)
    }

    private var proModeButton: some View {
        Button(action: onToggleProMode) {
            CenterAnchoredChromeRotation(
                rotation: state.contentRotation,
                width: Metrics.viewfinderButtonSize,
                height: Metrics.viewfinderButtonSize
            ) {
                ZStack {
                    Text("PRO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(state.proModeState.isActive ? highlightColor : .white)
                        .animation(.easeInOut(duration: 0.2)) { content in
                            content.opacity(state.proModeState.isTransitioning ? 0 : 1)
                        }
                    ProgressView()
                        .controlSize(.small)
                        .tint(highlightColor)
                        .animation(.easeInOut(duration: 0.2)) { content in
                            content.opacity(state.proModeState.isTransitioning ? 1 : 0)
                        }
                }
            }
            .background(.black.opacity(0.42), in: Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2)) { content in
            content.opacity(state.proModeState.isVisible ? 1 : 0)
        }
        .allowsHitTesting(state.proModeState.isInteractive)
        .accessibilityHidden(!state.proModeState.isVisible)
        .accessibilityLabel(
            Text(LocalizedStringKey(state.proModeState.accessibilityLabel))
        )
        .accessibilityValue(
            Text(LocalizedStringKey(state.proModeState.accessibilityValue))
        )
        .accessibilityIdentifier("camera.chrome.proMode")
        .help(state.proModeState.isActive ? "Leave Pro mode." : "Use Pro camera controls.")
    }

    private var flashButton: some View {
        Button(action: onCycleFlash) {
            CenterAnchoredChromeRotation(
                rotation: state.contentRotation,
                width: Metrics.viewfinderButtonSize,
                height: Metrics.viewfinderButtonSize
            ) {
                flashButtonIcon
            }
            .background(.black.opacity(0.42), in: Circle())
            .opacity(state.isFlashAvailable ? 1 : 0.36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isFlashAvailable ? "Flash \(state.flashMode.title)" : "Flash unavailable")
        .accessibilityIdentifier("camera.chrome.flash")
        .help("Cycle flash mode.")
    }

    @ViewBuilder
    private var flashButtonIcon: some View {
        switch state.flashMode {
        case .auto:
            Image(systemName: state.flashMode.systemImage)
                .symbolRenderingMode(.palette)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white, highlightColor)
        case .on:
            Image(systemName: state.flashMode.systemImage)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(highlightColor)
        case .off:
            Image(systemName: state.flashMode.systemImage)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var livePhotoButton: some View {
        Button(action: onToggleLivePhoto) {
            CenterAnchoredChromeRotation(
                rotation: state.contentRotation,
                width: Metrics.viewfinderButtonSize,
                height: Metrics.viewfinderButtonSize
            ) {
                Image(systemName: state.isLivePhotoEnabled ? "livephoto" : "livephoto.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(state.isLivePhotoEnabled ? highlightColor : .white)
            }
            .background(.black.opacity(0.42), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isLivePhotoEnabled ? "Live Photo on" : "Live Photo off")
        .accessibilityIdentifier("camera.chrome.livePhoto")
        .help("Toggle Live Photo capture.")
    }

    private enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let minimumShoulderHeight: CGFloat = 44
        static let dynamicIslandClearance: CGFloat = 96
        static let viewfinderButtonSize: CGFloat = 44
        static let timecodeWidth: CGFloat = 132
        static let bottomPadding: CGFloat = 4
    }
}
