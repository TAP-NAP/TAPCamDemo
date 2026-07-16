//
//  TAPDepthFrameDecoder.swift
//  TAPCamDemo
//

import Foundation
import ImageIO
import UIKit

nonisolated struct TAPDecodedDepthVideoFrame {
    let frameIndex: Int
    let presentationTimeSeconds: Double
    let width: Int
    let height: Int
    let pixelFormat: String
    let image: UIImage
    let retainedByteCount: Int

    func cacheMatches(_ other: TAPDecodedDepthVideoFrame) -> Bool {
        frameIndex == other.frameIndex
            || abs(presentationTimeSeconds - other.presentationTimeSeconds) < 0.000_5
    }
}

nonisolated enum TAPDepthFrameDecoder {
    static func decode(
        _ data: Data,
        presentationTimeSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) throws -> TAPDecodedDepthVideoFrame {
        guard shouldContinue() else {
            throw CancellationError()
        }
        let encodedFrame = try TAPDepthKLVFrame.decode(data)
        let decodeTrace = TAPVideoPerformanceTrace.beginDepthDecode(
            frameIndex: Int(encodedFrame.frameIndex)
        )
        var didDecode = false
        var decodedOutputByteCount = 0
        defer {
            TAPVideoPerformanceTrace.endDepthDecode(
                decodeTrace,
                succeeded: didDecode,
                outputByteCount: decodedOutputByteCount
            )
        }
        guard shouldContinue() else {
            throw CancellationError()
        }
        let width = Int(depthFormat.width)
        let height = Int(depthFormat.height)
        let rowStride = depthFormat.packedRowStride
        let pixelFormat = depthFormat.pixelFormat
        let expectedBytesPerSample = try bytesPerSample(for: pixelFormat)
        try validate(
            depthFormat: depthFormat,
            encodedFrame: encodedFrame,
            width: width,
            height: height,
            rowStride: rowStride,
            expectedBytesPerSample: expectedBytesPerSample
        )
        let depthPayload = try encodedFrame.decodedPackedBytes()
        guard depthPayload.count == depthFormat.uncompressedFrameByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth frame does not match manifest format"
            )
        }

        let rendered = try TAPDepthFrameRenderer.render(
            payload: depthPayload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            displayOrientation: displayOrientation,
            shouldContinue: shouldContinue
        )
        decodedOutputByteCount = rendered.retainedByteCount
        didDecode = true
        return TAPDecodedDepthVideoFrame(
            frameIndex: Int(encodedFrame.frameIndex),
            presentationTimeSeconds: presentationTimeSeconds,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            image: rendered.image,
            retainedByteCount: rendered.retainedByteCount
        )
    }

    private static func bytesPerSample(for pixelFormat: String) throws -> Int {
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

    private static func validate(
        depthFormat: TAPVideoManifest.DepthFormat,
        encodedFrame: TAPDepthKLVFrame,
        width: Int,
        height: Int,
        rowStride: Int,
        expectedBytesPerSample: Int
    ) throws {
        let (expectedRowStride, rowStrideOverflow) = width.multipliedReportingOverflow(
            by: expectedBytesPerSample
        )
        let (expectedFrameByteCount, frameByteCountOverflow) = rowStride
            .multipliedReportingOverflow(by: height)
        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(by: height)
        let (renderedByteCount, renderedByteCountOverflow) = pixelCount
            .multipliedReportingOverflow(by: 4)
        guard width > 0,
              height > 0,
              !rowStrideOverflow,
              !frameByteCountOverflow,
              !pixelCountOverflow,
              !renderedByteCountOverflow,
              depthFormat.bytesPerSample == expectedBytesPerSample,
              rowStride == expectedRowStride,
              expectedFrameByteCount == depthFormat.uncompressedFrameByteCount,
              renderedByteCount <= TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes,
              depthFormat.byteOrder == "little-endian",
              encodedFrame.uncompressedByteCount == depthFormat.uncompressedFrameByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth frame does not match manifest format"
            )
        }
    }
}

// Source compatibility for playback policy clients that used the former name.
typealias TAPDepthVideoFrameDecoder = TAPDepthFrameDecoder
