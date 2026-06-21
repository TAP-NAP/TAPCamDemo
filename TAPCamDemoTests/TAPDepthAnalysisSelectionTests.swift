//
//  TAPDepthAnalysisSelectionTests.swift
//  TAPCamDemoTests
//

import CoreGraphics
import Foundation
import simd
import Testing
@testable import TAPCamDemo

struct TAPDepthAnalysisSelectionTests {
    @Test func depthAnalysisRegionSelectionStateBeginsAndPreviewsWithoutDerivedProducts() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 4,
            samples: (1...16).map(Float.init),
            calibration: nil
        )
        var state = DepthAnalysisRegionSelectionState()
        state.finishSelection(CGRect(x: 1, y: 1, width: 2, height: 2), depthMap: depthMap)
        #expect(state.regionStats != nil)
        #expect(state.regionHeatmap != nil)

        state.beginSelection(CGRect(x: 0, y: 0, width: 2, height: 2), depthMap: depthMap)

        #expect(state.selectionRect == CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(state.interactionState == .drawingSelection)
        #expect(state.regionStats == nil)
        #expect(state.regionHeatmap == nil)
        #expect(state.regionHeatmapErrorMessage == nil)
        #expect(state.planeEstimate == nil)

        state.previewSelection(CGRect(x: 2, y: 2, width: 3, height: 3), depthMap: depthMap)

        #expect(state.selectionRect == CGRect(x: 2, y: 2, width: 2, height: 2))
        #expect(state.interactionState == .drawingSelection)
        #expect(state.regionStats == nil)
        #expect(state.regionHeatmap == nil)
        #expect(state.planeEstimate == nil)
    }

    @Test func depthAnalysisRegionSelectionStateFinishesWithStatsHeatmapAndPlaneEstimate() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        var state = DepthAnalysisRegionSelectionState()

        state.finishSelection(CGRect(x: 4, y: 4, width: 8, height: 8), depthMap: depthMap)

        #expect(state.selectionRect == CGRect(x: 4, y: 4, width: 8, height: 8))
        #expect(state.interactionState == .regionSelected)
        #expect(state.regionStats?.validSampleCount == 64)
        #expect(state.regionStats?.totalSampleCount == 64)
        #expect(state.regionHeatmap?.rangeScope == .region)
        #expect(state.regionHeatmapErrorMessage == nil)
        #expect(state.planeEstimate != nil)
    }

    @Test func depthAnalysisRegionSelectionStateClearRemovesSelectionAndDerivedProducts() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        var state = DepthAnalysisRegionSelectionState()
        state.finishSelection(CGRect(x: 4, y: 4, width: 8, height: 8), depthMap: depthMap)
        #expect(state.selectionRect != nil)
        #expect(state.regionStats != nil)
        #expect(state.planeEstimate != nil)

        state.clear()

        #expect(state.selectionRect == nil)
        #expect(state.interactionState == .idle)
        #expect(state.regionStats == nil)
        #expect(state.regionHeatmap == nil)
        #expect(state.regionHeatmapErrorMessage == nil)
        #expect(state.planeEstimate == nil)
    }

    @Test func depthAnalysisRegionSelectionStateClampsOutOfBoundsSelection() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 4,
            samples: (1...16).map(Float.init),
            calibration: nil
        )
        var state = DepthAnalysisRegionSelectionState()

        state.finishSelection(CGRect(x: -4, y: -2, width: 10, height: 8), depthMap: depthMap)

        #expect(state.selectionRect == CGRect(x: 0, y: 0, width: 4, height: 4))
        #expect(state.interactionState == .regionSelected)
        #expect(state.regionStats?.totalSampleCount == 16)
    }

    @Test func depthAnalysisRegionSelectionStateMapsInvalidRegionHeatmapToGenericMessage() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 4,
            samples: Array(repeating: Float(0), count: 16),
            calibration: nil
        )
        var state = DepthAnalysisRegionSelectionState()

        state.finishSelection(CGRect(x: 0, y: 0, width: 4, height: 4), depthMap: depthMap)

        #expect(state.interactionState == .regionSelected)
        #expect(state.regionStats?.validSampleCount == 0)
        #expect(state.regionHeatmap == nil)
        #expect(state.regionHeatmapErrorMessage == "Not enough valid depth samples in this region.")
        #expect(state.planeEstimate == nil)
    }

    @Test func depthAnalysisPlaneSelectionStateClampsSeedAndStrictness() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 3,
            samples: Array(repeating: Float(1.4), count: 12),
            calibration: nil
        )
        var state = DepthAnalysisPlaneSelectionState()

        state.selectSeed(CGPoint(x: -4, y: 10), depthMap: depthMap)
        state.updateStrictness(2)

        #expect(state.seedPoint == CGPoint(x: 0, y: 2))
        #expect(state.strictness == DepthAnalysisPlaneSelectionState.maximumStrictness)

        state.updateStrictness(-1)

        #expect(state.strictness == DepthAnalysisPlaneSelectionState.minimumStrictness)
    }

    @Test func depthAnalysisPlaneSelectionStateStartSuccessFailureAndClearTransitions() throws {
        var state = DepthAnalysisPlaneSelectionState()
        let region = Self.samplePlaneRegion()
        let detection = DepthAnalysisPlaneRegionDetection(region: region, geometryCache: nil)

        state.startDetection()

        #expect(state.selectedRegion == nil)
        #expect(state.isDetecting)
        #expect(state.errorMessage == nil)

        state.finishDetection(detection)

        #expect(state.selectedRegion == region)
        #expect(!state.isDetecting)
        #expect(state.errorMessage == nil)

        state.startDetection()
        state.finishFailure(TAPPlaneGrowthError.invalidSeed)

        #expect(state.selectedRegion == nil)
        #expect(!state.isDetecting)
        #expect(state.errorMessage == "No valid depth at this point.")

        state.startDetection()
        state.finishFailure(
            DepthAnalysisPlaneSelectionTestError.sensitiveLocalizedFailure("/private/tmp/plane-cache")
        )

        #expect(state.selectedRegion == nil)
        #expect(!state.isDetecting)
        #expect(state.errorMessage == "No stable plane region found from this point.")
        #expect(state.errorMessage?.contains("/private/tmp/plane-cache") == false)

        state.seedPoint = CGPoint(x: 2, y: 2)
        state.clear()

        #expect(state.seedPoint == nil)
        #expect(state.selectedRegion == nil)
        #expect(!state.isDetecting)
        #expect(state.errorMessage == nil)
    }

    @Test @MainActor func depthAnalysisViewModelBuildsRegionProductsOnlyAfterExplicitSelection() throws {
        let viewModel = DepthAnalysisViewModel()
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 4,
            samples: (1...16).map(Float.init),
            calibration: nil
        )
        viewModel.input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)

        #expect(viewModel.regionSelection.selectionRect == nil)
        #expect(viewModel.regionSelection.interactionState == .idle)
        #expect(viewModel.regionSelection.regionStats == nil)
        #expect(viewModel.regionSelection.regionHeatmap == nil)

        let explicitRegion = CGRect(x: 1, y: 1, width: 2, height: 2)
        viewModel.finishSelection(explicitRegion)

        #expect(viewModel.regionSelection.selectionRect == explicitRegion)
        #expect(viewModel.regionSelection.interactionState == .regionSelected)
        #expect(viewModel.regionSelection.regionStats?.validSampleCount == 4)
        #expect(viewModel.regionSelection.regionStats?.totalSampleCount == 4)
        #expect(viewModel.regionSelection.regionStats?.minimumDepthMeters == 6)
        #expect(viewModel.regionSelection.regionStats?.maximumDepthMeters == 11)
        #expect(viewModel.regionSelection.regionHeatmap?.rangeScope == .region)
    }

    @Test @MainActor func depthAnalysisViewModelClearSelectionRemovesDerivedRegionProducts() throws {
        let viewModel = DepthAnalysisViewModel()
        let stalePlaneEstimate = Self.samplePlaneEstimate()
        viewModel.regionSelection.selectionRect = CGRect(x: 1, y: 1, width: 4, height: 4)
        viewModel.regionSelection.interactionState = .regionSelected
        viewModel.regionSelection.regionStats = TAPDepthRegionStats(
            validSampleCount: 3,
            totalSampleCount: 4,
            minimumDepthMeters: 1,
            maximumDepthMeters: 2,
            medianDepthMeters: 1.5,
            validRatio: 0.75
        )
        viewModel.regionSelection.planeEstimate = stalePlaneEstimate
        viewModel.planeSelection.seedPoint = CGPoint(x: 3, y: 3)
        viewModel.planeSelection.selectedRegion = Self.samplePlaneRegion()
        viewModel.planeSelection.errorMessage = "stale plane"
        viewModel.regionSelection.regionHeatmapErrorMessage = "stale"

        viewModel.clearSelection()

        #expect(viewModel.regionSelection.selectionRect == nil)
        #expect(viewModel.regionSelection.interactionState == .idle)
        #expect(viewModel.regionSelection.regionStats == nil)
        #expect(viewModel.regionSelection.planeEstimate == nil)
        #expect(viewModel.regionSelection.regionHeatmap == nil)
        #expect(viewModel.regionSelection.regionHeatmapErrorMessage == nil)
        #expect(viewModel.planeSelection.seedPoint == nil)
        #expect(viewModel.planeSelection.selectedRegion == nil)
        #expect(viewModel.planeSelection.errorMessage == nil)
    }

    private static func syntheticPlaneDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.18, 0.08, 1.0))
        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: depthSamples(width: width, height: height, normal: normal, planeD: -1.55, calibration: calibration),
            calibration: calibration
        )
    }

    private static func samplePlaneEstimate() -> TAPPlaneEstimate {
        TAPPlaneEstimate(
            normal: SIMD3<Float>(0, 0, 1),
            centroid: SIMD3<Float>(0, 0, 1),
            averageResidualMeters: 0.01,
            inlierRatio: 0.9,
            depthRangeMeters: 1...2,
            imageBounds: CGRect(x: 1, y: 1, width: 4, height: 4)
        )
    }

    private static func samplePlaneRegion(seedPixel: CGPoint = CGPoint(x: 3, y: 3)) -> TAPPlaneRegion {
        TAPPlaneRegion(
            seedPixel: seedPixel,
            estimate: Self.samplePlaneEstimate(),
            pixelRuns: [TAPPlanePixelRun(y: 3, xStart: 3, xEndExclusive: 5)],
            gridCells: [
                TAPPlaneGridCell(
                    row: 0,
                    column: 0,
                    imageBounds: CGRect(x: 3, y: 3, width: 2, height: 1),
                    coverage: 1,
                    averageResidualMeters: 0.01,
                    confidence: 0.8,
                    sampleCount: 2
                )
            ],
            contourPoints: [CGPoint(x: 3, y: 3)],
            imageBounds: CGRect(x: 3, y: 3, width: 2, height: 1),
            confidence: 0.8,
            flatnessScore: 0.9,
            sampleCount: 2,
            areaSquareMeters: 0.01
        )
    }

    private static func calibration(width: Int, height: Int) -> TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: Double(width),
            intrinsicMatrixReferenceHeight: Double(height),
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: Double(width) / 2,
            lensDistortionCenterY: Double(height) / 2,
            intrinsicMatrix: [140, 0, 0, 0, 140, 0, Float(width) / 2, Float(height) / 2, 1],
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        )
    }

    private static func depthSamples(
        width: Int,
        height: Int,
        normal: SIMD3<Float>,
        planeD: Float,
        calibration: TAPDepthManifest.CameraCalibration
    ) -> [Float] {
        let intrinsics = TAPCameraIntrinsics(calibration: calibration, depthWidth: width, depthHeight: height)!
        var samples: [Float] = []
        samples.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let ray = SIMD3<Float>(
                    (Float(x) - intrinsics.cx) / intrinsics.fx,
                    (Float(y) - intrinsics.cy) / intrinsics.fy,
                    1
                )
                let denominator = simd_dot(normal, ray)
                samples.append(-planeD / denominator)
            }
        }

        return samples
    }
}

private enum DepthAnalysisPlaneSelectionTestError: LocalizedError {
    case sensitiveLocalizedFailure(String)

    var errorDescription: String? {
        switch self {
        case .sensitiveLocalizedFailure(let path):
            return "Raw plane failure at \(path)"
        }
    }
}
