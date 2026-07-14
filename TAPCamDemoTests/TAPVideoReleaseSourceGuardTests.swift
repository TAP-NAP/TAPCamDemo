//
//  TAPVideoReleaseSourceGuardTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing

@Suite("TAP video release source guard")
struct TAPVideoReleaseSourceGuardTests {
    private static let tapVideoOnlySourcePaths = [
        "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorder.swift",
        "TAPCamDemo/CameraCapture/Output/TAPBMFFStreamingFile.swift",
        "TAPCamDemo/CameraCapture/Output/TAPDepthFrameCodec.swift",
        "TAPCamDemo/CameraCapture/Output/TAPDepthKLV.swift",
        "TAPCamDemo/CameraCapture/Output/TAPVideoDepthTrackValidator.swift",
        "TAPCamDemo/CameraCapture/Output/TAPVideoManifestBox.swift",
        "TAPCamDemo/DepthAnalysis/TAPVideoDepthPlaybackSupport.swift",
        "TAPCamDemo/DepthAnalysis/TAPVideoDepthPlaybackView.swift",
        "TAPCamDemo/TAPLibrary/TAPVideoPhotosReadbackValidator.swift"
    ]

    private static let wholeFileDataPattern = #"Data\s*\(\s*contentsOf\s*:"#
    private static let videoNamedWholeFileDataPattern =
        #"(?i)Data\s*\(\s*contentsOf\s*:\s*(?!pairedVideoURL\b)[^)]{0,240}\b(?:mp4\w*|video(?:File|Artifact)?URL)\b[^)]*\)"#
    private static let explicitlyVideoNamedSubdataPattern =
        #"(?i)\b(?:mp4\w*|artifact\w*|video\w*)\.subdata\s*\("#
    private static let nearWholeDataSubdataPatterns = [
        #"\bdata\.subdata\s*\(\s*in:\s*0\s*\.\.<\s*data\.count\s*\)"#,
        #"\bdata\.subdata\s*\(\s*in:\s*0\s*\.\.<[^)]*(?:excluded|proof|slot)[^)]*lowerBound[^)]*\)"#,
        #"\bdata\.subdata\s*\(\s*in:[^)]*(?:excluded|proof|slot)[^)]*upperBound\s*\.\.<\s*data\.count[^)]*\)"#
    ]

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func twoDRegistrationDoesNotDependOnMetricCalibrationCompleteness() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorder.swift"
        )
        let registrationSource = try #require(TAPCamDemoTestSourceInspection.substring(
            in: source,
            from: "    private func spatialRegistration(",
            to: "    private static func normalizedQuarterTurn("
        ))

        #expect(!registrationSource.contains("!depthCalibrationTable.didOverflow"))
        #expect(!registrationSource.contains("sawDepthSampleWithoutCalibration"))
        #expect(!registrationSource.contains("isValidCalibration"))
        #expect(registrationSource.contains("calibrationCoverage: calibrationCoverage"))
        #expect(registrationSource.contains("registrationFailures"))
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func videoRecordingGraphPinsStabilizationOffInWarmAndColdPaths() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let marker = "connection.preferredVideoStabilizationMode = .off"
        let occurrenceCount = source.components(separatedBy: marker).count - 1

        #expect(occurrenceCount == 2)
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func calibrationTableCommitsOnlyAfterMetadataAppendSucceeds() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorder.swift"
        )
        let reservation = try #require(source.range(
            of: "var committedCalibrationTable = depthCalibrationTable"
        ))
        let append = try #require(source.range(
            of: "guard metadataAdaptor.append(group) else"
        ))
        let commit = try #require(source.range(
            of: "depthCalibrationTable = committedCalibrationTable"
        ))

        #expect(reservation.lowerBound < append.lowerBound)
        #expect(append.lowerBound < commit.lowerBound)
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func productionTargetContainsNoLegacyTAPVideoArtifactNames() throws {
        let productionPaths = try TAPCamDemoTestSourceInspection
            .swiftSourceRelativePathsRecursively(under: "TAPCamDemo")
        #expect(!productionPaths.isEmpty)

        for path in productionPaths {
            let source = try TAPCamDemoTestSourceInspection.source(relativePath: path)
            for legacyName in ["depth-preview.mp4", "unsigned.mp4", "signed.mp4"] {
                #expect(
                    !source.contains(legacyName),
                    "Legacy TAP video artifact \(legacyName) reappeared in \(path)"
                )
            }
        }
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func tapVideoFilePathsNeverLoadAWholeMP4IntoData() throws {
        for path in Self.tapVideoOnlySourcePaths {
            let source = try TAPCamDemoTestSourceInspection.source(relativePath: path)
            #expect(
                !Self.matches(Self.wholeFileDataPattern, in: source),
                "Whole-file Data loading is forbidden in TAP video source \(path)"
            )
        }

        let productionPaths = try TAPCamDemoTestSourceInspection
            .swiftSourceRelativePathsRecursively(under: "TAPCamDemo")
        for path in productionPaths {
            let source = try TAPCamDemoTestSourceInspection.source(relativePath: path)
            #expect(
                !Self.matches(Self.videoNamedWholeFileDataPattern, in: source),
                "A video-named production resource is loaded into Data in \(path)"
            )
        }

        let digestSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/CaptureContentDigest.swift"
        )
        let makeVideoSource = try #require(TAPCamDemoTestSourceInspection.substring(
            in: digestSource,
            from: "    static func makeVideo(",
            to: "    static func makeWithMetrics("
        ))
        #expect(!Self.matches(Self.wholeFileDataPattern, in: makeVideoSource))
        for forbiddenLegacyAPI in [
            "mp4Data: Data",
            "ensuringEmptyBMFFSlot(in data: Data)",
            "intoBMFF data: Data",
            "proofEnvelopeData(fromBMFF data: Data)",
            "locateBMFF(in data: Data)",
            "data + bmffProofBox"
        ] {
            #expect(
                !digestSource.contains(forbiddenLegacyAPI),
                "Legacy whole-MP4 Data API reappeared: \(forbiddenLegacyAPI)"
            )
        }
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func tapVideoFilePathsContainNoNearWholeMP4SubdataCopies() throws {
        for path in Self.tapVideoOnlySourcePaths {
            let source = try TAPCamDemoTestSourceInspection.source(relativePath: path)
            #expect(
                !Self.matches(Self.explicitlyVideoNamedSubdataPattern, in: source),
                "Video-identified Data is copied with subdata in \(path)"
            )
            for pattern in Self.nearWholeDataSubdataPatterns {
                #expect(
                    !Self.matches(pattern, in: source),
                    "Near-whole Data subdata copy reappeared in TAP video source \(path)"
                )
            }
        }

        let digestSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/CaptureContentDigest.swift"
        )
        let makeVideoSource = try #require(TAPCamDemoTestSourceInspection.substring(
            in: digestSource,
            from: "    static func makeVideo(",
            to: "    static func makeWithMetrics("
        ))
        #expect(!Self.matches(Self.explicitlyVideoNamedSubdataPattern, in: makeVideoSource))
        for pattern in Self.nearWholeDataSubdataPatterns {
            #expect(!Self.matches(pattern, in: makeVideoSource))
        }
    }

    private static func matches(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}
