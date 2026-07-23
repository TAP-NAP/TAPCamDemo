//
//  TAPCameraProModeChromeTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraProModeChromeTests {
    @Test func proModeChromeStateSeparatesAvailabilityTransitionAndActivePresentation() {
        #expect(!CameraProModeChromeState.unavailable.isVisible)
        #expect(!CameraProModeChromeState.unavailable.isInteractive)

        #expect(CameraProModeChromeState.standard.isVisible)
        #expect(CameraProModeChromeState.standard.isInteractive)
        #expect(!CameraProModeChromeState.standard.isActive)

        #expect(CameraProModeChromeState.transitioning.isVisible)
        #expect(!CameraProModeChromeState.transitioning.isInteractive)
        #expect(CameraProModeChromeState.transitioning.isTransitioning)

        #expect(CameraProModeChromeState.active.isVisible)
        #expect(CameraProModeChromeState.active.isInteractive)
        #expect(CameraProModeChromeState.active.isActive)
    }

    @Test func viewfinderTransitionPresentationKeepsRuntimeOwnershipOutsideTheOverlay() {
        #expect(!CameraViewfinderTransitionPresentation.hidden.isPresented)
        #expect(CameraViewfinderTransitionPresentation.hidden.message == nil)
        #expect(!CameraViewfinderTransitionPresentation.hidden.showsProgressIndicator)
        #expect(CameraViewfinderTransitionPresentation.activatingProMode.isPresented)
        #expect(CameraViewfinderTransitionPresentation.activatingProMode.showsProgressIndicator)
        #expect(CameraViewfinderTransitionPresentation.activatingProMode.message == "Starting Pro mode…")
        #expect(CameraViewfinderTransitionPresentation.deactivatingProMode.message == "Returning to standard mode…")
        #expect(CameraViewfinderTransitionPresentation.switchingToFrontCamera.message == "Switching to front camera…")
        #expect(CameraViewfinderTransitionPresentation.switchingToRearCamera.message == "Switching to rear camera…")
        #expect(CameraViewfinderTransitionPresentation.restoringProMode.message == "Restoring Pro mode…")

        let customMessage = CameraViewfinderTransitionPresentation.presented(message: "Preparing camera path…")
        #expect(customMessage.isPresented)
        #expect(customMessage.message == "Preparing camera path…")

        let failure = CameraViewfinderTransitionPresentation.failed(message: "Camera unavailable")
        #expect(failure.isPresented)
        #expect(!failure.showsProgressIndicator)
        #expect(failure.message == "Camera unavailable")
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func proModeButtonStaysAtTheFarRightOfTheExistingTopToolbar() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift"
        )
        let toolbarStart = try #require(source.range(of: "private var topToolbar: some View"))
        let proButtonDeclaration = try #require(source.range(of: "private var proModeButton: some View"))
        let toolbar = String(source[toolbarStart.lowerBound..<proButtonDeclaration.lowerBound])

        let flash = try #require(toolbar.range(of: "flashButton"))
        let livePhoto = try #require(toolbar.range(of: "livePhotoButton"))
        let spacer = try #require(toolbar.range(of: "Spacer(minLength: 0)"))
        let pro = try #require(toolbar.range(of: "proModeButton"))

        #expect(flash.lowerBound < livePhoto.lowerBound)
        #expect(livePhoto.lowerBound < spacer.lowerBound)
        #expect(spacer.lowerBound < pro.lowerBound)
        #expect(source.contains("CameraProModeChromeState"))
        #expect(source.contains("state.proModeState.isTransitioning"))
        #expect(source.contains("state.proModeState.isActive ? highlightColor : .white"))
        #expect(source.contains(#".accessibilityIdentifier("camera.chrome.proMode")"#))
        #expect(source.contains("static let viewfinderButtonSize: CGFloat = 44"))
        #expect(source.contains("let shouldShowBasicEV: Bool"))
        #expect(source.contains("shouldShowBasicEV: Bool = true"))
        #expect(source.contains(".allowsHitTesting(state.shouldShowBasicEV)"))
        #expect(!source.contains("#if !TAP_ENABLE_PRO_CAMERA_CONTROLS"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func transitionOverlaySupportsARealRetainedFrameWithoutClaimingSnapshotCapture() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewfinderTransitionOverlayView.swift"
        )

        #expect(source.contains("CameraViewfinderTransitionOverlayView<RetainedPreview: View>"))
        #expect(source.contains("@ViewBuilder retainedPreview"))
        #expect(source.contains("retainedPreview()"))
        #expect(source.contains(".fill(.regularMaterial)"))
        #expect(source.contains(".allowsHitTesting(presentation.isPresented)"))
        #expect(source.contains(#".accessibilityIdentifier("camera.viewfinder.transitionOverlay")"#))
        #expect(source.contains("Button(recoveryActionTitle, action: onRecoveryAction)"))
        #expect(source.contains(#".accessibilityIdentifier("camera.viewfinder.transitionRetry")"#))
        #expect(!source.contains("UIGraphicsImageRenderer"))
        #expect(!source.contains("drawHierarchy"))
        #expect(!source.contains("snapshotView"))
        #expect(!source.contains("AVCapturePhotoOutput"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraPathTransitionWaitsForPreviewLayerRenderingToResume() throws {
        let previewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewView.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )

        #expect(previewSource.contains(#"previewLayer.observe(\.isPreviewing"#))
        #expect(previewSource.contains("reportCurrentPreviewingState"))
        #expect(previewSource.contains("lastCurrentReportGeneration"))
        #expect(!previewSource.contains("previewLayer.connection?.isEnabled"))
        #expect(previewSource.contains("videoPreviewLayer.isPreviewing"))
        #expect(previewSource.contains("isCropPublicationPaused"))
        #expect(!cameraSource.contains("didObservePreviewStopForTransition"))
        #expect(cameraSource.contains("isPreviewLayerPreviewing"))
        #expect(cameraSource.contains("previewReadinessGeneration &+= 1"))
        #expect(cameraSource.contains("beginCameraPathPreviewWatchdog"))
        #expect(cameraSource.contains("failCameraPathAfterPreviewTimeout"))
        #expect(cameraSource.contains("releaseCameraPathTransitionIfPreviewResumed()"))
        #expect(cameraSource.contains("isCameraPathTransitioning: isCameraPathTransitioning"))
        #expect(cameraSource.contains("|| viewModel.photographerModeState.requiresStandardRecovery"))
        #expect(cameraSource.contains("previousState.isTransitioning || previousState.requiresStandardRecovery"))
        #expect(cameraSource.contains("viewModel.canRetryUnconfiguredCameraRecovery"))
        #expect(cameraSource.contains("retryUnconfiguredCameraRecovery"))
        #expect(cameraSource.contains(#"beginCameraPathTransition(.presented(message: "Restoring standard camera…"))"#))
        #expect(cameraSource.contains("await viewModel.configureCurrentSelection()\n            completeCameraPathRuntimeTransition()"))
        #expect(!cameraSource.contains("if recoveredMode == .unconfigured {\n                cancelCameraPathTransitionPresentation()"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func proManualFocusKeepsOnePreviewLayerAndLocksBeforeNumericMovement() throws {
        let previewStageSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let loupeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraManualFocusLoupeView.swift"
        )
        let previewStreamSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CameraManualFocusPreviewStream.swift"
        )
        let writeCoordinatorSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CameraManualFocusWriteCoordinator.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let viewModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel.swift"
        )
        let controlServiceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CameraControlService.swift"
        )
        let sessionControllerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let selectionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )

        let previewLayerBridgeCount = previewStageSource
            .components(separatedBy: "CameraPreviewView(")
            .count - 1
        #expect(previewLayerBridgeCount == 1)
        #expect(previewStageSource.contains("private func focusLoupe"))
        #expect(previewStageSource.contains("CameraManualFocusLoupePreview"))
        #expect(previewStageSource.contains("CameraManualFocusLoupeTransform("))
        #expect(previewStageSource.contains("loupeTransform.centeringOffset"))
        #expect(!previewStageSource.contains("isManualFocusMagnificationActive ? 2.4 : 1"))
        let stageBody = try #require(previewStageSource.range(of: "var body: some View"))
        let loupeDeclaration = try #require(previewStageSource.range(of: "private func focusLoupe"))
        let mainPreviewSource = String(
            previewStageSource[stageBody.lowerBound..<loupeDeclaration.lowerBound]
        )
        #expect(!mainPreviewSource.contains(".scaleEffect"))
        #expect(!mainPreviewSource.contains(".transformEffect"))
        #expect(!loupeSource.contains("AVCaptureVideoPreviewLayer"))
        #expect(loupeSource.contains("AVSampleBufferDisplayLayer"))
        #expect(loupeSource.contains("(0.5 - CGFloat(focusPoint.x))"))
        #expect(loupeSource.contains("(0.5 - CGFloat(focusPoint.y))"))
        #expect(loupeSource.contains("sampleBufferRenderer"))
        #expect(loupeSource.contains("layer.addSublayer(displayLayer)"))
        #expect(!loupeSource.contains("override class var layerClass"))
        #expect(previewStreamSource.contains("AVCaptureVideoDataOutput"))
        #expect(previewStreamSource.contains("alwaysDiscardsLateVideoFrames = true"))
        #expect(previewStreamSource.contains("deliversPreviewSizedOutputBuffers = true"))
        #expect(previewStreamSource.contains("kCMSampleAttachmentKey_DisplayImmediately"))
        #expect(previewStreamSource.contains("renderer.enqueue(sampleBuffer)"))
        #expect(previewStreamSource.contains("removingDisplayedImage: true"))

        let toggleStart = try #require(cameraSource.range(of: "private func toggleFocusMode()"))
        let alignStart = try #require(cameraSource.range(of: "private func alignVisibleAdjustmentControlsIfNeeded()"))
        let toggleSource = String(cameraSource[toggleStart.lowerBound..<alignStart.lowerBound])
        #expect(toggleSource.contains("await viewModel.lockManualFocusAtCurrentLensPosition()"))
        #expect(!toggleSource.contains("scheduleManualFocusApply()"))

        let alignEnd = try #require(cameraSource.range(of: "private func storeAdjustmentDraft"))
        let alignSource = String(cameraSource[alignStart.lowerBound..<alignEnd.lowerBound])
        #expect(!alignSource.contains("scheduleManualFocusApply()"))
        #expect(cameraSource.contains("viewModel.queueManualFocus(lensPosition: value)"))
        #expect(!cameraSource.contains("Task.sleep(for: .milliseconds(120))"))
        #expect(cameraSource.contains("manualFocusDraftRevision"))
        let assistStart = try #require(
            cameraSource.range(of: "private func manualFocusTapAssistAtPreviewPoint")
        )
        let assistEnd = try #require(
            cameraSource.range(
                of: "private func lockFocusAndExposure",
                range: assistStart.upperBound..<cameraSource.endIndex
            )
        )
        let assistSource = String(cameraSource[assistStart.lowerBound..<assistEnd.lowerBound])
        #expect(assistSource.contains("await viewModel.performManualFocusTapAssist(at: point)"))
        #expect(!assistSource.contains("Task.sleep"))
        #expect(!assistSource.contains("readManualControlSnapshot"))
        #expect(!assistSource.contains("queueManualFocus"))
        #expect(cameraSource.contains("manualFocusAssistToken == nil"))
        #expect(viewModelSource.contains("manualFocusWritePump"))
        #expect(viewModelSource.contains("manualFocusTransport"))
        #expect(viewModelSource.contains("CameraManualFocusTapAssistTransaction.perform"))
        #expect(viewModelSource.contains("autoFocusOnlyAndWaitForManualFocusTapAssist"))
        #expect(viewModelSource.contains("startNextManualFocusWriteIfNeeded()"))
        #expect(writeCoordinatorSource.contains("takeNextPositionIfReady"))
        #expect(writeCoordinatorSource.contains("let predecessor = tail"))
        #expect(writeCoordinatorSource.contains("guard preflight()"))
        #expect(viewModelSource.contains("photographerModeState.effectiveMode == .photographer"))
        #expect(viewModelSource.contains("configuration.device.position == .back"))
        #expect(viewModelSource.contains("configuration.device.deviceType == .builtInLiDARDepthCamera"))
        #expect(viewModelSource.contains("performSerializedManualFocusWrite(\n                .current"))
        #expect(controlServiceSource.contains("lensPosition: AVCaptureDevice.currentLensPosition"))
        #expect(controlServiceSource.contains("CameraManualFocusOperationToken"))
        #expect(controlServiceSource.contains("completionHandler: completionHandler"))
        #expect(controlServiceSource.contains("startManualFocusTapAssistAutoFocus"))
        #expect(controlServiceSource.contains("device.isSubjectAreaChangeMonitoringEnabled = false"))
        #expect(sessionControllerSource.contains("ManualFocusLockContinuationGate"))
        #expect(sessionControllerSource.contains("ManualFocusAutoFocusSettleContinuationGate"))
        #expect(sessionControllerSource.contains(#"\.isAdjustingFocus"#))
        #expect(sessionControllerSource.contains("cameraManualFocusAssistTimedOut"))
        #expect(sessionControllerSource.contains("cameraManualFocusLockTimedOut"))
        let manualFocusWriteStart = try #require(
            sessionControllerSource.range(of: "func setManualFocusLocked(")
        )
        let manualFocusWriteEnd = try #require(
            sessionControllerSource.range(
                of: "func applyManualControlIntent(",
                range: manualFocusWriteStart.upperBound..<sessionControllerSource.endIndex
            )
        )
        let manualFocusWriteSource = String(
            sessionControllerSource[
                manualFocusWriteStart.lowerBound..<manualFocusWriteEnd.lowerBound
            ]
        )
        let timeoutStart = try #require(manualFocusWriteSource.range(of: "asyncAfter"))
        let sessionQueueStart = try #require(manualFocusWriteSource.range(of: "sessionQueue.async"))
        #expect(timeoutStart.lowerBound < sessionQueueStart.lowerBound)
        #expect(manualFocusWriteSource.contains("guard operationToken.isValid"))
        #expect(sessionControllerSource.contains("auxiliaryPreviewPolicy == .manualFocusLoupe"))
        #expect(selectionSource.contains("auxiliaryPreviewPolicy: .manualFocusLoupe"))
    }
}
