//
//  TAPMediaTrackFacts.swift
//  TAPCamDemo
//

import Foundation

/// Value-semantic facts read from a finished media container. Callers apply
/// their own composition policy after inspection; the reader does not assume
/// that audio or timed metadata must be present.
nonisolated struct TAPMediaTrackFacts: Sendable {
    nonisolated struct Timing: Sendable {
        let startSeconds: Double
        let durationSeconds: Double
        let timeScale: Int32
    }

    nonisolated struct Video: Sendable {
        let trackID: Int32
        let codec: String
        let width: Int32
        let height: Int32
        let timing: Timing
        let nominalFrameRate: Double?
    }

    nonisolated struct Audio: Sendable {
        let trackID: Int32
        let codec: String?
        let timing: Timing
        let sampleRate: Double?
        let channelCount: Int?
    }

    nonisolated struct Metadata: Sendable {
        let trackID: Int32
        let codec: String?
        let timing: Timing
    }

    let durationSeconds: Double
    let timeScale: Int32
    let trackCount: Int
    let videoTrackCount: Int
    let audioTrackCount: Int
    let metadataTrackCount: Int
    let video: Video
    let audio: Audio?
    let metadata: Metadata?
}
