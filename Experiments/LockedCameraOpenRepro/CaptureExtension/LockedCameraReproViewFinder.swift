import LockedCameraCapture
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LockedCameraReproViewFinder: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession
    var sourceType: UIImagePickerController.SourceType = .camera

    init(session: LockedCameraCaptureSession) {
        self.session = session
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        LockedCameraReproDiagnostics.logger(category: "Capture")
            .notice("lccr5_picker_make pid=\(LockedCameraReproDiagnostics.processID) sourceType=camera")

        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = sourceType
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
        LockedCameraReproDiagnostics.logger(category: "Capture")
            .notice("lccr5_picker_dismantle pid=\(LockedCameraReproDiagnostics.processID)")
    }
}
