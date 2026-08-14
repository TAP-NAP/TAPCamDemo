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
    @AppStorage(AppLanguage.storageKey)
    private var appLanguageRawValue = AppLanguage.defaultValue.rawValue
    @State private var libraryStore: LibraryMediaStore
    private let libraryMediaFetcher: any LibraryMediaFetching
    private let videoPosterBackfillService = LibraryVideoPosterBackfillService.pendingCaptureStore(
        TAPPendingCaptureStore.shared
    )

    init() {
        let photoKitClient = PhotoKitLibraryMediaFetcher()
        self.libraryMediaFetcher = photoKitClient
        _libraryStore = State(
            initialValue: LibraryMediaStore(photoCatalog: photoKitClient)
        )
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let videoFixtureConfiguration = TAPVideoPlaybackFixtureLaunchConfiguration.current {
                TAPVideoPlaybackFixtureHarnessView(configuration: videoFixtureConfiguration)
                    .preferredColorScheme(.dark)
            } else {
                if ProcessInfo.processInfo.isCameraControlsUITestHarness {
                    CameraControlsUITestHarnessView()
                        .preferredColorScheme(.dark)
                } else {
                    standardAppContent
                }
            }
            #else
            standardAppContent
            #endif
        }
        .environment(
            \.locale,
            AppLanguage.resolved(rawValue: appLanguageRawValue).locale
        )
    }

    @ViewBuilder
    private var standardAppContent: some View {
        if ProcessInfo.processInfo.isXCTestHost {
            XCTestHostView()
        } else {
            StartupGateView(
                libraryStore: libraryStore,
                libraryMediaFetcher: libraryMediaFetcher,
                videoPosterBackfillService: videoPosterBackfillService
            )
                .preferredColorScheme(.dark)
        }
    }
}

private struct XCTestHostView: View {
    var body: some View {
        Color.black
    }
}

private extension ProcessInfo {
    #if DEBUG
    var isCameraControlsUITestHarness: Bool {
        environment["TAPCAM_UI_TEST_CAMERA_CONTROLS"] == "1"
            || arguments.contains("--tapcam-camera-controls-ui-test-harness")
    }
    #endif

    var isXCTestHost: Bool {
        guard environment["TAPCAM_UI_TEST_REAL_APP"] != "1" else {
            return false
        }

        return environment["TAPCAM_XCTEST_HOST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}
