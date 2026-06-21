//
//  TAPDepthAnalysisPresentationTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import CoreLocation
import Photos
import Testing
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

    @Test func analysisDepthAndMaskViewModeButtonsAreDebugOnly() throws {
        #expect(DepthAnalysisViewMode.heatmap.isDebugOnlyAnalysisButton)
        #expect(DepthAnalysisViewMode.mask.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.rgb.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.planes.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.pointCloud.isDebugOnlyAnalysisButton)
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
