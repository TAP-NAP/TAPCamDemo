import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct GeekModeCapturePlanTests {
    @Test func previewRequiresRGBDepthAndStillOutputsButNotMovieRecording() {
        let requiredOutputs: [AnyClass] = [
            AVCaptureVideoDataOutput.self, AVCaptureDepthDataOutput.self, AVCapturePhotoOutput.self
        ]
        for output in requiredOutputs {
            #expect(!GeekModeCapturePlan.supportsPreviewAndPhoto(unsupportedOutputClasses: [output]))
        }
        #expect(GeekModeCapturePlan.supportsPreviewAndPhoto(unsupportedOutputClasses: []))
        #expect(GeekModeCapturePlan.supportsPreviewAndPhoto(
            unsupportedOutputClasses: [AVCaptureMovieFileOutput.self]
        ))
    }

    @Test(.enabled(
        if: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && !CameraCapabilityResolver.depthDevices(in: CameraCapabilityResolver.availableDevices()).isEmpty,
        "Requires an authorized physical iPhone depth camera; no session or capture is started."
    ))
    func nativeLiDARPreferenceAndStandardFallbackKeepTheSelectedStreamingFormat() throws {
        let discovered = CameraCapabilityResolver.discover()
        let streamingCandidates = discovered.depthCandidates.map { candidate in
            DepthDeviceCandidate(
                kind: candidate.kind, device: candidate.device,
                formats: candidate.formats.filter {
                    let unsupported = $0.selection.videoFormat.unsupportedCaptureOutputClasses
                    return !unsupported.contains { $0 == AVCaptureVideoDataOutput.self }
                        && !unsupported.contains { $0 == AVCaptureDepthDataOutput.self }
                        && !unsupported.contains { $0 == AVCapturePhotoOutput.self }
                }
            )
        }
        let selections = GeekModeCapturePlan(capabilities: discovered)
        if let lidar = streamingCandidates.first(where: {
            $0.kind == .lidarDepth && $0.device.position == .back
                && $0.bestFormatSelection(preferredZoomFactor: 1, requiresPreferredZoomSupport: true) != nil
        }) {
            let rear = try #require(selections.rear)
            #expect(rear.resolvedCaptureDevice.uniqueID == lidar.device.uniqueID)
            #expect(rear.depthSource?.kind == .lidarDepth)
            #expect(rear.selectionMode == .automatic)
            #expect(rear.zoom?.matchesRawVideoZoomFactor(1) == true)
            let selected = try #require(rear.formatSelection)
            #expect(lidar.formats.contains { $0.selection.videoFormat == selected.videoFormat
                && $0.selection.depthFormat == selected.depthFormat })
        }

        // Removing LiDAR simulates a non-Pro phone without changing the existing
        // Standard source priority or assuming its raw main-camera zoom is 1x.
        let standard = CapabilityMatrix(
            rgbSources: discovered.rgbSources,
            depthCandidates: streamingCandidates.filter { $0.kind != .lidarDepth }
        )
        let withoutLiDAR = GeekModeCapturePlan(capabilities: standard)
        if let option = standard.bestOption(nearEquivalentMillimeters: 24),
           abs(option.equivalentFocalLength35mmMillimeters - 24) < 1 {
            let rear = try #require(withoutLiDAR.rear)
            #expect(rear.resolvedCaptureDevice.position == .back)
            #expect(rear.depthSource?.kind == option.depthSource?.kind)
            #expect(rear.rgbSource.id == option.rgbSource.id)
            #expect(rear.zoom?.rawVideoZoomFactor == option.zoom.rawVideoZoomFactor)
        } else {
            #expect(withoutLiDAR.rear == nil)
        }
        #expect(selections.front?.resolvedCaptureDevice.uniqueID
            == withoutLiDAR.front?.resolvedCaptureDevice.uniqueID)
        if let front = selections.front {
            #expect(front.resolvedCaptureDevice.position == .front)
            #expect(front.depthSource?.kind == .trueDepth)
        }
    }
}
