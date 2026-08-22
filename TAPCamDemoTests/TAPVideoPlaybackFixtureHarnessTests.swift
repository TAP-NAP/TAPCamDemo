//
//  TAPVideoPlaybackFixtureHarnessTests.swift
//  TAPCamDemoTests
//

#if DEBUG
import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

@Suite("TAP video runtime fixture harness")
struct TAPVideoPlaybackFixtureHarnessTests {
    @Test("small fixture is generated at runtime with manifest and no sidecar binary")
    func runtimeGeneratedArtifact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TAPVideoFixtureHarnessTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(
            scenario: .rotation90,
            outputDirectoryURL: directory
        )

        #expect(artifact.fileURL == directory.appendingPathComponent("artifact.mp4"))
        #expect(FileManager.default.fileExists(atPath: artifact.fileURL.path))
        #expect(artifact.manifest.schema.id == TAPVideoManifest.schemaIdentifier)
        #expect(artifact.manifest.schema.version == 2)
        #expect(artifact.manifest.proofs.isEmpty)
        #expect(artifact.manifest.payload.depthCoverage.sampleCount == 30)
        #expect(artifact.manifest.payload.spatialRegistration.status == .registered)
        #expect(artifact.manifest.payload.container.trackCount == 2)
        #expect(artifact.manifest.payload.rgbTrack.trackID != nil)
        #expect(artifact.manifest.payload.depthCoverage.trackID != nil)
        #expect(
            artifact.manifest.payload.rgbTrack.trackID
                != artifact.manifest.payload.depthCoverage.trackID
        )
        #expect(try TAPVideoManifestBox.decodedManifest(fromFileAt: artifact.fileURL) == artifact.manifest)

        let asset = AVURLAsset(url: artifact.fileURL)
        let duration = try await asset.load(.duration)
        #expect(abs(CMTimeGetSeconds(duration) - 2) < 0.01)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        #expect(videoTracks.count == 1)
        #expect(metadataTracks.count == 1)
        let videoTrack = try #require(videoTracks.first)
        let metadataTrack = try #require(metadataTracks.first)
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let videoNaturalTimeScale = try await videoTrack.load(.naturalTimeScale)
        let metadataTimeRange = try await metadataTrack.load(.timeRange)
        let metadataNaturalTimeScale = try await metadataTrack.load(.naturalTimeScale)
        let metadataDescriptions = try await metadataTrack.load(.formatDescriptions)
        let metadataDescription = try #require(metadataDescriptions.first)
        let manifestDepthDuration = try #require(
            artifact.manifest.payload.depthCoverage.trackDurationSeconds
        )

        #expect(
            abs(
                artifact.manifest.payload.rgbTrack.durationSeconds
                    - CMTimeGetSeconds(videoTimeRange.duration)
            ) < 0.000_001
        )
        #expect(
            artifact.manifest.payload.rgbTrack.timeScale
                == (videoNaturalTimeScale > 0
                    ? videoNaturalTimeScale
                    : videoTimeRange.duration.timescale)
        )
        #expect(
            abs(
                manifestDepthDuration - CMTimeGetSeconds(metadataTimeRange.duration)
            ) < 0.000_001
        )
        #expect(
            artifact.manifest.payload.depthCoverage.trackTimeScale
                == (metadataNaturalTimeScale > 0
                    ? metadataNaturalTimeScale
                    : metadataTimeRange.duration.timescale)
        )
        #expect(
            artifact.manifest.payload.depthCoverage.trackCodec
                == TAPFourCharCode.string(
                    from: CMFormatDescriptionGetMediaSubType(metadataDescription)
                )
        )
        try await TAPVideoDepthTrackValidator.validate(
            fileURL: artifact.fileURL,
            manifest: artifact.manifest
        )

        var manifestObject = try #require(
            try JSONSerialization.jsonObject(
                with: TAPVideoManifestEncoder.manifestData(artifact.manifest)
            ) as? [String: Any]
        )
        var payloadObject = try #require(manifestObject["payload"] as? [String: Any])
        var depthCoverageObject = try #require(
            payloadObject["depthCoverage"] as? [String: Any]
        )
        depthCoverageObject["sampleCount"] = artifact.manifest.payload.depthCoverage.sampleCount + 1
        payloadObject["depthCoverage"] = depthCoverageObject
        manifestObject["payload"] = payloadObject
        let mismatchedManifest = try JSONDecoder().decode(
            TAPVideoManifest.self,
            from: JSONSerialization.data(withJSONObject: manifestObject)
        )
        await #expect(throws: TAPDepthCaptureError.self) {
            try await TAPVideoDepthTrackValidator.validate(
                fileURL: artifact.fileURL,
                manifest: mismatchedManifest
            )
        }

        manifestObject = try #require(
            try JSONSerialization.jsonObject(
                with: TAPVideoManifestEncoder.manifestData(artifact.manifest)
            ) as? [String: Any]
        )
        payloadObject = try #require(manifestObject["payload"] as? [String: Any])
        var registrationObject = try #require(
            payloadObject["spatialRegistration"] as? [String: Any]
        )
        var calibrationCoverageObject = try #require(
            registrationObject["calibrationCoverage"] as? [String: Any]
        )
        calibrationCoverageObject["indexedSampleCount"] = artifact.manifest.payload
            .depthCoverage.sampleCount - 1
        calibrationCoverageObject["missingCalibrationSampleCount"] = 1
        registrationObject["calibrationCoverage"] = calibrationCoverageObject
        payloadObject["spatialRegistration"] = registrationObject
        manifestObject["payload"] = payloadObject
        let mismatchedCalibrationCoverageManifest = try JSONDecoder().decode(
            TAPVideoManifest.self,
            from: JSONSerialization.data(withJSONObject: manifestObject)
        )
        await #expect(throws: TAPDepthCaptureError.self) {
            try await TAPVideoDepthTrackValidator.validate(
                fileURL: artifact.fileURL,
                manifest: mismatchedCalibrationCoverageManifest
            )
        }
    }
}
#endif
