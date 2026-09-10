import Accelerate
import CoreGraphics
import CoreVideo
import Foundation
import simd
@preconcurrency import Vision

nonisolated struct TAPVideoPointCloudRegistrationFrame: Sendable {
    struct Sample: Sendable {
        let position: SIMD3<Float>
        /// Pixel centers in the supplied image, normalized from its top-left.
        let imagePoint: SIMD2<Float>
    }

    let image: CGImage
    let samples: [Sample]
}

/// A bounded pairwise estimate; the caller owns keyframes and serializes work.
nonisolated enum TAPVideoPointCloudRegistration {
    typealias Frame = TAPVideoPointCloudRegistrationFrame

    struct Match {
        let source: SIMD3<Float>
        let target: SIMD3<Float>
        let imagePoint: SIMD2<Float>
    }

    /// Returns a rigid transform from the first camera space into the second.
    static func transform(from: Frame, to: Frame) throws -> simd_float4x4? {
        try Task.checkCancellation()
        guard from.image.width == to.image.width, from.image.height == to.image.height,
              from.samples.count >= 24, to.samples.count >= 24,
              let first = reducedImage(from.image), let second = reducedImage(to.image) else { return nil }
        let matches = try correspondences(from: from, to: to, first: first, second: second)
        return try estimate(matches)
    }

    private static func reducedImage(_ image: CGImage) -> CGImage? {
        let scale = min(1, 320.0 / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        if width == image.width, height == image.height { return image }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func correspondences(from: Frame, to: Frame, first: CGImage, second: CGImage) throws -> [Match] {
        // The SDK example and a real translated-image check establish this direction:
        // handler=from, target=to; buffer rows and displacement use top-left pixels.
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: second, orientation: .up, options: [:])
        // Keep the classical revision paired with the small-image displacement check.
        request.revision = VNGenerateOpticalFlowRequestRevision1
        request.computationAccuracy = .high
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        try Task.checkCancellation()
        try VNImageRequestHandler(cgImage: first, orientation: .up, options: [:]).perform([request])
        // perform is synchronous. Cancellation prevents any publication or second
        // physical request until this bounded native operation has actually returned.
        try Task.checkCancellation()
        guard let buffer = request.results?.first?.pixelBuffer else { return [] }
        return try matches(from: from.samples, to: to.samples, flow: buffer)
    }

    private static func valid(_ sample: Frame.Sample) -> Bool {
        let point = sample.imagePoint
        return sample.position.x.isFinite && sample.position.y.isFinite && sample.position.z.isFinite
            && point.x.isFinite && point.y.isFinite && point.x >= 0 && point.y >= 0 && point.x < 1 && point.y < 1
    }

    private static func sparseSamples(_ samples: [Frame.Sample]) -> [Frame.Sample] {
        var cells: [Int: Frame.Sample] = [:]
        for sample in samples where valid(sample) {
            let key = Int(sample.imagePoint.y * 16) * 24 + Int(sample.imagePoint.x * 24)
            if cells[key] == nil { cells[key] = sample }
        }
        return cells.keys.sorted().compactMap { cells[$0] }
    }

    private static func matches(from: [Frame.Sample], to: [Frame.Sample], flow: CVPixelBuffer) throws -> [Match] {
        let width = CVPixelBufferGetWidth(flow), height = CVPixelBufferGetHeight(flow)
        guard width > 0, height > 0,
              CVPixelBufferGetPixelFormatType(flow) == kCVPixelFormatType_TwoComponent32Float,
              CVPixelBufferLockBaseAddress(flow, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(flow) else { return [] }
        let rowBytes = CVPixelBufferGetBytesPerRow(flow)
        let size = SIMD2<Float>(Float(width), Float(height))
        let grid = SampleGrid(samples: to, size: size)
        let source = sparseSamples(from)
        var result: [Match] = [], usedTargets = Set<Int>()
        for sample in source {
            try Task.checkCancellation()
            let pixel = sample.imagePoint * size
            let offset = Int(pixel.y) * rowBytes + Int(pixel.x) * MemoryLayout<SIMD2<Float>>.stride
            let displacement = base.loadUnaligned(fromByteOffset: offset, as: SIMD2<Float>.self)
            let predicted = pixel + displacement
            guard predicted.x.isFinite, predicted.y.isFinite,
                  let index = grid.nearest(to: predicted, samples: to), usedTargets.insert(index).inserted else { continue }
            result.append(Match(source: sample.position, target: to[index].position, imagePoint: sample.imagePoint))
        }
        return result.count >= max(24, source.count / 4) ? result : []
    }

    private struct SampleGrid {
        let size: SIMD2<Float>
        let columns: Int
        let rows: Int
        var cells: [[Int]]

        init(samples: [Frame.Sample], size: SIMD2<Float>) {
            self.size = size
            columns = Int(ceil(size.x / 4))
            rows = Int(ceil(size.y / 4))
            cells = Array(repeating: [], count: columns * rows)
            for (index, sample) in samples.enumerated() where valid(sample) {
                let pixel = sample.imagePoint * size
                cells[Int(pixel.y / 4) * columns + Int(pixel.x / 4)].append(index)
            }
        }

        func nearest(to pixel: SIMD2<Float>, samples: [Frame.Sample]) -> Int? {
            guard pixel.x >= 0, pixel.y >= 0, pixel.x < size.x, pixel.y < size.y else { return nil }
            let column = Int(pixel.x / 4), row = Int(pixel.y / 4)
            var nearest: Int?, distanceSquared: Float = 2.5 * 2.5
            for y in max(0, row - 1)...min(rows - 1, row + 1) {
                for x in max(0, column - 1)...min(columns - 1, column + 1) {
                    for index in cells[y * columns + x] {
                        let distance = simd_length_squared(samples[index].imagePoint * size - pixel)
                        if distance < distanceSquared { nearest = index; distanceSquared = distance }
                    }
                }
            }
            return nearest
        }
    }

    static func estimate(_ matches: [Match]) throws -> simd_float4x4? {
        guard matches.count >= 24 else { return nil }
        let depths = matches.map { simd_length($0.source) }.sorted()
        let tolerance = min(0.08, max(0.025, depths[depths.count / 2] * 0.015))
        let required = max(24, Int(ceil(Double(matches.count) * 0.6)))
        var best: [Match] = [], bestError = Float.infinity
        var seed: UInt64 = 0x5eed
        // ponytail: 96 deterministic RANSAC trials over at most 384 matches;
        // this assumes spatially distributed static-scene support, not object tracking.
        for _ in 0..<96 {
            try Task.checkCancellation()
            let subset = (0..<3).map { _ -> Match in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return matches[Int((seed >> 32) % UInt64(matches.count))]
            }
            guard let transform = fit(subset) else { continue }
            let inliers = matches.filter { residual($0, transform: transform) <= tolerance }
            let error = inliers.reduce(Float.zero) { $0 + residual($1, transform: transform) }
            if inliers.count > best.count || (inliers.count == best.count && error < bestError) {
                best = inliers
                bestError = error
            }
        }
        guard best.count >= required, let refined = fit(best) else { return nil }
        best = matches.filter { residual($0, transform: refined) <= tolerance }
        guard best.count >= required, hasImageCoverage(best), let result = fit(best), isBounded(result) else { return nil }
        let meanError = best.reduce(Float.zero) { $0 + residual($1, transform: result) } / Float(best.count)
        try Task.checkCancellation()
        return meanError <= tolerance * 0.6 ? result : nil
    }

    private static func residual(_ match: Match, transform: simd_float4x4) -> Float {
        let point = transform * SIMD4<Float>(match.source, 1)
        return simd_distance(SIMD3<Float>(point.x, point.y, point.z), match.target)
    }

    private static func hasImageCoverage(_ matches: [Match]) -> Bool {
        var lower = SIMD2<Float>(repeating: 1), upper = SIMD2<Float>(repeating: 0), cells = Set<Int>()
        for match in matches {
            lower = simd_min(lower, match.imagePoint)
            upper = simd_max(upper, match.imagePoint)
            cells.insert(Int(match.imagePoint.y * 4) * 4 + Int(match.imagePoint.x * 4))
        }
        return cells.count >= 6 && upper.x - lower.x >= 0.25 && upper.y - lower.y >= 0.25
    }

    private static func isBounded(_ transform: simd_float4x4) -> Bool {
        let translation = transform.columns.3
        let cosine = (transform[0, 0] + transform[1, 1] + transform[2, 2] - 1) / 2
        return simd_length(SIMD3<Float>(translation.x, translation.y, translation.z)) <= 0.75
            && cosine >= cos(.pi / 4)
    }

    private static func fit(_ matches: [Match]) -> simd_float4x4? {
        let count = Float(matches.count)
        let sourceCenter = matches.reduce(SIMD3<Float>.zero) { $0 + $1.source } / count
        let targetCenter = matches.reduce(SIMD3<Float>.zero) { $0 + $1.target } / count
        var covariance = simd_float3x3(0)
        for match in matches {
            let source = match.source - sourceCenter, target = match.target - targetCenter
            covariance += simd_float3x3(columns: (source * target.x, source * target.y, source * target.z))
        }
        var matrix = (0..<3).flatMap { column in (0..<3).map { covariance[column, $0] } }
        var singular = [Float](repeating: 0, count: 3), left = [Float](repeating: 0, count: 9)
        var right = [Float](repeating: 0, count: 9), work = [Float](repeating: 0, count: 64)
        var rows: __LAPACK_int = 3, columns: __LAPACK_int = 3, leading: __LAPACK_int = 3
        var leftLeading: __LAPACK_int = 3, rightLeading: __LAPACK_int = 3
        var workCount: __LAPACK_int = 64, info: __LAPACK_int = 0
        var leftJob: Int8 = 65, rightJob: Int8 = 65
        sgesvd_(&leftJob, &rightJob, &rows, &columns, &matrix, &leading, &singular,
                &left, &leftLeading, &right, &rightLeading, &work, &workCount, &info)
        // Planar support is valid for 3D-3D correspondences; a line or point is not.
        guard info == 0, singular.allSatisfy(\.isFinite), singular[0] > 0.00001,
              singular[1] > max(0.00001, singular[0] * 0.005) else { return nil }
        let sourceBasis = matrix3(left), targetBasis = matrix3(right).transpose
        var correction = matrix_identity_float3x3
        correction[2, 2] = simd_determinant(targetBasis * sourceBasis.transpose) < 0 ? -1 : 1
        let rotation = targetBasis * correction * sourceBasis.transpose
        let translation = targetCenter - rotation * sourceCenter
        return simd_float4x4(columns: (SIMD4<Float>(rotation.columns.0, 0), SIMD4<Float>(rotation.columns.1, 0),
                                     SIMD4<Float>(rotation.columns.2, 0), SIMD4<Float>(translation, 1)))
    }

    private static func matrix3(_ values: [Float]) -> simd_float3x3 {
        simd_float3x3(columns: (SIMD3<Float>(values[0], values[1], values[2]),
                               SIMD3<Float>(values[3], values[4], values[5]),
                               SIMD3<Float>(values[6], values[7], values[8])))
    }
}
