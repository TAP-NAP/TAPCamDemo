//
//  TAPVideoDepthSampleValidator.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// Streams one timed-metadata group at a time. No collection of compressed or
/// decoded frames is retained across iterations.
nonisolated enum TAPVideoDepthSampleValidator {
    private static let metadataIdentifier = AVMetadataIdentifier(
        rawValue: "mdta/com.tapnap.depth.klv"
    )

    static func validate(
        media: TAPVideoValidatedMedia,
        manifest: TAPVideoManifest,
        contract: TAPVideoDepthValidationContract,
        maximumCombinedFrameBufferBytes: Int
    ) async throws {
        var state = try State(
            manifest: manifest,
            media: media,
            contract: contract
        )
        let reader = try makeReader(for: media)
        let output = AVAssetReaderTrackOutput(
            track: media.metadataTrack,
            outputSettings: nil
        )
        guard reader.canAdd(output) else {
            throw invalid("depth metadata track cannot be read")
        }
        reader.add(output)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(
            assetReaderTrackOutput: output
        )
        guard reader.startReading() else {
            throw invalid("depth metadata reader could not start")
        }

        while let group = adaptor.nextTimedMetadataGroup() {
            let data = try await metadataData(in: group)
            let frame = try validatedFrame(
                from: data,
                expectedFrameIndex: state.sampleCount,
                format: contract.format,
                maximumCombinedFrameBufferBytes: maximumCombinedFrameBufferBytes
            )
            try state.observe(
                frame: frame,
                compressedDataByteCount: data.count,
                group: group,
                contract: contract,
                maximumCombinedFrameBufferBytes: maximumCombinedFrameBufferBytes
            )
        }

        guard reader.status == .completed else {
            throw invalid("depth metadata reader did not complete")
        }
        try state.finish(contract: contract)
    }

    private static func makeReader(
        for media: TAPVideoValidatedMedia
    ) throws -> AVAssetReader {
        try AVAssetReader(asset: media.asset)
    }

    private static func metadataData(
        in group: AVTimedMetadataGroup
    ) async throws -> Data {
        let matchingItems = group.items.filter {
            $0.identifier == metadataIdentifier
        }
        guard matchingItems.count == 1,
              let item = matchingItems.first,
              let data = try await item.load(.dataValue) else {
            throw invalid(
                "depth metadata sample must contain exactly one TAP KLV item"
            )
        }
        return data
    }

    private static func validatedFrame(
        from data: Data,
        expectedFrameIndex: Int,
        format: TAPVideoManifest.DepthFormat,
        maximumCombinedFrameBufferBytes: Int
    ) throws -> TAPDepthKLVFrame {
        let (duplicatedKLVBytes, klvOverflow) = data.count
            .multipliedReportingOverflow(by: 2)
        let (predecodeRetainedBytes, retainedOverflow) = duplicatedKLVBytes
            .addingReportingOverflow(format.uncompressedFrameByteCount)
        guard !klvOverflow,
              !retainedOverflow,
              predecodeRetainedBytes <= maximumCombinedFrameBufferBytes else {
            throw invalid("depth metadata frame exceeds the validator memory budget")
        }

        let frame = try TAPDepthKLVFrame.decode(data)
        let (compressedBytes, compressedOverflow) = data.count
            .addingReportingOverflow(frame.payload.count)
        let (retainedFrameBytes, frameOverflow) = compressedBytes
            .addingReportingOverflow(frame.uncompressedByteCount)
        guard !compressedOverflow,
              !frameOverflow,
              expectedFrameIndex < Int(UInt32.max),
              frame.frameIndex == UInt32(expectedFrameIndex),
              frame.timestampTimescale > 0,
              frame.uncompressedByteCount == format.uncompressedFrameByteCount,
              retainedFrameBytes <= maximumCombinedFrameBufferBytes else {
            throw invalid("depth metadata frame identity or bounded length is invalid")
        }
        guard isCodec(frame.compressionCodec, allowedBy: format.compressionPolicy) else {
            throw invalid("depth metadata codec violates the manifest policy")
        }
        return frame
    }

    private static func isCodec(
        _ codec: TAPDepthCompressionCodec,
        allowedBy policy: String
    ) -> Bool {
        switch policy {
        case "per-frame:zstd1|raw":
            return codec == .zstd1 || codec == .raw
        case "per-frame:lzfse|raw":
            return codec == .lzfse || codec == .raw
        case "per-frame:raw":
            return codec == .raw
        default:
            return false
        }
    }

    private static func invalid(_ reason: String) -> TAPDepthCaptureError {
        .invalidTAPManifest(reason)
    }
}

nonisolated private extension TAPVideoDepthSampleValidator {
    struct State {
        var timelinePolicy: TAPVideoDepthTimelineValidationPolicy
        var sampleCount = 0
        var indexedCalibrationSampleCount = 0
        var unindexedCalibrationSampleCount = 0
        var previousGroupPTS: Double?
        var previousFramePTS: Double?

        init(
            manifest: TAPVideoManifest,
            media: TAPVideoValidatedMedia,
            contract: TAPVideoDepthValidationContract
        ) throws {
            let coverage = contract.coverage
            timelinePolicy = try TAPVideoDepthTimelineValidationPolicy(
                trackStartSeconds: media.metadataTiming.startSeconds,
                trackDurationSeconds: media.metadataTiming.durationSeconds,
                presentationDurationSeconds: media.facts.durationSeconds,
                nominalDepthIntervalSeconds: manifest.payload.synchronization
                    .nominalDepthIntervalSeconds,
                reportedMaxObservedDepthIntervalSeconds: manifest.payload.synchronization
                    .maxObservedDepthIntervalSeconds,
                gaps: coverage.gaps,
                baseToleranceSeconds: max(
                    1 / Double(max(coverage.trackTimeScale ?? 1, 1)),
                    1 / 600
                )
            )
        }

        mutating func observe(
            frame: TAPDepthKLVFrame,
            compressedDataByteCount: Int,
            group: AVTimedMetadataGroup,
            contract: TAPVideoDepthValidationContract,
            maximumCombinedFrameBufferBytes: Int
        ) throws {
            guard sampleCount < contract.coverage.sampleCount else {
                throw TAPVideoDepthSampleValidator.invalid(
                    "depth metadata sample count exceeds manifest"
                )
            }
            try observeCalibration(frame, contract: contract)

            let decoded = try frame.decodedPackedBytes()
            guard decoded.count == contract.format.uncompressedFrameByteCount,
                  compressedDataByteCount + frame.payload.count + decoded.count
                    <= maximumCombinedFrameBufferBytes else {
                throw TAPVideoDepthSampleValidator.invalid(
                    "depth metadata decoded length does not match manifest"
                )
            }
            try observeTiming(frame, group: group)
            sampleCount += 1
        }

        mutating func finish(
            contract: TAPVideoDepthValidationContract
        ) throws {
            let expectedCalibration = contract.calibrationCoverage
            guard sampleCount == contract.coverage.sampleCount,
                  indexedCalibrationSampleCount == expectedCalibration.indexedSampleCount,
                  unindexedCalibrationSampleCount
                    == expectedCalibration.missingCalibrationSampleCount
                        + expectedCalibration.overflowUnindexedSampleCount else {
                throw TAPVideoDepthSampleValidator.invalid(
                    "depth metadata sample or calibration coverage does not match manifest"
                )
            }
            try timelinePolicy.finish()
        }

        private mutating func observeCalibration(
            _ frame: TAPDepthKLVFrame,
            contract: TAPVideoDepthValidationContract
        ) throws {
            if let calibrationIndex = frame.calibrationIndex {
                guard Int(calibrationIndex) < contract.calibrationTable.count else {
                    throw TAPVideoDepthSampleValidator.invalid(
                        "depth metadata calibration index is outside the manifest table"
                    )
                }
                indexedCalibrationSampleCount += 1
            } else {
                unindexedCalibrationSampleCount += 1
            }
        }

        private mutating func observeTiming(
            _ frame: TAPDepthKLVFrame,
            group: AVTimedMetadataGroup
        ) throws {
            let groupPTS = CMTimeGetSeconds(group.timeRange.start)
            let framePTS = Double(frame.timestampValue) / Double(frame.timestampTimescale)
            guard groupPTS.isFinite, framePTS.isFinite else {
                throw TAPVideoDepthSampleValidator.invalid(
                    "depth metadata timestamp is invalid"
                )
            }
            let tolerance = max(1 / Double(frame.timestampTimescale), 1 / 600)
            guard abs(framePTS - groupPTS) <= tolerance else {
                throw TAPVideoDepthSampleValidator.invalid(
                    "depth KLV PTS does not match its timed metadata sample"
                )
            }
            if let previousGroupPTS, let previousFramePTS {
                guard groupPTS > previousGroupPTS,
                      framePTS > previousFramePTS else {
                    throw TAPVideoDepthSampleValidator.invalid(
                        "depth metadata timestamps must be strictly increasing"
                    )
                }
            }
            try timelinePolicy.observe(
                framePTS,
                timestampToleranceSeconds: tolerance
            )
            previousGroupPTS = groupPTS
            previousFramePTS = framePTS
        }
    }
}
