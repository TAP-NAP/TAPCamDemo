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

}
