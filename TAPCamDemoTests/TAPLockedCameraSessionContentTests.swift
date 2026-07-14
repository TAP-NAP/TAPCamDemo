//
//  TAPLockedCameraSessionContentTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing

@Suite("Locked camera R2B source contract")
struct TAPLockedCameraR2BSourceContractTests {
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
        #expect(viewfinderSource.contains("locked-camera-r2b-shutter"))
        #expect(viewfinderSource.contains("TAPCamLockedCameraChrome("))
        #expect(viewfinderSource.contains("locked-camera-r2b-root"))
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
        #expect(!combinedSource.contains("openApplication(for:"))
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
    func mainAppStillDoesNotStartLockedCaptureImportOrPublishContext() throws {
        let appSource = try source("TAPCamDemo/App/TAPCamDemoApp.swift")
        let startupSource = try source("TAPCamDemo/App/StartupGateView.swift")
        let infoPlistSource = try source("TAPCamDemo-Info.plist")

        #expect(!appSource.contains("LockedCaptureSessionContentImportRuntime"))
        #expect(!startupSource.contains("LockedCameraAppContextPublisher"))
        #expect(!infoPlistSource.contains("CFBundleURLTypes"))
        #expect(!infoPlistSource.contains("tapcamdemo"))
    }

    private func source(_ relativePath: String) throws -> String {
        try TAPCamDemoTestSourceInspection.source(relativePath: relativePath)
    }
}
