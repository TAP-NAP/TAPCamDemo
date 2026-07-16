//
//  TAPVideoDepthTimelineValidator.swift
//  TAPCamDemo
//

import Foundation

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
        .invalidTAPManifest(reason)
    }
}
