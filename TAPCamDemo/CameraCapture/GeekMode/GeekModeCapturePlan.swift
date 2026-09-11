@preconcurrency import AVFoundation
import Foundation

/// Resolves the demo's two choices once from the existing capability snapshot.
/// Still-photo support alone does not guarantee simultaneous RGB/depth streams.
/// Filtering is local to this mode; the normal camera keeps its original plans.
nonisolated struct GeekModeCapturePlan {
    let rear: CaptureSourcePlan?
    let front: CaptureSourcePlan?

    init(capabilities: CapabilityMatrix) {
        let candidates = capabilities.depthCandidates.map { candidate in
            DepthDeviceCandidate(
                kind: candidate.kind,
                device: candidate.device,
                formats: candidate.formats.filter { format in
                    Self.supportsPreviewAndPhoto(
                        unsupportedOutputClasses: format.selection.videoFormat.unsupportedCaptureOutputClasses
                    )
                }
            )
        }
        let previewCapabilities = CapabilityMatrix(
            rgbSources: capabilities.rgbSources,
            depthCandidates: candidates
        )
        rear = Self.rearPlan(in: previewCapabilities)
        front = Self.frontPlan(in: previewCapabilities)
    }

    static func supportsPreviewAndPhoto(unsupportedOutputClasses: [AnyClass]) -> Bool {
        !unsupportedOutputClasses.contains { outputClass in
            outputClass == AVCaptureVideoDataOutput.self
                || outputClass == AVCaptureDepthDataOutput.self
                || outputClass == AVCapturePhotoOutput.self
        }
    }

    private static func rearPlan(in capabilities: CapabilityMatrix) -> CaptureSourcePlan? {
        if let lidar = lidarPlan(in: capabilities) {
            return lidar
        }
        guard let option = capabilities.bestOption(nearEquivalentMillimeters: 24),
              abs(option.equivalentFocalLength35mmMillimeters - 24) < 1 else { return nil }
        let plan = CaptureSourcePlan.make(
            rgbSource: option.rgbSource,
            depthSource: option.depthSource,
            selectionMode: .automatic,
            selectedZoomID: option.zoom.id,
            selectedZoomFactor: option.zoom.rawVideoZoomFactor,
            cropRectNormalized: .fullFrame
        )
        return plan.canCapturePhotoDepth ? plan : nil
    }

    private static func lidarPlan(in capabilities: CapabilityMatrix) -> CaptureSourcePlan? {
        guard let candidate = capabilities.depthCandidates.first(where: {
            $0.kind == .lidarDepth
                && $0.device.position == .back
                && $0.device.deviceType == .builtInLiDARDepthCamera
        }) else { return nil }
        // Playground uses automatic controls. PRO's ISO, shutter and MF eligibility
        // must not exclude an otherwise usable LiDAR RGB/depth pipeline.
        let source = capabilities.rgbSources.first(where: { $0.id == candidate.device.uniqueID })
            ?? CameraCapabilityResolver.cameraProfile(
                for: candidate.device, depthCandidates: capabilities.depthCandidates
            )
        guard let depth = capabilities.depthProfiles(for: source, preferredZoomFactor: 1.0)
            .first(where: { $0.kind == .lidarDepth && $0.isSelectable }) else { return nil }
        let plan = CaptureSourcePlan.make(
            rgbSource: source,
            depthSource: depth,
            selectionMode: .automatic,
            selectedZoomID: nil,
            selectedZoomFactor: 1.0,
            cropRectNormalized: .fullFrame
        )
        return plan.canCapturePhotoDepth && plan.zoom?.matchesRawVideoZoomFactor(1.0) == true
            ? plan : nil
    }

    private static func frontPlan(in capabilities: CapabilityMatrix) -> CaptureSourcePlan? {
        guard let source = capabilities.rgbSources.first(where: {
            $0.isEnabled && $0.device.position == .front && $0.device.deviceType == .builtInTrueDepthCamera
        }), let depth = capabilities.standardDepthProfiles(for: source).first(where: {
            $0.kind == .trueDepth && $0.isSelectable
        }) else { return nil }
        let plan = CaptureSourcePlan.make(
            rgbSource: source,
            depthSource: depth,
            selectionMode: .automatic,
            selectedZoomID: nil,
            cropRectNormalized: .fullFrame
        )
        return plan.canCapturePhotoDepth ? plan : nil
    }
}
