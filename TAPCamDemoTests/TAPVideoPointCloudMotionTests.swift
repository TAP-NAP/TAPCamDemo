import simd
import Testing
@testable import TAPCamDemo

struct TAPVideoPointCloudMotionTests {
    @Test func recordedRearCameraAxesRespectEveryQuarterTurnAndMirror() throws {
        let attitude = simd_quatf(angle: .pi / 6, axis: SIMD3(0, 1, 0))
        let motion = Self.motion([(0, simd_quatf(real: 1, imag: .zero)), (0.05, attitude)])
        let expectations: [(Int, SIMD3<Float>)] = [
            (0, SIMD3(0, 0.5, -sqrt(0.75))), (90, SIMD3(0.5, 0, -sqrt(0.75))),
            (180, SIMD3(0, -0.5, -sqrt(0.75))), (270, SIMD3(-0.5, 0, -sqrt(0.75)))
        ]
        for (degrees, expected) in expectations {
            for mirrored in [false, true] {
                let playback = try #require(TAPVideoPointCloudMotion(motion: motion,
                    projection: Self.projection(rotation: degrees, mirrored: mirrored)))
                let rotation = try #require(playback.rotation(from: 0, to: 0.05))
                let point = rotation * SIMD4<Float>(0, 0, -1, 1)
                let expected = SIMD3(mirrored ? -expected.x : expected.x, expected.y, expected.z)
                #expect(simd_length(SIMD3(point.x, point.y, point.z) - expected) < 0.00001)
                #expect(rotation.columns.3 == SIMD4(0, 0, 0, 1))
                #expect(abs(simd_determinant(rotation) - 1) < 0.00001)
            }
        }
    }

    @Test func heldReferenceUsesLiveAttitudeWithoutAccumulatingOrAddingTranslation() throws {
        let baseline = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let current = baseline * simd_quatf(angle: .pi / 3, axis: SIMD3(0, 1, 0))
        let playback = try #require(TAPVideoPointCloudMotion(
            motion: Self.motion([(0, baseline), (0.05, current)]), projection: Self.projection()))
        let halfway = try #require(playback.rotation(from: 0, to: 0.025))
        let final = try #require(playback.rotation(from: 0, to: 0.05))
        #expect(simd_length(halfway * SIMD4<Float>(0, 0, -1, 1) - SIMD4(0.5, 0, -sqrt(0.75), 1)) < 0.00001)
        #expect(simd_length(final * SIMD4<Float>(0, 0, -1, 1) - SIMD4(sqrt(0.75), 0, -0.5, 1)) < 0.00001)
        #expect(playback.rotation(from: 0, to: 0.025) == halfway)
        let rebased = try #require(playback.rotation(from: 0.05, to: 0.05))
        #expect((0..<4).allSatisfy { simd_length(rebased[$0] - matrix_identity_float4x4[$0]) < 0.00001 })
        #expect(halfway.columns.3 == SIMD4(0, 0, 0, 1) && final.columns.3 == halfway.columns.3)
    }

    @Test func interpolationUsesShortestQuaternionArcAndRefusesMissingIntervals() throws {
        let turned = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        let playback = try #require(TAPVideoPointCloudMotion(motion: Self.motion([
            (0.05, simd_quatf(real: 1, imag: .zero)), (0.10, simd_quatf(vector: -turned.vector)), (0.5, turned)
        ]), projection: Self.projection()))
        let halfway = try #require(playback.rotation(from: 0.05, to: 0.075))
        #expect(simd_length(halfway * SIMD4<Float>(0, 0, -1, 1) - SIMD4(sqrt(0.5), 0, -sqrt(0.5), 1)) < 0.00001)
        #expect(playback.rotation(from: 0.001, to: 0.55) != nil)
        for missing in [-0.01, 0.2, 0.6, .nan, .infinity] {
            #expect(playback.rotation(from: 0.05, to: missing) == nil)
            #expect(playback.rotation(from: missing, to: 0.05) == nil)
        }
        let sparse = Self.motion([(0.2, simd_quatf(real: 1, imag: .zero))], interval: 1)
        let bounded = try #require(TAPVideoPointCloudMotion(motion: sparse, projection: Self.projection()))
        #expect(bounded.rotation(from: 0.2, to: 0.09) == nil)
    }

    @Test func recordedQuaternionDirectionMatchesDeviceGravity() throws {
        // One real rear-camera sample: applying the inverse attitude to reference
        // gravity must recover gravity in device axes, rather than reverse it.
        let attitude = simd_quatf(vector: SIMD4(0.33843375, 0.06115073, -0.00084950, 0.93900083))
        let playback = try #require(TAPVideoPointCloudMotion(
            motion: Self.motion([(0, simd_quatf(real: 1, imag: .zero)), (0.05, attitude)]), projection: Self.projection()))
        let rotation = try #require(playback.rotation(from: 0, to: 0.05))
        let gravity = rotation * SIMD4<Float>(0, 0, -1, 0)
        #expect(simd_length(gravity - SIMD4(0.11541618, -0.63547528, -0.76344639, 0)) < 0.00001)
        #expect(TAPVideoPointCloudMotion(motion: Self.motion([]), projection: Self.projection()) == nil)
        let unordered = Self.motion([(0.1, simd_quatf(real: 1, imag: .zero)), (0.1, attitude)])
        #expect(TAPVideoPointCloudMotion(motion: unordered, projection: Self.projection()) == nil)
    }

    private static func motion(_ samples: [(Double, simd_quatf)], interval: Double = 1 / 30.0) -> TAPVideoCaptureTelemetry.Motion {
        .init(status: .available, motionToCaptureOffsetSeconds: 0, sampleIntervalSeconds: interval,
            samples: samples.map { time, quaternion in
                .init(ptsSeconds: time, quaternion: [quaternion.imag.x, quaternion.imag.y, quaternion.imag.z, quaternion.real].map(Double.init),
                      rotationRate: [0, 0, 0], gravity: [0, 0, -1], userAcceleration: [0, 0, 0])
            })
    }

    private static func projection(rotation: Int = 90, mirrored: Bool = false) -> TAPVideoRegistrationProjection {
        .init(depthWidth: 4, depthHeight: 3, alignedRGBWidth: 4, alignedRGBHeight: 3,
            encodedRGBWidth: 3, encodedRGBHeight: 4, depthToAlignedRGBPixelCenterAffine: [1, 0, 0, 0, 1, 0],
            connectionRotationDegrees: rotation, isEncodedHorizontallyMirrored: mirrored,
            rgbCleanAperture: .init(x: 0, y: 0, width: 3, height: 4))
    }
}
