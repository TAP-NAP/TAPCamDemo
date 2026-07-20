//
//  DepthAnalysisErrorPresentationTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct DepthAnalysisErrorPresentationTests {
    @Test func depthAnalysisErrorPresentationKeepsAnalysisLoadCopyFixedAndPublicSafe() throws {
        let sensitiveError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotOpenFile,
            userInfo: [
                NSLocalizedDescriptionKey: "Reader failed at /private/tmp/capture.heic https://example.test/source"
            ]
        )
        let generic = DepthAnalysisErrorPresentation.analysisLoadError(for: sensitiveError)
        let pending = DepthAnalysisErrorPresentation.analysisLoadError(
            for: DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
        )

        #expect(generic.title == "Unable to analyze image")
        #expect(generic.message == "This image cannot be analyzed as a TAP depth photo.")
        #expect(generic.systemImage == "exclamationmark.triangle")
        #expect(!generic.message.contains("/private/tmp/capture.heic"))
        #expect(!generic.message.contains("https://example.test/source"))

        #expect(pending.title == "Image unavailable")
        #expect(pending.message == "Temporarily not available. Return to TAP Library; it will refresh automatically.")
        #expect(pending.systemImage == "photo.badge.exclamationmark")
    }

    @Test func depthAnalysisErrorPresentationKeepsAlbumCopyFixedAndPublicSafe() throws {
        let sensitiveError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [
                NSLocalizedDescriptionKey: "Missing asset photos://private-asset at /private/var/mobile/TAPCamDepth"
            ]
        )
        let fullLoadMessage = DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: sensitiveError)
        let photosMessage = DepthAnalysisErrorPresentation.emptyAlbumPhotosErrorMessage(for: sensitiveError)

        #expect(fullLoadMessage == "Unable to load TAP Library. Check Photos access and try again.")
        #expect(photosMessage == "Unable to read the TAPCamDepth album. Check Photos access and try again.")
        #expect(!fullLoadMessage.contains("photos://private-asset"))
        #expect(!fullLoadMessage.contains("/private/var/mobile"))
        #expect(!photosMessage.contains("photos://private-asset"))
        #expect(!photosMessage.contains("/private/var/mobile"))
    }

    @Test func depthAnalysisErrorPresentationKeepsPlaneSelectionCopyFixedAndPublicSafe() throws {
        let sensitiveError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadCorruptFileError,
            userInfo: [
                NSLocalizedDescriptionKey: "Plane failed for asset local://hidden at /private/tmp/plane-cache"
            ]
        )
        let genericMessage = DepthAnalysisErrorPresentation.planeSelectionErrorMessage(for: sensitiveError)
        let typedMessages: [(TAPPlaneGrowthError, String)] = [
            (.invalidSeed, DepthAnalysisErrorPresentation.planeInvalidSeedMessage),
            (.cameraCalibrationMissing, DepthAnalysisErrorPresentation.planeCalibrationMissingMessage),
            (.notEnoughNearbySamples, DepthAnalysisErrorPresentation.planeNotEnoughSamplesMessage),
            (.noPlaneRegion, DepthAnalysisErrorPresentation.planeNoStableRegionMessage)
        ]

        for (error, expectedMessage) in typedMessages {
            #expect(DepthAnalysisErrorPresentation.planeSelectionErrorMessage(for: error) == expectedMessage)
        }
        #expect(genericMessage == DepthAnalysisErrorPresentation.planeNoStableRegionMessage)
        #expect(!genericMessage.contains("local://hidden"))
        #expect(!genericMessage.contains("/private/tmp/plane-cache"))
    }

    @Test func depthAnalysisInspectorErrorMessageKeepsRegionHeatmapCopyPublicSafe() throws {
        let expected = DepthAnalysisErrorPresentation.regionHeatmapErrorMessage
        let direct = DepthAnalysisInspectorErrorMessage.regionHeatmap(expected)
        let missing = DepthAnalysisInspectorErrorMessage.regionHeatmap(nil)
        let hostile = DepthAnalysisInspectorErrorMessage.regionHeatmap(
            "Reader failed at /private/tmp/region.heic https://example.invalid/asset?token=secret"
        )

        #expect(direct.text == expected)
        #expect(missing.text == expected)
        #expect(hostile.text == expected)
        #expect(!hostile.text.localizedCaseInsensitiveContains("/private/"))
        #expect(!hostile.text.localizedCaseInsensitiveContains("https://"))
        #expect(!hostile.text.localizedCaseInsensitiveContains("token="))
    }

    @Test func depthAnalysisInspectorErrorMessageKeepsPlaneSelectionCopyPublicSafe() throws {
        let allowedMessages = [
            DepthAnalysisErrorPresentation.planeInvalidSeedMessage,
            DepthAnalysisErrorPresentation.planeCalibrationMissingMessage,
            DepthAnalysisErrorPresentation.planeNotEnoughSamplesMessage,
            DepthAnalysisErrorPresentation.planeNoStableRegionMessage
        ]
        for allowedMessage in allowedMessages {
            #expect(DepthAnalysisInspectorErrorMessage.planeSelection(allowedMessage)?.text == allowedMessage)
        }

        let hostile = try #require(DepthAnalysisInspectorErrorMessage.planeSelection(
            "Plane proof failed for AppAttest keyID=private-key at file:///private/tmp/plane.json"
        ))

        #expect(DepthAnalysisInspectorErrorMessage.planeSelection(nil) == nil)
        #expect(hostile.text == DepthAnalysisErrorPresentation.planeNoStableRegionMessage)
        #expect(!hostile.text.localizedCaseInsensitiveContains("proof"))
        #expect(!hostile.text.localizedCaseInsensitiveContains("AppAttest"))
        #expect(!hostile.text.localizedCaseInsensitiveContains("keyID"))
        #expect(!hostile.text.localizedCaseInsensitiveContains("file://"))
        #expect(!hostile.text.localizedCaseInsensitiveContains("/private/"))
    }

    @Test func depthAnalysisInspectorViewsDoNotAcceptRawErrorStringSinks() throws {
        let regionSource = try Self.source(relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisRegionInspectorContent.swift")
        let planeSource = try Self.source(relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneFilterInspectorContent.swift")

        #expect(regionSource.contains("let heatmapErrorMessage: DepthAnalysisInspectorErrorMessage"))
        #expect(!regionSource.contains("let heatmapErrorMessage: String?"))
        #expect(!regionSource.contains("Label(heatmapErrorMessage ??"))

        #expect(planeSource.contains("let errorMessage: DepthAnalysisInspectorErrorMessage?"))
        #expect(!planeSource.contains("let errorMessage: String?"))
        #expect(!planeSource.contains("Label(errorMessage,"))
    }

    @Test func depthRegionStatsPresentationDoesNotAcceptSensitiveInputs() throws {
        let source = try Self.source(relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift")
        let block = try Self.sourceBlock(
            in: source,
            startMarker: "nonisolated struct DepthRegionStatsPresentation",
            endMarker: "\nstruct DepthMetricRow"
        )
        let forbiddenInputs = [
            "localizedDescription",
            "DepthAnalysisSource",
            "TAPDepthAnalysisInput",
            "TAPDepthManifest",
            "URL",
            "identifier",
            "proof",
            "keyID",
            "AppAttest",
            "Error",
            "String(describing:"
        ]

        #expect(block.contains("init(stats: TAPDepthRegionStats)"))
        for forbiddenInput in forbiddenInputs {
            #expect(!block.contains(forbiddenInput))
        }
    }

    private static func source(relativePath: String) throws -> String {
        let fileURL = try repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func sourceBlock(
        in source: String,
        startMarker: String,
        endMarker: String
    ) throws -> String {
        guard let startRange = source.range(of: startMarker),
              let endRange = source[startRange.lowerBound...].range(of: endMarker) else {
            throw DepthAnalysisErrorPresentationTestError.sourceMarkerNotFound(startMarker)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func repositoryRoot(
        startingAt filePath: String = #filePath
    ) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            let projectPath = directory.appendingPathComponent("TAPCamDemo.xcodeproj").path
            let testsPath = directory.appendingPathComponent("TAPCamDemoTests").path
            let depthAnalysisPath = directory
                .appendingPathComponent("TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift")
                .path
            if fileManager.fileExists(atPath: projectPath),
               fileManager.fileExists(atPath: testsPath),
               fileManager.fileExists(atPath: depthAnalysisPath) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw DepthAnalysisErrorPresentationTestError.repositoryRootNotFound(filePath)
    }
}

private enum DepthAnalysisErrorPresentationTestError: Error {
    case repositoryRootNotFound(String)
    case sourceMarkerNotFound(String)
}
