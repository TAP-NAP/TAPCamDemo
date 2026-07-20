//
//  CameraViewfinderChromeView.swift
//  TAPCamDemo
//

import SwiftUI

struct CameraViewfinderChromeState: Equatable {
    let flashMode: CameraFlashControlMode
    let isFlashAvailable: Bool
    let isLivePhotoAvailable: Bool
    let isLivePhotoEnabled: Bool
    #if !TAP_ENABLE_PRO_CAMERA_CONTROLS
    let basicEVState: CameraBasicEVControlState
    #endif
    let contentRotation: Angle
}

struct CameraViewfinderChromeView: View {
    let state: CameraViewfinderChromeState
    let highlightColor: Color
    let topSafeAreaInset: CGFloat
    #if !TAP_ENABLE_PRO_CAMERA_CONTROLS
    let onToggleBasicEV: () -> Void
    #endif
    let onOpenSettings: () -> Void
    let onCycleFlash: () -> Void
    let onToggleLivePhoto: () -> Void

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
            #if !TAP_ENABLE_PRO_CAMERA_CONTROLS
            CameraBasicEVButton(
                state: state.basicEVState,
                highlightColor: highlightColor,
                contentRotation: state.contentRotation,
                onToggle: onToggleBasicEV
            )
            #endif

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
        HStack(spacing: 10) {
            flashButton
            livePhotoButton
                .opacity(state.isLivePhotoAvailable ? 1 : 0)
                .allowsHitTesting(state.isLivePhotoAvailable)
                .accessibilityHidden(!state.isLivePhotoAvailable)
                .animation(.easeInOut(duration: 0.2), value: state.isLivePhotoAvailable)
            Spacer(minLength: 0)
        }
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
        static let bottomPadding: CGFloat = 4
    }
}
