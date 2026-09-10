import Foundation
import CoreGraphics
import simd

/// The still-unrevisited part of an observation, in its original camera coordinates.
nonisolated struct TAPVideoPointCloudKeyframe: Sendable {
    let presentationTimeSeconds: Double
    let vertices: [SIMD3<Float>]
    let colors: [SIMD4<Float>]
    let cameraToAnchor: simd_float4x4

    func outsideView(cameraToAnchor currentPose: simd_float4x4,
                     cameraModel: TAPDepthProjectionCameraModel) -> Self? {
        let toCurrent = simd_inverse(currentPose) * cameraToAnchor
        let remaining = vertices.indices.filter { index in
            let point = toCurrent * SIMD4(vertices[index], 1)
            guard point.z < 0 else { return true }
            let x = point.x / -point.z * cameraModel.fx + cameraModel.cx + 0.5
            let y = -point.y / -point.z * cameraModel.fy + cameraModel.cy + 0.5
            return x < 0 || x >= Float(cameraModel.imageWidth) || y < 0 || y >= Float(cameraModel.imageHeight)
        }
        guard !remaining.isEmpty else { return nil }
        if remaining.count == vertices.count { return self }
        return Self(presentationTimeSeconds: presentationTimeSeconds,
            vertices: remaining.map { vertices[$0] }, colors: remaining.map { colors[$0] },
            cameraToAnchor: cameraToAnchor)
    }
}

nonisolated struct TAPVideoPointCloudHistory: Sendable {
    // ponytail: retain this visit's unrevisited geometry in memory; large-area
    // scans would need spatial paging rather than reducing frozen point quality.
    private(set) var frames: [TAPVideoPointCloudKeyframe] = []
    private(set) var cameraToAnchor = matrix_identity_float4x4
    private(set) var latestTime: Double?
    private var registrationFrame: TAPVideoPointCloudRegistrationFrame?

    /// An unaligned current frame remains viewable. Crop old points only in this
    /// display snapshot; none of them are removed from the accepted spatial map.
    func presentation(of payload: TAPVideoPointCloudPayload,
                      cameraToAnchor pose: simd_float4x4) -> TAPVideoPointCloudPayload {
        var result = payload
        result.rawSamples = []
        result.cameraToAnchor = pose
        result.historicalFrames = frames.compactMap {
            $0.outsideView(cameraToAnchor: pose, cameraModel: payload.cameraModel)
        }
        return result
    }

    /// Failed alignment leaves the accepted spatial map and its reference intact.
    /// A later observation must align before it can replace any frozen region.
    mutating func accept(_ payload: TAPVideoPointCloudPayload, image: CGImage) throws -> TAPVideoPointCloudPayload? {
        try Task.checkCancellation()
        if payload.presentationTimeSeconds == latestTime { return accept(payload) }
        let current = TAPVideoPointCloudRegistrationFrame(image: image, samples: payload.rawSamples)
        var transform: simd_float4x4?
        if let previous = registrationFrame {
            do { transform = try TAPVideoPointCloudRegistration.transform(from: previous, to: current) }
            catch is CancellationError { throw CancellationError() }
            catch { transform = nil }
            try Task.checkCancellation()
            guard transform != nil else { return nil }
        } else if current.samples.count < 24 {
            // A sparse first frame can be viewed, but cannot become the reference:
            // every future registration against it would fail the minimum match count.
            var standalone = payload
            standalone.rawSamples = []
            return standalone
        }
        let result = accept(payload, previousToCurrent: transform)
        registrationFrame = current
        return result
    }

    /// New observations require alignment. Rebuilding the same capture frame
    /// changes only its display geometry, not its pose or previously frozen pieces.
    mutating func accept(_ payload: TAPVideoPointCloudPayload,
                         previousToCurrent: simd_float4x4? = nil) -> TAPVideoPointCloudPayload {
        if payload.presentationTimeSeconds == latestTime {
            frames.removeLast()
        } else {
            if let previousToCurrent { cameraToAnchor *= simd_inverse(previousToCurrent) }
            // Replace the observed region, keeping the original points everywhere
            // else. This removes repeat views instead of thinning older geometry.
            frames = frames.compactMap {
                $0.outsideView(cameraToAnchor: cameraToAnchor, cameraModel: payload.cameraModel)
            }
        }
        latestTime = payload.presentationTimeSeconds
        var result = payload
        result.rawSamples = []
        result.cameraToAnchor = cameraToAnchor
        result.historicalFrames = frames
        frames.append(.init(presentationTimeSeconds: payload.presentationTimeSeconds,
            vertices: payload.vertices, colors: payload.colors, cameraToAnchor: cameraToAnchor))
        return result
    }
}
