//
//  LockedCapturePreviewHost.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AVKit
import OSLog
import SwiftUI
import UIKit

struct LockedCapturePreviewHost: UIViewRepresentable {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    let session: AVCaptureSession
    let onCapture: () -> Void
    let onLayerStateChanged: (_ inWindow: Bool, _ hasSuperlayer: Bool) -> Void

    func makeUIView(context: Context) -> LockedCapturePreviewUIView {
        Self.logger.info("preview_host_make_ui_view")
        let view = LockedCapturePreviewUIView()
        view.configure(
            session: session,
            onCapture: onCapture,
            onLayerStateChanged: onLayerStateChanged
        )
        return view
    }

    func updateUIView(_ uiView: LockedCapturePreviewUIView, context: Context) {
        Self.logger.info("preview_host_update_ui_view")
        uiView.configure(
            session: session,
            onCapture: onCapture,
            onLayerStateChanged: onLayerStateChanged
        )
    }

    static func dismantleUIView(_ uiView: LockedCapturePreviewUIView, coordinator: ()) {
        Self.logger.info("preview_host_dismantle_ui_view")
        uiView.prepareForTeardown()
    }
}

final class LockedCapturePreviewUIView: UIView {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    private var captureEventInteraction: AVCaptureEventInteraction?
    private var onCapture: (() -> Void)?
    private var onLayerStateChanged: ((_ inWindow: Bool, _ hasSuperlayer: Bool) -> Void)?
    private var configuredSessionID: ObjectIdentifier?
    private var lastLoggedBoundsSize: CGSize = .zero

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func configure(
        session: AVCaptureSession,
        onCapture: @escaping () -> Void,
        onLayerStateChanged: @escaping (_ inWindow: Bool, _ hasSuperlayer: Bool) -> Void
    ) {
        let sessionID = ObjectIdentifier(session)
        if configuredSessionID != sessionID {
            Self.logger.info("preview_view_configure_session_changed")
            configuredSessionID = sessionID
        }
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        self.onCapture = onCapture
        self.onLayerStateChanged = onLayerStateChanged

        if captureEventInteraction == nil {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                Self.logger.info("preview_capture_event phase=\(String(describing: event.phase), privacy: .public)")
                guard event.phase == .ended else {
                    return
                }
                self?.onCapture?()
            }
            addInteraction(interaction)
            captureEventInteraction = interaction
            Self.logger.info("preview_capture_event_interaction_installed")
        }

        reportLayerState()
    }

    func prepareForTeardown() {
        Self.logger.info(
            "preview_view_prepare_for_teardown inWindow=\(self.window != nil, privacy: .public) hasSuperlayer=\(self.layer.superlayer != nil, privacy: .public)"
        )
        if let captureEventInteraction {
            removeInteraction(captureEventInteraction)
        }
        captureEventInteraction = nil
        previewLayer.session = nil
        configuredSessionID = nil
        onCapture = nil
        reportLayerState()
        onLayerStateChanged = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportLayerState()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        reportLayerState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLoggedBoundsSize else {
            return
        }
        lastLoggedBoundsSize = bounds.size
        Self.logger.info(
            "preview_view_layout width=\(self.bounds.width, privacy: .public) height=\(self.bounds.height, privacy: .public) inWindow=\(self.window != nil, privacy: .public) hasSuperlayer=\(self.layer.superlayer != nil, privacy: .public)"
        )
    }

    private func reportLayerState() {
        onLayerStateChanged?(window != nil, layer.superlayer != nil)
    }
}
