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
    let contentRotation: Angle
}

struct CameraViewfinderChromeView: View {
    let state: CameraViewfinderChromeState
    let topSafeAreaInset: CGFloat
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
                Image(systemName: state.flashMode.systemImage)
                    .font(.system(size: 16, weight: .semibold))
            }
            .background(.black.opacity(0.42), in: Circle())
            .opacity(state.isFlashAvailable ? 1 : 0.36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isFlashAvailable ? "Flash \(state.flashMode.title)" : "Flash unavailable")
        .accessibilityIdentifier("camera.chrome.flash")
        .help("Cycle flash mode.")
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
            }
            .background(.black.opacity(0.42), in: Circle())
            .opacity(state.isLivePhotoAvailable ? 1 : 0.36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(livePhotoAccessibilityLabel)
        .accessibilityIdentifier("camera.chrome.livePhoto")
        .help(state.isLivePhotoAvailable ? "Toggle Live Photo capture." : "Live Photo coming soon.")
    }

    private var livePhotoAccessibilityLabel: String {
        guard state.isLivePhotoAvailable else {
            return "Live Photo coming soon"
        }
        return state.isLivePhotoEnabled ? "Live Photo on" : "Live Photo off"
    }

    private enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let minimumShoulderHeight: CGFloat = 44
        static let dynamicIslandClearance: CGFloat = 96
        static let viewfinderButtonSize: CGFloat = 44
        static let bottomPadding: CGFloat = 4
    }
}
