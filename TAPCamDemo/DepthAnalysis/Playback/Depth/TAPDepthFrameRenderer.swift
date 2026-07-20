//
//  TAPDepthFrameRenderer.swift
//  TAPCamDemo
//

import Foundation
import ImageIO
import UIKit

nonisolated struct TAPDepthFrameRenderResult {
    let image: UIImage
    let retainedByteCount: Int
}

nonisolated enum TAPDepthFrameDisplayRangePolicy {
    static let maximumSampleCount = 4_096
    static let lowerPercentile = 0.01
    static let upperPercentile = 0.99
    static let minimumSpan: Float = 0.001

    static func robustRange(
        sampledValues: [Float],
        fallbackRange: ClosedRange<Float>
    ) -> ClosedRange<Float> {
        let sorted = sampledValues
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard sorted.count >= 2 else {
            return fallbackRange
        }
        let lastIndex = sorted.count - 1
        let lowerIndex = Int((Double(lastIndex) * lowerPercentile).rounded(.down))
        let upperIndex = Int((Double(lastIndex) * upperPercentile).rounded(.up))
        let lower = sorted[lowerIndex]
        let upper = sorted[min(upperIndex, lastIndex)]
        guard upper - lower >= minimumSpan else {
            return fallbackRange
        }
        return lower...upper
    }
}

nonisolated enum TAPDepthFrameRenderer {
    static func render(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        displayOrientation: CGImagePropertyOrientation,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> TAPDepthFrameRenderResult {
        guard width > 0,
              height > 0,
              rowStride > 0,
              payload.count >= rowStride * height else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "invalid TAP depth video frame shape"
            )
        }

        let bytesPerSample = try bytesPerSample(pixelFormat: pixelFormat)
        guard rowStride >= width * bytesPerSample else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "invalid TAP depth video row stride"
            )
        }
        let range = try depthRange(
            payload: payload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            bytesPerSample: bytesPerSample,
            shouldContinue: shouldContinue
        )
        let pixels = try heatmapPixels(
            payload: payload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            bytesPerSample: bytesPerSample,
            range: range,
            shouldContinue: shouldContinue
        )
        let heatmap = try TAPDepthRGBAImageRenderer.image(
            pixels: pixels,
            width: width,
            height: height
        )
        return TAPDepthFrameRenderResult(
            image: UIImage(
                cgImage: heatmap,
                scale: 1,
                orientation: displayOrientation.uiImageOrientation
            ),
            retainedByteCount: heatmap.bytesPerRow * heatmap.height
        )
    }

    private static func depthRange(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        bytesPerSample: Int,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> ClosedRange<Float> {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var hasValidValue = false
        let pixelCount = width * height
        let sampleStride = max(
            pixelCount / TAPDepthFrameDisplayRangePolicy.maximumSampleCount,
            1
        )
        var sampledValues: [Float] = []
        sampledValues.reserveCapacity(min(pixelCount, TAPDepthFrameDisplayRangePolicy.maximumSampleCount + 1))
        try payload.withUnsafeBytes { bytes in
            for y in 0..<height {
                guard shouldContinue() else {
                    throw CancellationError()
                }
                let rowOffset = y * rowStride
                for x in 0..<width {
                    let value = try sampleValue(
                        bytes: bytes,
                        offset: rowOffset + x * bytesPerSample,
                        pixelFormat: pixelFormat
                    )
                    guard value.isFinite, value > 0 else {
                        continue
                    }
                    minimum = min(minimum, value)
                    maximum = max(maximum, value)
                    hasValidValue = true
                    if (y * width + x).isMultiple(of: sampleStride) {
                        sampledValues.append(value)
                    }
                }
            }
        }
        guard hasValidValue else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }
        return TAPDepthFrameDisplayRangePolicy.robustRange(
            sampledValues: sampledValues,
            fallbackRange: minimum...maximum
        )
    }

    private static func heatmapPixels(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        bytesPerSample: Int,
        range: ClosedRange<Float>,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let span = max(range.upperBound - range.lowerBound, 0.001)
        try pixels.withUnsafeMutableBytes { output in
            try payload.withUnsafeBytes { input in
                for y in 0..<height {
                    guard shouldContinue() else {
                        throw CancellationError()
                    }
                    let rowOffset = y * rowStride
                    for x in 0..<width {
                        let value = try sampleValue(
                            bytes: input,
                            offset: rowOffset + x * bytesPerSample,
                            pixelFormat: pixelFormat
                        )
                        guard value.isFinite, value > 0 else {
                            continue
                        }
                        writeHeatmapPixel(
                            value: value,
                            range: range,
                            span: span,
                            output: output,
                            offset: (y * width + x) * 4
                        )
                    }
                }
            }
        }
        return pixels
    }

    private static func writeHeatmapPixel(
        value: Float,
        range: ClosedRange<Float>,
        span: Float,
        output: UnsafeMutableRawBufferPointer,
        offset: Int
    ) {
        let normalized = min(max((value - range.lowerBound) / span, 0), 1)
        let color = TAPDepthHeatmapRenderer.viridisColor(normalized: normalized)
        output[offset] = color.red
        output[offset + 1] = color.green
        output[offset + 2] = color.blue
        output[offset + 3] = color.alpha
    }

    private static func bytesPerSample(pixelFormat: String) throws -> Int {
        switch pixelFormat {
        case "fdep", "fdis":
            4
        case "hdep", "hdis":
            2
        default:
            throw TAPDepthCaptureError.invalidTAPManifest(
                "unsupported TAP depth video pixel format"
            )
        }
    }

    private static func sampleValue(
        bytes: UnsafeRawBufferPointer,
        offset: Int,
        pixelFormat: String
    ) throws -> Float {
        switch pixelFormat {
        case "fdep", "fdis":
            guard offset >= 0,
                  offset + 4 <= bytes.count else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "truncated TAP depth float32 row"
                )
            }
            let bits = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            return Float(bitPattern: bits)
        case "hdep", "hdis":
            guard offset >= 0,
                  offset + 2 <= bytes.count else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "truncated TAP depth float16 row"
                )
            }
            let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            return Float(Float16(bitPattern: bits))
        default:
            throw TAPDepthCaptureError.invalidTAPManifest(
                "unsupported TAP depth video pixel format"
            )
        }
    }
}

private extension CGImagePropertyOrientation {
    nonisolated var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        }
    }
}
