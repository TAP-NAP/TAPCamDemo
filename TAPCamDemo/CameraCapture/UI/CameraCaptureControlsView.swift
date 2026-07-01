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
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    let adjustmentControlState: CameraAdjustmentControlState?
    #else
    let basicEVControlState: CameraBasicEVControlState
    #endif
    let contentRotation: Angle

    var canOpenTAPLibrary: Bool {
        !isLibraryWriteInProgress
    }

    var recentThumbnailOpacity: Double {
        isLibraryWriteInProgress ? 0.42 : 1
    }

    var tapLibraryAccessibilityLabel: String {
        isLibraryWriteInProgress ? "Finishing capture write" : "Open TAPCamDepth album"
    }

    var tapLibraryHelpText: String {
        isLibraryWriteInProgress
            ? "TAP Library will be available after the current capture finishes writing."
            : "Open TAPCamDepth album."
    }
}

/// Bottom camera chrome: TAP Library entry, shutter, camera switch, and mode strip.
///
/// The view receives only presentation fields and action closures. It does not
/// receive App Attest clients, capture IDs, Photos asset IDs, photo bytes,
/// manifests, proofs, pending-store handles, or output profile objects.
struct CameraCaptureControlsView: View {
    let state: CameraCaptureControlsState
    let recentThumbnail: UIImage?
    let onOpenTAPLibrary: () -> Void
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void
    let onSelectMode: (CameraCaptureModeOption) -> Void
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    let onSelectAdjustmentControl: (CameraAdjustmentControl) -> Void
    let onToggleFocusMode: () -> Void
    let onAdjustEV: (Double) -> Void
    let onAdjustISO: (Double) -> Void
    let onAdjustShutterPosition: (Double) -> Void
    let onAdjustLensPosition: (Double) -> Void
    let onBeginAdjustment: (CameraAdjustmentControl) -> Void
    let onEndAdjustment: (CameraAdjustmentControl) -> Void
    #else
    let onAdjustEV: (Double) -> Void
    #endif

    @State private var isShutterTouchActive = false

    var body: some View {
        VStack(spacing: 8) {
            modeSelectorSlot
            #if TAP_ENABLE_PRO_CAMERA_CONTROLS
            lowerToolbar
            #endif
            bottomControls
        }
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private var modeSelectorSlot: some View {
        ZStack {
            #if TAP_ENABLE_PRO_CAMERA_CONTROLS
            if let adjustmentControlState = state.adjustmentControlState,
               adjustmentControlState.activeControl != nil {
                CameraTickedAdjustmentStrip(
                    state: adjustmentControlState,
                    contentRotation: state.contentRotation,
                    onAdjustEV: onAdjustEV,
                    onAdjustISO: onAdjustISO,
                    onAdjustShutterPosition: onAdjustShutterPosition,
                    onAdjustLensPosition: onAdjustLensPosition,
                    onBeginAdjustment: onBeginAdjustment,
                    onEndAdjustment: onEndAdjustment
                )
                .transition(.opacity)
            } else {
                modeStrip
                    .transition(.opacity)
            }
            #else
            if state.basicEVControlState.isStripVisible {
                CameraBasicEVAdjustmentStrip(
                    state: state.basicEVControlState,
                    contentRotation: state.contentRotation,
                    onAdjustEV: onAdjustEV
                )
                .transition(.opacity)
            } else {
                modeStrip
                    .transition(.opacity)
            }
            #endif
        }
        .frame(height: 50)
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        .animation(.easeInOut(duration: 0.16), value: state.adjustmentControlState?.activeControl)
        #else
        .animation(.easeInOut(duration: 0.16), value: state.basicEVControlState.isStripVisible)
        #endif
    }

    private var modeStrip: some View {
        HStack(spacing: 18) {
            ForEach(CameraCaptureModeOption.allCases) { mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .tracking(0)
                        .foregroundStyle(modeForegroundStyle(mode))
                        .frame(minWidth: 48, minHeight: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.isAvailableInStageOne ? "\(mode.title) mode" : "\(mode.title) mode coming soon")
            }
        }
    }

    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @ViewBuilder
    private var lowerToolbar: some View {
        if let adjustmentControlState = state.adjustmentControlState {
            CameraLowerToolbarView(
                state: adjustmentControlState,
                contentRotation: state.contentRotation,
                onSelectControl: onSelectAdjustmentControl,
                onToggleFocusMode: onToggleFocusMode
            )
        } else {
            CameraLowerToolbarPlaceholderView(contentRotation: state.contentRotation)
        }
    }
    #endif

    private func modeForegroundStyle(_ mode: CameraCaptureModeOption) -> Color {
        if mode == state.selectedMode {
            return .white
        }
        return mode.isAvailableInStageOne ? .white.opacity(0.78) : .white.opacity(0.34)
    }

    private var shutterControl: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 78, height: 78)

            Circle()
                .fill(state.isShutterEnabled ? Color.white : Color.gray)
                .frame(width: 62, height: 62)
        }
        .frame(width: 78, height: 78)
        .scaleEffect(isShutterTouchActive && state.isShutterEnabled ? 0.96 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isShutterTouchActive else { return }
                    isShutterTouchActive = true
                    onCapture()
                }
                .onEnded { _ in
                    isShutterTouchActive = false
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Capture depth photo")
        .accessibilityIdentifier("camera.capture.shutter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onCapture()
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

                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
