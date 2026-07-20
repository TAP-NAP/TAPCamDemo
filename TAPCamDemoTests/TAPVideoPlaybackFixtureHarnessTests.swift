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
    @Test("scenario matrix covers every release-gate presentation case")
    func scenarioMatrix() {
        #expect(Set(TAPVideoPlaybackFixtureScenario.allCases.map(\.rawValue)) == [
            "rotation-0",
            "rotation-90",
            "rotation-180",
            "rotation-270",
            "mirrored",
            "aspect-4x3",
            "aspect-16x9",
            "clean-aperture",
            "depth-gap",
            "seek-discontinuity",
            "performance-playback-15s",
            "metadata-stress-180s"
        ])

        #expect(TAPVideoPlaybackFixtureScenario.rotation0.specification.rotationDegrees == 0)
        #expect(TAPVideoPlaybackFixtureScenario.rotation90.specification.rotationDegrees == 90)
        #expect(TAPVideoPlaybackFixtureScenario.rotation180.specification.rotationDegrees == 180)
        #expect(TAPVideoPlaybackFixtureScenario.rotation270.specification.rotationDegrees == 270)
        #expect(TAPVideoPlaybackFixtureScenario.mirrored.specification.mirrored)
    }

    @Test("aspect and clean-aperture fixtures remain distinct")
    func aspectAndCleanApertureContracts() {
        let fourByThree = TAPVideoPlaybackFixtureScenario.aspect4x3.specification
        #expect(fourByThree.codedWidth * 3 == fourByThree.codedHeight * 4)

        let sixteenByNine = TAPVideoPlaybackFixtureScenario.aspect16x9.specification
        #expect(sixteenByNine.codedWidth * 9 == sixteenByNine.codedHeight * 16)

        let cleanAperture = TAPVideoPlaybackFixtureScenario.cleanAperture.specification
        #expect(cleanAperture.presentationAperture.width < cleanAperture.codedWidth)
        #expect(cleanAperture.presentationAperture.height < cleanAperture.codedHeight)
        #expect(cleanAperture.presentationAperture == .init(x: 8, y: 6, width: 64, height: 36))
    }

    @Test("gap, seek, and 180-second stress counts are deterministic")
    func temporalContracts() {
        let gap = TAPVideoPlaybackFixtureScenario.depthGap.specification
        #expect(gap.expectedDepthFrameCount == 36)
        #expect(gap.expectedVideoFrameCount == 45)
        #expect(gap.automaticSeekSeconds == 1.3)
        #expect(
            abs((gap.maxObservedStoredDepthIntervalSeconds ?? 0) - (10.0 / 15.0))
                < 0.000_001
        )

        let seek = TAPVideoPlaybackFixtureScenario.seekDiscontinuity.specification
        #expect(seek.automaticSeekSeconds == 4.5)
        #expect(seek.expectedDepthFrameCount == 90)

        let performance = TAPVideoPlaybackFixtureScenario.performancePlayback15Seconds.specification
        #expect(performance.durationSeconds == 15)
        #expect(performance.videoFramesPerSecond == 30)
        #expect(performance.depthFramesPerSecond == 30)
        #expect(performance.expectedVideoFrameCount == 450)
        #expect(performance.expectedDepthFrameCount == 450)

        let stress = TAPVideoPlaybackFixtureScenario.metadataStress180Seconds.specification
        #expect(stress.durationSeconds == 180)
        #expect(stress.expectedVideoFrameCount == 180)
        #expect(stress.expectedDepthFrameCount == 5_400)
    }

    @Test("launch configuration is opt-in and rejects unknown scenarios")
    func launchConfiguration() {
        #expect(TAPVideoPlaybackFixtureLaunchConfiguration.parse(
            arguments: ["TAPCamDemo"],
            environment: [:]
        ) == nil)
        #expect(TAPVideoPlaybackFixtureLaunchConfiguration.parse(
            arguments: ["TAPCamDemo", TAPVideoPlaybackFixtureLaunchConfiguration.enableArgument],
            environment: [:]
        )?.scenario == .rotation0)
        #expect(TAPVideoPlaybackFixtureLaunchConfiguration.parse(
            arguments: [
                "TAPCamDemo",
                TAPVideoPlaybackFixtureLaunchConfiguration.scenarioArgument,
                TAPVideoPlaybackFixtureScenario.depthGap.rawValue
            ],
            environment: [:]
        )?.scenario == .depthGap)
        #expect(TAPVideoPlaybackFixtureLaunchConfiguration.parse(
            arguments: [
                "TAPCamDemo",
                "\(TAPVideoPlaybackFixtureLaunchConfiguration.scenarioArgument)=unknown"
            ],
            environment: [:]
        ) == nil)
    }

    @Test("launch configuration validates autoplay and deterministic seek schedule")
    func launchPlaybackOverrides() throws {
        let configuration = try #require(
            TAPVideoPlaybackFixtureLaunchConfiguration.parse(
                arguments: [
                    "TAPCamDemo",
                    TAPVideoPlaybackFixtureLaunchConfiguration.enableArgument
                ],
                environment: [
                    TAPVideoPlaybackFixtureLaunchConfiguration.autoPlayEnvironmentKey: "1",
                    TAPVideoPlaybackFixtureLaunchConfiguration.seekScheduleEnvironmentKey:
                        "3, 10,6"
                ]
            )
        )
        #expect(configuration.autoPlay)
        #expect(configuration.seekScheduleSeconds == [3, 10, 6])
        #expect(!configuration.usesAccessibilityDynamicType)

        let accessibilityConfiguration = try #require(
            TAPVideoPlaybackFixtureLaunchConfiguration.parse(
                arguments: [
                    "TAPCamDemo",
                    TAPVideoPlaybackFixtureLaunchConfiguration.enableArgument
                ],
                environment: [
                    TAPVideoPlaybackFixtureLaunchConfiguration
                        .accessibilityDynamicTypeEnvironmentKey: "1"
                ]
            )
        )
        #expect(accessibilityConfiguration.usesAccessibilityDynamicType)

        #expect(TAPVideoPlaybackFixtureLaunchConfiguration.parse(
            arguments: [
                "TAPCamDemo",
                TAPVideoPlaybackFixtureLaunchConfiguration.enableArgument
            ],
            environment: [
                TAPVideoPlaybackFixtureLaunchConfiguration.seekScheduleEnvironmentKey:
                    "3,invalid,6"
            ]
        ) == nil)
        #expect(TAPVideoPlaybackFixtureLaunchConfiguration.parse(
            arguments: [
                "TAPCamDemo",
                TAPVideoPlaybackFixtureLaunchConfiguration.enableArgument
            ],
            environment: [
                TAPVideoPlaybackFixtureLaunchConfiguration.seekScheduleEnvironmentKey:
                    "3,-1,6"
            ]
        ) == nil)
    }

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
