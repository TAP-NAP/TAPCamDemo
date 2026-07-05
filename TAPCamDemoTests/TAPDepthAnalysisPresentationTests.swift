//
//  TAPDepthAnalysisPresentationTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import CoreLocation
import Photos
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPDepthAnalysisPresentationTests {
    @Test func analysisViewModesAllPublishUserFacingExplanations() throws {
        for viewMode in DepthAnalysisViewMode.allCases {
            #expect(!viewMode.shortExplanation.isEmpty)
            #expect(!viewMode.detailedExplanation.isEmpty)
            #expect(!viewMode.legendDescription.isEmpty)
        }
    }

    @Test func analysisViewModesPublishInspectorRoutes() throws {
        #expect(DepthAnalysisViewMode.rgb.inspectors == [.measurements, .region])
        #expect(DepthAnalysisViewMode.heatmap.inspectors == [.measurements, .legend, .overlay, .region])
        #expect(DepthAnalysisViewMode.mask.inspectors == [.measurements, .legend, .region])
        #expect(DepthAnalysisViewMode.planes.inspectors == [.planeFilter, .legend, .overlay])
        #expect(DepthAnalysisViewMode.pointCloud.inspectors == [.cloudInfo, .measurements, .region])
    }

    @Test func captureMetadataSummaryRequiresPayload() {
        let missingPayload: TAPDepthManifest.Payload? = nil
        #expect(CaptureMetadataSummary(payload: missingPayload) == nil)
    }

    @Test func captureMetadataSummaryPublishesExpectedPublicText() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(location: nil)
        let summary = try #require(CaptureMetadataSummary(payload: payload))

        #expect(summary.title == "2x · Back Triple Camera / Back Wide Camera")
        #expect(summary.detail == "RGB Wide · Depth Portrait Depth · stereo/computational · LiDAR not asserted · Zoom 2.00x")
        #expect(summary.accessibilityText == "\(summary.title). \(summary.detail).")
    }

    @Test func captureMetadataSummaryOmitsIdentifiersAndLocation() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(
            id: "private-capture-id",
            capturedAt: "2026-06-11T00:00:00.000Z",
            location: TAPCamDemoTestFixtures.sampleLocation
        )
        let summary = try #require(CaptureMetadataSummary(payload: payload))
        let visibleText = "\(summary.title) \(summary.detail) \(summary.accessibilityText)"

        #expect(!visibleText.contains("private-capture-id"))
        #expect(!visibleText.contains("31.2304"))
        #expect(!visibleText.contains("121.4737"))
        #expect(!visibleText.contains("2026-06-11T00:00:00.000Z"))
    }

    @Test func captureMetadataSummaryFallsBackForSensitiveManifestDisplayFields() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: nil,
            rgbSourceDisplayName: "https://example.invalid/camera?token=rgb-secret",
            selectedDepthCameraDisplayName: "/private/var/mobile/depth.heic",
            requestedFocalLengthLabel: "captureID private-capture-id",
            resolvedCaptureDeviceName: "AppAttest keyID=private-key",
            resolvedActivePrimaryConstituentDeviceName: "proof assertion private-proof",
            depthSourceSensingMethod: "https://example.invalid/method?token=depth-secret",
            depthSourceLidarParticipation: "rawProofValue"
        )
        let summary = try #require(CaptureMetadataSummary(payload: payload))
        let visibleText = "\(summary.title) \(summary.detail) \(summary.accessibilityText)"

        #expect(summary.title == "Lens · Camera")
        #expect(summary.detail == "RGB RGB source · Depth Depth source · Depth method · Zoom 2.00x")
        #expect(summary.accessibilityText == "\(summary.title). \(summary.detail).")

        let sensitiveFragments = [
            "https://",
            "token=",
            "/private/",
            ".heic",
            "captureID",
            "private-capture-id",
            "AppAttest",
            "keyID",
            "private-key",
            "proof",
            "assertion",
            "rawProofValue"
        ]
        for fragment in sensitiveFragments {
            #expect(!visibleText.localizedCaseInsensitiveContains(fragment))
        }
    }

    @Test func captureMetadataSummaryFallsBackForDepthSourceDeviceName() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: nil,
            selectedDepthCameraDisplayName: "None",
            depthSourceCaptureDeviceName: "file:///private/var/mobile/depth.json"
        )
        let summary = try #require(CaptureMetadataSummary(payload: payload))

        #expect(summary.detail.contains("Depth Depth source"))
        #expect(!summary.detail.localizedCaseInsensitiveContains("file://"))
        #expect(!summary.detail.localizedCaseInsensitiveContains("/private/"))
        #expect(!summary.detail.localizedCaseInsensitiveContains(".json"))
    }

    @Test func depthAnalysisScoreSummaryScoresHighQualityCalibratedDepth() throws {
        let input = try scoredAnalysisInput(
            payload: TAPCamDemoTestFixtures.samplePayload(location: nil),
            samples: [1, 1.1, 1.2, 1.3],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let score = DepthAnalysisScoreSummary(input: input)

        #expect(score.value == 100)
        #expect(score.scoreText == "100/100")
        #expect(score.grade == "Excellent")
        #expect(score.detail == "Coverage 100% · Quality high · Accuracy absolute · Calibration available")
        #expect(score.accessibilityText.contains("Analysis score 100 out of 100."))
    }

    @Test func depthAnalysisScoreSummaryUsesConservativeScoreWithoutManifestOrCalibration() throws {
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 0, 2, -1],
            calibration: nil
        ))
        let score = DepthAnalysisScoreSummary(input: input)

        #expect(score.value == 41)
        #expect(score.grade == "Limited")
        #expect(score.detail == "Coverage 50% · Manifest unavailable · Calibration unavailable")
    }

    @Test func depthAnalysisScoreSummaryNoDepthIsFixedAndPublicSafe() throws {
        let score = DepthAnalysisScoreSummary.noDepth
        let visibleText = "\(score.scoreText) \(score.grade) \(score.detail) \(score.accessibilityText)"

        #expect(score.value == 20)
        #expect(score.scoreText == "20/100")
        #expect(score.grade == "No Depth")
        #expect(score.detail == "RGB saved · Depth unavailable · Depth tools disabled")
        #expect(!visibleText.localizedCaseInsensitiveContains("captureID"))
        #expect(!visibleText.localizedCaseInsensitiveContains("asset"))
        #expect(!visibleText.localizedCaseInsensitiveContains("proof"))
    }

    @Test func depthAnalysisScoreSummaryOmitsManifestIdentifiersAndLocation() throws {
        let input = try scoredAnalysisInput(
            payload: TAPCamDemoTestFixtures.samplePayload(
                id: "private-capture-id",
                capturedAt: "2026-06-30T00:00:00.000Z",
                location: TAPCamDemoTestFixtures.sampleLocation
            ),
            samples: [1, 1, 1, 1],
            calibration: nil
        )
        let score = DepthAnalysisScoreSummary(input: input)
        let visibleText = "\(score.scoreText) \(score.grade) \(score.detail) \(score.accessibilityText)"

        #expect(!visibleText.contains("private-capture-id"))
        #expect(!visibleText.contains("2026-06-30T00:00:00.000Z"))
        #expect(!visibleText.contains("31.2304"))
        #expect(!visibleText.contains("121.4737"))
    }

    @Test func analysisDepthAndMaskViewModeButtonsAreDebugOnly() throws {
        #expect(DepthAnalysisViewMode.heatmap.isDebugOnlyAnalysisButton)
        #expect(DepthAnalysisViewMode.mask.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.rgb.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.planes.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.pointCloud.isDebugOnlyAnalysisButton)
    }

    @Test func analysisDrawerToolsMatchAgreedBottomControls() throws {
        #expect(AnalysisDrawerTool.allCases.map(\.title) == ["2D", "3D", "凭证"])
        #expect(AnalysisDrawerTool.allCases.map(\.systemImage) == ["square.on.square", "cube.transparent", "checkmark.shield"])
        #expect(AnalysisDrawerTool.twoD.accessibilityLabel == "2D analysis")
        #expect(AnalysisDrawerTool.threeD.accessibilityLabel == "3D projection")
        #expect(AnalysisDrawerTool.credential.systemImage == "checkmark.shield")
    }

    @Test func analysisToolViewportFollowsDisplayedImageAspectRatio() throws {
        let landscape = AnalysisToolViewportLayout.size(
            imageSize: CGSize(width: 400, height: 300),
            orientation: .up,
            viewportSize: CGSize(width: 424, height: 800)
        )
        let portrait = AnalysisToolViewportLayout.size(
            imageSize: CGSize(width: 300, height: 600),
            orientation: .up,
            viewportSize: CGSize(width: 424, height: 800)
        )
        let rotated = AnalysisToolViewportLayout.size(
            imageSize: CGSize(width: 400, height: 300),
            orientation: .right,
            viewportSize: CGSize(width: 424, height: 800)
        )

        #expect(landscape == CGSize(width: 400, height: 300))
        #expect(portrait == CGSize(width: 256, height: 512))
        #expect(rotated == CGSize(width: 384, height: 512))
    }

    @Test func analysisAlbumContextMovesThroughAdjacentEntries() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third]
        )

        #expect(context.adjacentEntry(offset: -1) == first)
        #expect(context.adjacentEntry(offset: 1) == third)
        #expect(context.adjacentEntry(offset: 2) == nil)
        #expect(context.selecting(third).currentItemID == third.id)
    }

    @Test @MainActor func analysisCarouselStoreKeepsStableThreeSlotWindow() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: .noop
        )

        #expect(store.currentIndex == 1)
        #expect(store.windowEntries().map(\.entry.id) == ["first", "second", "third"])
        let cachedSecondSlot = store.slot(for: store.windowEntries()[1].entry)

        let movedEntry = try #require(store.move(offset: 1))

        #expect(movedEntry.id == "third")
        #expect(store.currentIndex == 2)
        #expect(store.windowEntries().map(\.entry.id) == ["second", "third"])
        #expect(store.slot(for: DepthAnalysisCarouselEntry(albumEntry: second)) === cachedSecondSlot)
    }

    @Test @MainActor func analysisPhotoSlotPublishesThumbnailProgressAndDecodedInput() async throws {
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let thumbnail = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in thumbnail },
            inputLoader: { _, progress in
                await progress(0.35)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(entry: DepthAnalysisCarouselEntry(source: .photosAsset("asset-a")))

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition {
            slot.thumbnailImage != nil && slot.input != nil
        }

        #expect(slot.phase == .analysisReady)
        #expect(slot.thumbnailImage != nil)
        #expect(slot.input?.depthMap.width == 2)
        #expect(slot.loadProgress == nil)
    }

    @Test func analyzerHelpPreferenceDefaultsToEnabled() throws {
        #expect(DepthAnalyzerPreferences.defaultShowsAnalysisHelp)
        #expect(!DepthAnalyzerPreferences.showsAnalysisHelpKey.isEmpty)
    }

    @Test func analysisInteractionStateSeparatesDrawingFromRegionInspection() throws {
        #expect(!AnalysisInteractionState.idle.showsRegionInspector)
        #expect(!AnalysisInteractionState.drawingSelection.showsRegionInspector)
        #expect(AnalysisInteractionState.regionSelected.showsRegionInspector)
    }

    @Test func analysisPanelDestinationSelectsInspectorsOnly() throws {
        #expect(AnalysisPanelDestination.inspector(.region).selectedInspector == .region)
        #expect(AnalysisPanelDestination.inspector(.measurements).selectedInspector == .measurements)
        #expect(AnalysisPanelDestination.signatureVerification.selectedInspector == nil)
    }

    @Test func depthRegionStatsPresentationFormatsValidRegionStats() throws {
        let presentation = DepthRegionStatsPresentation(
            stats: TAPDepthRegionStats(
                validSampleCount: 3,
                totalSampleCount: 4,
                minimumDepthMeters: 1.0,
                maximumDepthMeters: 2.25,
                medianDepthMeters: 1.5,
                validRatio: 0.75
            )
        )

        #expect(presentation.medianDepthText == "1.50 m")
        #expect(presentation.rangeText == "1.00...2.25 m")
        #expect(presentation.validSamplesText == "3/4 · 75%")
    }

    @Test func depthRegionStatsPresentationUsesFixedNoDepthCopy() throws {
        let presentation = DepthRegionStatsPresentation(
            stats: TAPDepthRegionStats(
                validSampleCount: 0,
                totalSampleCount: 5,
                minimumDepthMeters: nil,
                maximumDepthMeters: nil,
                medianDepthMeters: nil,
                validRatio: 0
            )
        )

        #expect(presentation.medianDepthText == DepthRegionStatsPresentation.noValidDepthText)
        #expect(presentation.rangeText == DepthRegionStatsPresentation.noValidDepthText)
        #expect(presentation.validSamplesText == "0/5 · 0%")
    }

    @Test func depthRegionStatsPresentationRoundsValidSamplePercentage() throws {
        let presentation = DepthRegionStatsPresentation(
            stats: TAPDepthRegionStats(
                validSampleCount: 151,
                totalSampleCount: 200,
                minimumDepthMeters: 1,
                maximumDepthMeters: 2,
                medianDepthMeters: 1.5,
                validRatio: 0.755
            )
        )

        #expect(presentation.validSamplesText == "151/200 · 76%")
    }

    @Test func analysisViewModesAndInspectorsExposeLabelsAndIcons() throws {
        for viewMode in DepthAnalysisViewMode.allCases {
            #expect(!viewMode.title.isEmpty)
            #expect(!viewMode.systemImage.isEmpty)
        }

        for inspector in AnalysisInspector.allCases {
            #expect(!inspector.title.isEmpty)
            #expect(!inspector.systemImage.isEmpty)
        }
    }

    @Test func analyzerAuthorizationStatusTextIsPassiveAndDeterministic() throws {
        #expect(DepthAnalyzerAuthorizationStatusText.camera(.authorized) == "Authorized")
        #expect(DepthAnalyzerAuthorizationStatusText.camera(.notDetermined) == "Not requested")
        #expect(DepthAnalyzerAuthorizationStatusText.photos(.limited) == "Limited")
        #expect(DepthAnalyzerAuthorizationStatusText.photos(.denied) == "Denied")
        #expect(DepthAnalyzerAuthorizationStatusText.location(.authorizedWhenInUse) == "While using app")
        #expect(DepthAnalyzerAuthorizationStatusText.location(.restricted) == "Restricted")
    }
}

private func scoredAnalysisInput(
    payload: TAPDepthManifest.Payload,
    samples: [Float],
    calibration: TAPDepthManifest.CameraCalibration?
) throws -> TAPDepthAnalysisInput {
    let width = 2
    let height = samples.count / width
    let depthMap = TAPMetricDepthMap(
        width: width,
        height: height,
        samples: samples,
        calibration: calibration
    )
    let baseInput = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
    return TAPDepthAnalysisInput(
        manifest: TAPDepthManifest(payload: payload),
        image: baseInput.image,
        imageOrientation: baseInput.imageOrientation,
        depthMap: baseInput.depthMap,
        depthAccuracy: payload.depth.accuracy,
        depthQuality: payload.depth.quality,
        heatmap: baseInput.heatmap,
        validMask: baseInput.validMask
    )
}

private func analysisAlbumEntry(
    id: String,
    source: DepthAnalysisSource
) throws -> DepthAnalysisAlbumContext.Entry {
    let anchor = try #require(CameraRouteAlbumAnchor(itemID: id))
    return DepthAnalysisAlbumContext.Entry(
        id: id,
        source: source,
        routeAnchor: anchor
    )
}

private func singlePixelUIImage() throws -> UIImage {
    let image = try TAPDepthRGBAImageRenderer.image(
        pixels: [UInt8(255), 0, 0, 255],
        width: 1,
        height: 1
    )
    return UIImage(cgImage: image)
}

@MainActor
private func waitForCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @MainActor @escaping () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
    while Date() < deadline {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for condition.")
}

private extension DepthAnalysisProgressivePhotoLoader {
    static var noop: DepthAnalysisProgressivePhotoLoader {
        DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            inputLoader: { _, _ in
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            }
        )
    }
}
