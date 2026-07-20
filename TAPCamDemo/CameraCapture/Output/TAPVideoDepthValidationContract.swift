//
//  TAPVideoDepthValidationContract.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct TAPVideoDepthValidationContract: Sendable {
    let coverage: TAPVideoManifest.DepthCoverage
    let format: TAPVideoManifest.DepthFormat
    let calibrationTable: [TAPVideoManifest.CameraCalibration]
    let calibrationCoverage: TAPVideoManifest.CalibrationCoverage

    init(
        manifest: TAPVideoManifest,
        maximumSampleCount: Int
    ) throws {
        let coverage = manifest.payload.depthCoverage
        guard coverage.trackID != nil,
              let format = coverage.format,
              coverage.sampleCount > 0,
              coverage.sampleCount <= maximumSampleCount else {
            throw TAPDepthCaptureError.missingDepthData
        }
        try TAPVideoDepthFormatValidator.validate(
            format,
            maximumFrameBytes: TAPVideoDepthTrackValidator.maximumCombinedFrameBufferBytes
        )

        let spatialRegistration = manifest.payload.spatialRegistration
        let calibrationTable = spatialRegistration.calibrationTable
        let calibrationCoverage = spatialRegistration.calibrationCoverage
        guard calibrationTable.count <= TAPVideoManifest.SpatialRegistration
            .maximumCalibrationCount else {
            throw Self.invalid(
                "depth calibration table exceeds its bounded limit"
            )
        }
        guard calibrationCoverage.indexedSampleCount >= 0,
              calibrationCoverage.missingCalibrationSampleCount >= 0,
              calibrationCoverage.overflowUnindexedSampleCount >= 0,
              calibrationCoverage.accountedSampleCount == coverage.sampleCount,
              calibrationCoverage.indexedSampleCount == 0 || !calibrationTable.isEmpty,
              calibrationCoverage.tableOverflowed
                || calibrationCoverage.overflowUnindexedSampleCount == 0,
              !calibrationCoverage.tableOverflowed
                || calibrationTable.count
                    == TAPVideoManifest.SpatialRegistration.maximumCalibrationCount else {
            throw Self.invalid("depth calibration coverage is inconsistent")
        }

        self.coverage = coverage
        self.format = format
        self.calibrationTable = calibrationTable
        self.calibrationCoverage = calibrationCoverage
    }

    private static func invalid(_ reason: String) -> TAPDepthCaptureError {
        .invalidTAPManifest(reason)
    }
}

nonisolated enum TAPVideoDepthFormatValidator {
    static func validate(
        _ format: TAPVideoManifest.DepthFormat,
        maximumFrameBytes: Int
    ) throws {
        let (expectedStride, strideOverflow) = Int(format.width)
            .multipliedReportingOverflow(by: format.bytesPerSample)
        let (expectedByteCount, byteCountOverflow) = expectedStride
            .multipliedReportingOverflow(by: Int(format.height))
        guard format.width > 0,
              format.height > 0,
              format.bytesPerSample == 2 || format.bytesPerSample == 4,
              !strideOverflow,
              !byteCountOverflow,
              format.packedRowStride == expectedStride,
              format.sourceRowStride.map({ $0 >= expectedStride }) ?? true,
              format.uncompressedFrameByteCount == expectedByteCount,
              expectedByteCount > 0,
              expectedByteCount <= maximumFrameBytes,
              format.byteOrder == "little-endian",
              isKnownFloatDepthFormat(format) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth format dimensions or packed stride are invalid"
            )
        }
    }

    private static func isKnownFloatDepthFormat(
        _ format: TAPVideoManifest.DepthFormat
    ) -> Bool {
        switch (format.pixelFormat, format.kind, format.bytesPerSample) {
        case ("hdep", "depth", 2),
             ("fdep", "depth", 4),
             ("hdis", "disparity", 2),
             ("fdis", "disparity", 4):
            return true
        default:
            return false
        }
    }
}
