//
//  TAPLockedCameraSessionContentTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing

@Suite("Locked camera R4G source contract")
struct TAPLockedCameraR4GSourceContractTests {
    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func captureExtensionUsesTheXcodeTemplateCameraHost() throws {
        let extensionSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraCaptureExtension.swift"
        )
        let templateSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraR4GTemplateHost.swift"
        )

        #expect(extensionSource.contains("LockedCameraCaptureUIScene"))
        #expect(extensionSource.contains("LockedCameraCaptureUIScene { session in"))
        #expect(extensionSource.contains("TAPCamLockedCameraR4GTemplateHost(session: session)"))
        #expect(extensionSource.contains("r4g_capture_extension_init"))
        #expect(!extensionSource.contains("TAPCamLockedCameraModel"))
        #expect(!extensionSource.contains("TAPCamLockedCameraViewFinder"))
        #expect(!extensionSource.contains("sessionContentURL"))
        #expect(!extensionSource.contains("camera.start()"))

        #expect(templateSource.contains("UIViewControllerRepresentable"))
        #expect(templateSource.contains("UIImagePickerController"))
        #expect(templateSource.contains("imagePicker.sourceType = .camera"))
        #expect(templateSource.contains("UTType.image.identifier"))
        #expect(templateSource.contains("UTType.movie.identifier"))
        #expect(templateSource.contains("imagePicker.cameraDevice = .rear"))
        #expect(templateSource.contains("TAPCamLockedCameraOpenControl(session: session)"))
        #expect(templateSource.contains("r4g_template_root_appear"))
        #expect(templateSource.contains("r4g_template_root_disappear"))
        #expect(templateSource.contains("r4g_image_picker_dismantle"))
        #expect(!templateSource.contains("AVCaptureSession"))
        #expect(!templateSource.contains("AVCapturePhotoOutput"))
        #expect(!templateSource.contains("sessionContentURL"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func templateHostKeepsOpenAsItsOnlyCustomAction() throws {
        let extensionSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraCaptureExtension.swift"
        )
        let templateSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraR4GTemplateHost.swift"
        )
        let openControlSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraOpenControl.swift"
        )
        let activeSource = [extensionSource, templateSource, openControlSource]
            .joined(separator: "\n")

        #expect(templateSource.contains("TAPCamLockedCameraOpenControl(session: session)"))
        #expect(openControlSource.contains("TAPCamLockedCameraOpenActivity.makeTapLibraryActivity()"))
        #expect(openControlSource.contains("session.openApplication(for: activity)"))
        #expect(openControlSource.contains("r4_open_tap_received"))
        #expect(openControlSource.contains("r4_open_request_begin"))
        #expect(openControlSource.contains("r4_open_request_accepted"))
        #expect(openControlSource.contains("r4_open_request_failed"))
        #expect(!openControlSource.contains("captureDepthPhoto"))
        #expect(!openControlSource.contains("sessionContentURL"))
        #expect(!openControlSource.contains("stopRunning"))
        #expect(!openControlSource.contains("invalidateSessionContent"))
        #expect(!openControlSource.contains("Task.sleep"))
        let openApplicationCallCount = activeSource
            .components(separatedBy: "openApplication(for:")
            .count - 1
        #expect(openApplicationCallCount == 1)
        #expect(!activeSource.contains("LockedCameraCaptureManager"))
        #expect(!activeSource.contains("URLSession"))
        #expect(!activeSource.contains("scenePhase"))
        #expect(!activeSource.contains("stopRunning"))
        #expect(!activeSource.contains("sessionContentURL"))
        #expect(!activeSource.contains("captureDepthPhoto"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func controlAndIntentMetadataRemainAtThePassedR0Baseline() throws {
        let controlSource = try source(
            "TAPCamLockedCameraControlExtension/TAPCamLockedCameraControlExtension.swift"
        )
        let intentSource = try source(
            "TAPCamLockedCameraIntents/TAPCamLockedCameraIntent.swift"
        )

        let configurationCount = controlSource
            .components(separatedBy: "StaticControlConfiguration")
            .count - 1

        #expect(configurationCount == 1)
        #expect(controlSource.contains("TAP-NAP.TAPCamDemo.locked-camera.r0"))
        #expect(controlSource.contains("ControlWidgetButton(action: TAPCamLockedCameraIntent())"))
        #expect(!controlSource.contains("OpenApp"))
        #expect(!controlSource.contains("open-app"))

        #expect(intentSource.contains("struct TAPCamLockedCameraIntent: CameraCaptureIntent"))
        #expect(!intentSource.contains("OpenIntent"))
        #expect(!intentSource.contains("openAppWhenRun"))
        #expect(!intentSource.contains("typealias AppContext"))
        #expect(!intentSource.contains("authenticationPolicy"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func mainAppKeepsR3ImporterIndependentFromR4CInertLanding() throws {
        let appSource = try source("TAPCamDemo/App/TAPCamDemoApp.swift")
        let importerSource = try source(
            "TAPCamDemo/App/LockedCaptureSessionContentImporter.swift"
        )
        let packagerSource = try source(
            "TAPCamDemo/App/LockedCaptureTAPArtifactPackager.swift"
        )
        let startupSource = try source("TAPCamDemo/App/StartupGateView.swift")
        let activitySource = try source(
            "TAPCamLockedCameraIntents/TAPCamLockedCameraOpenActivity.swift"
        )
        let routerSource = try source(
            "TAPCamDemo/App/LockedCameraOpenActivityRouter.swift"
        )
        let librarySource = try source(
            "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )
        let infoPlistSource = try source("TAPCamDemo-Info.plist")

        #expect(appSource.contains("@StateObject private var lockedCaptureImportRuntime"))
        #expect(appSource.contains("lockedCaptureImportRuntime.start()"))
        #expect(importerSource.contains("for await update in manager.sessionContentUpdates"))
        #expect(importerSource.contains("case .initial(let urls)"))
        #expect(importerSource.contains("case .added(let url)"))
        #expect(importerSource.contains("importSessionContent(at: url"))
        #expect(importerSource.contains("TAPPendingCaptureStore"))
        #expect(importerSource.contains("ingestLockedCapture"))
        #expect(importerSource.contains("invalidateSessionContent"))
        #expect(importerSource.contains("tapCamLockedCaptureImportDidAddPendingCaptures"))
        #expect(importerSource.contains("flatHEICCaptureID"))
        #expect(packagerSource.contains("TAPDepthPhotoFileReader.validateContainer"))
        #expect(packagerSource.contains("TAPDepthPhotoFileReader.depthData"))
        #expect(packagerSource.contains("writeManifest"))
        #expect(packagerSource.contains("TAPProofSlot.locate"))
        #expect(!importerSource.contains("sessionContentURLs"))
        #expect(!importerSource.contains("Task.sleep"))
        #expect(!importerSource.contains("beginDelayingAppearance"))
        #expect(!importerSource.contains("endDelayingAppearance"))
        #expect(!importerSource.contains("lateSessionContentPoll"))
        #expect(!importerSource.contains("waitForInitialSessionContentUpdate"))
        #expect(activitySource.contains("NSUserActivityTypeLockedCameraCapture"))
        #expect(activitySource.contains("TAPCamLockedCameraDestination"))
        #expect(activitySource.contains("tapLibraryDestination"))
        #expect(startupSource.contains("onContinueUserActivity(NSUserActivityTypeLockedCameraCapture)"))
        #expect(startupSource.contains("guard LockedCameraOpenActivityRouter.handle(activity) else"))
        #expect(startupSource.contains("@StateObject private var routeStore = CameraRouteStore()"))
        #expect(startupSource.contains("@State private var isLockedCameraInertLanding = false"))
        #expect(startupSource.contains("isLockedCameraInertLanding = true"))
        #expect(startupSource.contains("LockedCameraOpenDiagnosticLandingView()"))
        #expect(startupSource.contains("locked-camera-r4c-inert-app-landing"))
        #expect(startupSource.contains("CameraView(routeStore: routeStore)"))
        #expect(startupSource.contains("r4c_app_inert_landing_route"))
        #expect(startupSource.contains("r4c_app_inert_host_appear cameraViewCreated=false libraryViewCreated=false photoKitRequested=false"))
        #expect(!startupSource.contains("routeStore.presentDepthAlbum()"))
        #expect(!startupSource.contains("LockedCameraLibraryLandingView"))
        #expect(!startupSource.contains("DepthAlbumPickerView"))
        #expect(!startupSource.contains("NavigationStack"))
        #expect(!startupSource.contains("PHPhotoLibrary"))
        #expect(!startupSource.contains("retryPendingCaptures"))
        #expect(routerSource.contains("TAPCamLockedCameraOpenActivity.requestsTapLibrary"))
        #expect(routerSource.contains("r4_app_activity_received"))
        #expect(routerSource.contains("r4c_app_activity_validated"))
        #expect(!routerSource.contains("TAPCamIntentHandoffStore"))
        #expect(!routerSource.contains("tapCamIntentHandoffDidChange"))
        #expect(!routerSource.contains("NotificationCenter"))
        #expect(!routerSource.contains("LockedCaptureSessionContentImporter"))
        #expect(!routerSource.contains("LockedCameraCaptureManager"))
        #expect(!routerSource.contains("beginDelayingAppearance"))
        #expect(!routerSource.contains("endDelayingAppearance"))
        #expect(!routerSource.contains("Task.sleep"))
        #expect(!startupSource.contains("beginDelayingAppearance"))
        #expect(!librarySource.contains("LockedCaptureSessionContentImportCoordinator"))
        #expect(!startupSource.contains("LockedCameraAppContextPublisher"))
        #expect(!infoPlistSource.contains("CFBundleURLTypes"))
        #expect(!infoPlistSource.contains("tapcamdemo"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func releaseContainingAppUsesR4EMinimalHostAndR4FSingleScene() throws {
        let appSource = try source("TAPCamDemo/App/TAPCamDemoApp.swift")
        let infoPlistSource = try source("TAPCamDemo-Info.plist")

        #expect(appSource.contains("#if !DEBUG"))
        #expect(appSource.contains("LockedCameraR4EMinimalAppHost()"))
        #expect(appSource.contains("r4e_minimal_app_host_appear"))
        #expect(appSource.contains("r4e_minimal_app_activity_received"))
        #expect(appSource.contains("managerStreamStarted=false"))
        #expect(appSource.contains("cameraViewCreated=false"))
        #expect(appSource.contains("onContinueUserActivity(NSUserActivityTypeLockedCameraCapture)"))
        #expect(infoPlistSource.contains("<key>UIApplicationSupportsMultipleScenes</key>\n\t\t<false/>"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func containingAppAwaitsCameraStopWhenItsSceneLeavesActive() throws {
        let lifecycleSource = try source(
            "TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift"
        )
        let viewModelSource = try source(
            "TAPCamDemo/CameraCapture/UI/CameraViewModel.swift"
        )
        let sessionSource = try source(
            "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let cameraViewSource = try source(
            "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let selectionSource = try source(
            "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )

        #expect(lifecycleSource.contains("guard phase == .active else"))
        #expect(lifecycleSource.contains("return [.stopCamera]"))
        #expect(lifecycleSource.contains("cameraSceneTransitionGeneration"))
        #expect(lifecycleSource.contains("func prepareSceneTransition("))
        #expect(lifecycleSource.contains("func performSceneTransition("))
        #expect(lifecycleSource.contains("generation == cameraSceneTransitionGeneration"))
        #expect(lifecycleSource.contains("stage: \"beforeAction\""))
        #expect(lifecycleSource.contains("stage: \"afterStart\""))
        #expect(lifecycleSource.contains("await viewModel.stopForSceneTransition("))
        #expect(lifecycleSource.contains("await viewModel.restartAfterSceneTransition()"))
        #expect(lifecycleSource.contains("r4d_scene_transition_superseded"))
        #expect(viewModelSource.contains("await sessionController.stopAndWait()"))
        #expect(viewModelSource.contains("r4d_main_camera_scene_stop_finish"))
        #expect(viewModelSource.contains("await configureCurrentSelection()"))
        #expect(viewModelSource.contains("await configureDefaultSelection()"))
        #expect(sessionSource.contains("func stopAndWait() async -> CaptureSessionStopSnapshot"))
        #expect(sessionSource.contains("withCheckedContinuation"))
        #expect(sessionSource.contains("session.stopRunning()"))
        #expect(!cameraViewSource.contains("stopActiveVideoRecordingForLifecycleIfNeeded"))
        #expect(selectionSource.contains("r4d_main_camera_stale_config_ignored"))
    }

    private func source(_ relativePath: String) throws -> String {
        try TAPCamDemoTestSourceInspection.source(relativePath: relativePath)
    }
}
