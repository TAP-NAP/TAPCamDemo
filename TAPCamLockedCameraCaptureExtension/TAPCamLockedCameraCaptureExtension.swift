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
    init() {
        TAPCamLockedCameraDiagnostics.logger().info("r0_capture_extension_init")
    }

    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            TAPCamLockedCameraViewFinder(session: session)
        }
    }
}
