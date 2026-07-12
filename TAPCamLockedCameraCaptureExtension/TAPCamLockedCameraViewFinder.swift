//
//  TAPCamLockedCameraViewFinder.swift
//  TAPCamDemo
//

import LockedCameraCapture
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TAPCamLockedCameraViewFinder: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession
    var sourceType: UIImagePickerController.SourceType = .camera

    init(session: LockedCameraCaptureSession) {
        self.session = session
        TAPCamLockedCameraDiagnostics.logger().info("r0_viewfinder_init")
    }

    func makeUIViewController(context: Self.Context) -> UIImagePickerController {
        TAPCamLockedCameraDiagnostics.logger().info("r0_viewfinder_make")

        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = sourceType
        imagePicker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        imagePicker.cameraDevice = .rear
        return imagePicker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Self.Context
    ) {}
}
