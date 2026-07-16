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

@Suite(.serialized)
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

    @Test func analysisViewerToolsMatchAgreedBottomControls() throws {
        #expect(AnalysisViewerTool.allCases.map(\.title) == ["RAW", "2D", "3D"])
        #expect(AnalysisViewerTool.raw.accessibilityLabel == "Raw photo")
        #expect(AnalysisViewerTool.twoD.accessibilityLabel == "2D analysis")
        #expect(AnalysisViewerTool.threeD.accessibilityLabel == "3D projection")
        #expect(AnalysisViewerTool.allCases.map(\.systemImage) == ["photo", "square.on.square", "cube"])

        let modeItems = AnalysisViewerTool.allCases.map(\.modeItem)
        #expect(modeItems.map(\.id) == ["raw", "twoD", "threeD"])
        #expect(modeItems.map(\.accessibilityIdentifier) == [
            "tap.viewer.mode.raw",
            "tap.viewer.mode.2d",
            "tap.viewer.mode.3d"
        ])
        #expect(modeItems.allSatisfy { $0.isEnabled })
    }

    @Test func videoViewerModesKeepPhotoOrderAndFailClosedAvailability() throws {
        let registeredDescriptor = TAPVideoDepthRegistrationDescriptor(
            schemaID: "test.registered-rgb-presentation",
            rgbPresentationWidth: 1,
            rgbPresentationHeight: 1,
            mapping: .preRegisteredRGBPresentation
        )
        let availableItems = TAPVideoViewerModePolicy.items(
            availability: .available(registeredDescriptor),
            selectedTool: .raw,
            isTwoDPlaybackReady: false
        )

        #expect(availableItems.map(\.id) == ["raw", "twoD", "threeD"])
        #expect(availableItems.map(\.accessibilityIdentifier) == [
            "tap.viewer.mode.raw",
            "tap.viewer.mode.2d",
            "tap.viewer.mode.3d"
        ])
        #expect(availableItems.map(\.accessibilityLabel) == [
            "Raw video",
            "2D analysis",
            "3D projection"
        ])
        #expect(availableItems.map(\.isEnabled) == [true, true, false])
        #expect(availableItems.map(\.accessibilityValue) == [
            "Selected",
            "Available",
            "Unavailable for video"
        ])

        let readyTwoDItems = TAPVideoViewerModePolicy.items(
            availability: .available(registeredDescriptor),
            selectedTool: .twoD,
            isTwoDPlaybackReady: true
        )
        #expect(readyTwoDItems[1].accessibilityValue == "Selected, Ready")

        let unavailableItems = TAPVideoViewerModePolicy.items(
            availability: .unavailable,
            selectedTool: .raw,
            isTwoDPlaybackReady: false
        )
        #expect(unavailableItems.map(\.isEnabled) == [true, false, false])
        #expect(unavailableItems[1].accessibilityValue == "Registered depth unavailable")

        let incompleteDescriptor = TAPVideoDepthRegistrationDescriptor(
            schemaID: "test.incomplete",
            rgbPresentationWidth: 0,
            rgbPresentationHeight: 0,
            mapping: .preRegisteredRGBPresentation
        )
        let incompleteItems = TAPVideoViewerModePolicy.items(
            availability: .available(incompleteDescriptor),
            selectedTool: .raw,
            isTwoDPlaybackReady: false
        )
        #expect(incompleteItems.map(\.isEnabled) == [true, false, false])
    }

    @Test func videoTransportTreatsBufferingAsActivePlaybackIntent() {
        #expect(!TAPVideoPlaybackTransportPolicy.hasActivePlaybackIntent(status: .paused))
        #expect(TAPVideoPlaybackTransportPolicy.hasActivePlaybackIntent(status: .playing))
        #expect(
            TAPVideoPlaybackTransportPolicy.hasActivePlaybackIntent(
                status: .waitingToPlayAtSpecifiedRate
            )
        )
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisBottomControlsUseIconOnlyModes() throws {
        let controlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisControlsView.swift"
        )

        #expect(controlsSource.contains("DepthViewerModeCapsule"))
        #expect(controlsSource.contains("Image(systemName: item.systemImage)"))
        #expect(controlsSource.contains(".disabled(!item.isEnabled)"))
        #expect(controlsSource.contains(".opacity(item.isEnabled ? 1 : 0.35)"))
        #expect(controlsSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(controlsSource.contains("button.accessibilityIdentifier(accessibilityIdentifier)"))
        #expect(!controlsSource.contains("square.and.arrow.up"))
        #expect(!controlsSource.contains("trash"))
        #expect(!controlsSource.contains("Text(tool.title)"))
        #expect(!controlsSource.contains("Label(\""))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisChromeSeparatesGlobalActionsFromModeCapsule() throws {
        let chromeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisViewerChromeView.swift"
        )

        #expect(chromeSource.contains("square.and.arrow.up"))
        #expect(chromeSource.contains("trash"))
        #expect(chromeSource.contains("DepthViewerChromeView("))
        #expect(chromeSource.contains("DepthViewerModeCapsule("))
        #expect(chromeSource.contains("HStack(alignment: .center"))
        #expect(chromeSource.contains("Circle()"))
        #expect(chromeSource.contains(#".accessibilityIdentifier("tap.viewer.back")"#))
        #expect(chromeSource.contains(#"accessibilityIdentifier: "tap.viewer.share""#))
        #expect(chromeSource.contains(#"accessibilityIdentifier: "tap.viewer.delete""#))
        #expect(chromeSource.contains("bottomAccessory: EmptyView()"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisTwoDChromeUsesOverlayOpacityControlAndImageDivider() throws {
        let viewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let chromeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisViewerChromeView.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let interactiveSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInteractiveImage.swift"
        )

        #expect(chromeSource.contains("AnalysisOpacityControl"))
        #expect(chromeSource.contains("2D overlay opacity"))
        #expect(!chromeSource.contains("AnalysisPlaneStrictnessControl"))
        #expect(!chromeSource.contains("Plane strictness"))
        #expect(!viewSource.contains("planeStrictness: planeStrictness"))
        #expect(settingsSource.contains("planeGrowthStrictnessKey"))
        #expect(settingsSource.contains("Plane Strictness"))
        #expect(settingsSource.contains("DepthAnalysisPlaneSelectionState.minimumStrictness...DepthAnalysisPlaneSelectionState.maximumStrictness"))
        #expect(viewSource.contains("strictness: planeGrowthStrictness"))
        #expect(viewSource.contains("updatePlaneGrowthStrictness(planeGrowthStrictness)"))
        #expect(!chromeSource.contains("AnalysisComparisonControl"))
        #expect(!chromeSource.contains("2D comparison position"))
        #expect(interactiveSource.contains("ComparisonDivider"))
        #expect(interactiveSource.contains("comparisonDividerX"))
        #expect(interactiveSource.contains("comparisonDividerCoordinateSpaceName"))
        #expect(interactiveSource.contains(".highPriorityGesture(comparisonDragGesture)"))
        #expect(interactiveSource.contains(".fill(Color.white.opacity(0.001))"))
        #expect(interactiveSource.contains(".position(x: dividerX, y: imageFrame.height / 2)"))
        #expect(interactiveSource.contains("isNearComparisonDivider"))
        #expect(interactiveSource.contains("UIImpactFeedbackGenerator(style: .light).impactOccurred()"))
        #expect(!interactiveSource.contains("arrow.left.and.right"))
        #expect(!interactiveSource.contains("comparisonClipRect"))
        #expect(!interactiveSource.contains("@State private var dragStart"))
        #expect(!interactiveSource.contains("selectionFill"))
        #expect(!interactiveSource.contains("DragGesture(minimumDistance: 4)"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisPlaneHighlightPaletteFeedsTwoDAndThreeD() throws {
        let viewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let interactiveSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInteractiveImage.swift"
        )
        let pointCloudSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AnalysisTools/DepthPointCloudPreview.swift"
        )

        #expect(viewSource.contains("AnalysisHighlightPalette.resolved"))
        #expect(viewSource.contains("highlightColor: highlightPalette.uiColor"))
        #expect(interactiveSource.contains("PlaneSeedMarker(highlightPalette: highlightPalette)"))
        #expect(interactiveSource.contains("highlightPalette.gridFill"))
        #expect(pointCloudSource.contains("material.diffuse.contents = uiColor"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisPlaneConfidenceBadgeIsDebugOnly() throws {
        let interactiveSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInteractiveImage.swift"
        )
        let badgeSection = try #require(TAPCamDemoTestSourceInspection.substring(
            in: interactiveSource,
            from: "#if DEBUG\n                    let rect = viewRect(for: planeRegion.imageBounds",
            to: "#endif\n                } else if let planeSeedPoint"
        ))

        #expect(badgeSection.contains("PlaneRegionBadge"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisGridReadyToastUsesViewfinderEdgeToastLanguage() throws {
        let viewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )

        #expect(viewSource.contains("analysis.edgeToast"))
        #expect(viewSource.contains("Grid ready"))
        #expect(viewSource.contains(".background(.black.opacity(0.58), in: Capsule())"))
        #expect(viewSource.contains(".allowsHitTesting(false)"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisPlaneGridAnimationCanBeDisabledInSettings() throws {
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let interactiveSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInteractiveImage.swift"
        )

        #expect(settingsSource.contains("planeGridAnimationEnabledKey"))
        #expect(settingsSource.contains("Grid Growth Animation"))
        #expect(interactiveSource.contains("accessibilityReduceMotion || !isPlaneGridAnimationEnabled"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisShareButtonPresentsSystemShareDirectly() throws {
        let analysisSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )

        #expect(analysisSource.contains("DepthAnalysisSystemSharePayload"))
        #expect(analysisSource.contains("VerificationExportActivityView(activityItems: [payload.export.fileURL])"))
        #expect(analysisSource.contains("TAPVerificationExportBuilder().export(assetID: assetID)"))
        #expect(!analysisSource.contains("DepthAnalysisShareSheet(source:"))
        #expect(!analysisSource.contains("presentationDetents([.height(380), .medium])"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisShareSheetKeepsCredentialPresentationMinimalOutsideDebug() throws {
        let shareSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisShareSheet.swift"
        )

        #expect(shareSource.contains("Valid credential"))
        #expect(shareSource.contains("viewModel.hasValidCredential ? \"Yes\" : \"No\""))
        #expect(shareSource.contains("File information"))
        #expect(shareSource.contains("fileURL.lastPathComponent"))
        #expect(shareSource.contains("exportBuilder.hasValidCredential"))
        #expect(shareSource.contains("#if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS"))
        #expect(shareSource.contains("Debug status"))
        #expect(!shareSource.contains("AppAttestCaptureSignatureVerifier"))
        #expect(!shareSource.contains(".verify("))
        #expect(!shareSource.contains("assertionObject"))
        #expect(!shareSource.contains("keyId"))
        #expect(!shareSource.contains("signingBinding"))
        #expect(!shareSource.contains("proof"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisRawViewerSupportsLongPressLivePhotoPlaybackForPhotosAssets() throws {
        let analysisSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let soundButtonOverlay = try #require(TAPCamDemoTestSourceInspection.substring(
            in: analysisSource,
            from: "private struct AnalysisLivePhotoSoundButtonOverlay: View",
            to: "private enum DepthAnalysisLivePhotoSourceResolver"
        ))

        #expect(analysisSource.contains("import PhotosUI"))
        #expect(analysisSource.contains("PHLivePhotoView"))
        #expect(analysisSource.contains("UILongPressGestureRecognizer"))
        #expect(analysisSource.contains("requestLivePhoto"))
        #expect(analysisSource.contains("case .photosAsset(let assetID)"))
        #expect(analysisSource.contains("case .pendingCapture(let captureID)"))
        #expect(analysisSource.contains("PHLivePhoto.request("))
        #expect(analysisSource.contains("withResourceFileURLs: [resources.photoURL, resources.pairedVideoURL]"))
        #expect(analysisSource.contains("bestAvailablePhotoURL(captureID: captureID)"))
        #expect(analysisSource.contains("pairedVideoURL(captureID: captureID)"))
        #expect(analysisSource.contains("AnalysisLivePhotoSoundButtonOverlay"))
        #expect(analysisSource.contains("@State private var isLivePhotoMuted = true"))
        #expect(analysisSource.contains(#"Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")"#))
        #expect(soundButtonOverlay.contains(".frame(width: 42, height: 42)"))
        #expect(soundButtonOverlay.contains(".foregroundStyle(.white)"))
        #expect(soundButtonOverlay.contains(".shadow(color: .black.opacity(0.72), radius: 2, y: 1)"))
        #expect(!soundButtonOverlay.contains(".background("))
        #expect(!soundButtonOverlay.contains(".stroke("))
        #expect(analysisSource.contains("livePhotoView.isMuted = isLivePhotoMuted"))
        #expect(analysisSource.contains("startPlayback(with: .full)"))
        #expect(analysisSource.contains("stopPlayback()"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func albumAndAnalysisUseLivePhotoLogoBadges() throws {
        let badgeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisLivePhotoBadge.swift"
        )
        let cellSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPLibraryItemCell.swift"
        )
        let analysisSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let itemProviderSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumItemProvider.swift"
        )

        #expect(badgeSource.contains(#"Image(systemName: "livephoto")"#))
        #expect(badgeSource.contains(#".accessibilityLabel("Live Photo")"#))
        #expect(!badgeSource.contains(".background("))
        #expect(!badgeSource.contains("Circle()"))
        #expect(cellSource.contains("item.isLivePhoto"))
        #expect(cellSource.contains("DepthAnalysisLivePhotoBadge(size: .thumbnail)"))
        #expect(analysisSource.contains("AnalysisLivePhotoBadgeOverlay"))
        #expect(analysisSource.contains("DepthAnalysisLivePhotoBadge(size: .viewer)"))
        #expect(analysisSource.contains("centeredToolContainerRect"))
        #expect(itemProviderSource.contains("return asset.isLivePhoto && !asset.isVideo"))
        #expect(itemProviderSource.contains("record.pairedVideoFilename != nil"))
    }

    @Test func videoAlbumContextKeepsSwipeAndDeleteOrdering() throws {
        let entries = try ["a", "b", "c"].map { id in
            TAPVideoAlbumContext.Entry(
                id: id,
                source: .photosAsset(id),
                routeAnchor: try #require(CameraRouteAlbumAnchor(itemID: id))
            )
        }
        let context = TAPVideoAlbumContext(currentItemID: "b", entries: entries)

        #expect(context.adjacentEntry(offset: -1, excluding: [])?.id == "a")
        #expect(context.adjacentEntry(offset: 1, excluding: [])?.id == "c")
        #expect(context.adjacentEntry(offset: 2, excluding: []) == nil)
        #expect(
            context.entryAfterDeletingCurrent(excluding: ["b"])?.id == "c"
        )
        #expect(
            context.entryAfterDeletingCurrent(excluding: ["b", "c"])?.id == "a"
        )
        #expect(TAPVideoPlaybackSource.pendingCapture("p")
            .requiresUnsavedDeleteConfirmation)
        #expect(!TAPVideoPlaybackSource.photosAsset("p")
            .requiresUnsavedDeleteConfirmation)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisDeleteUsesPhotosPromptAndPendingStoreBoundaries() throws {
        let analysisSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let writerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift"
        )

        #expect(analysisSource.contains("PhotoLibraryWriter.deleteAsset"))
        #expect(analysisSource.contains("TAPPendingCaptureStore.shared.removeRecord"))
        #expect(analysisSource.contains("DepthAnalysisPendingDeleteRequest"))
        #expect(analysisSource.contains("Delete unsaved photo?"))
        #expect(analysisSource.contains("This capture has not finished exporting to Photos."))
        #expect(analysisSource.contains("case .pendingCapture = source"))
        #expect(analysisSource.contains("advanceAfterDeletingCurrent"))
        #expect(!analysisSource.contains("DepthAnalysisDeleteConfirmationDialog"))
        #expect(!analysisSource.contains("Toggle(\"Don't Ask Again\", isOn: $dontAskAgain)"))
        #expect(!analysisSource.contains("AnalysisCheckboxToggleStyle"))
        #expect(!analysisSource.contains("checkmark.square.fill"))
        #expect(!analysisSource.contains("Delete and Don't Ask Again"))
        #expect(!analysisSource.contains(".confirmationDialog("))
        #expect(!analysisSource.contains("confirmsDeleteBeforeDeleting"))
        #expect(!settingsSource.contains("confirmsDeleteBeforeDeletingKey"))
        #expect(!settingsSource.contains("Delete Confirmation"))
        #expect(writerSource.contains("PHAssetChangeRequest.deleteAssets"))
    }

    @Test func analysisNativePagingUsesEighteenPointBlackGap() throws {
        #expect(DepthAnalysisViewerInteractionPolicy.nativePageSpacing == 18)
    }

    @Test func analysisEdgeBackPolicyRequiresLeftEdgeRightwardDominantDrag() throws {
        #expect(AnalysisEdgeBackPolicy.shouldReturn(
            startX: 12,
            translation: CGSize(width: 72, height: 8),
            predictedTranslation: CGSize(width: 80, height: 8)
        ))
        #expect(AnalysisEdgeBackPolicy.shouldReturn(
            startX: 12,
            translation: CGSize(width: 32, height: 4),
            predictedTranslation: CGSize(width: 120, height: 4)
        ))
        #expect(!AnalysisEdgeBackPolicy.shouldReturn(
            startX: 28,
            translation: CGSize(width: 100, height: 4),
            predictedTranslation: CGSize(width: 120, height: 4)
        ))
        #expect(!AnalysisEdgeBackPolicy.shouldReturn(
            startX: 12,
            translation: CGSize(width: -90, height: 2),
            predictedTranslation: CGSize(width: -130, height: 2)
        ))
        #expect(!AnalysisEdgeBackPolicy.shouldReturn(
            startX: 12,
            translation: CGSize(width: 90, height: 90),
            predictedTranslation: CGSize(width: 130, height: 90)
        ))
    }

    @Test func analysisToolContainerRectMatchesRawAspectFitAndStaysCentered() throws {
        let viewportSize = CGSize(width: 390, height: 844)
        let containerRect = DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
            imageSize: CGSize(width: 400, height: 300),
            orientation: .up,
            viewportSize: viewportSize
        )
        let rotatedRect = DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
            imageSize: CGSize(width: 400, height: 300),
            orientation: .right,
            viewportSize: viewportSize
        )

        #expect(containerRect == CGRect(x: 0, y: 275.75, width: 390, height: 292.5))
        #expect(containerRect.midX == viewportSize.width * 0.5)
        #expect(containerRect.midY == viewportSize.height * 0.5)
        #expect(rotatedRect == CGRect(x: 0, y: 162, width: 390, height: 520))
        #expect(rotatedRect.midX == viewportSize.width * 0.5)
        #expect(rotatedRect.midY == viewportSize.height * 0.5)
    }

    @Test func analysisPhotoLayoutUsesAspectFit() throws {
        let containerSize = CGSize(width: 300, height: 300)
        let landscapeRect = DepthAnalysisViewerInteractionPolicy.aspectFitRect(
            imageSize: CGSize(width: 400, height: 300),
            orientation: .up,
            containerSize: containerSize
        )
        let rotatedRect = DepthAnalysisViewerInteractionPolicy.aspectFitRect(
            imageSize: CGSize(width: 400, height: 300),
            orientation: .right,
            containerSize: containerSize
        )

        #expect(landscapeRect == CGRect(x: 0, y: 37.5, width: 300, height: 225))
        #expect(rotatedRect == CGRect(x: 37.5, y: 0, width: 225, height: 300))
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

    @Test @MainActor func analysisCarouselStoreMoveKeepsAlbumRouteContext() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .photosAsset("asset-second"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: first.id,
            entries: [first, second]
        )
        let store = DepthAnalysisCarouselStore(
            source: first.source,
            albumContext: context,
            loader: .noop
        )

        let movedEntry = try #require(store.move(offset: 1))

        #expect(movedEntry.albumEntry?.id == second.id)
        #expect(movedEntry.albumEntry?.routeAnchor == second.routeAnchor)
        #expect(store.currentItemID == second.id)
    }

    @Test @MainActor func analysisCarouselStoreSelectsNextEntryAfterDeletingCurrent() throws {
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

        let nextEntry = try #require(store.advanceAfterDeletingCurrent())

        #expect(nextEntry.id == third.id)
        #expect(store.currentEntry?.id == third.id)
        #expect(store.windowEntries().map(\.entry.id) == ["first", "third"])
        #expect(store.entry(offset: -1)?.id == first.id)
        #expect(store.entry(offset: 1) == nil)
    }

    @Test @MainActor func analysisCarouselStoreSelectsPreviousEntryAfterDeletingLast() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .photosAsset("asset-second"))
        let third = try analysisAlbumEntry(id: "third", source: .pendingCapture("capture-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: third.id,
            entries: [first, second, third]
        )
        let store = DepthAnalysisCarouselStore(
            source: third.source,
            albumContext: context,
            loader: .noop
        )

        let previousEntry = try #require(store.advanceAfterDeletingCurrent())

        #expect(previousEntry.id == second.id)
        #expect(store.currentEntry?.id == second.id)
        #expect(store.windowEntries().map(\.entry.id) == ["first", "second"])
        #expect(store.entry(offset: -1)?.id == first.id)
        #expect(store.entry(offset: 1) == nil)
    }

    @Test @MainActor func analysisCarouselStoreReturnsNilAfterDeletingOnlyEntry() throws {
        let only = try analysisAlbumEntry(id: "only", source: .pendingCapture("capture-only"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: only.id,
            entries: [only]
        )
        let store = DepthAnalysisCarouselStore(
            source: only.source,
            albumContext: context,
            loader: .noop
        )

        let nextEntry = store.advanceAfterDeletingCurrent()

        #expect(nextEntry == nil)
        #expect(store.currentEntry == nil)
        #expect(store.windowEntries().isEmpty)
    }

    @Test @MainActor func analysisCarouselStoreEvictsSlotsOutsideVisibleWindow() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let fourth = try analysisAlbumEntry(id: "fourth", source: .photosAsset("asset-fourth"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third, fourth]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: .noop
        )
        let firstEntry = DepthAnalysisCarouselEntry(albumEntry: first)
        let cachedFirstSlot = store.slot(for: firstEntry)
        cachedFirstSlot.updatePlaneGrowthStrictness(0.9)

        let movedEntry = try #require(store.move(offset: 1))

        #expect(movedEntry.id == third.id)
        #expect(store.windowEntries().map(\.entry.id) == ["second", "third", "fourth"])
        #expect(store.retainedSlotCount == 3)

        let restoredFirstSlot = store.slot(for: firstEntry)
        #expect(restoredFirstSlot !== cachedFirstSlot)
        #expect(abs(restoredFirstSlot.planeSelection.strictness - 0.9) < 0.0001)
    }

    @Test @MainActor func analysisCarouselStoreLoadsCurrentOriginalAndAdjacentThumbnails() async throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .photosAsset("asset-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let fourth = try analysisAlbumEntry(id: "fourth", source: .photosAsset("asset-fourth"))
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let thumbnail = try singlePixelUIImage()
        let events = AnalysisLoaderEventRecorder()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { source, _ in
                await events.recordThumbnail(source)
                return thumbnail
            },
            displayLoader: { source, _ in
                await events.recordDisplay(source)
                return AnalysisDisplayPhoto(image: thumbnail)
            },
            inputLoader: { source, _ in
                await events.recordInput(source)
                return input
            }
        )
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third, fourth]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: loader
        )

        store.ensureVisibleWindowLoaded(pixelLength: 80)
        try await waitForLoaderEvents(events, thumbnailCount: 3, displayCount: 1, inputCount: 1)

        var snapshot = await events.snapshot()
        #expect(Set(snapshot.thumbnails) == ["photos:asset-first", "photos:asset-second", "photos:asset-third"])
        #expect(snapshot.displays == ["photos:asset-second"])
        #expect(snapshot.inputs == ["photos:asset-second"])

        let movedEntry = try #require(store.move(offset: 1))
        #expect(movedEntry.id == third.id)
        try await waitForLoaderEvents(events, thumbnailCount: 4, displayCount: 2, inputCount: 2)

        snapshot = await events.snapshot()
        #expect(Set(snapshot.thumbnails) == [
            "photos:asset-first",
            "photos:asset-second",
            "photos:asset-third",
            "photos:asset-fourth"
        ])
        #expect(snapshot.displays == ["photos:asset-second", "photos:asset-third"])
        #expect(snapshot.inputs == ["photos:asset-second", "photos:asset-third"])
        let previousSlot = store.slot(for: DepthAnalysisCarouselEntry(albumEntry: second))
        let currentSlot = store.slot(for: DepthAnalysisCarouselEntry(albumEntry: third))
        try await waitForCondition { currentSlot.input != nil }
        #expect(previousSlot.input == nil)
        #expect(currentSlot.input != nil)
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
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: thumbnail) },
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
        #expect(slot.displayPhoto?.image.size == thumbnail.size)
        #expect(slot.input?.depthMap.width == 2)
        #expect(slot.loadProgress == nil)
    }

    @Test @MainActor func currentPhotoKeepsDisplayPreviewDuringICloudOriginalDownload() async throws {
        let image = try singlePixelUIImage()
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, progress in
                await progress(0.42)
                try await Task.sleep(nanoseconds: 300_000_000)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("icloud-original"))
        )

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition {
            guard slot.displayPhoto != nil,
                  case .downloadingFromICloud(let hasPreview, let progress) = slot.mediaFetchPhase else {
                return false
            }
            return hasPreview == true && progress == 0.42
        }

        #expect(slot.displayPhoto?.image.size == image.size)
        #expect(slot.input == nil)
        try await waitForCondition { slot.input != nil }
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func originalICloudProgressNeverRegressesOrReturnsToIndeterminate() async throws {
        let image = try singlePixelUIImage()
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, progress in
                await progress(0.64)
                await progress(nil)
                await progress(0.21)
                try await Task.sleep(nanoseconds: 300_000_000)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("icloud-monotonic-progress"))
        )

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition {
            slot.mediaFetchPhase == .downloadingFromICloud(true, progress: 0.64)
        }

        #expect(slot.loadProgress == 0.64)
        try await waitForCondition { slot.input != nil }
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func livePhotoProgressAggregatesWithReadyOriginalAndCanonicalIdentity() async throws {
        let image = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in throw CancellationError() }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("live-photo-progress"))
        )

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition { slot.mediaFetchPhase == .ready(true) }

        let requestKey = slot.beginLivePhotoFetch(onCancel: {}, onRetry: {})
        #expect(requestKey.itemID == .photosAsset("live-photo-progress"))
        #expect(requestKey.purpose == .livePhotoPlayback)

        slot.markLivePhotoFetchResolving(requestKey: requestKey)
        #expect(slot.mediaFetchPhase == .resolving(true))
        slot.applyLivePhotoICloudProgress(0.42, requestKey: requestKey)
        #expect(slot.mediaFetchPhase == .downloadingFromICloud(true, progress: 0.42))

        slot.completeLivePhotoFetch(requestKey: requestKey)
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func staleLivePhotoCallbacksCannotOverrideReplacementRequestOrPreview() async throws {
        let image = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in throw CancellationError() }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("live-photo-race"))
        )
        var cancellationCount = 0

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition { slot.mediaFetchPhase == .ready(true) }

        let staleKey = slot.beginLivePhotoFetch(
            onCancel: { cancellationCount += 1 },
            onRetry: {}
        )
        slot.applyLivePhotoICloudProgress(0.1, requestKey: staleKey)
        let replacementKey = slot.beginLivePhotoFetch(onCancel: {}, onRetry: {})
        #expect(cancellationCount == 1)
        #expect(slot.mediaFetchPhase == .ready(true))

        slot.applyLivePhotoICloudProgress(0.99, requestKey: staleKey)
        slot.failLivePhotoFetch(MediaFetchFailure.download, requestKey: staleKey)
        #expect(slot.mediaFetchPhase == .ready(true))

        slot.applyLivePhotoICloudProgress(0.25, requestKey: replacementKey)
        #expect(slot.mediaFetchPhase == .downloadingFromICloud(true, progress: 0.25))
        slot.completeLivePhotoFetch(requestKey: replacementKey)

        slot.applyLivePhotoICloudProgress(0.75, requestKey: staleKey)
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func cancelAndRetryControlOriginalAndLivePhotoRequestsTogether() async throws {
        let image = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in throw CancellationError() }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("live-photo-cancel"))
        )
        var cancellationCount = 0
        var retryCount = 0

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition { slot.mediaFetchPhase == .ready(true) }
        let requestKey = slot.beginLivePhotoFetch(
            onCancel: { cancellationCount += 1 },
            onRetry: { retryCount += 1 }
        )
        slot.applyLivePhotoICloudProgress(0.3, requestKey: requestKey)

        slot.cancelCurrentMediaFetch()
        #expect(cancellationCount == 1)
        #expect(slot.mediaFetchPhase == .cloudOnly(true))

        slot.retryLastMediaFetch()
        #expect(retryCount == 1)
        #expect(slot.mediaFetchPhase == .resolving(true))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func rawViewerDoesNotGateCurrentOriginalRequestOnSelectedTool() throws {
        let stateSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisCarouselState.swift"
        )
        let viewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )

        #expect(stateSource.contains("slot.ensureLoading("))
        #expect(!stateSource.contains("loadCurrentAnalysis"))
        #expect(!viewSource.contains("loadCurrentAnalysis: selectedTool != .raw"))
    }

    @Test @MainActor func cancelledDisplayTaskCannotClearReplacementTaskHandle() async throws {
        let image = try singlePixelUIImage()
        let calls = CancellationRaceLoaderCallRecorder()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in
                let call = await calls.beginCall()
                if call == 1 {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        await nonCancellableDelay(nanoseconds: 80_000_000)
                        throw CancellationError()
                    }
                }
                try await Task.sleep(nanoseconds: 400_000_000)
                return AnalysisDisplayPhoto(image: image)
            },
            inputLoader: { _, _ in
                throw CancellationError()
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("display-race"))
        )

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCancellationRaceCalls(calls, count: 1)
        slot.cancelCurrentMediaFetch()
        slot.retryLastMediaFetch()
        try await waitForCancellationRaceCalls(calls, count: 2)

        try await Task.sleep(nanoseconds: 120_000_000)
        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await Task.sleep(nanoseconds: 40_000_000)

        let callCount = await calls.callCount()
        #expect(callCount == 2)
        slot.prepareForEviction()
    }

    @Test @MainActor func cancelledInputTaskCannotClearReplacementTaskHandle() async throws {
        let image = try singlePixelUIImage()
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let calls = CancellationRaceLoaderCallRecorder()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in
                let call = await calls.beginCall()
                if call == 1 {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        await nonCancellableDelay(nanoseconds: 80_000_000)
                        throw CancellationError()
                    }
                }
                try await Task.sleep(nanoseconds: 400_000_000)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("input-race"))
        )

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCancellationRaceCalls(calls, count: 1)
        try await waitForCondition { slot.displayPhoto != nil }
        slot.cancelCurrentMediaFetch()
        slot.retryLastMediaFetch()
        try await waitForCancellationRaceCalls(calls, count: 2)

        try await Task.sleep(nanoseconds: 120_000_000)
        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await Task.sleep(nanoseconds: 40_000_000)

        let callCount = await calls.callCount()
        #expect(callCount == 2)
        slot.prepareForEviction()
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
        #expect(DepthAnalyzerAuthorizationStatusText.microphone(.authorized) == "Authorized")
        #expect(DepthAnalyzerAuthorizationStatusText.microphone(.notDetermined) == "Not requested")
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
    let mediaID: LibraryMediaID
    switch source {
    case .photosAsset(let assetID):
        mediaID = .photosAsset(assetID)
    case .pendingCapture(let captureID):
        mediaID = .tapCapture(captureID)
    }
    return DepthAnalysisAlbumContext.Entry(
        id: id,
        mediaID: mediaID,
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
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let maximumAttempts = max(1, Int(timeoutNanoseconds / pollIntervalNanoseconds))
    for _ in 0..<maximumAttempts {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    if condition() {
        return
    }
    Issue.record("Timed out waiting for condition.")
}

private func waitForLoaderEvents(
    _ events: AnalysisLoaderEventRecorder,
    thumbnailCount: Int,
    displayCount: Int,
    inputCount: Int,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let maximumAttempts = max(1, Int(timeoutNanoseconds / pollIntervalNanoseconds))
    for _ in 0..<maximumAttempts {
        let snapshot = await events.snapshot()
        if snapshot.thumbnails.count >= thumbnailCount,
           snapshot.displays.count >= displayCount,
           snapshot.inputs.count >= inputCount {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    let finalSnapshot = await events.snapshot()
    if finalSnapshot.thumbnails.count >= thumbnailCount,
       finalSnapshot.displays.count >= displayCount,
       finalSnapshot.inputs.count >= inputCount {
        return
    }
    Issue.record("Timed out waiting for loader events.")
}

private func waitForCancellationRaceCalls(
    _ recorder: CancellationRaceLoaderCallRecorder,
    count: Int,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let maximumAttempts = max(1, Int(timeoutNanoseconds / pollIntervalNanoseconds))
    for _ in 0..<maximumAttempts {
        if await recorder.callCount() >= count {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    if await recorder.callCount() >= count {
        return
    }
    Issue.record("Timed out waiting for cancellation-race loader calls.")
}

private func nonCancellableDelay(nanoseconds: UInt64) async {
    await Task.detached(priority: .utility) {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }.value
}

private actor CancellationRaceLoaderCallRecorder {
    private var count = 0

    func beginCall() -> Int {
        count += 1
        return count
    }

    func callCount() -> Int {
        count
    }
}

private actor AnalysisLoaderEventRecorder {
    private(set) var thumbnails: [String] = []
    private(set) var displays: [String] = []
    private(set) var inputs: [String] = []

    func recordThumbnail(_ source: DepthAnalysisSource) {
        thumbnails.append(Self.id(for: source))
    }

    func recordDisplay(_ source: DepthAnalysisSource) {
        displays.append(Self.id(for: source))
    }

    func recordInput(_ source: DepthAnalysisSource) {
        inputs.append(Self.id(for: source))
    }

    func snapshot() -> (thumbnails: [String], displays: [String], inputs: [String]) {
        (thumbnails, displays, inputs)
    }

    private static func id(for source: DepthAnalysisSource) -> String {
        switch source {
        case .photosAsset(let assetID):
            "photos:\(assetID)"
        case .pendingCapture(let captureID):
            "pending:\(captureID)"
        }
    }
}

private extension DepthAnalysisProgressivePhotoLoader {
    static var noop: DepthAnalysisProgressivePhotoLoader {
        DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            },
            inputLoader: { _, _ in
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            }
        )
    }
}
