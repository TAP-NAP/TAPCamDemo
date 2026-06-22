//
//  DepthAnalysisInputValidation.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation

/// Fail-closed input limits shared by the local depth-analysis reader and tools.
///
/// The analysis surface accepts saved or pending TAP depth photo bytes. Before those bytes
/// fan out into RGB rendering, dense Float32 samples, masks, point clouds, and
/// plane-growth caches, this type keeps the cheap structural checks in one
/// place: file size, depth-map dimensions, sample count, and camera intrinsics.
nonisolated enum TAPDepthAnalysisInputValidation {
    /// A TAP depth photo is expected to be a still image with Apple auxiliary
    /// depth. Larger inputs should be rejected before ImageIO and AVDepthData
    /// work expand them into decoded images and Float32 sample arrays.
    static let maximumHEICByteCount = 64 * 1024 * 1024

    /// The visible still can be larger than the auxiliary depth map. This limit
    /// rejects obviously unsuitable inputs before the reader asks ImageIO to
    /// decode the primary image.
    static let maximumPrimaryImagePixelCount = 60_000_000

    /// Depth maps from iPhone still-photo captures are far below this in normal
    /// operation. The limit leaves room for future higher-resolution still depth
    /// while bounding heatmap, mask, point-cloud, and plane-cache allocations.
    static let maximumDepthPixelCount = 5_000_000

    private static let minimumFocalLengthMagnitude: Float = 0.000001

    static func validateHEICByteCount(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumHEICByteCount else {
            throw TAPDepthAnalysisError.analysisInputTooLarge
        }
    }

    static func validatedDepthPixelCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else {
            throw TAPDepthAnalysisError.invalidDepthMap
        }
        guard width <= maximumDepthPixelCount / height else {
            throw TAPDepthAnalysisError.analysisInputTooLarge
        }
        return width * height
    }

    static func validatePrimaryImageDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw TAPDepthAnalysisError.missingPrimaryImage
        }
        guard width <= maximumPrimaryImagePixelCount / height else {
            throw TAPDepthAnalysisError.analysisInputTooLarge
        }
    }

    static func validateDepthMapLayout(width: Int, height: Int, sampleCount: Int) throws {
        let expectedSampleCount = try validatedDepthPixelCount(width: width, height: height)
        guard sampleCount == expectedSampleCount else {
            throw TAPDepthAnalysisError.invalidDepthMap
        }
    }

    static func validateMinimumValidDepthSample(_ samples: [Float]) throws {
        guard samples.contains(where: { $0.isFinite && $0 > 0 }) else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }
    }

    static func validatedDepthPixelCount(for depthMap: TAPMetricDepthMap) throws -> Int {
        try validateDepthMapLayout(
            width: depthMap.width,
            height: depthMap.height,
            sampleCount: depthMap.samples.count
        )
        return depthMap.samples.count
    }

    static func isValidDepthMapLayout(_ depthMap: TAPMetricDepthMap) -> Bool {
        (try? validateDepthMapLayout(
            width: depthMap.width,
            height: depthMap.height,
            sampleCount: depthMap.samples.count
        )) != nil
    }

    static func sampleIndex(depthMap: TAPMetricDepthMap, x: Int, y: Int) -> Int? {
        guard x >= 0, y >= 0, x < depthMap.width, y < depthMap.height,
              isValidDepthMapLayout(depthMap) else {
            return nil
        }

        let index = y * depthMap.width + x
        guard index >= 0, index < depthMap.samples.count else {
            return nil
        }
        return index
    }

    static func validateRGBAImageLayout(width: Int, height: Int, byteCount: Int) throws {
        let pixelCount = try validatedDepthPixelCount(width: width, height: height)
        guard pixelCount <= Int.max / 4, byteCount == pixelCount * 4 else {
            throw TAPDepthAnalysisError.invalidDepthMap
        }
    }

    static func isFiniteRegion(_ region: CGRect) -> Bool {
        region.origin.x.isFinite
            && region.origin.y.isFinite
            && region.size.width.isFinite
            && region.size.height.isFinite
    }

    static func preferredCameraCalibration(
        manifestCalibration: TAPDepthManifest.CameraCalibration?,
        fallbackCalibration: TAPDepthManifest.CameraCalibration?,
        depthWidth: Int,
        depthHeight: Int
    ) -> TAPDepthManifest.CameraCalibration? {
        if let manifestCalibration,
           isUsableCameraCalibration(manifestCalibration, depthWidth: depthWidth, depthHeight: depthHeight) {
            return manifestCalibration
        }
        if let fallbackCalibration,
           isUsableCameraCalibration(fallbackCalibration, depthWidth: depthWidth, depthHeight: depthHeight) {
            return fallbackCalibration
        }
        return nil
    }

    static func isUsableCameraCalibration(
        _ calibration: TAPDepthManifest.CameraCalibration?,
        depthWidth: Int,
        depthHeight: Int
    ) -> Bool {
        guard let calibration,
              scaledIntrinsics(calibration: calibration, depthWidth: depthWidth, depthHeight: depthHeight) != nil,
              calibration.pixelSizeMillimeters.isFinite,
              calibration.lensDistortionCenterX.isFinite,
              calibration.lensDistortionCenterY.isFinite,
              calibration.extrinsicMatrix.count == 12,
              calibration.extrinsicMatrix.allSatisfy(\.isFinite) else {
            return false
        }
        return true
    }

    static func scaledIntrinsics(
        calibration: TAPDepthManifest.CameraCalibration?,
        depthWidth: Int,
        depthHeight: Int
    ) -> (fx: Float, fy: Float, cx: Float, cy: Float)? {
        guard let calibration,
              (try? validatedDepthPixelCount(width: depthWidth, height: depthHeight)) != nil,
              calibration.intrinsicMatrixReferenceWidth.isFinite,
              calibration.intrinsicMatrixReferenceHeight.isFinite,
              calibration.intrinsicMatrixReferenceWidth > 0,
              calibration.intrinsicMatrixReferenceHeight > 0,
              calibration.intrinsicMatrix.count == 9,
              calibration.intrinsicMatrix.allSatisfy(\.isFinite) else {
            return nil
        }

        let scaleX = Float(Double(depthWidth) / calibration.intrinsicMatrixReferenceWidth)
        let scaleY = Float(Double(depthHeight) / calibration.intrinsicMatrixReferenceHeight)
        let fx = calibration.intrinsicMatrix[0] * scaleX
        let fy = calibration.intrinsicMatrix[4] * scaleY
        let cx = calibration.intrinsicMatrix[6] * scaleX
        let cy = calibration.intrinsicMatrix[7] * scaleY

        guard fx.isFinite, fy.isFinite, cx.isFinite, cy.isFinite,
              abs(fx) > minimumFocalLengthMagnitude,
              abs(fy) > minimumFocalLengthMagnitude else {
            return nil
        }
        return (fx, fy, cx, cy)
    }
}
