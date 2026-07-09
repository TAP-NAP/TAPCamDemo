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

    @Test func analysisViewerToolsMatchAgreedBottomControls() throws {
        #expect(AnalysisViewerTool.allCases.map(\.title) == ["RAW", "2D", "3D"])
        #expect(AnalysisViewerTool.raw.accessibilityLabel == "Raw photo")
        #expect(AnalysisViewerTool.twoD.accessibilityLabel == "2D analysis")
        #expect(AnalysisViewerTool.threeD.accessibilityLabel == "3D projection")
        #expect(AnalysisViewerTool.allCases.map(\.systemImage) == ["photo", "square.on.square", "cube"])
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisBottomControlsUseIconOnlyModes() throws {
        let controlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisControlsView.swift"
        )

        #expect(controlsSource.contains("DepthViewerModeCapsule"))
        #expect(controlsSource.contains("Image(systemName: systemImage)"))
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
        let albumSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
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
        #expect(albumSource.contains("item.isLivePhoto"))
        #expect(albumSource.contains("DepthAnalysisLivePhotoBadge(size: .thumbnail)"))
        #expect(analysisSource.contains("AnalysisLivePhotoBadgeOverlay"))
        #expect(analysisSource.contains("DepthAnalysisLivePhotoBadge(size: .viewer)"))
        #expect(analysisSource.contains("centeredToolContainerRect"))
        #expect(itemProviderSource.contains("asset.mediaSubtypes.contains(.photoLive)"))
        #expect(itemProviderSource.contains("record.pairedVideoFilename != nil"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func videoDepthPlaybackDefaultsToPhotoStyleTwoDOverlayHeatmap() throws {
        let videoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPVideoDepthPlaybackView.swift"
        )
        let albumSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )

        #expect(videoSource.contains("@State private var selectedLayer = TAPVideoPlaybackLayer.twoD"))
        #expect(videoSource.contains("@State private var depthOverlayOpacity = 0.58"))
        #expect(videoSource.contains("case twoD"))
        #expect(videoSource.contains(#""2D video""#))
        #expect(!videoSource.contains(#""Overlay""#))
        #expect(!videoSource.contains(#""Depth""#))
        #expect(videoSource.contains("VideoPlayer(player: player)"))
        #expect(videoSource.contains(".opacity(depthOverlayOpacity)"))
        #expect(videoSource.contains("DepthViewerChromeView("))
        #expect(videoSource.contains("modeItems: TAPVideoPlaybackLayer.allCases.map(\\.modeItem)"))
        #expect(videoSource.contains("showsOpacityControl: selectedLayer == .twoD"))
        #expect(videoSource.contains("viewModel.prepareTwoDPlaybackGate()"))
        #expect(videoSource.contains("isPreparingTwoDPlayback"))
        #expect(videoSource.contains("twoDPlaybackGateNanoseconds: UInt64 = 2_000_000_000"))
        #expect(videoSource.contains("Preparing 2D playback"))
        #expect(videoSource.contains("preferredTwoDBufferDurationSeconds: TimeInterval = 3"))
        #expect(videoSource.contains("player.currentItem?.preferredForwardBufferDuration = Self.preferredTwoDBufferDurationSeconds"))
        #expect(videoSource.contains("VerificationExportActivityView(activityItems: [payload.fileURL])"))
        #expect(videoSource.contains("TAPVideoAlbumContext"))
        #expect(videoSource.contains("DragGesture(minimumDistance: 24)"))
        #expect(videoSource.contains("TAPVideoDeletionService"))
        #expect(videoSource.contains("PhotoLibraryWriter.deleteAsset"))
        #expect(videoSource.contains("TAPPendingCaptureStore.shared.removeRecord"))
        #expect(albumSource.contains("TAPVideoAlbumContext("))
        #expect(albumSource.contains("updatePresentedVideoRoute(entry)"))
        #expect(albumSource.contains(".id(selectedVideoRoute.itemID)"))
        #expect(!videoSource.contains("Picker(\"Playback layer\""))
        #expect(!videoSource.contains("layerPicker"))
        #expect(!videoSource.contains("playbackControls"))
        #expect(!videoSource.contains("viewModel.togglePlayback()"))
        #expect(!videoSource.contains("Text(viewModel.timecodeText)"))
        #expect(!videoSource.contains("ProgressView(value: viewModel.playbackProgress)"))
        #expect(videoSource.contains("AVPlayerItemMetadataOutput(identifiers: [Self.depthMetadataIdentifierRawValue])"))
        #expect(videoSource.contains("depthMetadataAdvanceIntervalSeconds: TimeInterval = 2"))
        #expect(videoSource.contains("output.advanceIntervalForDelegateInvocation = Self.depthMetadataAdvanceIntervalSeconds"))
        #expect(videoSource.contains("output.setDelegate(self, queue: metadataQueue)"))
        #expect(videoSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(videoSource.contains("item.load(.dataValue)"))
        #expect(videoSource.contains("decodeQueue = DispatchQueue("))
        #expect(videoSource.contains("TAPVideoDepthDecodeBackpressure"))
        #expect(videoSource.contains("maxPendingDepthDecodeCount = 90"))
        #expect(videoSource.contains("tap_video_depth_pipeline_backpressure_drop"))
        #expect(videoSource.contains("tap_video_depth_pipeline_miss"))
        #expect(videoSource.contains("CMTimeGetSeconds(group.timeRange.start)"))
        #expect(videoSource.contains("storeDepthFrame(frame)"))
        #expect(videoSource.contains("updateDepthFrame(for: playbackTimeSeconds)"))
        #expect(videoSource.contains("presentationTimeSeconds"))
        #expect(!videoSource.contains("lastPresentedFrameIndex"))
        #expect(videoSource.contains("warmPlayback(player: player)"))
        #expect(videoSource.contains("playerStatusObservation = player.observe(\\.status"))
        #expect(videoSource.contains("guard player.status == .readyToPlay else"))
        #expect(videoSource.contains("prerollIfReady(player: player)"))
        #expect(videoSource.contains("player.preroll(atRate: 1)"))
        #expect(!videoSource.contains("state = .ready\n            play()"))
        #expect(videoSource.contains("TAPVideoManifestBox.decodedManifest(from: data)"))
        #expect(videoSource.contains("manifest.payload.rgbTrack.transform"))
        #expect(videoSource.contains("TAPVideoDepthDisplayOrientation.cgImageOrientation"))
        #expect(videoSource.contains("TAPMetricDepthMap(width: width, height: height, samples: values, calibration: nil)"))
        #expect(videoSource.contains("TAPDepthHeatmapRenderer.heatmap(for: depthMap)"))
        #expect(videoSource.contains("orientation: displayOrientation.uiImageOrientation"))
        #expect(!videoSource.contains("depth-preview.mp4"))
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

    @Test @MainActor func analysisCarouselStoreLoadsDisplayBeforeCurrentAnalysis() async throws {
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
        try await waitForLoaderEvents(events, thumbnailCount: 3, displayCount: 3, inputCount: 0)

        var snapshot = await events.snapshot()
        #expect(Set(snapshot.thumbnails) == ["photos:asset-first", "photos:asset-second", "photos:asset-third"])
        #expect(Set(snapshot.displays) == ["photos:asset-first", "photos:asset-second", "photos:asset-third"])
        #expect(snapshot.inputs.isEmpty)

        store.ensureVisibleWindowLoaded(pixelLength: 80, loadCurrentAnalysis: true)
        try await waitForLoaderEvents(events, thumbnailCount: 3, displayCount: 3, inputCount: 1)

        snapshot = await events.snapshot()
        #expect(snapshot.inputs == ["photos:asset-second"])

        let movedEntry = try #require(store.move(offset: 1, loadCurrentAnalysis: true))
        #expect(movedEntry.id == third.id)
        try await waitForLoaderEvents(events, thumbnailCount: 4, displayCount: 4, inputCount: 2)

        snapshot = await events.snapshot()
        #expect(Set(snapshot.thumbnails) == [
            "photos:asset-first",
            "photos:asset-second",
            "photos:asset-third",
            "photos:asset-fourth"
        ])
        #expect(Set(snapshot.displays) == [
            "photos:asset-first",
            "photos:asset-second",
            "photos:asset-third",
            "photos:asset-fourth"
        ])
        #expect(snapshot.inputs == ["photos:asset-second", "photos:asset-third"])
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

private func waitForLoaderEvents(
    _ events: AnalysisLoaderEventRecorder,
    thumbnailCount: Int,
    displayCount: Int,
    inputCount: Int,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws {
    let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
    while Date() < deadline {
        let snapshot = await events.snapshot()
        if snapshot.thumbnails.count >= thumbnailCount,
           snapshot.displays.count >= displayCount,
           snapshot.inputs.count >= inputCount {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for loader events.")
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
