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
        let generationID = 1
        state.generationID = generationID

        state.startDetection(generationID: generationID)

        #expect(state.selectedRegion == nil)
        #expect(state.isDetecting)
        #expect(state.errorMessage == nil)

        state.finishDetection(detection, generationID: generationID)

        #expect(state.selectedRegion == region)
        #expect(!state.isDetecting)
        #expect(state.errorMessage == nil)
        #expect(state.completedGridToastID != nil)

        state.startDetection(generationID: generationID)
        state.finishFailure(TAPPlaneGrowthError.invalidSeed, generationID: generationID)

        #expect(state.selectedRegion == nil)
        #expect(!state.isDetecting)
        #expect(state.errorMessage == "No valid depth at this point.")

        state.startDetection(generationID: generationID)
        state.finishFailure(
            DepthAnalysisPlaneSelectionTestError.sensitiveLocalizedFailure("/private/tmp/plane-cache"),
            generationID: generationID
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

    @Test func depthAnalysisPlaneSelectionStateStreamsPartialGridAndDropsStaleEvents() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        var state = DepthAnalysisPlaneSelectionState()
        let generationID = state.selectSeed(CGPoint(x: 4, y: 4), depthMap: depthMap)
        let staleRegion = Self.samplePlaneRegion(seedPixel: CGPoint(x: 1, y: 1))
        let currentRegion = Self.samplePlaneRegion(seedPixel: CGPoint(x: 4, y: 4))

        state.applyPartialGrid(
            TAPPlaneGridProgress(seedPixel: CGPoint(x: 1, y: 1), gridCells: staleRegion.gridCells, progress: 0.4),
            generationID: generationID - 1
        )
        #expect(state.partialGridCells.isEmpty)

        state.applyPartialGrid(
            TAPPlaneGridProgress(seedPixel: CGPoint(x: 4, y: 4), gridCells: currentRegion.gridCells, progress: 0.5),
            generationID: generationID
        )
        #expect(state.partialGridCells == currentRegion.gridCells)
        #expect(state.gridProgress == 0.5)

        state.finishDetection(
            DepthAnalysisPlaneRegionDetection(region: staleRegion, geometryCache: nil),
            generationID: generationID - 1
        )
        #expect(state.selectedRegion == nil)
        #expect(state.partialGridCells == currentRegion.gridCells)

        state.finishDetection(
            DepthAnalysisPlaneRegionDetection(region: currentRegion, geometryCache: nil),
            generationID: generationID
        )
        #expect(state.selectedRegion == currentRegion)
        #expect(state.partialGridCells.isEmpty)
        #expect(state.gridProgress == 1)
        #expect(state.completedGridToastID != nil)
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
