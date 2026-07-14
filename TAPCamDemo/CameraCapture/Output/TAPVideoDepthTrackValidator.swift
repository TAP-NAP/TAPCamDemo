//
//  TAPVideoDepthTrackValidator.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// Reads the actual timed-metadata track before signing and after Photos
/// readback. Validation is streaming: at most one bounded KLV payload and one
/// decoded depth frame are retained at a time.
nonisolated enum TAPVideoDepthTrackValidator {
    private static let metadataIdentifier = AVMetadataIdentifier(
        rawValue: "mdta/com.tapnap.depth.klv"
    )
    static let maximumCombinedFrameBufferBytes = 32 * 1024 * 1024
    private static let maximumSampleCount = 1_000_000

    static func validate(
        fileURL: URL,
        manifest: TAPVideoManifest
    ) async throws {
        let coverage = manifest.payload.depthCoverage
        guard let expectedTrackID = coverage.trackID,
              let format = coverage.format,
              coverage.sampleCount > 0,
              coverage.sampleCount <= maximumSampleCount else {
            throw TAPDepthCaptureError.missingDepthData
        }
        try validateDepthFormat(format)
        let calibrationTable = manifest.payload.spatialRegistration.calibrationTable
        let calibrationCoverage = manifest.payload.spatialRegistration.calibrationCoverage
        guard calibrationTable.count <= TAPVideoManifest.SpatialRegistration
            .maximumCalibrationCount else {
            throw TAPDepthCaptureError.invalidTAPManifest(
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
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth calibration coverage is inconsistent"
            )
        }

        let asset = AVURLAsset(url: fileURL)
        async let loadedTracks = asset.load(.tracks)
        async let loadedVideoTracks = asset.loadTracks(withMediaType: .video)
        async let loadedAudioTracks = asset.loadTracks(withMediaType: .audio)
        async let loadedMetadataTracks = asset.loadTracks(withMediaType: .metadata)
        async let loadedDuration = asset.load(.duration)
        let tracks = try await loadedTracks
        let videoTracks = try await loadedVideoTracks
        let audioTracks = try await loadedAudioTracks
        let metadataTracks = try await loadedMetadataTracks
        let duration = try await loadedDuration
        let expectedAudioTrackCount = manifest.payload.audioTrack.status == .captured ? 1 : 0
        guard videoTracks.count == 1,
              metadataTracks.count == 1,
              audioTracks.count == expectedAudioTrackCount,
              tracks.count == 2 + expectedAudioTrackCount else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "TAP video contains an unexpected media track composition"
            )
        }
        try await validateContainerAndMediaTracks(
            manifest: manifest,
            tracks: tracks,
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            duration: duration
        )
        guard let metadataTrack = metadataTracks.first(where: { $0.trackID == expectedTrackID }) else {
            throw TAPDepthCaptureError.missingDepthData
        }
        let metadataTimeRange = try await validateMetadataTrackFacts(
            metadataTrack,
            coverage: coverage
        )
        var timelinePolicy = try TAPVideoDepthTimelineValidationPolicy(
            trackStartSeconds: CMTimeGetSeconds(metadataTimeRange.start),
            trackDurationSeconds: CMTimeGetSeconds(metadataTimeRange.duration),
            presentationDurationSeconds: CMTimeGetSeconds(duration),
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

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth metadata track cannot be read"
            )
        }
        reader.add(output)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(
            assetReaderTrackOutput: output
        )
        guard reader.startReading() else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth metadata reader could not start"
            )
        }

        var sampleCount = 0
        var indexedCalibrationSampleCount = 0
        var unindexedCalibrationSampleCount = 0
        var previousGroupPTS: Double?
        var previousFramePTS: Double?
        while let group = adaptor.nextTimedMetadataGroup() {
            let matchingItems = group.items.filter {
                $0.identifier == metadataIdentifier
            }
            guard matchingItems.count == 1,
                  let item = matchingItems.first,
                  let data = try await item.load(.dataValue) else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata sample must contain exactly one TAP KLV item"
                )
            }
            guard sampleCount < coverage.sampleCount else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata sample count exceeds manifest"
                )
            }

            let (duplicatedKLVBytes, klvOverflow) = data.count
                .multipliedReportingOverflow(by: 2)
            let (predecodeRetainedBytes, retainedOverflow) = duplicatedKLVBytes
                .addingReportingOverflow(format.uncompressedFrameByteCount)
            guard !klvOverflow,
                  !retainedOverflow,
                  predecodeRetainedBytes <= maximumCombinedFrameBufferBytes else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata frame exceeds the validator memory budget"
                )
            }

            let frame = try TAPDepthKLVFrame.decode(data)
            let retainedFrameBytes = data.count
                + frame.payload.count
                + frame.uncompressedByteCount
            guard frame.frameIndex == UInt32(sampleCount),
                  frame.timestampTimescale > 0,
                  frame.uncompressedByteCount == format.uncompressedFrameByteCount,
                  retainedFrameBytes <= maximumCombinedFrameBufferBytes else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata frame identity or bounded length is invalid"
                )
            }
            guard isCodec(
                frame.compressionCodec,
                allowedBy: format.compressionPolicy
            ) else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata codec violates the manifest policy"
                )
            }
            if let calibrationIndex = frame.calibrationIndex {
                guard Int(calibrationIndex) < calibrationTable.count else {
                    throw TAPDepthCaptureError.invalidTAPManifest(
                        "depth metadata calibration index is outside the manifest table"
                    )
                }
                indexedCalibrationSampleCount += 1
            } else {
                unindexedCalibrationSampleCount += 1
            }
            let decoded = try frame.decodedPackedBytes()
            guard decoded.count == format.uncompressedFrameByteCount else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata decoded length does not match manifest"
                )
            }

            let groupPTS = CMTimeGetSeconds(group.timeRange.start)
            let framePTS = Double(frame.timestampValue) / Double(frame.timestampTimescale)
            guard groupPTS.isFinite, framePTS.isFinite else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth metadata timestamp is invalid"
                )
            }
            let currentOffset = framePTS - groupPTS
            let tolerance = max(
                1 / Double(frame.timestampTimescale),
                1 / 600
            )
            guard abs(currentOffset) <= tolerance else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "depth KLV PTS does not match its timed metadata sample"
                )
            }
            if let previousGroupPTS, let previousFramePTS {
                guard groupPTS > previousGroupPTS,
                      framePTS > previousFramePTS else {
                    throw TAPDepthCaptureError.invalidTAPManifest(
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
            sampleCount += 1
        }

        guard reader.status == .completed else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth metadata reader did not complete"
            )
        }
        guard sampleCount == coverage.sampleCount,
              indexedCalibrationSampleCount == calibrationCoverage.indexedSampleCount,
              unindexedCalibrationSampleCount
                == calibrationCoverage.missingCalibrationSampleCount
                    + calibrationCoverage.overflowUnindexedSampleCount else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth metadata sample or calibration coverage does not match manifest"
            )
        }
        try timelinePolicy.finish()
    }

    static func validateDepthFormat(_ format: TAPVideoManifest.DepthFormat) throws {
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
              expectedByteCount <= maximumCombinedFrameBufferBytes,
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

    private static func validateContainerAndMediaTracks(
        manifest: TAPVideoManifest,
        tracks: [AVAssetTrack],
        videoTracks: [AVAssetTrack],
        audioTracks: [AVAssetTrack],
        duration: CMTime
    ) async throws {
        let container = manifest.payload.container
        guard tracks.count == container.trackCount,
              duration.timescale == container.timeScale,
              approximatelyEqual(
                CMTimeGetSeconds(duration),
                container.durationSeconds,
                timeScale: container.timeScale
              ),
              let expectedVideoID = manifest.payload.rgbTrack.trackID,
              let videoTrack = videoTracks.first(where: { $0.trackID == expectedVideoID }) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "container or RGB track facts do not match the MP4"
            )
        }
        try await validateVideoTrackFacts(
            videoTrack,
            expected: manifest.payload.rgbTrack
        )

        let expectedAudio = manifest.payload.audioTrack
        switch expectedAudio.status {
        case .captured:
            guard let expectedAudioID = expectedAudio.trackID,
                  let audioTrack = audioTracks.first(where: { $0.trackID == expectedAudioID }) else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "captured audio track is missing from the MP4"
                )
            }
            try await validateAudioTrackFacts(audioTrack, expected: expectedAudio)
        case .notCaptured, .unavailable:
            guard audioTracks.isEmpty else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "manifest omits an audio track present in the MP4"
                )
            }
        }
    }

    private static func validateVideoTrackFacts(
        _ track: AVAssetTrack,
        expected: TAPVideoManifest.RGBTrack
    ) async throws {
        let descriptions = try await track.load(.formatDescriptions)
        let timeRange = try await track.load(.timeRange)
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        let nominalFrameRate = Double(try await track.load(.nominalFrameRate))
        guard let description = descriptions.first else {
            throw TAPDepthCaptureError.invalidTAPManifest("RGB track format is missing")
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let codec = TAPFourCharCode.string(
            from: CMFormatDescriptionGetMediaSubType(description)
        )
        let resolvedTimeScale = naturalTimeScale > 0
            ? naturalTimeScale
            : timeRange.duration.timescale
        guard codec == expected.codec,
              dimensions.width == expected.width,
              dimensions.height == expected.height,
              resolvedTimeScale == expected.timeScale,
              approximatelyEqual(
                CMTimeGetSeconds(timeRange.duration),
                expected.durationSeconds,
                timeScale: expected.timeScale
              ),
              expected.nominalFrameRate.map({
                  nominalFrameRate > 0 && abs(nominalFrameRate - $0) <= 0.01
              }) ?? true else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "RGB track facts do not match the MP4"
            )
        }
    }

    private static func validateAudioTrackFacts(
        _ track: AVAssetTrack,
        expected: TAPVideoManifest.AudioTrack
    ) async throws {
        let descriptions = try await track.load(.formatDescriptions)
        let timeRange = try await track.load(.timeRange)
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        guard let description = descriptions.first,
              let expectedCodec = expected.codec,
              let expectedDuration = expected.durationSeconds,
              let expectedTimeScale = expected.timeScale else {
            throw TAPDepthCaptureError.invalidTAPManifest("audio track facts are missing")
        }
        let codec = TAPFourCharCode.string(
            from: CMFormatDescriptionGetMediaSubType(description)
        )
        let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        let resolvedTimeScale = naturalTimeScale > 0
            ? naturalTimeScale
            : timeRange.duration.timescale
        guard codec == expectedCodec,
              resolvedTimeScale == expectedTimeScale,
              approximatelyEqual(
                CMTimeGetSeconds(timeRange.duration),
                expectedDuration,
                timeScale: expectedTimeScale
              ),
              expected.sampleRate.map({
                  abs((stream?.mSampleRate ?? -1) - $0) <= 0.01
              }) ?? true,
              expected.channelCount.map({
                  Int(stream?.mChannelsPerFrame ?? 0) == $0
              }) ?? true else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "audio track facts do not match the MP4"
            )
        }
    }

    private static func validateMetadataTrackFacts(
        _ track: AVAssetTrack,
        coverage: TAPVideoManifest.DepthCoverage
    ) async throws -> CMTimeRange {
        let descriptions = try await track.load(.formatDescriptions)
        let timeRange = try await track.load(.timeRange)
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        guard let description = descriptions.first,
              let expectedCodec = coverage.trackCodec,
              let expectedDuration = coverage.trackDurationSeconds,
              let expectedTimeScale = coverage.trackTimeScale else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth metadata track facts are missing"
            )
        }
        let codec = TAPFourCharCode.string(
            from: CMFormatDescriptionGetMediaSubType(description)
        )
        let resolvedTimeScale = naturalTimeScale > 0
            ? naturalTimeScale
            : timeRange.duration.timescale
        guard codec == expectedCodec,
              resolvedTimeScale == expectedTimeScale,
              approximatelyEqual(
                CMTimeGetSeconds(timeRange.duration),
                expectedDuration,
                timeScale: expectedTimeScale
              ) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "depth metadata track facts do not match the MP4"
            )
        }
        return timeRange
    }

    private static func approximatelyEqual(
        _ actual: Double,
        _ expected: Double,
        timeScale: Int32
    ) -> Bool {
        actual.isFinite
            && expected.isFinite
            && abs(actual - expected) <= max(1 / Double(max(timeScale, 1)), 0.001)
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
}

/// Pure, bounded reconciliation of the signed depth timeline against the
/// actual stored KLV presentation timestamps. The streaming validator feeds
/// one timestamp at a time; tests can exercise the same policy without making
/// an AVFoundation asset.
nonisolated struct TAPVideoDepthTimelineValidationPolicy: Sendable {
    private struct GapInterval: Sendable {
        let start: Double
        let end: Double
    }

    private let trackStartSeconds: Double
    private let trackEndSeconds: Double
    private let presentationDurationSeconds: Double
    private let nominalDepthIntervalSeconds: Double?
    private let reportedMaxObservedDepthIntervalSeconds: Double?
    private let gapIntervals: [GapInterval]
    private let baseToleranceSeconds: Double

    private var firstPTS: Double?
    private var previousPTS: Double?
    private var previousToleranceSeconds: Double?
    private var actualMaxObservedDepthIntervalSeconds: Double?
    private var maximumObservedToleranceSeconds: Double
    private var observedSampleCount = 0

    init(
        trackStartSeconds: Double,
        trackDurationSeconds: Double,
        presentationDurationSeconds: Double,
        nominalDepthIntervalSeconds: Double?,
        reportedMaxObservedDepthIntervalSeconds: Double?,
        gaps: [TAPVideoManifest.DepthGap],
        baseToleranceSeconds: Double
    ) throws {
        let trackEndSeconds = trackStartSeconds + trackDurationSeconds
        guard trackStartSeconds.isFinite,
              trackDurationSeconds.isFinite,
              trackDurationSeconds >= 0,
              trackEndSeconds.isFinite,
              presentationDurationSeconds.isFinite,
              presentationDurationSeconds >= 0,
              baseToleranceSeconds.isFinite,
              baseToleranceSeconds > 0,
              nominalDepthIntervalSeconds.map({ $0.isFinite && $0 > 0 }) ?? true,
              reportedMaxObservedDepthIntervalSeconds.map({
                  $0.isFinite && $0 > 0
              }) ?? true,
              gaps.count <= TAPVideoManifest.DepthCoverage.maximumGapCount else {
            throw Self.invalid("depth timeline configuration is invalid")
        }

        self.trackStartSeconds = trackStartSeconds
        self.trackEndSeconds = trackEndSeconds
        self.presentationDurationSeconds = presentationDurationSeconds
        self.nominalDepthIntervalSeconds = nominalDepthIntervalSeconds
        self.reportedMaxObservedDepthIntervalSeconds = reportedMaxObservedDepthIntervalSeconds
        self.baseToleranceSeconds = baseToleranceSeconds
        self.maximumObservedToleranceSeconds = baseToleranceSeconds
        self.gapIntervals = try gaps.map { gap in
            guard gap.startPTS.timescale > 0,
                  gap.endPTS.timescale > 0 else {
                throw Self.invalid("depth gap timescale is invalid")
            }
            let start = Double(gap.startPTS.value) / Double(gap.startPTS.timescale)
            let end = Double(gap.endPTS.value) / Double(gap.endPTS.timescale)
            guard start.isFinite,
                  end.isFinite,
                  start >= 0,
                  end >= start else {
                throw Self.invalid("depth gap interval is invalid")
            }
            return GapInterval(start: start, end: end)
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start {
                return lhs.start < rhs.start
            }
            return lhs.end < rhs.end
        }
    }

    mutating func observe(
        _ presentationTimeSeconds: Double,
        timestampToleranceSeconds: Double
    ) throws {
        guard presentationTimeSeconds.isFinite,
              presentationTimeSeconds >= 0,
              timestampToleranceSeconds.isFinite,
              timestampToleranceSeconds > 0 else {
            throw Self.invalid("depth metadata PTS is invalid")
        }
        let tolerance = max(baseToleranceSeconds, timestampToleranceSeconds)
        guard presentationTimeSeconds >= trackStartSeconds - tolerance,
              presentationTimeSeconds <= trackEndSeconds + tolerance,
              presentationTimeSeconds <= presentationDurationSeconds + tolerance else {
            throw Self.invalid("depth metadata PTS is outside the signed track duration")
        }

        if let previousPTS {
            guard presentationTimeSeconds > previousPTS else {
                throw Self.invalid("depth metadata PTS must be strictly increasing")
            }
            let interval = presentationTimeSeconds - previousPTS
            actualMaxObservedDepthIntervalSeconds = max(
                actualMaxObservedDepthIntervalSeconds ?? 0,
                interval
            )
            let intervalTolerance = max(
                tolerance,
                previousToleranceSeconds ?? baseToleranceSeconds
            )
            if interval > discontinuityThresholdSeconds {
                let missingStart = min(
                    presentationTimeSeconds,
                    previousPTS + (nominalDepthIntervalSeconds ?? 0)
                )
                try requireGapCoverage(
                    from: missingStart,
                    through: presentationTimeSeconds,
                    toleranceSeconds: intervalTolerance
                )
            }
        } else {
            firstPTS = presentationTimeSeconds
            if presentationTimeSeconds > discontinuityThresholdSeconds {
                try requireGapCoverage(
                    from: 0,
                    through: presentationTimeSeconds,
                    toleranceSeconds: tolerance
                )
            }
        }

        previousPTS = presentationTimeSeconds
        previousToleranceSeconds = tolerance
        maximumObservedToleranceSeconds = max(maximumObservedToleranceSeconds, tolerance)
        observedSampleCount += 1
    }

    func finish() throws {
        guard observedSampleCount > 0,
              firstPTS != nil,
              let previousPTS else {
            throw Self.invalid("depth timeline contains no stored samples")
        }

        let trailingInterval = presentationDurationSeconds - previousPTS
        if trailingInterval > discontinuityThresholdSeconds {
            let missingStart = min(
                presentationDurationSeconds,
                previousPTS + (nominalDepthIntervalSeconds ?? 0)
            )
            try requireGapCoverage(
                from: missingStart,
                through: presentationDurationSeconds,
                toleranceSeconds: previousToleranceSeconds ?? baseToleranceSeconds
            )
        }

        switch (
            actualMaxObservedDepthIntervalSeconds,
            reportedMaxObservedDepthIntervalSeconds
        ) {
        case (nil, nil):
            break
        case let (actual?, reported?) where abs(actual - reported)
            <= maximumObservedToleranceSeconds:
            break
        default:
            throw Self.invalid(
                "depth max observed interval does not match actual stored KLV timing"
            )
        }
    }

    static func validate(
        sampleTimesSeconds: [Double],
        trackStartSeconds: Double,
        trackDurationSeconds: Double,
        presentationDurationSeconds: Double,
        nominalDepthIntervalSeconds: Double?,
        reportedMaxObservedDepthIntervalSeconds: Double?,
        gaps: [TAPVideoManifest.DepthGap],
        timestampToleranceSeconds: Double
    ) throws {
        var policy = try Self(
            trackStartSeconds: trackStartSeconds,
            trackDurationSeconds: trackDurationSeconds,
            presentationDurationSeconds: presentationDurationSeconds,
            nominalDepthIntervalSeconds: nominalDepthIntervalSeconds,
            reportedMaxObservedDepthIntervalSeconds: reportedMaxObservedDepthIntervalSeconds,
            gaps: gaps,
            baseToleranceSeconds: timestampToleranceSeconds
        )
        for sampleTime in sampleTimesSeconds {
            try policy.observe(
                sampleTime,
                timestampToleranceSeconds: timestampToleranceSeconds
            )
        }
        try policy.finish()
    }

    private var discontinuityThresholdSeconds: Double {
        max(2 * (nominalDepthIntervalSeconds ?? 0), 0.1)
    }

    private func requireGapCoverage(
        from requiredStart: Double,
        through requiredEnd: Double,
        toleranceSeconds: Double
    ) throws {
        guard isCovered(
            from: requiredStart,
            through: requiredEnd,
            toleranceSeconds: toleranceSeconds
        ) else {
            throw Self.invalid("actual depth discontinuity is not covered by manifest gaps")
        }
    }

    private func isCovered(
        from requiredStart: Double,
        through requiredEnd: Double,
        toleranceSeconds: Double
    ) -> Bool {
        guard requiredEnd > requiredStart else {
            return true
        }
        var coveredThrough = requiredStart
        for interval in gapIntervals {
            if interval.end < coveredThrough - toleranceSeconds {
                continue
            }
            if interval.start > coveredThrough + toleranceSeconds {
                return false
            }
            coveredThrough = max(coveredThrough, interval.end)
            if coveredThrough >= requiredEnd - toleranceSeconds {
                return true
            }
        }
        return false
    }

    private static func invalid(_ reason: String) -> TAPDepthCaptureError {
        TAPDepthCaptureError.invalidTAPManifest(reason)
    }
}
