import simd

/// Recorded rear-camera attitude changes for presentation, without estimating translation.
/// The caller admits rear-camera recordings and keeps this separate from the spatial map.
nonisolated struct TAPVideoPointCloudMotion: Sendable {
    private struct Sample: Sendable {
        let time: Double
        let attitude: simd_quatf
    }

    private let samples: [Sample]
    private let deviceToCamera: simd_float3x3
    private let maximumSampleDistance: Double

    init?(motion: TAPVideoCaptureTelemetry.Motion, projection: TAPVideoRegistrationProjection) {
        guard motion.status == .available || motion.status == .partial,
              motion.referenceFrame == "xArbitraryZVertical",
              motion.deviceCoordinateSystem == "core-motion-device-right-handed",
              motion.timeBase == "capture-relative-seconds",
              motion.sampleIntervalSeconds.isFinite, motion.sampleIntervalSeconds > 0,
              !motion.samples.isEmpty,
              [0, 90, 180, 270].contains(projection.connectionRotationDegrees) else { return nil }
        var compact: [Sample] = []
        compact.reserveCapacity(motion.samples.count)
        for sample in motion.samples {
            guard sample.ptsSeconds.isFinite, sample.ptsSeconds >= 0,
                  sample.ptsSeconds > (compact.last?.time ?? -.infinity),
                  sample.quaternion.count == 4, sample.quaternion.allSatisfy(\.isFinite),
                  abs(sample.quaternion.reduce(0) { $0 + $1 * $1 } - 1) <= 0.01 else { return nil }
            let values = sample.quaternion.map(Float.init)
            compact.append(Sample(time: sample.ptsSeconds,
                attitude: simd_normalize(simd_quatf(vector: SIMD4(values[0], values[1], values[2], values[3])))))
        }
        samples = compact
        maximumSampleDistance = min(2 * motion.sampleIntervalSeconds, 0.1)
        // iPhone rear sensors need a 90-degree pixel rotation for portrait.
        // Projection.vertex then rotates the pixel grid and flips its y/z axes.
        // https://developer.apple.com/videos/play/wwdc2023/10106/
        let angle = Float(90 - projection.connectionRotationDegrees) * .pi / 180
        let mirror: Float = projection.isEncodedHorizontallyMirrored ? -1 : 1
        deviceToCamera = simd_float3x3(diagonal: SIMD3(mirror, 1, 1))
            * simd_float3x3(simd_quatf(angle: angle, axis: SIMD3(0, 0, 1)))
    }

    func rotation(from referenceTime: Double, to playbackTime: Double) -> simd_float4x4? {
        guard let reference = attitude(at: referenceTime), let current = attitude(at: playbackTime) else { return nil }
        // Core Motion's quaternion maps device vectors into its reference frame.
        let change = deviceToCamera * simd_float3x3(current.inverse * reference) * deviceToCamera.transpose
        return simd_float4x4(columns: (SIMD4(change.columns.0, 0), SIMD4(change.columns.1, 0),
                                      SIMD4(change.columns.2, 0), SIMD4(0, 0, 0, 1)))
    }

    private func attitude(at time: Double) -> simd_quatf? {
        guard time.isFinite, time >= 0 else { return nil }
        var lower = 0, upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].time < time { lower = middle + 1 } else { upper = middle }
        }
        if lower == 0 {
            return samples[0].time - time <= maximumSampleDistance ? samples[0].attitude : nil
        }
        let previous = samples[lower - 1]
        if lower == samples.count {
            return time - previous.time <= maximumSampleDistance ? previous.attitude : nil
        }
        let next = samples[lower]
        if next.time == time { return next.attitude }
        let span = next.time - previous.time
        guard span <= maximumSampleDistance else { return nil }
        return simd_slerp(previous.attitude, next.attitude, Float((time - previous.time) / span))
    }
}
