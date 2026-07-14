//
//  TAPLockedCameraSessionContentTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing

@Suite("Locked camera R4C source contract")
struct TAPLockedCameraR4CSourceContractTests {
    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func captureExtensionOwnsOneLongLivedCameraModel() throws {
        let extensionSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraCaptureExtension.swift"
        )
        let modelSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraModel.swift"
        )
        let serviceSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCaptureService.swift"
        )

        #expect(extensionSource.contains("@State private var camera = TAPCamLockedCameraModel()"))
        #expect(extensionSource.contains("LockedCameraCaptureUIScene"))
        #expect(extensionSource.contains("LockedCameraCaptureUIScene { session in"))
        #expect(extensionSource.contains("TAPCamLockedCameraViewFinder("))
        #expect(extensionSource.contains("session: session"))
        #expect(extensionSource.contains("sessionContentURL: session.sessionContentURL"))
        #expect(extensionSource.contains("await camera.start()"))

        #expect(modelSource.contains("@Observable"))
        #expect(modelSource.contains("final class TAPCamLockedCameraModel"))
        #expect(modelSource.contains("private let captureService: TAPCamLockedCaptureService"))
        #expect(modelSource.contains("case starting"))
        #expect(modelSource.contains("case live"))
        #expect(modelSource.contains("case interrupted"))
        #expect(modelSource.contains("case unavailable"))
        #expect(!modelSource.contains("hasStarted"))

        #expect(serviceSource.contains("actor TAPCamLockedCaptureService"))
        #expect(serviceSource.contains("private let captureSession = AVCaptureSession()"))
        #expect(serviceSource.contains("DispatchSerialQueue"))
        #expect(serviceSource.contains("asUnownedSerialExecutor()"))
        #expect(serviceSource.contains("captureSession.startRunning()"))
        #expect(serviceSource.contains("guard !captureSession.isRunning else"))
        #expect(serviceSource.contains("AVCaptureSession.wasInterruptedNotification"))
        #expect(serviceSource.contains("AVCaptureSession.interruptionEndedNotification"))
        #expect(serviceSource.contains("AVCaptureSession.runtimeErrorNotification"))
        #expect(serviceSource.contains("error?.code == .mediaServicesWereReset"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func photoAndHardwareTriggersAtomicallyStoreFlatDepthHEIC() throws {
        let previewSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraPreview.swift"
        )
        let viewfinderSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraViewFinder.swift"
        )
        let openControlSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraOpenControl.swift"
        )
        let captureSources = try TAPCamDemoTestSourceInspection
            .swiftSourceRelativePaths(under: "TAPCamLockedCameraCaptureExtension")
        let combinedSource = try captureSources
            .map(source)
            .joined(separator: "\n")

        #expect(previewSource.contains("UIViewRepresentable"))
        #expect(previewSource.contains("AVCaptureVideoPreviewLayer.self"))
        #expect(previewSource.contains("previewLayer.session = session"))
        #expect(previewSource.contains("previewLayer.videoGravity = .resizeAspectFill"))
        #expect(viewfinderSource.contains("Color.black"))
        #expect(viewfinderSource.contains("TAPCamLockedCameraPreview(source: camera.previewSource)"))
        #expect(viewfinderSource.contains("onCameraCaptureEvent"))
        #expect(viewfinderSource.contains("trigger: .hardwareEvent"))
        #expect(viewfinderSource.contains("trigger: .shutterButton"))
        #expect(viewfinderSource.contains("sessionContentURL: sessionContentURL"))
        #expect(viewfinderSource.contains("locked-camera-r4-shutter"))
        #expect(viewfinderSource.contains("TAPCamLockedCameraChrome("))
        #expect(viewfinderSource.contains("locked-camera-r4-root"))
        #expect(viewfinderSource.contains("TAPCamLockedCameraOpenControl(session: session)"))
        #expect(combinedSource.contains("Starting Camera"))
        #expect(combinedSource.contains("Camera Paused"))
        #expect(combinedSource.contains("Unlock to Continue"))

        #expect(!combinedSource.contains("UIImagePickerController"))
        #expect(combinedSource.contains("AVCapturePhotoOutput"))
        #expect(combinedSource.contains("isDepthDataDeliverySupported"))
        #expect(combinedSource.contains("isDepthDataDeliveryEnabled = true"))
        #expect(combinedSource.contains("embedsDepthDataInPhoto = true"))
        #expect(combinedSource.contains("photoOutput.capturePhoto(with: settings"))
        #expect(combinedSource.contains("photo.fileDataRepresentation()"))
        #expect(combinedSource.contains("photo.depthData"))
        #expect(combinedSource.contains("session.sessionContentURL"))
        #expect(combinedSource.contains("TAPCamLockedSessionContentWriter"))
        #expect(combinedSource.contains("TAPCam-\\(UUID().uuidString).heic"))
        #expect(combinedSource.contains(".tmp"))
        #expect(combinedSource.contains("photoData.write(to: stagingURL"))
        #expect(combinedSource.contains("moveItem(at: stagingURL, to: finalURL)"))
        #expect(combinedSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(combinedSource.contains("r2b_session_write_succeeded"))
        #expect(combinedSource.contains("SAVED "))
        #expect(!combinedSource.contains("AVCaptureVideoDataOutput"))
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
        let openApplicationCallCount = combinedSource
            .components(separatedBy: "openApplication(for:")
            .count - 1
        #expect(openApplicationCallCount == 1)
        #expect(!combinedSource.contains("LockedCameraCaptureManager"))
        #expect(!combinedSource.contains("URLSession"))
        #expect(!combinedSource.contains("scenePhase"))
        #expect(!combinedSource.contains("stopRunning()"))
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

    private func source(_ relativePath: String) throws -> String {
        try TAPCamDemoTestSourceInspection.source(relativePath: relativePath)
    }
}
