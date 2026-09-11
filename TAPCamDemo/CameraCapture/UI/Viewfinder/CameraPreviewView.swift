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
/// and persistence in `TAPPendingCaptureArtifactWriter`.
///
/// The view also reports the normalized metadata rectangle for the currently
/// visible preview bounds. This records "what the user saw" for downstream
/// readers without destructively cropping the image or depth map.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let controller: CameraPreviewController?
    let isCameraPathTransitioning: Bool
    let previewReadinessGeneration: Int
    let onCropRectChanged: (CGRect) -> Void
    let onPreviewingChanged: (Bool, Int) -> Void

    init(
        session: AVCaptureSession,
        controller: CameraPreviewController? = nil,
        isCameraPathTransitioning: Bool = false,
        previewReadinessGeneration: Int = 0,
        onCropRectChanged: @escaping (CGRect) -> Void,
        onPreviewingChanged: @escaping (Bool, Int) -> Void = { _, _ in }
    ) {
        self.session = session
        self.controller = controller
        self.isCameraPathTransitioning = isCameraPathTransitioning
        self.previewReadinessGeneration = previewReadinessGeneration
        self.onCropRectChanged = onCropRectChanged
        self.onPreviewingChanged = onPreviewingChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCropRectChanged: onCropRectChanged,
            onPreviewingChanged: onPreviewingChanged
        )
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.isCropPublicationPaused = isCameraPathTransitioning
        view.cropRectPublisher = context.coordinator
        controller?.attach(to: view)
        context.coordinator.attach(to: view.videoPreviewLayer, generation: previewReadinessGeneration)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onCropRectChanged = onCropRectChanged
        context.coordinator.onPreviewingChanged = onPreviewingChanged
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        uiView.isCropPublicationPaused = isCameraPathTransitioning
        uiView.cropRectPublisher = context.coordinator
        controller?.attach(to: uiView)
        context.coordinator.attach(to: uiView.videoPreviewLayer, generation: previewReadinessGeneration)
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
        var onPreviewingChanged: (Bool, Int) -> Void

        private var lastPublishedRect: CGRect?
        private var pendingRect: CGRect?
        private var isPublishScheduled = false
        private weak var observedPreviewLayer: AVCaptureVideoPreviewLayer?
        private var previewingObservation: NSKeyValueObservation?
        private var observedGeneration: Int?

        init(
            onCropRectChanged: @escaping (CGRect) -> Void,
            onPreviewingChanged: @escaping (Bool, Int) -> Void
        ) {
            self.onCropRectChanged = onCropRectChanged
            self.onPreviewingChanged = onPreviewingChanged
        }

        func attach(to previewLayer: AVCaptureVideoPreviewLayer, generation: Int) {
            guard observedPreviewLayer !== previewLayer || observedGeneration != generation else {
                return
            }
            previewingObservation?.invalidate()
            observedPreviewLayer = previewLayer
            observedGeneration = generation
            previewingObservation = previewLayer.observe(\.isPreviewing, options: [.initial, .new]) { [weak self] _, change in
                guard let isPreviewing = change.newValue else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard self?.observedGeneration == generation else { return }
                    self?.onPreviewingChanged(isPreviewing, generation)
                }
            }
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

/// Controls preview presentation and converts touches using its actual layer.
/// `AVCaptureDevice` points of interest use the unrotated sensor space,
/// so a display-space normalization or crop interpolation is not sufficient.
@MainActor
final class CameraPreviewController {
    private weak var previewView: PreviewView?

    fileprivate func attach(to previewView: PreviewView) {
        self.previewView = previewView
    }

    func retainCurrentAppearance() {
        previewView?.retainCurrentAppearance()
    }

    func releaseRetainedAppearance() {
        previewView?.releaseRetainedAppearance()
    }

    func captureDevicePoint(fromLayerPoint point: CGPoint) -> CGPoint? {
        guard let previewView,
              previewView.bounds.width > 0,
              previewView.bounds.height > 0 else {
            return nil
        }

        let converted = previewView.videoPreviewLayer.captureDevicePointConverted(
            fromLayerPoint: point
        )
        guard converted.x.isFinite, converted.y.isFinite else {
            return nil
        }
        return converted
    }
}

final class PreviewView: UIView {
    weak var cropRectPublisher: CameraPreviewView.Coordinator?
    var isCropPublicationPaused = false
    private var transitionSnapshot: UIView?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    // Capture the already-rendered view synchronously, before the session input
    // changes. This is one native snapshot per transition, not a frame pipeline.
    func retainCurrentAppearance() {
        if let transitionSnapshot {
            transitionSnapshot.layer.removeAllAnimations()
            transitionSnapshot.alpha = 1
            return
        }
        guard window != nil, videoPreviewLayer.isPreviewing,
              let snapshot = snapshotView(afterScreenUpdates: false) else { return }
        snapshot.frame = bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        addSubview(snapshot)
        transitionSnapshot = snapshot
    }

    func releaseRetainedAppearance() {
        guard let snapshot = transitionSnapshot else { return }
        UIView.animate(withDuration: CameraViewfinderTransitionPresentation.duration, delay: 0, options: [.curveEaseInOut]) {
            snapshot.alpha = 0
        } completion: { [weak self] finished in
            guard finished else { return }
            snapshot.removeFromSuperview()
            if self?.transitionSnapshot === snapshot {
                self?.transitionSnapshot = nil
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishCurrentCropRect()
    }

    func publishCurrentCropRect() {
        guard !isCropPublicationPaused,
              videoPreviewLayer.isPreviewing,
              videoPreviewLayer.connection != nil,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }
        let rect = videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: bounds)
        cropRectPublisher?.enqueueCropRect(rect)
    }
}
