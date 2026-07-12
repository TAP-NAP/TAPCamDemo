//
//  TAPCamLockedCameraControlExtension.swift
//  TAPCamDemo
//

import OSLog
import SwiftUI
import WidgetKit

@main
struct TAPCamLockedCameraControlBundle: WidgetBundle {
    var body: some Widget {
        TAPCamLockedCameraControlExtension()
    }
}

struct TAPCamLockedCameraControlExtension: ControlWidget {
    init() {
        TAPCamLockedCameraDiagnostics.logger().info("r0_control_widget_init")
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TAP-NAP.TAPCamDemo.locked-camera.r0") {
            ControlWidgetButton(action: TAPCamLockedCameraIntent()) {
                Label("TAPCam R0", systemImage: "camera.viewfinder")
            }
        }
        .displayName("TAPCam R0")
        .description("Open the TAPCam lock-screen camera baseline.")
    }
}
