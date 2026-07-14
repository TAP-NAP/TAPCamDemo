//
//  TAPDepthFrameCodec.swift
//  TAPCamDemo
//

import CZstd
import Compression
import CoreVideo
import Foundation

nonisolated enum TAPDepthCompressionCodec: String, Codable, CaseIterable, Sendable {
    case raw
    case lzfse
    case zstd1
}

nonisolated struct TAPPackedDepthFrame: Equatable, Sendable {
    let bytes: Data
    let kind: String
    let pixelFormat: String
    let width: Int
    let height: Int
    let packedRowStride: Int
    let sourceRowStride: Int
    let bytesPerSample: Int
}

nonisolated struct TAPEncodedDepthFrame: Equatable, Sendable {
    let codec: TAPDepthCompressionCodec
    let uncompressedByteCount: Int
    let payload: Data
}

nonisolated enum TAPDepthCompressionProductionPolicy {
    /// Pinned by the release plan. The diagnostic corpus benchmark may only
    /// change this to LZFSE or raw after the documented p95/drop gates fail.
    static let preferredCodec: TAPDepthCompressionCodec = .zstd1
}

nonisolated enum TAPDepthFrameCodec {
    static let maximumFrameByteCount = 32 * 1024 * 1024

    static func pack(_ pixelBuffer: CVPixelBuffer) throws -> TAPPackedDepthFrame {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 0 else {
            throw TAPDepthCaptureError.videoRecordingFailed("planar depth pixel buffers are unsupported")
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bytesPerSample = try bytesPerSample(for: pixelFormat)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceRowStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let packedRowStride = try checkedMultiply(width, bytesPerSample)
        guard sourceRowStride >= packedRowStride else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth source row stride is smaller than logical pixels")
        }
        let packedByteCount = try checkedMultiply(packedRowStride, height)
        guard packedByteCount <= maximumFrameByteCount else {
            throw TAPDepthCaptureError.videoRecordingFailed("packed depth frame exceeds bounded codec input")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth pixel buffer base address missing")
        }

        var packedBytes = Data(count: packedByteCount)
        packedBytes.withUnsafeMutableBytes { destinationBytes in
            guard let destinationBaseAddress = destinationBytes.baseAddress else {
                return
            }
            for row in 0..<height {
                memcpy(
                    destinationBaseAddress.advanced(by: row * packedRowStride),
                    sourceBaseAddress.advanced(by: row * sourceRowStride),
                    packedRowStride
                )
            }
        }

        return TAPPackedDepthFrame(
            bytes: packedBytes,
            kind: depthKind(for: pixelFormat),
            pixelFormat: TAPFourCharCode.string(from: pixelFormat),
            width: width,
            height: height,
            packedRowStride: packedRowStride,
            sourceRowStride: sourceRowStride,
            bytesPerSample: bytesPerSample
        )
    }

    static func encode(
        _ packedBytes: Data,
        preferredCodec: TAPDepthCompressionCodec = .zstd1
    ) throws -> TAPEncodedDepthFrame {
        guard packedBytes.count <= maximumFrameByteCount else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth frame exceeds bounded codec input")
        }
        guard !packedBytes.isEmpty else {
            return TAPEncodedDepthFrame(codec: .raw, uncompressedByteCount: 0, payload: Data())
        }

        let compressed: Data
        switch preferredCodec {
        case .raw:
            compressed = packedBytes
        case .lzfse:
            compressed = lzfseEncode(packedBytes) ?? packedBytes
        case .zstd1:
            compressed = zstdEncodeLevel1(packedBytes) ?? packedBytes
        }

        guard preferredCodec != .raw, compressed.count < packedBytes.count else {
            return TAPEncodedDepthFrame(
                codec: .raw,
                uncompressedByteCount: packedBytes.count,
                payload: packedBytes
            )
        }
        return TAPEncodedDepthFrame(
            codec: preferredCodec,
            uncompressedByteCount: packedBytes.count,
            payload: compressed
        )
    }

    static func decode(_ encodedFrame: TAPEncodedDepthFrame) throws -> Data {
        guard encodedFrame.uncompressedByteCount >= 0,
              encodedFrame.uncompressedByteCount <= maximumFrameByteCount,
              encodedFrame.payload.count <= maximumFrameByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("depth frame exceeds bounded codec limits")
        }

        let decoded: Data
        switch encodedFrame.codec {
        case .raw:
            decoded = encodedFrame.payload
        case .lzfse:
            decoded = try lzfseDecode(
                encodedFrame.payload,
                uncompressedByteCount: encodedFrame.uncompressedByteCount
            )
        case .zstd1:
            decoded = try zstdDecode(
                encodedFrame.payload,
                uncompressedByteCount: encodedFrame.uncompressedByteCount
            )
        }

        guard decoded.count == encodedFrame.uncompressedByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("depth frame decoded byte count mismatch")
        }
        return decoded
    }

    private static func lzfseEncode(_ data: Data) -> Data? {
        var destination = Data(count: data.count)
        let destinationCapacity = destination.count
        let scratchByteCount = compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)
        let scratch = UnsafeMutableRawPointer.allocate(
            byteCount: max(1, scratchByteCount),
            alignment: MemoryLayout<UInt8>.alignment
        )
        defer {
            scratch.deallocate()
        }

        let encodedByteCount = destination.withUnsafeMutableBytes { destinationBytes in
            data.withUnsafeBytes { sourceBytes in
                guard let destinationBaseAddress = destinationBytes.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBaseAddress = sourceBytes.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(
                    destinationBaseAddress,
                    destinationCapacity,
                    sourceBaseAddress,
                    data.count,
                    scratch,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard encodedByteCount > 0, encodedByteCount < data.count else {
            return nil
        }
        destination.removeSubrange(encodedByteCount..<destination.count)
        return destination
    }

    private static func zstdEncodeLevel1(_ data: Data) -> Data? {
        guard data.count > 1 else {
            return nil
        }
        do {
            // ZSTD_compress may require its documented bound as destination
            // capacity even when the final frame is smaller than raw. Allocate
            // that bounded scratch, then retain the result only if it wins.
            let destinationCapacity = try CZstd.compressBound(
                sourceByteCount: data.count,
                maximumInputByteCount: maximumFrameByteCount
            )
            let compressed = try CZstd.compress(
                data,
                maximumInputByteCount: maximumFrameByteCount,
                maximumOutputByteCount: destinationCapacity
            )
            return compressed.count < data.count ? compressed : nil
        } catch {
            return nil
        }
    }

    private static func lzfseDecode(
        _ payload: Data,
        uncompressedByteCount: Int
    ) throws -> Data {
        guard uncompressedByteCount > 0 else {
            guard payload.isEmpty else {
                throw TAPDepthCaptureError.invalidTAPManifest("non-empty compressed depth frame has zero size")
            }
            return Data()
        }

        var output = Data(count: uncompressedByteCount)
        let decodedByteCount = output.withUnsafeMutableBytes { outputBytes in
            payload.withUnsafeBytes { payloadBytes in
                guard let outputBaseAddress = outputBytes.bindMemory(to: UInt8.self).baseAddress,
                      let payloadBaseAddress = payloadBytes.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    outputBaseAddress,
                    uncompressedByteCount,
                    payloadBaseAddress,
                    payload.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard decodedByteCount == uncompressedByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid LZFSE depth frame")
        }
        return output
    }

    private static func zstdDecode(
        _ payload: Data,
        uncompressedByteCount: Int
    ) throws -> Data {
        guard uncompressedByteCount > 0 else {
            guard payload.isEmpty else {
                throw TAPDepthCaptureError.invalidTAPManifest("non-empty zstd depth frame has zero size")
            }
            return Data()
        }

        do {
            return try CZstd.decompress(
                payload,
                originalByteCount: uncompressedByteCount,
                maximumCompressedByteCount: maximumFrameByteCount,
                maximumOutputByteCount: maximumFrameByteCount
            )
        } catch {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid zstd1 depth frame")
        }
    }

    private static func bytesPerSample(for pixelFormat: OSType) throws -> Int {
        switch pixelFormat {
        case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DisparityFloat16:
            return 2
        case kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32:
            return 4
        default:
            throw TAPDepthCaptureError.videoRecordingFailed(
                "unsupported depth pixel format \(TAPFourCharCode.string(from: pixelFormat))"
            )
        }
    }

    private static func depthKind(for pixelFormat: OSType) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32:
            return "depth"
        case kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32:
            return "disparity"
        default:
            return "unknown"
        }
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, value >= 0 else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth frame dimensions overflow")
        }
        return value
    }
}
