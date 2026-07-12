//
//  TAPLockedCameraSessionContentTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing

@Suite("Locked camera R0 source contract")
struct TAPLockedCameraR0SourceContractTests {
    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func captureExtensionMatchesTheXcodeViewfinderTemplate() throws {
        let extensionSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraCaptureExtension.swift"
        )
        let viewfinderSource = try source(
            "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraViewFinder.swift"
        )
        let captureSources = try TAPCamDemoTestSourceInspection
            .swiftSourceRelativePaths(under: "TAPCamLockedCameraCaptureExtension")

        #expect(extensionSource.contains("LockedCameraCaptureUIScene { session in"))
        #expect(extensionSource.contains("TAPCamLockedCameraViewFinder(session: session)"))
        #expect(viewfinderSource.contains("UIViewControllerRepresentable"))
        #expect(viewfinderSource.contains("UIImagePickerController()"))
        #expect(viewfinderSource.contains("imagePicker.sourceType = sourceType"))
        #expect(viewfinderSource.contains("imagePicker.cameraDevice = .rear"))
        #expect(viewfinderSource.contains("UTType.image.identifier"))
        #expect(viewfinderSource.contains("UTType.movie.identifier"))

        #expect(!captureSources.contains("TAPCamLockedCameraCaptureExtension/LockedCaptureCameraController.swift"))
        #expect(!captureSources.contains("TAPCamLockedCameraCaptureExtension/LockedCapturePreviewHost.swift"))
        #expect(!captureSources.contains("TAPCamLockedCameraCaptureExtension/LockedCaptureRootView.swift"))

        let combinedSource = try captureSources
            .map(source)
            .joined(separator: "\n")
        #expect(!combinedSource.contains("openApplication(for:"))
        #expect(!combinedSource.contains("AVCaptureSession"))
        #expect(!combinedSource.contains("sessionContentURL"))
        #expect(!combinedSource.contains("LockedCameraCaptureManager"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func controlPublishesOnlyTheR0CameraCaptureAction() throws {
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
    func mainAppDoesNotStartLockedCaptureImportOrPublishContextInR0() throws {
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
