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
/// boundary clear makes the data pipeline easier to audit: every saved byte is
/// produced by `CameraController`, `TAPDepthHEICWriter`, and `PhotoLibraryWriter`.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
