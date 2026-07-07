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
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    init() {
        Self.logger.info("locked_camera_extension_init")
    }

    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCaptureSceneRoot(session: session)
        }
    }
}

private struct LockedCaptureSceneRoot: View {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    let session: LockedCameraCaptureSession

    init(session: LockedCameraCaptureSession) {
        self.session = session
        Self.logger.info(
            "locked_camera_scene_content_invoked contentURL=\(session.sessionContentURL.path, privacy: .private(mask: .hash))"
        )
    }

    var body: some View {
        LockedCaptureRootView(session: session)
    }
}
