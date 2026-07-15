//
//  TAPCamLockedCameraR4GTemplateHost.swift
//  TAPCamDemo
//

import LockedCameraCapture
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TAPCamLockedCameraR4GTemplateHost: View {
    let session: LockedCameraCaptureSession

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TAPCamLockedCameraR4GImagePicker()
                .ignoresSafeArea()

            TAPCamLockedCameraOpenControl(session: session)
                .padding(.leading, 24)
                .padding(.bottom, 132)
                .zIndex(1)
        }
        .background(Color.black)
        .accessibilityIdentifier("locked-camera-r4g-template-root")
        .onAppear {
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4G")
                .notice("r4g_template_root_appear")
        }
        .onDisappear {
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4G")
                .notice("r4g_template_root_disappear")
        }
    }
}

private struct TAPCamLockedCameraR4GImagePicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIImagePickerController {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4G")
            .notice("r4g_image_picker_make sourceType=camera")

        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        imagePicker.cameraDevice = .rear
        return imagePicker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: UIImagePickerController,
        coordinator: Void
    ) {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4G")
            .notice("r4g_image_picker_dismantle")
    }
}
