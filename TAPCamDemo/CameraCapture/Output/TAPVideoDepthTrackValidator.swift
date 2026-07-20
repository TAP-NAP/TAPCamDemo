//
//  TAPVideoDepthTrackValidator.swift
//  TAPCamDemo
//

import Foundation

/// Facade for fail-closed validation before signing and after Photos readback.
/// Container, sample, calibration, and timeline stages live in focused types.
nonisolated enum TAPVideoDepthTrackValidator {
    static let maximumCombinedFrameBufferBytes = 32 * 1024 * 1024
    private static let maximumSampleCount = 1_000_000

    static func validate(
        fileURL: URL,
        manifest: TAPVideoManifest
    ) async throws {
        let contract = try TAPVideoDepthValidationContract(
            manifest: manifest,
            maximumSampleCount: maximumSampleCount
        )
        guard let metadataTrackID = contract.coverage.trackID else {
            throw TAPDepthCaptureError.missingDepthData
        }
        let media = try await TAPVideoContainerValidator.validate(
            fileURL: fileURL,
            manifest: manifest,
            expectedMetadataTrackID: metadataTrackID
        )
        try await TAPVideoDepthSampleValidator.validate(
            media: media,
            manifest: manifest,
            contract: contract,
            maximumCombinedFrameBufferBytes: maximumCombinedFrameBufferBytes
        )
    }

    static func validateDepthFormat(
        _ format: TAPVideoManifest.DepthFormat
    ) throws {
        try TAPVideoDepthFormatValidator.validate(
            format,
            maximumFrameBytes: maximumCombinedFrameBufferBytes
        )
    }
}
