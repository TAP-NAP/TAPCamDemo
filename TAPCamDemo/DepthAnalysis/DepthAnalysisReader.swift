//
//  DepthAnalysisReader.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// Reads a TAP depth HEIC/JPG into analysis-ready objects.
///
/// This type belongs to the analysis module: it does not know about live camera
/// configuration, lens selection, or UI state. It accepts final file bytes and
/// reconstructs everything from the persisted image container.
///
/// Principle:
/// - RGB pixels come from the primary image item via ImageIO.
/// - Depth pixels come from Apple's auxiliary depth/disparity attachment and
///   are rebuilt as `AVDepthData`.
/// - Disparity is normalized into metric depth with
///   `AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)`.
///
/// Functions enabled by this reader:
/// - Depth: colorized depth heatmap for visual inspection.
/// - Planes: region statistics and plane fitting from metric depth samples.
/// - Cloud: camera-coordinate point preview using calibration intrinsics.
///
/// Data dependencies:
/// - `CGImageSourceCreateImageAtIndex` for the visible RGB image.
/// - `CGImageSourceCopyAuxiliaryDataInfoAtIndex` inside `TAPDepthPhotoFileReader`
///   for `kCGImageAuxiliaryDataTypeDepth` / `kCGImageAuxiliaryDataTypeDisparity`.
/// - `AVDepthData.depthDataMap` for the `CVPixelBuffer` depth samples.
/// - `AVDepthData.cameraCalibrationData`, mirrored into the TAP manifest, for
///   projection from depth pixels to camera-space points.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/imageio/cgimagesource
/// - https://developer.apple.com/documentation/avfoundation/avdepthdata
/// - https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata
nonisolated enum TAPDepthMapReader {
    static func analysisInput(from photoData: Data) throws -> TAPDepthAnalysisInput {
        try TAPDepthAnalysisInputValidation.validateHEICByteCount(photoData.count)
        _ = try TAPDepthPhotoFileReader.validateSupportedContainer(photoData)
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: photoData)

        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let primaryImageDimensions = primaryImageDimensions(from: source) else {
            throw TAPDepthAnalysisError.missingPrimaryImage
        }
        try TAPDepthAnalysisInputValidation.validatePrimaryImageDimensions(
            width: primaryImageDimensions.width,
            height: primaryImageDimensions.height
        )

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TAPDepthAnalysisError.missingPrimaryImage
        }
        let imageOrientation = imageOrientation(from: source)

        guard let depthData = try TAPDepthPhotoFileReader.depthData(from: photoData) else {
            throw TAPDepthAnalysisError.missingDepthData
        }

        let metricDepth = try metricDepthMap(from: depthData, manifest: manifest)
        let heatmap = try TAPDepthHeatmapRenderer.heatmap(for: metricDepth)

        return TAPDepthAnalysisInput(
            manifest: manifest,
            image: image,
            imageOrientation: imageOrientation,
            depthMap: metricDepth,
            depthAccuracy: manifest.payload.depth.accuracy,
            depthQuality: manifest.payload.depth.quality,
            heatmap: heatmap
        )
    }

    static func metricDepthMap(from depthData: AVDepthData, manifest: TAPDepthManifest?) throws -> TAPMetricDepthMap {
        let metricDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let pixelBuffer = metricDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TAPDepthAnalysisError.unreadableDepthMap
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelCount = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(
            width: width,
            height: height
        )
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32,
              width <= Int.max / MemoryLayout<Float>.stride,
              bytesPerRow >= width * MemoryLayout<Float>.stride else {
            throw TAPDepthAnalysisError.unreadableDepthMap
        }

        var samples = [Float]()
        samples.reserveCapacity(pixelCount)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                samples.append(row[x])
            }
        }

        try TAPDepthAnalysisInputValidation.validateDepthMapLayout(
            width: width,
            height: height,
            sampleCount: samples.count
        )
        try TAPDepthAnalysisInputValidation.validateMinimumValidDepthSample(samples)

        let fallbackCalibration = metricDepthData.cameraCalibrationData.map(cameraCalibration)
        let calibration = TAPDepthAnalysisInputValidation.preferredCameraCalibration(
            manifestCalibration: manifest?.payload.depth.cameraCalibration,
            fallbackCalibration: fallbackCalibration,
            depthWidth: width,
            depthHeight: height
        )

        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: samples,
            calibration: calibration
        )
    }

    private static func cameraCalibration(_ calibration: AVCameraCalibrationData) -> TAPDepthManifest.CameraCalibration {
        let intrinsic = calibration.intrinsicMatrix
        let extrinsic = calibration.extrinsicMatrix
        return TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: calibration.intrinsicMatrixReferenceDimensions.width,
            intrinsicMatrixReferenceHeight: calibration.intrinsicMatrixReferenceDimensions.height,
            pixelSizeMillimeters: calibration.pixelSize,
            lensDistortionLookupTablePresent: calibration.lensDistortionLookupTable != nil,
            inverseLensDistortionLookupTablePresent: calibration.inverseLensDistortionLookupTable != nil,
            lensDistortionCenterX: calibration.lensDistortionCenter.x,
            lensDistortionCenterY: calibration.lensDistortionCenter.y,
            intrinsicMatrix: [
                intrinsic.columns.0.x, intrinsic.columns.0.y, intrinsic.columns.0.z,
                intrinsic.columns.1.x, intrinsic.columns.1.y, intrinsic.columns.1.z,
                intrinsic.columns.2.x, intrinsic.columns.2.y, intrinsic.columns.2.z
            ],
            extrinsicMatrix: [
                extrinsic.columns.0.x, extrinsic.columns.0.y, extrinsic.columns.0.z,
                extrinsic.columns.1.x, extrinsic.columns.1.y, extrinsic.columns.1.z,
                extrinsic.columns.2.x, extrinsic.columns.2.y, extrinsic.columns.2.z,
                extrinsic.columns.3.x, extrinsic.columns.3.y, extrinsic.columns.3.z
            ]
        )
    }

    private static func primaryImageDimensions(from source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = integerValue(from: properties[kCGImagePropertyPixelWidth]),
              let height = integerValue(from: properties[kCGImagePropertyPixelHeight]) else {
            return nil
        }
        return (width, height)
    }

    private static func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientation = imageOrientation(from: properties) else {
            return .up
        }

        return orientation
    }

    static func imageOrientation(from properties: [CFString: Any]) -> CGImagePropertyOrientation? {
        guard let rawValue = orientationRawValue(from: properties[kCGImagePropertyOrientation]) else {
            return nil
        }
        return CGImagePropertyOrientation(rawValue: rawValue)
    }

    static func orientationRawValue(from value: Any?) -> UInt32? {
        switch value {
        case let value as UInt32:
            return value
        case let value as UInt:
            return UInt32(exactly: value)
        case let value as Int:
            return UInt32(exactly: value)
        case let value as Int32:
            return UInt32(exactly: value)
        case let value as NSNumber:
            return UInt32(exactly: value.int64Value)
        default:
            return nil
        }
    }

    private static func integerValue(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Int32:
            return Int(value)
        case let value as Int64:
            return Int(exactly: value)
        case let value as UInt:
            return Int(exactly: value)
        case let value as UInt32:
            return Int(exactly: value)
        case let value as UInt64:
            return Int(exactly: value)
        case let value as NSNumber:
            return Int(exactly: value.int64Value)
        default:
            return nil
        }
    }
}
