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

/// Reads a TAP Depth HEIC or any Apple depth HEIC into analysis-ready objects.
///
/// This type belongs to the analysis module: it does not know about live camera
/// configuration, lens selection, or UI state. It accepts final file bytes and
/// reconstructs everything from the persisted image container.
///
/// Principle:
/// - RGB pixels come from the primary HEIC image item via ImageIO.
/// - Depth pixels come from Apple's auxiliary depth/disparity attachment and
///   are rebuilt as `AVDepthData`.
/// - Disparity is normalized into metric depth with
///   `AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)`.
///
/// Functions enabled by this reader:
/// - Depth: colorized depth heatmap for visual inspection.
/// - Mask: valid/invalid depth coverage map.
/// - Planes: region statistics and plane fitting from metric depth samples.
/// - Cloud: camera-coordinate point preview using calibration intrinsics.
///
/// Data dependencies:
/// - `CGImageSourceCreateImageAtIndex` for the visible RGB image.
/// - `CGImageSourceCopyAuxiliaryDataInfoAtIndex` inside `TAPDepthHEICReader`
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
    static func analysisInput(from heicData: Data) throws -> TAPDepthAnalysisInput {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TAPDepthAnalysisError.missingPrimaryImage
        }
        let imageOrientation = imageOrientation(from: source)

        guard let depthData = try TAPDepthHEICReader.depthData(from: heicData) else {
            throw TAPDepthAnalysisError.missingDepthData
        }

        let manifest = try? TAPDepthHEICReader.decodedManifest(from: heicData)
        let metricDepth = try metricDepthMap(from: depthData, manifest: manifest)
        let heatmap = try TAPDepthHeatmapRenderer.heatmap(for: metricDepth)
        let validMask = try TAPDepthMaskRenderer.validMask(for: metricDepth)

        return TAPDepthAnalysisInput(
            manifest: manifest,
            image: image,
            imageOrientation: imageOrientation,
            depthMap: metricDepth,
            heatmap: heatmap,
            validMask: validMask
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
        var samples = [Float]()
        samples.reserveCapacity(width * height)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                samples.append(row[x])
            }
        }

        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: samples,
            calibration: manifest?.payload.depth.cameraCalibration
        )
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
}
