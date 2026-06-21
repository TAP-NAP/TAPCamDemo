//
//  TAPCamDemoApp.swift
//  TAPCamDemo
//
//  Created by Harold on 2026/4/24.
//

import SwiftUI
import UIKit

/// Locks the SwiftUI scene in portrait so the camera screen behaves like a
/// camera chrome instead of a normal rotating app page.
///
/// Device rotation is still observed by `CameraChromeOrientationController`.
/// That lets individual controls rotate in place while the preview, shutter
/// rail, and overlay anchors keep their portrait layout positions.
final class TAPCamAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct TAPCamDemoApp: App {
    @UIApplicationDelegateAdaptor(TAPCamAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.isXCTestHost {
                XCTestHostView()
            } else {
                StartupGateView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}

private struct XCTestHostView: View {
    var body: some View {
        Color.black
    }
}

private extension ProcessInfo {
    var isXCTestHost: Bool {
        environment["TAPCAM_XCTEST_HOST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}
