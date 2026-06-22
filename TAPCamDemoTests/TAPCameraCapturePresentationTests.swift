//
//  TAPCameraCapturePresentationTests.swift
//  TAPCamDemoTests
//

import Foundation
import SwiftUI
import Testing
@testable import TAPCamDemo

struct TAPCameraCapturePresentationTests {
    @Test func cameraUISmokeTestAnchorsStayExplicit() throws {
        let appSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift")
        let controlsSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift")
        let overlaySource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewDebugOverlayView.swift")
        let uiTestSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemoUITests/ShutterCaptureSmokeTests.swift")

        #expect(appSource.contains("TAPCAM_UI_TEST_REAL_APP"))
        #expect(controlsSource.contains(#".accessibilityIdentifier("camera.capture.shutter")"#))
        #expect(overlaySource.contains(#".accessibilityIdentifier("camera.capture.status")"#))
        #expect(uiTestSource.contains(#"app.launchEnvironment["TAPCAM_UI_TEST_REAL_APP"] = "1""#))
        #expect(uiTestSource.contains(#"app.buttons["camera.capture.shutter"]"#))
    }

    @Test func captureLifecycleCoordinatorKeepsPendingSigningWarmupAndRetryPoliciesExplicit() {
        #expect(CaptureLifecycleCoordinator.initialCameraActions(startsAutomatically: true) == [.startCamera])
        #expect(CaptureLifecycleCoordinator.initialCameraActions(startsAutomatically: false) == [])

        #expect(CaptureLifecycleCoordinator.launchCredentialActions(startsAutomatically: true) == [
            .warmPendingCaptureSigningCredential,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.launchCredentialActions(startsAutomatically: false) == [
            .retryPendingCaptures
        ])

        #expect(CaptureLifecycleCoordinator.viewDidAppearActions() == [.startChromeOrientation])
        #expect(CaptureLifecycleCoordinator.viewDidDisappearActions() == [
            .stopChromeOrientation,
            .stopCamera
        ])

        #expect(CaptureLifecycleCoordinator.depthAlbumPresentationActions(isPresented: false) == [
            .resumeAfterAnalysis,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.depthAlbumPresentationActions(isPresented: true) == [])

        #expect(CaptureLifecycleCoordinator.scenePhaseActions(for: .active) == [
            .loadRecentTAPLibraryPreview,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.scenePhaseActions(
            for: .active,
            shouldReturnToCameraOnForeground: true
        ) == [
            .restoreCameraRoute,
            .loadRecentTAPLibraryPreview,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.scenePhaseActions(for: .inactive) == [])
        #expect(CaptureLifecycleCoordinator.scenePhaseActions(for: .background) == [])

        #expect(CaptureLifecycleCoordinator.credentialPreparationActions(
            wasPreparing: true,
            isPreparing: false
        ) == [.retryPendingCaptures])
        #expect(CaptureLifecycleCoordinator.credentialPreparationActions(
            wasPreparing: false,
            isPreparing: false
        ) == [])
        #expect(CaptureLifecycleCoordinator.credentialPreparationActions(
            wasPreparing: true,
            isPreparing: true
        ) == [])

        #expect(CaptureLifecycleCoordinator.pendingCaptureRetryActions(isCredentialPreparationActive: false) == [.retryPendingCaptures])
        #expect(CaptureLifecycleCoordinator.pendingCaptureRetryActions(isCredentialPreparationActive: true) == [])

        #expect(!CaptureLifecycleCoordinator.shouldRestoreCamera(for: .active))
        #expect(CaptureLifecycleCoordinator.shouldRestoreCamera(
            for: .active,
            shouldReturnToCameraOnForeground: true
        ))
        #expect(!CaptureLifecycleCoordinator.shouldRestoreCamera(for: .inactive))
        #expect(!CaptureLifecycleCoordinator.shouldRestoreCamera(for: .background))

        #expect(CaptureLifecycleCoordinator.shouldResumeCameraAfterDepthAlbumPresentationChange(isPresented: false))
        #expect(!CaptureLifecycleCoordinator.shouldResumeCameraAfterDepthAlbumPresentationChange(isPresented: true))

        #expect(CaptureLifecycleCoordinator.shouldRetryPendingCaptures(isCredentialPreparationActive: false))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCaptures(isCredentialPreparationActive: true))

        #expect(CaptureLifecycleCoordinator.shouldRetryPendingCapturesAfterCredentialPreparationChange(
            wasPreparing: true,
            isPreparing: false
        ))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCapturesAfterCredentialPreparationChange(
            wasPreparing: false,
            isPreparing: false
        ))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCapturesAfterCredentialPreparationChange(
            wasPreparing: true,
            isPreparing: true
        ))
    }

    @Test func shutterHapticsPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterHapticsEnabled)
        #expect(!CameraFeedbackPreferences.shutterHapticsEnabledKey.isEmpty)
    }

    @Test func shutterSoundPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterSoundEnabled)
        #expect(!CameraFeedbackPreferences.shutterSoundEnabledKey.isEmpty)
    }

    @Test func cameraRouteForegroundPreferenceDefaultsToDisabled() throws {
        let suiteName = "TAPCameraCapturePresentationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(!CameraRoutePreferences.defaultReturnToCameraOnForeground)
        #expect(!CameraRoutePreferences.returnToCameraOnForegroundKey.isEmpty)
        #expect(!CameraRoutePreferences.returnToCameraOnForeground(in: userDefaults))

        userDefaults.set(true, forKey: CameraRoutePreferences.returnToCameraOnForegroundKey)

        #expect(CameraRoutePreferences.returnToCameraOnForeground(in: userDefaults))
    }

    @Test @MainActor func foregroundCameraRouteRestoreRequiresEnabledPreferenceAndPriorInactivePhase() throws {
        let coordinator = CaptureLifecycleCoordinator()

        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: true
        ))
        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .inactive,
            returnsToCameraOnForeground: true
        ))
        #expect(coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: true
        ))

        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .background,
            returnsToCameraOnForeground: false
        ))
        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: false
        ))
    }

    @Test func foregroundCameraRouteRestoreDisablesNavigationAnimation() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift"
        )

        #expect(source.contains("restoreCameraRouteWithoutAnimation"))
        #expect(source.contains("transaction.animation = nil"))
        #expect(source.contains("transaction.disablesAnimations = true"))
        #expect(source.contains("withTransaction(transaction)"))
    }

    @Test func cameraCaptureControlsStateLocksLibraryWhileCaptureWrites() throws {
        let readyState = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: false,
            contentRotation: .zero
        )
        #expect(readyState.canOpenTAPLibrary)
        #expect(readyState.recentThumbnailOpacity == 1)
        #expect(readyState.tapLibraryAccessibilityLabel == "Open TAPCamDepth album")
        #expect(readyState.tapLibraryHelpText == "Open TAPCamDepth album.")

        let writingState = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: true,
            contentRotation: .zero
        )
        #expect(!writingState.canOpenTAPLibrary)
        #expect(writingState.recentThumbnailOpacity == 0.42)
        #expect(writingState.tapLibraryAccessibilityLabel == "Finishing capture write")
        #expect(writingState.tapLibraryHelpText == "TAP Library will be available after the current capture finishes writing.")
    }

    @Test func cameraCaptureControlsStateDoesNotNameSensitiveInputs() throws {
        let state = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: false,
            contentRotation: .zero
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "id",
            "capture",
            "asset",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraPreviewStageStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraPreviewStageState(
            nativePreviewAspectRatio: 3.0 / 4.0,
            focalLengthOptions: [],
            shouldShowFocalLengthSelector: false,
            contentRotation: .zero
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraFocalLengthDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraFocalLengthDisplayOption(
            selectionToken: "fov-0",
            displayName: "24 mm Wide",
            numericLabel: "24",
            unitLabel: "mm",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "camera",
            "device",
            "profile",
            "source",
            "depth",
            "zoom",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    #if DEBUG
    @Test func cameraPreviewDebugStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraPreviewDebugState(
            isDepthReady: true,
            activeCameraDisplayName: "Debug camera",
            statusMessage: "Debug status",
            recentMetrics: [],
            queuedJobCount: 0,
            depthOptions: [],
            showsZoomControl: false,
            zoomOptions: [],
            selectedZoomFactor: 1,
            fovLabel: "24mm",
            sliderRange: 1...1,
            isSliderEnabled: false
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "route",
            "data",
            "session",
            "controller",
            "capability",
            "plan",
            "profile",
            "format",
            "device"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraDebugDepthDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraDebugDepthDisplayOption(
            selectionToken: "debug-depth-0",
            displayName: "Wide",
            iconName: "camera",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "device",
            "profile",
            "source",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "plan"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraDebugZoomDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraDebugZoomDisplayOption(
            selectionToken: "debug-zoom-0",
            displayName: "1x",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "device",
            "profile",
            "source",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "plan"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }
    #endif
}
