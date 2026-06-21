//
//  CameraPreviewStageView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

@preconcurrency import AVFoundation
import SwiftUI

/// Field-level state for the live preview stage.
///
/// The stage can render an `AVCaptureSession` because it owns the preview layer
/// bridge. It does not receive capture pipelines, writers, pending stores, App
/// Attest clients, camera/depth profiles, raw device identifiers, Photos
/// identifiers, HEIC bytes, manifests, or proofs.
struct CameraPreviewStageState {
    let nativePreviewAspectRatio: Double
    let focalLengthOptions: [CameraFocalLengthDisplayOption]
    let shouldShowFocalLengthSelector: Bool
    let contentRotation: Angle
}

/// Live camera preview, release FOV selector, and Debug-only instrumentation.
///
/// `CameraView` still owns lifecycle and action orchestration. This view owns
/// only preview-stage layout. Release FOV uses display-only tokens so this view
/// does not receive hardware planning objects.
struct CameraPreviewStageView: View {
    let session: AVCaptureSession
    let state: CameraPreviewStageState
    let onPreviewCropChange: (CropRectNormalized) -> Void
    let onSelectFocalLengthOption: (CameraFocalLengthDisplayOption) -> Void
    #if DEBUG
    let debugState: CameraPreviewDebugState
    let onSelectDebugDepthOption: (CameraDebugDepthDisplayOption) -> Void
    let onSelectDebugZoomOption: (CameraDebugZoomDisplayOption) -> Void
    let onSelectDebugZoomFactor: (Double) -> Void
    #endif

    var body: some View {
        GeometryReader { proxy in
            let previewSize = previewSize(in: proxy.size)

            CameraPreviewView(
                session: session,
                onCropRectChanged: { rect in
                    onPreviewCropChange(CropRectNormalized(metadataRect: rect))
                }
            )
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                viewfinderControls
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            #if DEBUG
            .overlay {
                /*
                 Debug overlays are instrumentation, not camera chrome. They
                 stay pinned to the portrait-locked preview coordinates so
                 rotation does not move them or rotate their text while we are
                 inspecting capture devices, zoom ranges, and performance state.
                 */
                CameraPreviewDebugOverlayView(
                    state: debugState,
                    onSelectDepthOption: onSelectDebugDepthOption,
                    onSelectZoomOption: onSelectDebugZoomOption,
                    onSelectZoomFactor: onSelectDebugZoomFactor
                )
            }
            #endif
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewCornerRadius: CGFloat {
        10
    }

    private func previewSize(in containerSize: CGSize) -> CGSize {
        let horizontalInset: CGFloat = 8
        let availableWidth = max(0, containerSize.width - horizontalInset * 2)
        let availableHeight = containerSize.height
        let nativeAspectRatio = CGFloat(max(0.01, state.nativePreviewAspectRatio))
        let widthFromHeight = availableHeight * nativeAspectRatio
        let previewWidth = min(availableWidth, widthFromHeight)
        let previewHeight = previewWidth / nativeAspectRatio
        return CGSize(width: previewWidth, height: previewHeight)
    }

    private var viewfinderControls: some View {
        ZStack(alignment: .bottom) {
            if state.shouldShowFocalLengthSelector {
                FocalLengthSelectorView(
                    options: state.focalLengthOptions,
                    contentRotation: state.contentRotation,
                    select: onSelectFocalLengthOption
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .bottom)
    }

}
