import OSLog
import SwiftUI
import WidgetKit

@main
struct LockedCameraOpenReproControlBundle: WidgetBundle {
    var body: some Widget {
        LockedCameraOpenReproControl()
    }
}

struct LockedCameraOpenReproControl: ControlWidget {
    init() {
        LockedCameraReproDiagnostics.logger(category: "Control")
            .notice("lccr5_control_init pid=\(LockedCameraReproDiagnostics.processID)")
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TAP-NAP.TAPCam.LockedCameraOpenRepro.control") {
            ControlWidgetButton(action: LockedCameraReproIntent()) {
                Label("LCC Repro", systemImage: "camera.viewfinder")
            }
        }
        .displayName("LCC Repro")
        .description("Launch the isolated locked-camera lifecycle reproduction.")
    }
}
