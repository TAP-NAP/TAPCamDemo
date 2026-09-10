import CoreGraphics
import Foundation
import simd
#if !TAP_REGISTRATION_STANDALONE
import Testing
@testable import TAPCamDemo
#endif

private enum RegistrationCheck {
    typealias Registration = TAPVideoPointCloudRegistration
    typealias Frame = TAPVideoPointCloudRegistrationFrame
    enum Failure: Error { case check(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }

    static func knownTransform() -> simd_float4x4 {
        var value = simd_float4x4(simd_quatf(angle: 0.19, axis: simd_normalize(SIMD3<Float>(1, 2, 0.5))))
        value.columns.3 = SIMD4<Float>(0.08, -0.04, 0.12, 1)
        return value
    }

    static func correspondences(transform: simd_float4x4, outliers: Bool = false) -> [Registration.Match] {
        (0..<80).map { index in
            let x = Float(index % 10), y = Float(index / 10)
            let source = SIMD3<Float>(x * 0.09 - 0.45, y * 0.08 - 0.28, -1.5 - Float(index % 7) * 0.025)
            let projected = transform * SIMD4<Float>(source, 1)
            var target = SIMD3<Float>(projected.x, projected.y, projected.z)
            if outliers && index.isMultiple(of: 3) { target += SIMD3<Float>(0.4 + x * 0.05, -0.3, y * 0.04) }
            return Registration.Match(source: source, target: target, imagePoint: SIMD2<Float>(0.1 + x * 0.08, 0.1 + y * 0.1))
        }
    }

    static func rigidAndOutliers() throws {
        let expected = knownTransform()
        for outliers in [false, true] {
            guard let actual = try Registration.estimate(correspondences(transform: expected, outliers: outliers)) else {
                throw Failure.check("known rigid transform was rejected")
            }
            let error = (0..<4).map { simd_length(actual[$0] - expected[$0]) }.max() ?? .infinity
            try require(error < 0.0001, "rigid fit has wrong rotation, translation, or direction: \(error)")
        }
    }

    static func rejectsUnsupportedFits() throws {
        let line = (0..<80).map { index in
            let point = SIMD3<Float>(Float(index) * 0.01, 0, -2)
            return Registration.Match(source: point, target: point,
                                      imagePoint: SIMD2<Float>(Float(index % 10) / 10, Float(index / 10) / 8))
        }
        try require(try Registration.estimate(line) == nil, "collinear support was accepted")
        var jump = matrix_identity_float4x4
        jump.columns.3.x = 2
        try require(try Registration.estimate(correspondences(transform: jump)) == nil, "large jump was accepted")
        let small = Array(correspondences(transform: knownTransform()).prefix(12))
        try require(try Registration.estimate(small) == nil, "too few correspondences were accepted")
        let local = correspondences(transform: knownTransform()).map {
            Registration.Match(source: $0.source, target: $0.target, imagePoint: $0.imagePoint * 0.1)
        }
        try require(try Registration.estimate(local) == nil, "localized support was accepted")
    }

    static func image(width: Int, height: Int, dx: Int, dy: Int, textureScale: Int, splitDepth: Bool) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let motionScale = splitDepth && y < height / 2 ? 2 : 1
                let sourceX = x - dx * motionScale, sourceY = y - dy * motionScale
                var value: UInt8 = 0
                if sourceX >= 0 && sourceY >= 0 && sourceX < width && sourceY < height {
                    let cellX = sourceX / (4 * textureScale), cellY = sourceY / (4 * textureScale)
                    value = UInt8(truncatingIfNeeded: (cellX * 1237) ^ (cellY * 7919) ^ (cellX * cellY * 31))
                }
                let offset = (y * width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        guard let provider, let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Failure.check("synthetic image creation failed")
        }
        return image
    }

    static func visionDirectionAndResize() throws {
        // Also exercises the real image resize, CVPixelBuffer rows, and sparse lookup.
        for (scale, splitDepth) in [(1, false), (3, false), (1, true)] {
            let width = 160 * scale, height = 120 * scale
            var samples: [Frame.Sample] = []
            for y in stride(from: 10 * scale, to: height - 10 * scale, by: 2 * scale) {
                if splitDepth && abs(y - height / 2) < 15 { continue }
                for x in stride(from: 10 * scale, to: width - 10 * scale, by: 2 * scale) {
                    let point = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                    let depth: Float = splitDepth && y < height / 2 ? 1 : 2
                    samples.append(Frame.Sample(position: SIMD3<Float>((point.x / Float(scale) * 0.01 - 0.8) * depth / 2,
                        (0.6 - point.y / Float(scale) * 0.01) * depth / 2, -depth),
                        imagePoint: point / SIMD2<Float>(Float(width), Float(height))))
                }
            }
            let from = Frame(image: try image(width: width, height: height, dx: 0, dy: 0,
                textureScale: scale, splitDepth: splitDepth), samples: samples)
            let to = Frame(image: try image(width: width, height: height, dx: 6 * scale, dy: 4 * scale,
                textureScale: scale, splitDepth: splitDepth), samples: samples)
            guard let result = try Registration.transform(from: from, to: to) else {
                throw Failure.check("Vision translation fit was rejected at scale \(scale), splitDepth \(splitDepth)")
            }
            let translation = result.columns.3
            try require(abs(translation.x - 0.06) < 0.012 && abs(translation.y + 0.04) < 0.012
                        && abs(translation.z) < 0.012,
                        "Vision direction or top-left convention is wrong at scale \(scale), splitDepth \(splitDepth): \(translation)")
        }
    }

    static func cancellation() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try Registration.estimate(correspondences(transform: knownTransform()))
        }
        do {
            _ = try await task.value
            throw Failure.check("cancelled estimate completed")
        } catch is CancellationError { }
    }
}

#if TAP_REGISTRATION_STANDALONE
// Run without Simulator by compiling this file with the one production source:
// swiftc -Xcc -DACCELERATE_NEW_LAPACK -D TAP_REGISTRATION_STANDALONE -parse-as-library <source> <this-file> -o /tmp/tap-registration-check
@main
private struct RegistrationChecksMain {
    static func main() async throws {
        try RegistrationCheck.rigidAndOutliers()
        try RegistrationCheck.rejectsUnsupportedFits()
        try await RegistrationCheck.cancellation()
        print("rigid transform, outliers, degeneracy, coverage, jump, cancellation: passed")
        try RegistrationCheck.visionDirectionAndResize()
        print("real Vision flow direction, Y convention, resize, planar 3D fit: passed")
    }
}
#else
struct TAPVideoPointCloudRegistrationTests {
    @Test func rigidTransformRejectsOutliersAndDegeneracy() throws {
        try RegistrationCheck.rigidAndOutliers()
        try RegistrationCheck.rejectsUnsupportedFits()
    }

    @Test func realVisionFlowHasCorrectDirectionAndCoordinates() throws {
        try RegistrationCheck.visionDirectionAndResize()
    }

    @Test func cancellationStopsEstimate() async throws {
        try await RegistrationCheck.cancellation()
    }
}
#endif
