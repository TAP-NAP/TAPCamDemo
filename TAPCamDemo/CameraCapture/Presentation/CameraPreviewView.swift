//
//  CameraPreviewView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import UIKit
import SwiftUI

/// A tiny SwiftUI bridge around `AVCaptureVideoPreviewLayer`.
///
/// The preview layer is deliberately kept separate from the capture pipeline:
/// it renders whatever `AVCaptureSession` is attached to it, but it never owns
/// session configuration, photo output, or metadata decisions. Keeping that
/// boundary clear makes the data pipeline easier to audit: session mutation
/// lives in `CaptureSessionController`, packaging in `EmbeddedPhotoPackager`,
/// and persistence in `PhotoLibraryCaptureArtifactWriter`.
///
/// The view also reports the normalized metadata rectangle for the currently
/// visible preview bounds. This records "what the user saw" for downstream
/// readers without destructively cropping the image or depth map.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onCropRectChanged: (CGRect) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCropRectChanged: onCropRectChanged)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.cropRectPublisher = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onCropRectChanged = onCropRectChanged
        uiView.videoPreviewLayer.session = session
        uiView.cropRectPublisher = context.coordinator
        uiView.publishCurrentCropRect()
    }

    /// Defers preview-crop metadata publication out of SwiftUI's update pass.
    ///
    /// `UIViewRepresentable.updateUIView` and `UIView.layoutSubviews` can be called
    /// while SwiftUI is reconciling the view tree. Calling back into
    /// `CameraViewModel` synchronously from those methods mutates `@Published`
    /// state during a view update, which triggers SwiftUI's
    /// "Publishing changes from within view updates" warning. The coordinator
    /// coalesces repeated layout callbacks and publishes the most recent rect on
    /// the next main-run-loop turn, preserving crop metadata without fighting the
    /// renderer.
    final class Coordinator {
        var onCropRectChanged: (CGRect) -> Void

        private var lastPublishedRect: CGRect?
        private var pendingRect: CGRect?
        private var isPublishScheduled = false

        init(onCropRectChanged: @escaping (CGRect) -> Void) {
            self.onCropRectChanged = onCropRectChanged
        }

        func enqueueCropRect(_ rect: CGRect) {
            guard shouldPublish(rect) else { return }

            pendingRect = rect
            guard !isPublishScheduled else { return }

            isPublishScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isPublishScheduled = false

                guard let rect = self.pendingRect else { return }
                self.pendingRect = nil

                guard self.shouldPublish(rect) else { return }
                self.lastPublishedRect = rect
                FOVDiagnostics.logPreviewCropRect(rect)
                self.onCropRectChanged(rect)
            }
        }

        private func shouldPublish(_ rect: CGRect) -> Bool {
            guard let lastPublishedRect else { return true }

            let epsilon: CGFloat = 0.0001
            return abs(lastPublishedRect.origin.x - rect.origin.x) > epsilon
                || abs(lastPublishedRect.origin.y - rect.origin.y) > epsilon
                || abs(lastPublishedRect.size.width - rect.size.width) > epsilon
                || abs(lastPublishedRect.size.height - rect.size.height) > epsilon
        }
    }
}

final class PreviewView: UIView {
    weak var cropRectPublisher: CameraPreviewView.Coordinator?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishCurrentCropRect()
    }

    func publishCurrentCropRect() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rect = videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: bounds)
        cropRectPublisher?.enqueueCropRect(rect)
    }
}
