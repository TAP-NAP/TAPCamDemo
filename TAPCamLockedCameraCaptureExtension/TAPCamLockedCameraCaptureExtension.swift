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
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4G")
            .notice("r4g_capture_extension_init")
    }

    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            TAPCamLockedCameraR4GTemplateHost(session: session)
        }
    }
}
