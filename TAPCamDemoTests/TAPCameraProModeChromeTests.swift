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

}
