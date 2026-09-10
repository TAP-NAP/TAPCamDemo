//
//  CameraCaptureControlsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI
import UIKit

/// Field-level state for the visible camera controls.
///
/// This value keeps the controls view out of capture, App Attest, Photos, and
/// pending-storage ownership. `CameraView` still owns the action closures.
struct CameraCaptureControlsState {
    let isShutterEnabled: Bool
    let isLibraryWriteInProgress: Bool
    let selectedMode: CameraCaptureModeOption
    let isRecordingMovie: Bool
    let isPreparingMovie: Bool
    let isPhotographerModeActive: Bool
    let isInteractionLocked: Bool
    let adjustmentControlState: CameraAdjustmentControlState?
    let basicEVControlState: CameraBasicEVControlState
    let contentRotation: Angle

    var canOpenTAPLibrary: Bool {
        !isLibraryWriteInProgress && !isRecordingMovie
    }

    var recentThumbnailOpacity: Double {
        isLibraryWriteInProgress ? 0.42 : 1
    }

    var tapLibraryAccessibilityLabel: String {
        if isLibraryWriteInProgress {
            return "Finishing capture write"
        }
        if isRecordingMovie {
            return "TAP Library unavailable during video capture"
        }
        return "Open TAPCamDepth album"
    }

    var tapLibraryHelpText: String {
        if isLibraryWriteInProgress {
            return "TAP Library will be available after the current capture finishes writing."
        }
        if isRecordingMovie {
            return "TAP Library will be available after video capture finishes."
        }
        return "Open TAPCamDepth album."
    }
}

/// Bottom camera chrome: TAP Library entry, shutter, camera switch, and mode strip.
///
/// The view receives only presentation fields and action closures. It does not
/// receive App Attest clients, capture IDs, Photos asset IDs, photo bytes,
/// manifests, proofs, pending-store handles, or output profile objects.
struct CameraCaptureControlsView: View {
    let state: CameraCaptureControlsState
    let highlightColor: Color
    let recentThumbnail: UIImage?
    var recentLibraryPresentation: RecentLibraryPresentation? = nil
    let onOpenTAPLibrary: () -> Void
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void
    let onSelectMode: (CameraCaptureModeOption) -> Void
    let onSelectAdjustmentControl: (CameraAdjustmentControl) -> Void
    let onAdjustEV: (Double) -> Void
    let onAdjustISO: (Double) -> Void
    let onAdjustShutterPosition: (Double) -> Void
    let onAdjustLensPosition: (Double) -> Void
    let onRestoreAutomaticMode: (CameraAdjustmentControl) -> Void
    let onBeginAdjustment: (CameraAdjustmentControl) -> Void
    let onEndAdjustment: (CameraAdjustmentControl) -> Void

    @State private var isShutterTouchActive = false

    var body: some View {
        VStack(spacing: 8) {
            professionalToolbarSlot
            bottomControls
            modeSelectorSlot
        }
        .padding(.bottom, 4)
        .disabled(state.isInteractionLocked)
    }

    private var professionalToolbarSlot: some View {
        lowerToolbar
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.professionalToolbarSlotHeight)
            .opacity(state.isPhotographerModeActive ? 1 : 0)
            .allowsHitTesting(state.isPhotographerModeActive)
            .accessibilityHidden(!state.isPhotographerModeActive)
            .animation(.easeInOut(duration: 0.2), value: state.isPhotographerModeActive)
    }

    private var bottomControls: some View {
        HStack {
            CenterAnchoredChromeRotation(
                rotation: state.contentRotation,
                width: 78,
                height: 78
            ) {
                recentPhotoButton
                    .frame(width: 78, height: 78)
            }

            Spacer()

            shutterControl

            Spacer()

            Button(action: onSwitchCamera) {
                CenterAnchoredChromeRotation(
                    rotation: state.contentRotation,
                    width: 58,
                    height: 58
                ) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 27, weight: .semibold))
                }
            }
            .accessibilityLabel("Switch front and back camera")
            .frame(width: 78, height: 78)
            .disabled(state.isInteractionLocked)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity)
    }

    private var modeSelectorSlot: some View {
        ZStack {
            if state.isPhotographerModeActive,
               let adjustmentControlState = state.adjustmentControlState,
               adjustmentControlState.activeControl != nil {
                CameraTickedAdjustmentStrip(
                    state: adjustmentControlState,
                    highlightColor: highlightColor,
                    contentRotation: state.contentRotation,
                    onAdjustEV: onAdjustEV,
                    onAdjustISO: onAdjustISO,
                    onAdjustShutterPosition: onAdjustShutterPosition,
                    onAdjustLensPosition: onAdjustLensPosition,
                    onRestoreAutomaticMode: onRestoreAutomaticMode,
                    onBeginAdjustment: onBeginAdjustment,
                    onEndAdjustment: onEndAdjustment
                )
                .transition(.opacity)
            } else if !state.isPhotographerModeActive,
                      state.basicEVControlState.isStripVisible {
                CameraBasicEVAdjustmentStrip(
                    state: state.basicEVControlState,
                    highlightColor: highlightColor,
                    contentRotation: state.contentRotation,
                    onAdjustEV: onAdjustEV
                )
                .transition(.opacity)
            } else {
                modeStrip
                    .transition(.opacity)
            }
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.16), value: state.adjustmentControlState?.activeControl)
        .animation(.easeInOut(duration: 0.16), value: state.basicEVControlState.isStripVisible)
        .animation(.easeInOut(duration: 0.16), value: state.isPhotographerModeActive)
    }

    private var modeStrip: some View {
        HStack(spacing: 18) {
            ForEach(CameraCaptureModeOption.allCases) { mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    Text(LocalizedStringKey(mode.title))
                        .font(.caption.weight(.semibold))
                        .tracking(0)
                        .foregroundStyle(modeForegroundStyle(mode))
                        .frame(minWidth: 48, minHeight: 26)
                }
                .buttonStyle(.plain)
                .disabled(state.isInteractionLocked)
                .accessibilityLabel(Text(LocalizedStringKey(mode.accessibilityLabel)))
                .accessibilityIdentifier("camera.mode.\(mode.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var lowerToolbar: some View {
        if let adjustmentControlState = state.adjustmentControlState {
            CameraLowerToolbarView(
                state: adjustmentControlState,
                contentRotation: state.contentRotation,
                onSelectControl: onSelectAdjustmentControl
            )
        } else {
            CameraLowerToolbarPlaceholderView(contentRotation: state.contentRotation)
        }
    }

    private func modeForegroundStyle(_ mode: CameraCaptureModeOption) -> Color {
        if mode == state.selectedMode {
            return .white
        }
        return .white.opacity(0.78)
    }

    private var shutterControl: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 78, height: 78)

            Circle()
                .fill(state.isShutterEnabled ? Color.white : Color.gray)
                .frame(width: 62, height: 62)
                .opacity(state.selectedMode == .video ? 0 : 1)

            if state.selectedMode == .video {
                if state.isPreparingMovie {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                        .frame(width: 58, height: 58)
                } else if state.isRecordingMovie {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 34, height: 34)
                } else {
                    Circle()
                        .fill(state.isShutterEnabled ? Color.red : Color.gray)
                        .frame(width: 58, height: 58)
                }
            }
        }
        .frame(width: 78, height: 78)
        .scaleEffect(isShutterTouchActive && state.isShutterEnabled ? 0.96 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard state.isShutterEnabled,
                          !state.isInteractionLocked,
                          !isShutterTouchActive else { return }
                    isShutterTouchActive = true
                    onCapture()
                }
                .onEnded { _ in
                    isShutterTouchActive = false
                }
        )
        .accessibilityElement()
        .opacity(state.isInteractionLocked ? 0.55 : 1)
        .accessibilityLabel(shutterAccessibilityLabel)
        .accessibilityIdentifier("camera.capture.shutter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onCapture()
        }
    }

    private var shutterAccessibilityLabel: String {
        switch state.selectedMode {
        case .photo:
            return "Capture depth photo"
        case .video:
            if state.isPreparingMovie {
                return "Preparing TAP video"
            }
            return state.isRecordingMovie ? "Stop TAP video recording" : "Start TAP video recording"
        }
    }

    private var recentPhotoButton: some View {
        Button {
            guard state.canOpenTAPLibrary else {
                return
            }
            onOpenTAPLibrary()
        } label: {
            ZStack {
                recentPhotoThumbnail
                    .opacity(state.recentThumbnailOpacity)

                if state.isLibraryWriteInProgress {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.36))
                        .frame(width: 58, height: 58)

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if recentLibraryPresentation?.isLoadingFromICloud == true {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.36))
                        .frame(width: 58, height: 58)

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
        }
        .disabled(!state.canOpenTAPLibrary)
        .accessibilityLabel(state.tapLibraryAccessibilityLabel)
        .help(state.tapLibraryHelpText)
        .animation(.easeInOut(duration: 0.18), value: state.isLibraryWriteInProgress)
    }

    @ViewBuilder
    private var recentPhotoThumbnail: some View {
        if let recentThumbnail {
            Image(uiImage: recentThumbnail)
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

                if recentLibraryPresentation?.showsPlaceholderSymbol ?? true {
                    Image(systemName: recentLibraryPresentation?.kind == .tapVideo ? "video" : "photo.on.rectangle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private enum Metrics {
        static let professionalToolbarSlotHeight: CGFloat = 38
    }
}
