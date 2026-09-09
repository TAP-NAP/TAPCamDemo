//
//  TAPVideoPlaybackFetchState.swift
//  TAPCamDemo
//

import Foundation

struct TAPVideoPlaybackFetchState {
    private(set) var phase: MediaFetchPhase<Bool, Bool> = .idle(false)
    private var lastOriginalProgress: Double?

    mutating func begin(hasPreview: Bool) {
        lastOriginalProgress = nil
        phase = .resolving(hasPreview)
    }

    mutating func publishProgress(_ progress: Double?, hasPreview: Bool) {
        if let progress {
            let normalized = min(max(progress, 0), 1)
            lastOriginalProgress = max(lastOriginalProgress ?? 0, normalized)
        }
        phase = .downloadingFromICloud(
            hasPreview,
            progress: lastOriginalProgress
        )
    }

    mutating func publishPreviewAvailability(_ hasPreview: Bool) {
        switch phase {
        case .idle:
            phase = .idle(hasPreview)
        case .resolving:
            phase = .resolving(hasPreview)
        case .localPreview:
            phase = hasPreview ? .localPreview(true) : .idle(false)
        case .cloudOnly:
            phase = .cloudOnly(hasPreview)
        case .downloadingFromICloud(_, let progress):
            phase = .downloadingFromICloud(hasPreview, progress: progress)
        case .ready(let value):
            phase = .ready(value)
        case .failed(_, let reason, let retryable):
            phase = .failed(hasPreview, reason: reason, retryable: retryable)
        }
    }

    mutating func finish() {
        phase = .ready(true)
    }

    mutating func fail(_ failure: MediaFetchFailure, hasPreview: Bool) {
        phase = .failed(
            hasPreview,
            reason: failure,
            retryable: failure.isRetryable
        )
    }

    mutating func cancel(hasPreview: Bool) {
        let wasCloudFetch: Bool
        switch phase {
        case .cloudOnly, .downloadingFromICloud:
            wasCloudFetch = true
        default:
            wasCloudFetch = false
        }
        lastOriginalProgress = nil
        phase = wasCloudFetch ? .cloudOnly(hasPreview) : .idle(hasPreview)
    }

    mutating func reset(hasPreview: Bool, preservingCloudOnly: Bool = false) {
        lastOriginalProgress = nil
        if preservingCloudOnly, case .cloudOnly = phase {
            return
        }
        phase = .idle(hasPreview)
    }

    mutating func cancelLoadAfterTaskCancellation(hasPreview: Bool) {
        if case .downloadingFromICloud = phase {
            phase = .cloudOnly(hasPreview)
        } else {
            phase = .idle(hasPreview)
        }
    }
}
