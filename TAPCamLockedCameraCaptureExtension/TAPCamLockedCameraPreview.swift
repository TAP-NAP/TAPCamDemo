//
//  TAPCamLockedCameraPreview.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import OSLog
import SwiftUI
import UIKit

struct TAPCamLockedCameraPreview: UIViewRepresentable {
    private let source: any TAPCamLockedCameraPreviewSource

    init(source: any TAPCamLockedCameraPreviewSource) {
        self.source = source
    }

    func makeUIView(context: Context) -> TAPCamLockedCameraPreviewView {
        let preview = TAPCamLockedCameraPreviewView()
        source.connect(to: preview)
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Preview")
            .info("r1_preview_make")
        return preview
    }

    func updateUIView(_ previewView: TAPCamLockedCameraPreviewView, context: Context) {}
}

final class TAPCamLockedCameraPreviewView: UIView, TAPCamLockedCameraPreviewTarget {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated func setSession(_ session: AVCaptureSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            previewLayer.session = session
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Preview")
                .info("r1_preview_session_connected")
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Preview")
            .info(
                "r1_preview_window attached=\(self.window != nil) sessionAttached=\(self.previewLayer.session != nil)"
            )
    }

    deinit {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1Preview")
            .info("r1_preview_deinit")
    }
}

nonisolated protocol TAPCamLockedCameraPreviewSource: Sendable {
    func connect(to target: any TAPCamLockedCameraPreviewTarget)
}

nonisolated protocol TAPCamLockedCameraPreviewTarget: AnyObject {
    func setSession(_ session: AVCaptureSession)
}

nonisolated final class TAPCamLockedCameraDefaultPreviewSource: TAPCamLockedCameraPreviewSource, @unchecked Sendable {
    private let session: AVCaptureSession

    init(session: AVCaptureSession) {
        self.session = session
    }

    func connect(to target: any TAPCamLockedCameraPreviewTarget) {
        target.setSession(session)
    }
}
