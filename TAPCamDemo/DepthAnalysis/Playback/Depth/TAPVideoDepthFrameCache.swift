//
//  TAPVideoDepthFrameCache.swift
//  TAPCamDemo
//

import Foundation

@MainActor
final class TAPVideoDepthFrameCache {
    let maximumRetainedBytes: Int
    let lookBehindSeconds: TimeInterval
    let lookAheadSeconds: TimeInterval

    private(set) var frames: [TAPDecodedDepthVideoFrame] = []
    private(set) var retainedByteCount = 0

    init(
        maximumRetainedBytes: Int = TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes,
        lookBehindSeconds: TimeInterval = TAPVideoDepthPlaybackBudget.cacheLookBehindSeconds,
        lookAheadSeconds: TimeInterval = TAPVideoDepthPlaybackBudget.cacheLookAheadSeconds
    ) {
        self.maximumRetainedBytes = min(
            max(0, maximumRetainedBytes),
            TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes
        )
        self.lookBehindSeconds = max(0, lookBehindSeconds)
        self.lookAheadSeconds = max(0, lookAheadSeconds)
    }

    @discardableResult
    func insert(
        _ frame: TAPDecodedDepthVideoFrame,
        around playbackTimeSeconds: Double
    ) -> Bool {
        guard frame.retainedByteCount > 0,
              frame.retainedByteCount <= maximumRetainedBytes else {
            return false
        }

        if let duplicateIndex = frames.firstIndex(where: { $0.cacheMatches(frame) }) {
            retainedByteCount -= frames[duplicateIndex].retainedByteCount
            frames.remove(at: duplicateIndex)
        }
        frames.append(frame)
        retainedByteCount += frame.retainedByteCount
        prune(around: playbackTimeSeconds)

        while retainedByteCount > maximumRetainedBytes,
              let evictionIndex = farthestFrameIndex(from: playbackTimeSeconds) {
            retainedByteCount -= frames[evictionIndex].retainedByteCount
            frames.remove(at: evictionIndex)
        }
        frames.sort { $0.presentationTimeSeconds < $1.presentationTimeSeconds }
        return frames.contains(where: { $0.cacheMatches(frame) })
    }

    func nearestFrame(
        to playbackTimeSeconds: Double,
        staleToleranceSeconds: TimeInterval =
            TAPVideoDepthPlaybackBudget.failSafeFrameStaleToleranceSeconds,
        leadToleranceSeconds: TimeInterval =
            TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds
    ) -> TAPDecodedDepthVideoFrame? {
        let earliest = playbackTimeSeconds - max(0, staleToleranceSeconds)
        let latest = playbackTimeSeconds + max(0, leadToleranceSeconds)
        return frames
            .filter { frame in
                frame.presentationTimeSeconds >= earliest
                    && frame.presentationTimeSeconds <= latest
            }
            .min { lhs, rhs in
                abs(lhs.presentationTimeSeconds - playbackTimeSeconds)
                    < abs(rhs.presentationTimeSeconds - playbackTimeSeconds)
            }
    }

    func prune(around playbackTimeSeconds: Double) {
        guard playbackTimeSeconds.isFinite else {
            clear()
            return
        }
        let earliest = playbackTimeSeconds - lookBehindSeconds
        let latest = playbackTimeSeconds + lookAheadSeconds
        frames.removeAll { frame in
            let shouldRemove = frame.presentationTimeSeconds < earliest
                || frame.presentationTimeSeconds > latest
            if shouldRemove {
                retainedByteCount -= frame.retainedByteCount
            }
            return shouldRemove
        }
        retainedByteCount = max(0, retainedByteCount)
    }

    func clear() {
        frames.removeAll(keepingCapacity: false)
        retainedByteCount = 0
    }

    private func farthestFrameIndex(from playbackTimeSeconds: Double) -> Int? {
        frames.indices.max { lhs, rhs in
            abs(frames[lhs].presentationTimeSeconds - playbackTimeSeconds)
                < abs(frames[rhs].presentationTimeSeconds - playbackTimeSeconds)
        }
    }
}
