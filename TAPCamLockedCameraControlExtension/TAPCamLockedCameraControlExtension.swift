//
//  TAPCamLockedCameraControlExtension.swift
//  TAPCamDemo
//

import AppIntents
import OSLog
import SwiftUI
import WidgetKit

@main
struct TAPCamLockedCameraControlBundle: WidgetBundle {
    var body: some Widget {
        TAPCamLockedCameraControlExtension()
        TAPCamOpenAppControlExtension()
    }
}

struct TAPCamLockedCameraControlExtension: ControlWidget {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    init() {
        Self.logger.info("locked_camera_control_widget_init")
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TAP-NAP.TAPCamDemo.locked-camera") {
            ControlWidgetButton(action: TAPCamLockedCameraIntent()) {
                TAPCamLockedCameraControlLabel()
            }
        }
        .displayName("TAPCam")
        .description("Open TAPCam from the Lock Screen.")
    }
}

private struct TAPCamOpenAppControlExtension: ControlWidget {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    init() {
        Self.logger.info("locked_camera_open_app_control_widget_init")
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TAP-NAP.TAPCamDemo.open-app") {
            ControlWidgetButton(action: TAPCamOpenAppFromLockScreenIntent()) {
                TAPCamOpenAppControlLabel()
            }
        }
        .displayName("Open TAPCam")
        .description("Unlock and open TAPCam without starting locked camera capture.")
    }
}

private struct TAPCamLockedCameraControlLabel: View {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    init() {
        Self.logger.info("locked_camera_control_widget_button_label_init intent=TAPCamLockedCameraIntent")
    }

    var body: some View {
        Label("TAPCam", systemImage: "camera.viewfinder")
    }
}

private struct TAPCamOpenAppControlLabel: View {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    init() {
        Self.logger.info("locked_camera_open_app_control_widget_button_label_init intent=TAPCamOpenAppFromLockScreenIntent")
    }

    var body: some View {
        Label("Open TAPCam", systemImage: "app")
    }
}
