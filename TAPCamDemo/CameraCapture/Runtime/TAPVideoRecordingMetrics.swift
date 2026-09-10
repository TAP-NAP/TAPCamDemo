//
//  TAPVideoRecordingMetrics.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Keeps the signed depth-gap table compact under sustained output pressure.
nonisolated struct TAPDepthGapAccumulator: Sendable {
    static let maximumGapCount = TAPVideoManifest.DepthCoverage.maximumGapCount

    private(set) var gaps: [TAPVideoManifest.DepthGap] = []

    mutating func record(_ gap: TAPVideoManifest.DepthGap) {
        if let last = gaps.last,
           last.reason == gap.reason,
           Self.canMerge(last, with: gap) {
            gaps[gaps.count - 1] = Self.merged(last, gap, reason: last.reason)
            return
        }
        guard gaps.count >= Self.maximumGapCount else {
            gaps.append(gap)
            return
        }
        let last = gaps[gaps.count - 1]
        gaps[gaps.count - 1] = Self.merged(last, gap, reason: .boundedAggregation)
    }

    private static func canMerge(
        _ lhs: TAPVideoManifest.DepthGap,
        with rhs: TAPVideoManifest.DepthGap
    ) -> Bool {
        guard lhs.endPTS.timescale > 0, rhs.startPTS.timescale > 0 else {
            return false
        }
        let lhsEnd = CMTime(value: lhs.endPTS.value, timescale: lhs.endPTS.timescale)
        let rhsStart = CMTime(value: rhs.startPTS.value, timescale: rhs.startPTS.timescale)
        return CMTimeCompare(rhsStart, lhsEnd) <= 0
    }

    private static func merged(
        _ lhs: TAPVideoManifest.DepthGap,
        _ rhs: TAPVideoManifest.DepthGap,
        reason: TAPVideoManifest.DepthGapReason
    ) -> TAPVideoManifest.DepthGap {
        TAPVideoManifest.DepthGap(
            reason: reason,
            startPTS: compare(lhs.startPTS, rhs.startPTS) <= 0
                ? lhs.startPTS : rhs.startPTS,
            endPTS: compare(lhs.endPTS, rhs.endPTS) >= 0
                ? lhs.endPTS : rhs.endPTS,
            nearestStartRGBFrame: lhs.nearestStartRGBFrame ?? rhs.nearestStartRGBFrame,
            nearestEndRGBFrame: rhs.nearestEndRGBFrame ?? lhs.nearestEndRGBFrame
        )
    }

    private static func compare(
        _ lhs: TAPVideoManifest.MediaTime,
        _ rhs: TAPVideoManifest.MediaTime
    ) -> Int32 {
        guard lhs.timescale > 0, rhs.timescale > 0 else {
            if lhs.value == rhs.value { return 0 }
            return lhs.value < rhs.value ? -1 : 1
        }
        return CMTimeCompare(
            CMTime(value: lhs.value, timescale: lhs.timescale),
            CMTime(value: rhs.value, timescale: rhs.timescale)
        )
    }
}

/// Converts capture-device timestamps into the media timeline signed by the
/// TAP manifest and embedded in each KLV frame.
nonisolated enum TAPVideoCaptureTimeline {
    static let timescale: CMTimeScale = 600
    static let tick = CMTime(value: 1, timescale: timescale)

    static func relativeMediaTime(
        _ timestamp: CMTime,
        from origin: CMTime
    ) -> TAPVideoManifest.MediaTime? {
        guard timestamp.isValid,
              origin.isValid,
              !timestamp.isIndefinite,
              !origin.isIndefinite,
              timestamp.timescale > 0,
              origin.timescale > 0 else {
            return nil
        }
        let delta = CMTimeSubtract(timestamp, origin)
        guard delta.isValid, !delta.isIndefinite else {
            return nil
        }
        let nonnegativeDelta = CMTimeCompare(delta, .zero) < 0 ? .zero : delta
        let normalized = CMTimeConvertScale(
            nonnegativeDelta,
            timescale: timescale,
            method: .default
        )
        guard normalized.isValid,
              !normalized.isIndefinite,
              normalized.timescale > 0 else {
            return nil
        }
        return TAPVideoManifest.MediaTime(
            value: normalized.value,
            timescale: normalized.timescale
        )
    }

    static func depthGap(
        reason: TAPVideoManifest.DepthGapReason,
        start: CMTime,
        end: CMTime,
        relativeTo origin: CMTime,
        nearestStartRGBFrame: Int?,
        nearestEndRGBFrame: Int?
    ) -> TAPVideoManifest.DepthGap? {
        guard start.isValid,
              end.isValid,
              CMTimeCompare(end, start) >= 0,
              let startPTS = relativeMediaTime(start, from: origin),
              let endPTS = relativeMediaTime(end, from: origin),
              CMTimeCompare(
                CMTime(value: endPTS.value, timescale: endPTS.timescale),
                CMTime(value: startPTS.value, timescale: startPTS.timescale)
              ) >= 0 else {
            return nil
        }
        return TAPVideoManifest.DepthGap(
            reason: reason,
            startPTS: startPTS,
            endPTS: endPTS,
            nearestStartRGBFrame: nearestStartRGBFrame,
            nearestEndRGBFrame: nearestEndRGBFrame
        )
    }

    static func absoluteMediaEndTime(
        origin: CMTime,
        durationSeconds: Double,
        lastSampleTime: CMTime?
    ) -> CMTime? {
        guard origin.isValid,
              !origin.isIndefinite,
              origin.timescale > 0,
              durationSeconds.isFinite,
              durationSeconds >= 0 else {
            return nil
        }
        let trackEnd = CMTimeAdd(
            origin,
            CMTime(seconds: durationSeconds, preferredTimescale: timescale)
        )
        guard trackEnd.isValid, !trackEnd.isIndefinite else {
            return nil
        }
        guard let lastSampleTime,
              lastSampleTime.isValid,
              !lastSampleTime.isIndefinite else {
            return trackEnd
        }
        return CMTimeCompare(lastSampleTime, trackEnd) > 0
            ? lastSampleTime : trackEnd
    }
}

/// Stable, bounded calibration dictionary referenced by KLV frame indices.
nonisolated struct TAPVideoCalibrationTable: Sendable {
    static let maximumEntryCount = TAPVideoManifest.SpatialRegistration.maximumCalibrationCount

    private(set) var entries: [TAPVideoManifest.CameraCalibration] = []
    private(set) var didOverflow = false

    mutating func index(
        for calibration: TAPVideoManifest.CameraCalibration?
    ) -> UInt32? {
        guard let calibration else {
            return nil
        }
        if let existingIndex = entries.firstIndex(of: calibration) {
            return UInt32(existingIndex)
        }
        guard entries.count < Self.maximumEntryCount else {
            didOverflow = true
            return nil
        }
        entries.append(calibration)
        return UInt32(entries.count - 1)
    }
}

/// All counters, timestamps, gap accounting, calibration coverage, and
/// connection observations produced while one recording is active.
nonisolated struct TAPVideoRecordingMetrics {
    var usesSynchronizedRGBDepthOutput = false
    var observedSynchronizedRGBDepthPair = false
    var appliedVideoRotationAngle: CGFloat?
    var appliedVideoMirrored = false
    var appliedVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off
    var observedDepthConnectionConfiguration = false
    var appliedDepthRotationAngle: CGFloat?
    var appliedDepthMirrored = false

    var stopReason: TAPVideoManifest.StopReason = .userStop
    var firstVideoTime: CMTime?
    var lastVideoTime: CMTime?
    var firstVideoFormatDescription: CMFormatDescription?
    var videoFrameCount = 0
    var videoDropCount = 0
    var audioSampleCount = 0
    var audioDropCount = 0
    var depthOutputSampleCount = 0
    var depthOutputDropCount = 0
    var depthSampleCount = 0
    var depthFrameIndex = 0
    var depthSamplesBeforeVideoStart = 0
    var depthMetadataDropCount = 0
    var depthEncodingDropCount = 0
    var depthDeliveredSampleCount = 0
    var firstDepthFormat: TAPVideoManifest.DepthFormat?
    var depthFormatChanged = false
    var depthCalibrationTable = TAPVideoCalibrationTable()
    var depthSamplesWithCalibrationIndex = 0
    var depthSamplesMissingCalibration = 0
    var depthSamplesWithUnindexedCalibration = 0
    var depthGapAccumulator = TAPDepthGapAccumulator()
    var lastDepthTime: CMTime?
    var maxObservedDepthIntervalSeconds: Double?
    var maxObservedRGBDepthDeltaSeconds: Double?

    var recordedDurationSeconds: Double {
        guard let firstVideoTime, let lastVideoTime else {
            return 0
        }
        return max(0, CMTimeGetSeconds(CMTimeSubtract(lastVideoTime, firstVideoTime)))
    }

    var droppedDepthSampleCount: Int {
        depthOutputDropCount + depthMetadataDropCount + depthEncodingDropCount
    }

    mutating func recordDepthGap(
        reason: TAPVideoManifest.DepthGapReason,
        start: CMTime,
        end: CMTime,
        nearestStartRGBFrame: Int? = nil,
        nearestEndRGBFrame: Int? = nil
    ) {
        guard let firstVideoTime else {
            return
        }
        let nearestRGBFrame = videoFrameCount > 0 ? videoFrameCount - 1 : nil
        guard let gap = TAPVideoCaptureTimeline.depthGap(
            reason: reason,
            start: start,
            end: end,
            relativeTo: firstVideoTime,
            nearestStartRGBFrame: nearestStartRGBFrame ?? nearestRGBFrame,
            nearestEndRGBFrame: nearestEndRGBFrame ?? nearestRGBFrame
        ) else {
            return
        }
        depthGapAccumulator.record(gap)
    }

    func finalizedDepthGaps(
        videoDurationSeconds: Double,
        cadenceThresholdSeconds: Double
    ) -> [TAPVideoManifest.DepthGap] {
        guard depthSampleCount > 0,
              let firstVideoTime,
              let lastDepthTime,
              let videoEndTime = TAPVideoCaptureTimeline.absoluteMediaEndTime(
                origin: firstVideoTime,
                durationSeconds: videoDurationSeconds,
                lastSampleTime: lastVideoTime
              ) else {
            return depthGapAccumulator.gaps
        }
        let trailingInterval = max(
            0,
            CMTimeGetSeconds(CMTimeSubtract(videoEndTime, lastDepthTime))
        )
        guard trailingInterval > cadenceThresholdSeconds,
              let trailingGap = TAPVideoCaptureTimeline.depthGap(
                reason: .silentCadence,
                start: CMTimeAdd(lastDepthTime, TAPVideoCaptureTimeline.tick),
                end: videoEndTime,
                relativeTo: firstVideoTime,
                nearestStartRGBFrame: videoFrameCount > 0 ? videoFrameCount - 1 : nil,
                nearestEndRGBFrame: videoFrameCount > 0 ? videoFrameCount - 1 : nil
              ) else {
            return depthGapAccumulator.gaps
        }
        var accumulator = depthGapAccumulator
        accumulator.record(trailingGap)
        return accumulator.gaps
    }
}
