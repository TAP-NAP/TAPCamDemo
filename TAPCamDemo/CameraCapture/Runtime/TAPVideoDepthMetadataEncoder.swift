//
//  TAPVideoDepthMetadataEncoder.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

nonisolated struct TAPVideoEncodedDepthSample {
    let format: TAPVideoManifest.DepthFormat
    let calibration: TAPVideoManifest.CameraCalibration?
    let calibrationIndex: UInt32?
    let calibrationTable: TAPVideoCalibrationTable
}

/// Owns depth packing, compression, KLV construction, and metadata-adaptor
/// append. Recording metrics are committed by the caller only after append.
nonisolated enum TAPVideoDepthMetadataEncoder {
    private static let metadataIdentifier = AVMetadataIdentifier(
        rawValue: "mdta/com.tapnap.depth.klv"
    )

    static func append(
        depthData: AVDepthData,
        timestamp: CMTime,
        frameIndex: Int,
        firstVideoTime: CMTime,
        calibrationTable: TAPVideoCalibrationTable,
        adaptor: AVAssetWriterInputMetadataAdaptor
    ) throws -> TAPVideoEncodedDepthSample? {
        let trace = TAPVideoPerformanceTrace.beginDepthEncode(frameIndex: frameIndex)
        var tracedCodec = "failed"
        var tracedInputByteCount = 0
        var tracedOutputByteCount = 0
        defer {
            TAPVideoPerformanceTrace.endDepthEncode(
                trace,
                codec: tracedCodec,
                inputByteCount: tracedInputByteCount,
                outputByteCount: tracedOutputByteCount
            )
        }

        let packed = try TAPDepthFrameCodec.pack(depthData.depthDataMap)
        let format = TAPVideoManifest.DepthFormat(
            kind: packed.kind,
            pixelFormat: packed.pixelFormat,
            width: Int32(packed.width),
            height: Int32(packed.height),
            packedRowStride: packed.packedRowStride,
            sourceRowStride: packed.sourceRowStride,
            bytesPerSample: packed.bytesPerSample,
            uncompressedFrameByteCount: packed.bytes.count
        )
        tracedInputByteCount = packed.bytes.count
        let encodedFrame = try TAPDepthFrameCodec.encode(
            packed.bytes,
            preferredCodec: TAPDepthCompressionProductionPolicy.preferredCodec
        )
        tracedCodec = encodedFrame.codec.rawValue
        tracedOutputByteCount = encodedFrame.payload.count

        let calibration = cameraCalibration(from: depthData.cameraCalibrationData)
        var committedCalibrationTable = calibrationTable
        let calibrationIndex = committedCalibrationTable.index(for: calibration)
        guard let relativeTimestamp = TAPVideoCaptureTimeline.relativeMediaTime(
            timestamp,
            from: firstVideoTime
        ),
              frameIndex >= 0,
              frameIndex <= Int(UInt32.max) else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "depth timestamp or frame index cannot be represented"
            )
        }
        let encoded = try TAPDepthKLVFrame(
            frameIndex: UInt32(frameIndex),
            timestampValue: relativeTimestamp.value,
            timestampTimescale: relativeTimestamp.timescale,
            compressionCodec: encodedFrame.codec,
            uncompressedByteCount: encodedFrame.uncompressedByteCount,
            calibrationIndex: calibrationIndex,
            payload: encodedFrame.payload,
            inlineCalibration: calibrationIndex == nil ? TAPDepthInlineCalibration.bounded(calibration) : nil
        )
        .encodedData()
        guard adaptor.append(metadataGroup(data: encoded, timestamp: timestamp)) else {
            return nil
        }
        return TAPVideoEncodedDepthSample(
            format: format,
            calibration: calibration,
            calibrationIndex: calibrationIndex,
            calibrationTable: committedCalibrationTable
        )
    }

    static func makeFormatDescription() throws -> CMMetadataFormatDescription {
        guard let description = metadataGroup(data: Data([0]), timestamp: .zero)
            .copyFormatDescription() else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "unable to create TAP depth metadata format description"
            )
        }
        return description
    }

    private static func metadataGroup(
        data: Data,
        timestamp: CMTime
    ) -> AVTimedMetadataGroup {
        let item = AVMutableMetadataItem()
        item.identifier = metadataIdentifier
        item.dataType = kCMMetadataBaseDataType_RawData as String
        item.value = data as NSData
        return AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(
                start: timestamp,
                duration: CMTime(value: 1, timescale: 600)
            )
        )
    }

    private static func cameraCalibration(
        from calibration: AVCameraCalibrationData?
    ) -> TAPVideoManifest.CameraCalibration? {
        guard let calibration else {
            return nil
        }
        let intrinsic = calibration.intrinsicMatrix
        let extrinsic = calibration.extrinsicMatrix
        return TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [
                intrinsic.columns.0.x, intrinsic.columns.0.y, intrinsic.columns.0.z,
                intrinsic.columns.1.x, intrinsic.columns.1.y, intrinsic.columns.1.z,
                intrinsic.columns.2.x, intrinsic.columns.2.y, intrinsic.columns.2.z
            ],
            intrinsicMatrixReferenceDimensions: TAPVideoManifest.Dimensions(
                width: calibration.intrinsicMatrixReferenceDimensions.width,
                height: calibration.intrinsicMatrixReferenceDimensions.height
            ),
            extrinsicMatrix: [
                extrinsic.columns.0.x, extrinsic.columns.0.y, extrinsic.columns.0.z,
                extrinsic.columns.1.x, extrinsic.columns.1.y, extrinsic.columns.1.z,
                extrinsic.columns.2.x, extrinsic.columns.2.y, extrinsic.columns.2.z,
                extrinsic.columns.3.x, extrinsic.columns.3.y, extrinsic.columns.3.z
            ],
            pixelSizeMillimeters: calibration.pixelSize,
            lensDistortionCenter: TAPVideoManifest.Point(
                x: calibration.lensDistortionCenter.x,
                y: calibration.lensDistortionCenter.y
            ),
            lensDistortionLookupTable: calibration.lensDistortionLookupTable,
            inverseLensDistortionLookupTable: calibration.inverseLensDistortionLookupTable
        )
    }
}
