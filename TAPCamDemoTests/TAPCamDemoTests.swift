//
//  TAPCamDemoTests.swift
//  TAPCamDemoTests
//
//  Created by Harold on 2026/4/24.
//

import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCamDemoTests {
    @Test func manifestSchemaDefinesThePublishedXMPContract() throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(location: nil))

        #expect(manifest.schema.id == "urn:tapnap:tapcam:depth-manifest:v1")
        #expect(manifest.schema.mediaType == "application/vnd.tapnap.depth-manifest+json;version=1")
        #expect(manifest.schema.xmpNamespaceURI == "urn:tapnap:tapcam:depth:1.0")
        #expect(manifest.schema.xmpPrefix == "tapdepth")
        #expect(manifest.schema.xmpManifestPath == "tapdepth:Manifest")
    }

    @Test func manifestJSONDocumentsSingleCamSelectionAndNullableLocation() throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(location: nil))
        let json = try TAPDepthManifestEncoder.manifestJSON(manifest)

        #expect(json.contains("\"location\":null"))
        #expect(json.contains("\"proofs\":[]"))
        #expect(json.contains("\"depthDataType\":\"hdep\""))
        #expect(json.contains("\"metricUnit\":\"meters\""))
        #expect(json.contains("\"depthToImage\":\"appleAuxiliaryDepthNative\""))
        #expect(json.contains("\"sessionMode\":\"singleCam\""))
        #expect(json.contains("\"pairingMode\":\"rgbWithApplePairedDepth\""))
        #expect(json.contains("\"alignmentStatus\":\"sameCapturePipeline\""))
        #expect(json.contains("\"rgbSource\""))
        #expect(json.contains("\"depthSource\""))
        #expect(json.contains("\"pairing\""))
        #expect(json.contains("\"zoom\""))
        #expect(json.contains("\"crop\""))
        #expect(json.contains("\"resolvedSession\""))
        #expect(json.contains("\"selectedDepthCamera\""))
        #expect(json.contains("\"selectedZoom\""))
        #expect(json.contains("\"displayName\":\"Wide\""))
        #expect(json.contains("\"displayName\":\"2x\""))
        #expect(json.contains("\"selectionMode\":\"auto\""))
        #expect(json.contains("\"labelSource\":\"rgbSourceAndDepthSafeZoom\""))
        #expect(json.contains("\"sensingMethod\":\"multiCameraStereoOrComputational\""))
        #expect(json.contains("\"lidarParticipation\":\"notAsserted\""))
        #expect(json.contains("\"xmpManifestPath\":\"tapdepth:Manifest\""))
    }

    @Test func depthSourceClassificationUsesOnlyPublicDeviceTypeClaims() throws {
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue).sensingMethod == "lidarDepthCamera")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue).lidarParticipation == "explicit")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue).sensingMethod == "trueDepthCamera")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue).lidarParticipation == "notApplicable")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue).sensingMethod == "multiCameraStereoOrComputational")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue).lidarParticipation == "notAsserted")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue).sensingMethod == "singleCameraComputationalOrUnknown")
    }

    @Test func depthRowsKeepFixedDebugOrdering() throws {
        #expect(DepthProfileKind.lidarDepth.fixedOrder < DepthProfileKind.trueDepth.fixedOrder)
        #expect(DepthProfileKind.trueDepth.fixedOrder < DepthProfileKind.dualCameraDisparity.fixedOrder)
        #expect(DepthProfileKind.dualCameraDisparity.fixedOrder < DepthProfileKind.dualWideDisparity.fixedOrder)
        #expect(DepthProfileKind.dualWideDisparity.fixedOrder < DepthProfileKind.portraitSemanticDepth.fixedOrder)
    }

    @Test func automaticPriorityPrefersApplePairedVirtualPhotoPipelines() throws {
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInTripleCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInDualWideCamera))
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInDualWideCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInDualCamera))
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInDualCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInWideAngleCamera))
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInLiDARDepthCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInTrueDepthCamera))
    }

    @Test func zoomProfilesDisableUnsupportedDepthDeliveryRanges() throws {
        let profiles = CameraCapabilityResolver.makeZoomProfiles(
            candidateZooms: [1, 2, 3],
            minimumZoom: 1,
            maximumZoom: 3,
            depthDeliveryRanges: [1.0...2.0],
            allowsZoomOutsideDepthDeliveryRanges: false
        )

        #expect(profiles.map(\.displayName) == ["1x", "2x", "3x"])
        #expect(profiles[0].isEnabled)
        #expect(profiles[1].isEnabled)
        #expect(!profiles[2].isEnabled)
        #expect(profiles[2].disabledReason == "Outside depth zoom range")
    }

    @Test func zoomProfilesStillDisableZoomOutsideDepthSafeRangesWhenFormatAllowsPreviewZoom() throws {
        let profiles = CameraCapabilityResolver.makeZoomProfiles(
            candidateZooms: [1, 2, 3],
            minimumZoom: 1,
            maximumZoom: 3,
            depthDeliveryRanges: [1.0...1.0],
            allowsZoomOutsideDepthDeliveryRanges: true
        )

        #expect(profiles[0].isEnabled)
        #expect(!profiles[1].isEnabled)
        #expect(!profiles[2].isEnabled)
        #expect(profiles[1].disabledReason == "Zoom would drop depth delivery")
    }

    @Test func zoomProfilesWithoutDepthPairingUseCameraZoomRange() throws {
        let profiles = CameraCapabilityResolver.makeZoomProfiles(
            candidateZooms: [1, 2, 3],
            minimumZoom: 1,
            maximumZoom: 3,
            depthDeliveryRanges: [],
            allowsZoomOutsideDepthDeliveryRanges: true,
            requiresDepthSafeZoom: false
        )

        #expect(profiles.allSatisfy { $0.isEnabled })
    }

    @Test func debugZoomFOVUsesBaseEquivalentFocalLengthTimesVideoZoom() throws {
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 24, zoomFactor: 1) == 24)
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 24, zoomFactor: 2) == 48)
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 24, zoomFactor: 3) == 72)
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 13, zoomFactor: 2) == 26)
    }

    @Test func virtualDepthPipelinesUseWideBaselineForFOVLabels() throws {
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue))
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInDualWideCamera.rawValue))
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInDualCamera.rawValue))
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue))
        #expect(!FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue))
        #expect(FocalLengthLabelResolver.equivalentMillimeters(baseMillimeters: 24, zoomFactor: 1) == 24)
        #expect(FocalLengthLabelResolver.equivalentMillimeters(baseMillimeters: 24, zoomFactor: 2) == 48)
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 13, zoomFactor: 0.5))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 13, zoomFactor: 1))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 24, zoomFactor: 1))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 48, zoomFactor: 2))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 77, zoomFactor: 3))
        #expect(!FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 26, zoomFactor: 2))
        #expect(!FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 154, zoomFactor: 2))
    }

    @Test func debugZoomDisplayIsRelativeToWideFOVBaseline() throws {
        #expect(FocalLengthLabelResolver.displayZoomFactor(rawVideoZoomFactor: 2, wideReferenceZoomFactor: 2) == 1)
        #expect(FocalLengthLabelResolver.displayZoomFactor(rawVideoZoomFactor: 4, wideReferenceZoomFactor: 2) == 2)
        #expect(FocalLengthLabelResolver.displayZoomFactor(rawVideoZoomFactor: 6, wideReferenceZoomFactor: 2) == 3)

        let profile = ZoomProfile.enabled(2, displayZoomFactor: 1)
        #expect(profile.id == "zoom-2x")
        #expect(profile.displayName == "1x")
        #expect(profile.rawVideoZoomFactor == 2)
    }

    @Test func discovered48mmFOVOptionUsesResolvedRawVideoZoomWhenAvailable() throws {
        let options = CameraCapabilityResolver.discover().focalLengthOptions()
        if let option = options.first(where: { $0.displayName == "48mm" && $0.isEnabled }) {
            let expectedRawZoom = FocalLengthLabelResolver.releaseVideoZoomFactor(
                for: option.rgbSource,
                targetEquivalentMillimeters: 48,
                formatSelection: option.depthSource?.formatSelection
            )
            #expect(abs(option.zoom.rawVideoZoomFactor - expectedRawZoom) < 0.001)

            let lowerDepthSafeBound = option.depthSource?.formatSelection?.videoFormat.supportedVideoZoomRangesForDepthDataDelivery
                .map { Double($0.lowerBound) }
                .min() ?? 1
            if lowerDepthSafeBound > 1.0 {
                #expect(option.zoom.rawVideoZoomFactor > 2.0)
            }
        }
        #expect(!options.contains(where: { $0.displayName == "26mm" && $0.zoom.rawVideoZoomFactor == 2.0 }))
        #expect(!options.contains(where: { $0.displayName == "154mm" && $0.zoom.rawVideoZoomFactor == 2.0 }))
    }

    @Test func pairingPlanKeepsCustomReleaseFOVZoomFactor() throws {
        let options = CameraCapabilityResolver.discover().focalLengthOptions()
        if let option = options.first(where: { $0.displayName == "48mm" && $0.isEnabled }) {
            let plan = CaptureSourcePlan.make(
                rgbSource: option.rgbSource,
                depthSource: option.depthSource,
                selectionMode: .automatic,
                selectedZoomID: option.zoom.id,
                selectedZoomFactor: option.zoom.rawVideoZoomFactor,
                cropRectNormalized: .fullFrame
            )

            #expect(abs((plan.zoom?.rawVideoZoomFactor ?? 0) - option.zoom.rawVideoZoomFactor) < 0.001)
        }
    }

    @Test func runtimePackagingStrategyIsEmbeddedPhotoOnly() throws {
        #expect(PackagingStrategy.embeddedPhoto.rawValue == "embeddedPhoto")
    }

    @Test func depthSelectionModeKeepsPublishedManifestRawValues() throws {
        #expect(DepthSelectionMode.automatic.rawValue == "auto")
        #expect(DepthSelectionMode.manual.rawValue == "manual")
        #expect(DepthSelectionMode.debugDepthOverride.rawValue == "debugDepthOverride")
    }

    @Test func orientationMapperRoundTripsRightRotatedSelectionRect() throws {
        let nativeSize = CGSize(width: 4, height: 3)
        let nativeRect = CGRect(x: 1, y: 0, width: 2, height: 1)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: nativeRect,
            nativeSize: nativeSize,
            orientation: .right
        )
        let roundTripped = TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedRect,
            nativeSize: nativeSize,
            orientation: .right
        )

        #expect(roundTripped == nativeRect)
        #expect(TAPImageOrientationMapper.displayedSize(nativeSize: nativeSize, orientation: .right) == CGSize(width: 3, height: 4))
    }

    @Test func heatmapVisualizationPublishesRangeLegendAndDistinctColors() throws {
        let depthMap = TAPMetricDepthMap(
            width: 3,
            height: 1,
            samples: [0, 1.0, 3.0],
            calibration: nil
        )

        let heatmap = try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        #expect(abs(heatmap.rangeMeters.lowerBound - 1.0) < 0.0001)
        #expect(abs(heatmap.rangeMeters.upperBound - 3.0) < 0.0001)
        #expect(heatmap.legendStops.count == 5)
        #expect(heatmap.legendStops.first?.label.contains("Near") == true)
        #expect(heatmap.legendStops.last?.label.contains("Far") == true)

        let near = TAPDepthHeatmapRenderer.viridisColor(normalized: 0)
        let middle = TAPDepthHeatmapRenderer.viridisColor(normalized: 0.5)
        let far = TAPDepthHeatmapRenderer.viridisColor(normalized: 1)
        #expect(near != middle)
        #expect(middle != far)
        #expect(near != far)

        let pixels = TAPDepthHeatmapRenderer.heatmapPixels(for: depthMap, rangeMeters: heatmap.rangeMeters)
        #expect(pixels[3] == 0)
        #expect(pixels[7] == 255)
    }

    @Test func regionHeatmapUsesSelectedSamplesForRangeAndMasksOutsideRegion() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 1,
            samples: [1.0, 2.0, 8.0, 9.0],
            calibration: nil
        )

        let globalHeatmap = try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        let regionHeatmap = try TAPDepthHeatmapRenderer.heatmap(
            for: depthMap,
            region: CGRect(x: 2, y: 0, width: 2, height: 1)
        )
        let regionPixels = TAPDepthHeatmapRenderer.heatmapPixels(
            for: depthMap,
            rangeMeters: regionHeatmap.rangeMeters,
            visibleRegion: CGRect(x: 2, y: 0, width: 2, height: 1)
        )

        #expect(globalHeatmap.rangeScope == .global)
        #expect(regionHeatmap.rangeScope == .region)
        #expect(abs(globalHeatmap.rangeMeters.lowerBound - 1.0) < 0.0001)
        #expect(abs(globalHeatmap.rangeMeters.upperBound - 9.0) < 0.0001)
        #expect(abs(regionHeatmap.rangeMeters.lowerBound - 8.0) < 0.0001)
        #expect(abs(regionHeatmap.rangeMeters.upperBound - 9.0) < 0.0001)
        #expect(regionHeatmap.legendStops.count == 5)
        #expect(regionPixels[3] == 0)
        #expect(regionPixels[7] == 0)
        #expect(regionPixels[11] == 255)
        #expect(regionPixels[15] == 255)
    }

    @Test func regionHeatmapRejectsInvalidOnlySelection() throws {
        let depthMap = TAPMetricDepthMap(
            width: 3,
            height: 1,
            samples: [0, .nan, 2.0],
            calibration: nil
        )

        do {
            _ = try TAPDepthHeatmapRenderer.heatmap(
                for: depthMap,
                region: CGRect(x: 0, y: 0, width: 2, height: 1)
            )
            #expect(Bool(false), "Expected invalid-only region to throw.")
        } catch TAPDepthAnalysisError.noValidDepthSamples {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func maskOverlayUsesTransparencyAndBoundaryColorInsteadOfPureWhite() throws {
        let fullValid = TAPMetricDepthMap(
            width: 3,
            height: 3,
            samples: Array(repeating: 1.0, count: 9),
            calibration: nil
        )

        let pixels = TAPDepthMaskRenderer.overlayPixels(for: fullValid)
        let centerOffset = (1 + 1 * fullValid.width) * 4
        let cornerOffset = 0
        #expect(pixels[centerOffset + 3] == TAPDepthMaskRenderer.validFillColor.alpha)
        #expect(pixels[cornerOffset + 3] == TAPDepthMaskRenderer.boundaryColor.alpha)
        #expect(Array(pixels[centerOffset..<(centerOffset + 3)]) != [255, 255, 255])

        let mixed = TAPMetricDepthMap(
            width: 1,
            height: 2,
            samples: [1.0, 0],
            calibration: nil
        )
        let mixedPixels = TAPDepthMaskRenderer.overlayPixels(for: mixed)
        #expect(mixedPixels[3] == TAPDepthMaskRenderer.boundaryColor.alpha)
        #expect(mixedPixels[7] == 0)

        let mask = try TAPDepthMaskRenderer.validMask(for: mixed)
        #expect(mask.validSampleCount == 1)
        #expect(mask.totalSampleCount == 2)
        #expect(mask.validRatio == 0.5)
        #expect(mask.legendStops.map(\.label) == ["Valid depth", "Valid/invalid edge"])
    }

    @Test func appAppearanceIsLockedToDarkMode() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String == "Dark")
    }

    @Test func photoSettingsSuppressShutterSoundOnlyWhenRequestedAndSupported() throws {
        let photoOutput = AVCapturePhotoOutput()
        let resolvedOutput = try SingleCamPhotoSettingsFactory.resolvedOutput(photoOutput: photoOutput)
        let defaultSettings = SingleCamPhotoSettingsFactory.make(
            photoOutput: photoOutput,
            resolvedOutput: resolvedOutput
        )
        let quietSettings = SingleCamPhotoSettingsFactory.make(
            photoOutput: photoOutput,
            resolvedOutput: resolvedOutput,
            suppressesShutterSound: true
        )

        #expect(!defaultSettings.isShutterSoundSuppressionEnabled)
        #expect(quietSettings.isShutterSoundSuppressionEnabled == photoOutput.isShutterSoundSuppressionSupported)
    }

    @Test func analysisPanelLayoutMetricsUsesOnePointViewportBeforeMeasurement() throws {
        let metrics = AnalysisPanelLayoutMetrics(maxHeight: 300, measuredContentHeight: 0)

        #expect(metrics.contentMaxHeight == 222)
        #expect(metrics.contentViewportHeight == 1)
        #expect(!metrics.showsScrollIndicators)
    }

    @Test func analysisPanelLayoutMetricsFitsShortMeasuredContentWithoutScrolling() throws {
        let metrics = AnalysisPanelLayoutMetrics(maxHeight: 300, measuredContentHeight: 120)

        #expect(metrics.contentMaxHeight == 222)
        #expect(metrics.contentViewportHeight == 120)
        #expect(!metrics.showsScrollIndicators)
    }

    @Test func analysisPanelLayoutMetricsCapsOverflowingContentAndEnablesScrolling() throws {
        let metrics = AnalysisPanelLayoutMetrics(maxHeight: 300, measuredContentHeight: 260)

        #expect(metrics.contentMaxHeight == 222)
        #expect(metrics.contentViewportHeight == 222)
        #expect(metrics.showsScrollIndicators)
    }

    @Test func analysisPanelLayoutMetricsKeepsMinimumContentHeightForSmallPanels() throws {
        let fittingMetrics = AnalysisPanelLayoutMetrics(maxHeight: 120, measuredContentHeight: 70)
        let overflowingMetrics = AnalysisPanelLayoutMetrics(maxHeight: 120, measuredContentHeight: 90)

        #expect(fittingMetrics.contentMaxHeight == 72)
        #expect(fittingMetrics.contentViewportHeight == 70)
        #expect(!fittingMetrics.showsScrollIndicators)

        #expect(overflowingMetrics.contentMaxHeight == 72)
        #expect(overflowingMetrics.contentViewportHeight == 72)
        #expect(overflowingMetrics.showsScrollIndicators)
    }

    private static func source(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func swiftSourceRelativePaths(under relativeDirectory: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directoryURL = root.appendingPathComponent(relativeDirectory)
        let fileManager = FileManager.default
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        return fileURLs
            .filter { $0.pathExtension == "swift" }
            .map { relativeDirectory + "/" + $0.lastPathComponent }
            .sorted()
    }

    private static func reflectedNames(in value: Any, depth: Int = 0) -> [String] {
        guard depth < 6 else {
            return []
        }

        let mirror = Mirror(reflecting: value)
        var names = [String(reflecting: type(of: value))]
        for child in mirror.children {
            if let label = child.label {
                names.append(label)
            }
            names.append(contentsOf: reflectedNames(in: child.value, depth: depth + 1))
        }
        return names
    }
}
