//
//  TAPCameraProModeChromeTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import TAPCamDemo

struct TAPCameraProModeChromeTests {
    @Test(.timeLimit(.minutes(1))) @MainActor
    func previewConfirmationDiscardsCallbacksFromThePreviousConfiguration() async {
        let (reports, continuation) = AsyncStream<Int>.makeStream()
        defer { continuation.finish() }
        let previewLayer = AVCaptureVideoPreviewLayer()
        let coordinator = CameraPreviewView.Coordinator(
            onCropRectChanged: { _ in },
            onPreviewingChanged: { _, generation in continuation.yield(generation) }
        )
        coordinator.attach(to: previewLayer, generation: 0)
        // Both notifications are queued before the main actor can deliver them.
        coordinator.attach(to: previewLayer, generation: 1)
        var iterator = reports.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        coordinator.attach(to: previewLayer, generation: 2)
        #expect(await iterator.next() == 2)
    }

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

    @Test func photoVideoChromeChangeKeepsBasicEVVisibleWhileHidingLivePhoto() {
        let photo = chromeState(proMode: .standard, isLivePhotoAvailable: true)
        let video = chromeState(proMode: .standard, isLivePhotoAvailable: false)

        #expect(photo.shouldShowBasicEV)
        #expect(video.shouldShowBasicEV)
        #expect(photo.isLivePhotoAvailable)
        #expect(!video.isLivePhotoAvailable)
    }

    @Test func basicEVVisibilityFollowsOnlyProModePresentation() {
        #expect(chromeState(proMode: .unavailable).shouldShowBasicEV)
        #expect(chromeState(proMode: .standard).shouldShowBasicEV)
        #expect(!chromeState(proMode: .transitioning).shouldShowBasicEV)
        #expect(!chromeState(proMode: .active).shouldShowBasicEV)
    }

    @Test func viewfinderTransitionPresentationKeepsRuntimeOwnershipOutsideTheOverlay() {
        #expect(!CameraViewfinderTransitionPresentation.hidden.isPresented)
        #expect(CameraViewfinderTransitionPresentation.hidden.message == nil)
        #expect(!CameraViewfinderTransitionPresentation.hidden.showsProgressIndicator)
        #expect(CameraViewfinderTransitionPresentation.hidden.keepsFocalLengthSelector)
        #expect(CameraViewfinderTransitionPresentation.switchingCaptureMode.keepsFocalLengthSelector)
        #expect(CameraViewfinderTransitionPresentation.switchingFocalLength.keepsFocalLengthSelector)
        #expect(!CameraViewfinderTransitionPresentation.switchingFocalLength.showsProgressIndicator)
        #expect(!CameraViewfinderTransitionPresentation.switchingToFrontCamera.keepsFocalLengthSelector)
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

    private func chromeState(
        proMode: CameraProModeChromeState,
        isLivePhotoAvailable: Bool = false
    ) -> CameraViewfinderChromeState {
        CameraViewfinderChromeState(
            flashMode: .off,
            isFlashAvailable: false,
            isLivePhotoAvailable: isLivePhotoAvailable,
            isLivePhotoEnabled: false,
            proModeState: proMode,
            contentRotation: .zero
        )
    }
}
