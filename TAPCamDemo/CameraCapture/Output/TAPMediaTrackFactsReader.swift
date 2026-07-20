//
//  TAPMediaTrackFactsReader.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// The single AVAsset postflight-inspection boundary used by recording,
/// validation, and runtime fixture generation.
nonisolated enum TAPMediaTrackFactsReader {
    static func read(from fileURL: URL) async throws -> TAPMediaTrackFacts {
        try await read(from: AVURLAsset(url: fileURL))
    }

    static func read(from asset: AVAsset) async throws -> TAPMediaTrackFacts {
        async let loadedTracks = asset.load(.tracks)
        async let loadedVideoTracks = asset.loadTracks(withMediaType: .video)
        async let loadedAudioTracks = asset.loadTracks(withMediaType: .audio)
        async let loadedMetadataTracks = asset.loadTracks(withMediaType: .metadata)
        async let loadedDuration = asset.load(.duration)

        let tracks = try await loadedTracks
        let videoTracks = try await loadedVideoTracks
        let audioTracks = try await loadedAudioTracks
        let metadataTracks = try await loadedMetadataTracks
        guard let videoTrack = videoTracks.first else {
            throw inspectionFailure("finished media is missing its video track")
        }

        let duration = try await loadedDuration
        let video = try await videoFacts(for: videoTrack)
        let audio: TAPMediaTrackFacts.Audio?
        if let audioTrack = audioTracks.first {
            audio = try await audioFacts(for: audioTrack)
        } else {
            audio = nil
        }
        let metadata: TAPMediaTrackFacts.Metadata?
        if let metadataTrack = metadataTracks.first {
            metadata = try await metadataFacts(for: metadataTrack)
        } else {
            metadata = nil
        }

        return TAPMediaTrackFacts(
            durationSeconds: max(0, CMTimeGetSeconds(duration)),
            timeScale: duration.timescale,
            trackCount: tracks.count,
            videoTrackCount: videoTracks.count,
            audioTrackCount: audioTracks.count,
            metadataTrackCount: metadataTracks.count,
            video: video,
            audio: audio,
            metadata: metadata
        )
    }

    private static func videoFacts(
        for track: AVAssetTrack
    ) async throws -> TAPMediaTrackFacts.Video {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first else {
            throw inspectionFailure("finished media video format is unavailable")
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let nominalFrameRate = Double(try await track.load(.nominalFrameRate))
        return TAPMediaTrackFacts.Video(
            trackID: track.trackID,
            codec: TAPFourCharCode.string(
                from: CMFormatDescriptionGetMediaSubType(description)
            ),
            width: dimensions.width,
            height: dimensions.height,
            timing: try await trackTiming(track),
            nominalFrameRate: nominalFrameRate > 0 ? nominalFrameRate : nil
        )
    }

    private static func audioFacts(
        for track: AVAssetTrack
    ) async throws -> TAPMediaTrackFacts.Audio {
        let descriptions = try await track.load(.formatDescriptions)
        let description = descriptions.first
        let streamDescription = description.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        return TAPMediaTrackFacts.Audio(
            trackID: track.trackID,
            codec: description.map {
                TAPFourCharCode.string(from: CMFormatDescriptionGetMediaSubType($0))
            },
            timing: try await trackTiming(track),
            sampleRate: streamDescription?.mSampleRate,
            channelCount: streamDescription.map { Int($0.mChannelsPerFrame) }
        )
    }

    private static func metadataFacts(
        for track: AVAssetTrack
    ) async throws -> TAPMediaTrackFacts.Metadata {
        let descriptions = try await track.load(.formatDescriptions)
        return TAPMediaTrackFacts.Metadata(
            trackID: track.trackID,
            codec: descriptions.first.map {
                TAPFourCharCode.string(from: CMFormatDescriptionGetMediaSubType($0))
            },
            timing: try await trackTiming(track)
        )
    }

    private static func trackTiming(
        _ track: AVAssetTrack
    ) async throws -> TAPMediaTrackFacts.Timing {
        async let loadedTimeRange = track.load(.timeRange)
        async let loadedNaturalTimeScale = track.load(.naturalTimeScale)
        let timeRange = try await loadedTimeRange
        let naturalTimeScale = try await loadedNaturalTimeScale
        let startSeconds = CMTimeGetSeconds(timeRange.start)
        let durationSeconds = CMTimeGetSeconds(timeRange.duration)
        let timeScale = naturalTimeScale > 0
            ? naturalTimeScale
            : timeRange.duration.timescale
        guard startSeconds.isFinite,
              durationSeconds.isFinite,
              durationSeconds >= 0,
              timeScale > 0 else {
            throw inspectionFailure("finished media track timing is invalid")
        }
        return TAPMediaTrackFacts.Timing(
            startSeconds: startSeconds,
            durationSeconds: durationSeconds,
            timeScale: timeScale
        )
    }

    private static func inspectionFailure(_ reason: String) -> TAPDepthCaptureError {
        .videoRecordingFailed(reason)
    }
}
