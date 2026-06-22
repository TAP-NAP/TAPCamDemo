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

/// Bottom camera chrome: settings, TAP Library entry, shutter, and camera switch.
///
/// The view receives only presentation fields and action closures. It does not
/// receive App Attest clients, capture IDs, Photos asset IDs, photo bytes,
/// manifests, proofs, pending-store handles, or output profile objects.
struct CameraCaptureControlsView: View {
    let state: CameraCaptureControlsState
    let recentThumbnail: UIImage?
    let onOpenSettings: () -> Void
    let onOpenTAPLibrary: () -> Void
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void

    @State private var isShutterTouchActive = false

    var body: some View {
        VStack(spacing: 10) {
            settingsRow
            bottomControls
        }
    }

    private var settingsRow: some View {
        HStack {
            Spacer()

            Button(action: onOpenSettings) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))

                    Image(systemName: "gearshape")
                        .font(.system(size: 21, weight: .semibold))
                        .rotationEffect(state.contentRotation)
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
                .rotationEffect(state.contentRotation)

            Spacer()

            shutterControl

            Spacer()

            Button(action: onSwitchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .rotationEffect(state.contentRotation)
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
