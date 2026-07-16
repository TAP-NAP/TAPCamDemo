//
//  TAPVideoContainerValidator.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

nonisolated struct TAPVideoValidatedMedia {
    let asset: AVURLAsset
    let metadataTrack: AVAssetTrack
    let facts: TAPMediaTrackFacts
    let metadataTiming: TAPMediaTrackFacts.Timing
}

nonisolated enum TAPVideoContainerValidator {
    static func validate(
        fileURL: URL,
        manifest: TAPVideoManifest,
        expectedMetadataTrackID: Int32
    ) async throws -> TAPVideoValidatedMedia {
        let asset = AVURLAsset(url: fileURL)
        let facts: TAPMediaTrackFacts
        do {
            facts = try await TAPMediaTrackFactsReader.read(from: asset)
        } catch {
            throw invalid("TAP video media track facts could not be read")
        }

        try validateComposition(facts: facts, manifest: manifest)
        try validateContainerAndTracks(facts: facts, manifest: manifest)

        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        guard let metadataTrack = metadataTracks.first(where: {
            $0.trackID == expectedMetadataTrackID
        }) else {
            throw TAPDepthCaptureError.missingDepthData
        }
        let metadataTiming = try validateMetadata(
            facts.metadata,
            expected: manifest.payload.depthCoverage
        )
        return TAPVideoValidatedMedia(
            asset: asset,
            metadataTrack: metadataTrack,
            facts: facts,
            metadataTiming: metadataTiming
        )
    }

    private static func validateComposition(
        facts: TAPMediaTrackFacts,
        manifest: TAPVideoManifest
    ) throws {
        let audioTrackCount = manifest.payload.audioTrack.status == .captured ? 1 : 0
        guard facts.videoTrackCount == 1,
              facts.metadataTrackCount == 1,
              facts.audioTrackCount == audioTrackCount,
              facts.trackCount == 2 + audioTrackCount else {
            throw invalid("TAP video contains an unexpected media track composition")
        }
    }

    private static func validateContainerAndTracks(
        facts: TAPMediaTrackFacts,
        manifest: TAPVideoManifest
    ) throws {
        let container = manifest.payload.container
        let expectedVideo = manifest.payload.rgbTrack
        guard facts.trackCount == container.trackCount,
              facts.timeScale == container.timeScale,
              approximatelyEqual(
                facts.durationSeconds,
                container.durationSeconds,
                timeScale: container.timeScale
              ),
              let expectedVideoID = expectedVideo.trackID,
              facts.video.trackID == expectedVideoID else {
            throw invalid("container or RGB track facts do not match the MP4")
        }
        try validateVideo(facts.video, expected: expectedVideo)
        try validateAudio(facts.audio, expected: manifest.payload.audioTrack)
    }

    private static func validateVideo(
        _ facts: TAPMediaTrackFacts.Video,
        expected: TAPVideoManifest.RGBTrack
    ) throws {
        let nominalFrameRateMatches = expected.nominalFrameRate.map { expectedRate in
            facts.nominalFrameRate.map {
                abs($0 - expectedRate) <= 0.01
            } ?? false
        } ?? true
        guard facts.codec == expected.codec,
              facts.width == expected.width,
              facts.height == expected.height,
              facts.timing.timeScale == expected.timeScale,
              approximatelyEqual(
                facts.timing.durationSeconds,
                expected.durationSeconds,
                timeScale: expected.timeScale
              ),
              nominalFrameRateMatches else {
            throw invalid("RGB track facts do not match the MP4")
        }
    }

    private static func validateAudio(
        _ facts: TAPMediaTrackFacts.Audio?,
        expected: TAPVideoManifest.AudioTrack
    ) throws {
        switch expected.status {
        case .captured:
            guard let facts,
                  facts.trackID == expected.trackID,
                  let codec = facts.codec,
                  codec == expected.codec,
                  let expectedDuration = expected.durationSeconds,
                  let expectedTimeScale = expected.timeScale,
                  facts.timing.timeScale == expectedTimeScale,
                  approximatelyEqual(
                    facts.timing.durationSeconds,
                    expectedDuration,
                    timeScale: expectedTimeScale
                  ),
                  expected.sampleRate.map({
                    abs((facts.sampleRate ?? -1) - $0) <= 0.01
                  }) ?? true,
                  expected.channelCount.map({ facts.channelCount == $0 }) ?? true else {
                throw invalid("captured audio track facts do not match the MP4")
            }
        case .notCaptured, .unavailable:
            guard facts == nil else {
                throw invalid("manifest omits an audio track present in the MP4")
            }
        }
    }

    private static func validateMetadata(
        _ facts: TAPMediaTrackFacts.Metadata?,
        expected: TAPVideoManifest.DepthCoverage
    ) throws -> TAPMediaTrackFacts.Timing {
        guard let facts,
              facts.trackID == expected.trackID,
              let codec = facts.codec,
              codec == expected.trackCodec,
              let expectedDuration = expected.trackDurationSeconds,
              let expectedTimeScale = expected.trackTimeScale,
              facts.timing.timeScale == expectedTimeScale,
              approximatelyEqual(
                facts.timing.durationSeconds,
                expectedDuration,
                timeScale: expectedTimeScale
              ) else {
            throw invalid("depth metadata track facts do not match the MP4")
        }
        return facts.timing
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

    private static func invalid(_ reason: String) -> TAPDepthCaptureError {
        .invalidTAPManifest(reason)
    }
}
