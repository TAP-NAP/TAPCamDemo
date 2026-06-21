//
//  TAPDepthAnalysisPlaneRegionTests.swift
//  TAPCamDemoTests
//
//  Created by OpenAI on 2026/6/13.
//

import CoreGraphics
import Foundation
import simd
import Testing
@testable import TAPCamDemo

struct TAPDepthAnalysisPlaneRegionTests {
    @Test func projectorUsesCalibrationToProduceCameraCoordinates() throws {
        let depthMap = TAPMetricDepthMap(
            width: 8,
            height: 8,
            samples: Array(repeating: 2.0, count: 64),
            calibration: Self.sampleCalibration
        )

        let center = try #require(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 4, y: 4))
        let right = try #require(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 5, y: 4))

        #expect(abs(center.x) < 0.0001)
        #expect(abs(center.y) < 0.0001)
        #expect(abs(center.z - 2.0) < 0.0001)
        #expect(abs(right.x - 0.02) < 0.0001)
    }

    @Test func cameraIntrinsicsRejectNonFiniteAndZeroCalibration() throws {
        let zeroFocalCalibration = Self.calibration(
            width: 8,
            height: 8,
            intrinsicMatrix: [0, 0, 0, 0, 140, 0, 4, 4, 1]
        )
        let nonFiniteCalibration = Self.calibration(
            width: 8,
            height: 8,
            intrinsicMatrix: [Float.nan, 0, 0, 0, 140, 0, 4, 4, 1]
        )
        let badReferenceCalibration = Self.calibration(
            width: 8,
            height: 8,
            referenceWidth: .infinity
        )

        #expect(TAPCameraIntrinsics(calibration: zeroFocalCalibration, depthWidth: 8, depthHeight: 8) == nil)
        #expect(TAPCameraIntrinsics(calibration: nonFiniteCalibration, depthWidth: 8, depthHeight: 8) == nil)
        #expect(TAPCameraIntrinsics(calibration: badReferenceCalibration, depthWidth: 8, depthHeight: 8) == nil)

        let depthMap = TAPMetricDepthMap(
            width: 8,
            height: 8,
            samples: Array(repeating: Float(1.5), count: 64),
            calibration: nonFiniteCalibration
        )

        #expect(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 4, y: 4) == nil)

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 4, y: 4),
                strictness: 0.68
            )
            Issue.record("Expected invalid calibration to use the missing-calibration plane error.")
        } catch TAPPlaneGrowthError.cameraCalibrationMissing {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected plane growth error: \(error)")
        }
    }

    @Test func seedPlaneGrowthRejectsNonFiniteSeedBeforePixelConversion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: CGFloat.nan, y: 8),
                strictness: 0.68
            )
            Issue.record("Expected non-finite seed to fail before pixel conversion.")
        } catch TAPPlaneGrowthError.invalidSeed {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected non-finite seed error: \(error)")
        }
    }

    @Test func planeEstimatorFindsSyntheticFlatDepthRegion() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: 1.5, count: 256),
            calibration: TAPDepthManifest.CameraCalibration(
                intrinsicMatrixReferenceWidth: 16,
                intrinsicMatrixReferenceHeight: 16,
                pixelSizeMillimeters: 0.001,
                lensDistortionLookupTablePresent: false,
                inverseLensDistortionLookupTablePresent: false,
                lensDistortionCenterX: 8,
                lensDistortionCenterY: 8,
                intrinsicMatrix: [120, 0, 0, 0, 120, 0, 8, 8, 1],
                extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
            )
        )

        let plane = try #require(TAPPlaneEstimator.estimatePlane(depthMap: depthMap, region: CGRect(x: 0, y: 0, width: 16, height: 16)))

        #expect(plane.averageResidualMeters < 0.001)
        #expect(plane.inlierRatio > 0.95)
        #expect(abs(abs(plane.normal.z) - 1) < 0.001)
    }

    @Test func planeDetectorFindsAndFiltersHighConfidenceFlatRegions() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: 1.5, count: 256),
            calibration: TAPDepthManifest.CameraCalibration(
                intrinsicMatrixReferenceWidth: 16,
                intrinsicMatrixReferenceHeight: 16,
                pixelSizeMillimeters: 0.001,
                lensDistortionLookupTablePresent: false,
                inverseLensDistortionLookupTablePresent: false,
                lensDistortionCenterX: 8,
                lensDistortionCenterY: 8,
                intrinsicMatrix: [120, 0, 0, 0, 120, 0, 8, 8, 1],
                extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
            )
        )

        let planes = TAPPlaneEstimator.detectPlanes(depthMap: depthMap)

        #expect(!planes.isEmpty)
        #expect(planes.first?.confidence ?? 0 > 0.95)
        #expect(TAPPlaneEstimator.filteredPlanes(planes, minimumConfidence: 0.95).count == planes.count)
        #expect(TAPPlaneEstimator.filteredPlanes(planes, minimumConfidence: 1.01).isEmpty)
    }

    @Test func seedPlaneGrowthFindsLargeTiltedPlaneRegion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68
        )

        #expect(region.sampleCount > 700)
        #expect(region.confidence > 0.82)
        #expect(region.flatnessScore > 0.90)
        #expect(region.areaSquareMeters > 0)
        #expect(!region.pixelRuns.isEmpty)
        #expect(!region.gridCells.isEmpty)
        #expect(region.gridCells.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })
        #expect(!region.contourPoints.isEmpty)
    }

    @Test func depthAnalysisPlaneRegionDetectorBuildsGeometryAndDetectsRegion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)
        let detector = DepthAnalysisPlaneRegionDetector()

        let detection = try detector.detectRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68,
            geometryCache: nil
        )

        #expect(detection.geometryCache?.matches(depthMap: depthMap) == true)
        #expect(detection.region.sampleCount > 700)
        #expect(detection.region.confidence > 0.82)
    }

    @Test func depthAnalysisPlaneRegionDetectorReusesMatchingGeometryCache() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)
        let builtGeometryCache = try TAPDepthGeometryProjector.geometryCache(for: depthMap)
        let geometryCache = try #require(builtGeometryCache)
        var builderWasCalled = false
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { _, _ in
                builderWasCalled = true
                return nil
            },
            planeRegionGrower: { depthMap, seed, strictness, geometryCache, shouldCancel in
                #expect(geometryCache?.matches(depthMap: depthMap) == true)
                return try TAPPlaneEstimator.growPlaneRegion(
                    depthMap: depthMap,
                    seed: seed,
                    strictness: strictness,
                    geometryCache: geometryCache,
                    shouldCancel: shouldCancel
                )
            }
        )

        let detection = try detector.detectRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68,
            geometryCache: geometryCache
        )

        #expect(builderWasCalled == false)
        #expect(detection.geometryCache?.matches(depthMap: depthMap) == true)
    }

    @Test @MainActor func depthAnalysisPlaneRegionRequestCoordinatorKeepsGeometryCacheAcrossRegionCancel() async throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        let builderCallCount = LockedCounter()
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { depthMap, shouldCancel in
                builderCallCount.increment()
                return try TAPDepthGeometryProjector.geometryCache(
                    for: depthMap,
                    shouldCancel: shouldCancel
                )
            },
            planeRegionGrower: { depthMap, seed, _, geometryCache, _ in
                #expect(geometryCache?.matches(depthMap: depthMap) == true)
                return Self.samplePlaneRegion(seedPixel: seed)
            }
        )
        let coordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: detector)
        var events: [DepthAnalysisPlaneRegionRequestEvent] = []

        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 4, y: 4),
            strictness: 0.68,
            eventHandler: { events.append($0) }
        )
        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 1
        }
        #expect(builderCallCount.count == 1)

        coordinator.cancelRegionRequest()
        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 5, y: 5),
            strictness: 0.68,
            eventHandler: { events.append($0) }
        )
        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 2
        }

        #expect(builderCallCount.count == 1)
        #expect(Self.succeededPlaneRegions(in: events).map(\.seedPixel) == [
            CGPoint(x: 4, y: 4),
            CGPoint(x: 5, y: 5)
        ])
    }

    @Test @MainActor func depthAnalysisPlaneRegionRequestCoordinatorPublishesOnlyNewestRegionRequest() async throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { _, _ in nil },
            planeRegionGrower: { _, seed, _, _, _ in
                if seed == CGPoint(x: 1, y: 1) {
                    Thread.sleep(forTimeInterval: 0.06)
                }
                return Self.samplePlaneRegion(seedPixel: seed)
            }
        )
        let coordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: detector)
        var events: [DepthAnalysisPlaneRegionRequestEvent] = []

        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 1, y: 1),
            strictness: 0.68,
            eventHandler: { events.append($0) }
        )
        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 2, y: 2),
            strictness: 0.68,
            eventHandler: { events.append($0) }
        )

        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 1
        }
        try await Task.sleep(nanoseconds: 90_000_000)

        #expect(Self.startedPlaneRequestCount(in: events) == 2)
        #expect(Self.succeededPlaneRegions(in: events).map(\.seedPixel) == [
            CGPoint(x: 2, y: 2)
        ])
    }

    @Test func seedPlaneGrowthFindsContinuousPlanesAcrossTiltAngles() throws {
        let width = 56
        let height = 44
        let cases: [(normal: SIMD3<Float>, seed: CGPoint)] = [
            (simd_normalize(SIMD3<Float>(-0.20, 0.00, 0.98)), CGPoint(x: 28, y: 22)),
            (simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70)), CGPoint(x: 22, y: 22)),
            (simd_normalize(SIMD3<Float>(0.74, -0.24, 0.63)), CGPoint(x: 34, y: 20)),
            (simd_normalize(SIMD3<Float>(-0.86, 0.18, 0.48)), CGPoint(x: 20, y: 24))
        ]

        for testCase in cases {
            let depthMap = Self.syntheticObliqueWallDepthMap(
                width: width,
                height: height,
                normal: testCase.normal
            )

            let region = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: testCase.seed,
                strictness: 0.68
            )

            #expect(region.sampleCount > Int(Double(width * height) * 0.70))
            #expect(region.confidence > 0.80)
            #expect(region.flatnessScore > 0.88)
            #expect(region.imageBounds.width > CGFloat(width) * 0.65)
            #expect(region.imageBounds.height > CGFloat(height) * 0.65)
        }
    }

    @Test func seedPlaneGrowthKeepsNoisyObliqueWallConnected() throws {
        let depthMap = Self.syntheticNoisyObliqueWallDepthMap(width: 52, height: 42)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 24, y: 21),
            strictness: 0.55
        )

        #expect(region.sampleCount > 1_100)
        #expect(region.gridCells.count > 8)
        #expect(region.confidence > 0.62)
    }

    @Test func seedPlaneGrowthDoesNotLeakAcrossObliqueWallBoundary() throws {
        let depthMap = Self.syntheticSplitPlaneDepthMap(width: 48, height: 40)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 14, y: 20),
            strictness: 0.62
        )

        #expect(region.sampleCount > 650)
        #expect(region.imageBounds.maxX < 30)
    }

    @Test func seedPlaneGrowthShrinksOnCurvedDepthWhenStrictnessIncreases() throws {
        let depthMap = Self.syntheticCurvedDepthMap(width: 36, height: 36)

        let loose = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 18, y: 18),
            strictness: 0.35
        )
        let strict = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 18, y: 18),
            strictness: 0.95
        )

        #expect(strict.sampleCount <= loose.sampleCount)
        #expect(strict.flatnessScore <= loose.flatnessScore || strict.sampleCount < loose.sampleCount)
    }

    @Test func seedPlaneGrowthRejectsInvalidSeed() throws {
        var samples = Array(repeating: Float(1.4), count: 16 * 16)
        samples[8 + 8 * 16] = 0
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: samples,
            calibration: Self.calibration(width: 16, height: 16)
        )

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 8, y: 8),
                strictness: 0.68
            )
            #expect(Bool(false), "Expected invalid seed to throw.")
        } catch TAPPlaneGrowthError.invalidSeed {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func seedPlaneGrowthReportsMissingCameraCalibration() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: Float(1.4), count: 16 * 16),
            calibration: nil
        )

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 8, y: 8),
                strictness: 0.68
            )
            #expect(Bool(false), "Expected missing calibration to throw.")
        } catch TAPPlaneGrowthError.cameraCalibrationMissing {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
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

    @MainActor
    private static func waitForCondition(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: () -> Bool
    ) async throws {
        let pollIntervalNanoseconds: UInt64 = 10_000_000
        let attempts = Int(max(timeoutNanoseconds / pollIntervalNanoseconds, 1))

        for _ in 0..<attempts {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        try #require(condition())
    }

    private static func startedPlaneRequestCount(in events: [DepthAnalysisPlaneRegionRequestEvent]) -> Int {
        events.filter { event in
            if case .started = event {
                return true
            }
            return false
        }.count
    }

    private static func succeededPlaneRegions(in events: [DepthAnalysisPlaneRegionRequestEvent]) -> [TAPPlaneRegion] {
        events.compactMap { event in
            if case .succeeded(let detection) = event {
                return detection.region
            }
            return nil
        }
    }

    private static func syntheticCurvedDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.10, 0.04, 1.0))
        var samples = depthSamples(width: width, height: height, normal: normal, planeD: -1.45, calibration: calibration)
        let centerX = Float(width - 1) / 2
        let centerY = Float(height - 1) / 2

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                samples[x + y * width] += (dx * dx + dy * dy) * 0.00022
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func syntheticObliqueWallDepthMap(
        width: Int,
        height: Int,
        normal: SIMD3<Float> = simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70))
    ) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: depthSamples(width: width, height: height, normal: normal, planeD: -1.55, calibration: calibration),
            calibration: calibration
        )
    }

    private static func syntheticNoisyObliqueWallDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.70, 0.03, 0.71))
        var samples = depthSamples(width: width, height: height, normal: normal, planeD: -1.60, calibration: calibration)

        for y in 0..<height {
            for x in 0..<width {
                let index = x + y * width
                if (x + y * 3).isMultiple(of: 23) {
                    samples[index] = 0
                } else {
                    let deterministicNoise = Float(((x * 17 + y * 29) % 11) - 5) * 0.0012
                    samples[index] += deterministicNoise
                }
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func syntheticSplitPlaneDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let leftNormal = simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70))
        let rightNormal = simd_normalize(SIMD3<Float>(0.18, -0.04, 1.0))
        let left = depthSamples(width: width, height: height, normal: leftNormal, planeD: -1.52, calibration: calibration)
        let right = depthSamples(width: width, height: height, normal: rightNormal, planeD: -2.25, calibration: calibration)
        var samples = left

        for y in 0..<height {
            for x in width / 2..<width {
                samples[x + y * width] = right[x + y * width]
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
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

    private static func calibration(
        width: Int,
        height: Int,
        referenceWidth: Double? = nil,
        referenceHeight: Double? = nil,
        intrinsicMatrix: [Float]? = nil,
        extrinsicMatrix: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    ) -> TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: referenceWidth ?? Double(width),
            intrinsicMatrixReferenceHeight: referenceHeight ?? Double(height),
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: Double(width) / 2,
            lensDistortionCenterY: Double(height) / 2,
            intrinsicMatrix: intrinsicMatrix ?? [140, 0, 0, 0, 140, 0, Float(width) / 2, Float(height) / 2, 1],
            extrinsicMatrix: extrinsicMatrix
        )
    }

    private static var sampleCalibration: TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: 8,
            intrinsicMatrixReferenceHeight: 8,
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: 4,
            lensDistortionCenterY: 4,
            intrinsicMatrix: [100, 0, 0, 0, 100, 0, 4, 4, 1],
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock {
            value
        }
    }

    func increment() {
        lock.withLock {
            value += 1
        }
    }
}
