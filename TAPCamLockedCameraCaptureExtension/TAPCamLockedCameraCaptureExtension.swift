//
//  TAPCamLockedCameraCaptureExtension.swift
//  TAPCamDemo
//

import ExtensionKit
import LockedCameraCapture
import OSLog
import SwiftUI

@main
struct TAPCamLockedCameraCaptureExtension: LockedCameraCaptureExtension {
    @State private var camera = TAPCamLockedCameraModel()

    init() {
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR1")
            .info("r1_capture_extension_init")
    }

    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            TAPCamLockedCameraViewFinder(
                camera: camera,
                sessionContentURL: session.sessionContentURL
            )
                .statusBarHidden(true)
                .task {
                    await camera.start()
                }
        }
    }
}
