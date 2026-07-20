//
//  DepthPlaneEstimator.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics
import simd

/// Fits approximate planes in camera coordinates. This is a single-image,
/// depth-map estimator; ARKit-style tracked planes require a separate AR
/// capture mode and are intentionally outside this module.
///
/// Planes mode principle:
/// Rectangular region analysis samples a selected image region into camera-space
/// points, then fits an approximate plane. Plane Filter uses the seed-grown path:
/// a tapped depth pixel validates an optional prewarmed geometry cache, fits a
/// seed-local weighted plane, grows a connected mask with point-to-plane
/// residuals, refits, and grows one more pass. Both paths describe approximate
/// coplanarity: normal, centroid, average residual, inlier ratio, depth range,
/// and image-space bounds.
///
/// Function and limits:
/// - Useful for asking "are these visible pixels roughly on the same plane?"
/// - Not equivalent to ARKit `ARPlaneAnchor`: there is no temporal tracking,
///   no world transform, and no system-level semantic plane classification.
///
/// Data dependencies:
/// - `TAPDepthGeometryProjector.sampledPoints` for region samples.
/// - `TAPDepthGeometryCache` for tap-time reuse of projected points and local
///   normals during seed-grown panel detection.
/// - `simd_cross`, `simd_dot`, and `simd_length` for plane equations and point
///   residuals.
/// - A cancellation closure for asynchronous Planes taps and cache prewarming.
///
/// File map:
/// - This file keeps the public facade and shared internal fitting models.
/// - `DepthPlaneEstimator+Fitting.swift` contains least-squares, RANSAC, and
///   robust threshold helpers.
/// - `DepthPlaneEstimator+RegionGrowth.swift` contains seed fitting, BFS
///   growth, pixel acceptance, and cancellation checks.
/// - `DepthPlaneEstimator+RegionOutput.swift` contains tile detection and the
///   final region runs, contours, grid cells, confidence, and bounds.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/accelerate/simd
/// - https://developer.apple.com/documentation/arkit/arplaneanchor
nonisolated enum TAPPlaneEstimator {
    struct PlaneModel {
        let normal: SIMD3<Float>
        let centroid: SIMD3<Float>
        let d: Float
        let residualThresholdMeters: Float
    }

    struct PlaneGrowthMask {
        let accepted: [Bool]
        /// Accepted pixels are retained separately so later samples, contours,
        /// and bounds do not need to scan the full depth map again.
        let acceptedPixels: [(x: Int, y: Int)]
    }

    struct SymmetricMatrix3 {
        var m00: Double = 0
        var m01: Double = 0
        var m02: Double = 0
        var m11: Double = 0
        var m12: Double = 0
        var m22: Double = 0

        func smallestEigenVector() -> SIMD3<Float>? {
            var matrix = [
                [m00, m01, m02],
                [m01, m11, m12],
                [m02, m12, m22]
            ]
            var vectors = [
                [1.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
                [0.0, 0.0, 1.0]
            ]

            for _ in 0..<16 {
                var p = 0
                var q = 1
                var largest = abs(matrix[0][1])
                let pairs = [(0, 2), (1, 2)]
                for pair in pairs where abs(matrix[pair.0][pair.1]) > largest {
                    p = pair.0
                    q = pair.1
                    largest = abs(matrix[p][q])
                }
                if largest < 1e-12 {
                    break
                }

                let theta = (matrix[q][q] - matrix[p][p]) / (2 * matrix[p][q])
                let sign = theta >= 0 ? 1.0 : -1.0
                let t = sign / (abs(theta) + sqrt(theta * theta + 1))
                let c = 1 / sqrt(t * t + 1)
                let s = t * c
                let app = matrix[p][p]
                let aqq = matrix[q][q]
                let apq = matrix[p][q]

                matrix[p][p] = c * c * app - 2 * s * c * apq + s * s * aqq
                matrix[q][q] = s * s * app + 2 * s * c * apq + c * c * aqq
                matrix[p][q] = 0
                matrix[q][p] = 0

                for r in 0..<3 where r != p && r != q {
                    let arp = matrix[r][p]
                    let arq = matrix[r][q]
                    matrix[r][p] = c * arp - s * arq
                    matrix[p][r] = matrix[r][p]
                    matrix[r][q] = s * arp + c * arq
                    matrix[q][r] = matrix[r][q]
                }

                for r in 0..<3 {
                    let vrp = vectors[r][p]
                    let vrq = vectors[r][q]
                    vectors[r][p] = c * vrp - s * vrq
                    vectors[r][q] = s * vrp + c * vrq
                }
            }

            let diagonal = [matrix[0][0], matrix[1][1], matrix[2][2]]
            guard let index = diagonal.indices.min(by: { diagonal[$0] < diagonal[$1] }) else {
                return nil
            }
            let normal = SIMD3<Float>(
                Float(vectors[0][index]),
                Float(vectors[1][index]),
                Float(vectors[2][index])
            )
            let length = simd_length(normal)
            guard length > 0.000001 else {
                return nil
            }
            return normal / length
        }
    }

    static func estimatePlane(
        depthMap: TAPMetricDepthMap,
        region: CGRect,
        residualThresholdMeters: Float = 0.035
    ) -> TAPPlaneEstimate? {
        guard TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap) else {
            return nil
        }

        let samples = TAPDepthGeometryProjector.sampledPoints(from: depthMap, in: region)
        return estimatePlane(from: samples, residualThresholdMeters: residualThresholdMeters)
    }

    /// Grows the Plane Filter region from a tapped seed.
    ///
    /// Callers should pass a prewarmed `TAPDepthGeometryCache` when available.
    /// If the cache is missing or stale, this method builds one before growth.
    /// `shouldCancel` is checked during cache construction, seed fitting, and
    /// BFS so stale taps do not keep doing invisible work.
    static func growPlaneRegion(
        depthMap: TAPMetricDepthMap,
        seed: CGPoint,
        strictness: Double,
        geometryCache: TAPDepthGeometryCache? = nil,
        shouldCancel: () -> Bool = { false },
        progressHandler: (TAPPlaneGridProgress) -> Void = { _ in }
    ) throws -> TAPPlaneRegion {
        let parameters = TAPPlaneGrowthParameters(strictness: strictness)
        _ = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(for: depthMap)

        guard seed.x.isFinite, seed.y.isFinite else {
            throw TAPPlaneGrowthError.invalidSeed
        }
        guard TAPDepthAnalysisInputValidation.isUsableCameraCalibration(
            depthMap.calibration,
            depthWidth: depthMap.width,
            depthHeight: depthMap.height
        ) else {
            throw TAPPlaneGrowthError.cameraCalibrationMissing
        }

        let seedX = min(max(Int(seed.x.rounded(.down)), 0), depthMap.width - 1)
        let seedY = min(max(Int(seed.y.rounded(.down)), 0), depthMap.height - 1)
        let preparedGeometryCache: TAPDepthGeometryCache
        if let geometryCache, geometryCache.matches(depthMap: depthMap) {
            preparedGeometryCache = geometryCache
        } else if let builtCache = try TAPDepthGeometryProjector.geometryCache(
            for: depthMap,
            shouldCancel: shouldCancel
        ) {
            preparedGeometryCache = builtCache
        } else {
            throw TAPPlaneGrowthError.cameraCalibrationMissing
        }

        try checkCancellation(shouldCancel)
        guard preparedGeometryCache.point(x: seedX, y: seedY) != nil else {
            throw TAPPlaneGrowthError.invalidSeed
        }
        guard let initialPlane = try seedPlane(
            depthMap: depthMap,
            seedX: seedX,
            seedY: seedY,
            parameters: parameters,
            geometryCache: preparedGeometryCache,
            shouldCancel: shouldCancel
        ) else {
            throw TAPPlaneGrowthError.notEnoughNearbySamples
        }

        let firstAccepted = try growMask(
            depthMap: depthMap,
            seedX: seedX,
            seedY: seedY,
            plane: initialPlane,
            parameters: parameters,
            geometryCache: preparedGeometryCache,
            shouldCancel: shouldCancel
        )
        let firstSamples = planeSamples(
            from: firstAccepted.acceptedPixels,
            geometryCache: preparedGeometryCache
        )
        guard firstSamples.count >= parameters.minimumRegionSamples,
              let firstEstimate = estimatePlane(
                from: firstSamples,
                residualThresholdMeters: initialPlane.residualThresholdMeters
              ) else {
            throw TAPPlaneGrowthError.noPlaneRegion
        }

        let refitPlane = planeModel(
            estimate: firstEstimate,
            samples: firstSamples,
            baseResidualThresholdMeters: initialPlane.residualThresholdMeters,
            parameters: parameters
        )
        let secondAccepted = try growMask(
            depthMap: depthMap,
            seedX: seedX,
            seedY: seedY,
            plane: refitPlane,
            parameters: parameters,
            geometryCache: preparedGeometryCache,
            shouldCancel: shouldCancel
        )
        let secondSamples = planeSamples(
            from: secondAccepted.acceptedPixels,
            geometryCache: preparedGeometryCache
        )
        let useSecondPass = secondSamples.count >= parameters.minimumRegionSamples
        let accepted = useSecondPass ? secondAccepted : firstAccepted
        let acceptedSamples = useSecondPass ? secondSamples : firstSamples
        let residualThreshold = useSecondPass
            ? refitPlane.residualThresholdMeters
            : initialPlane.residualThresholdMeters

        guard let estimate = estimatePlane(
            from: acceptedSamples,
            residualThresholdMeters: residualThreshold
        ) else {
            throw TAPPlaneGrowthError.noPlaneRegion
        }

        try checkCancellation(shouldCancel)
        let bounds = imageBounds(for: accepted.acceptedPixels)
        let runs = pixelRuns(
            from: accepted.accepted,
            width: depthMap.width,
            height: depthMap.height,
            imageBounds: bounds
        )
        let finalPlane = (normal: estimate.normal, d: -simd_dot(estimate.normal, estimate.centroid))
        let gridCells = planeGridCells(
            from: accepted.accepted,
            depthMap: depthMap,
            plane: finalPlane,
            imageBounds: bounds,
            residualThresholdMeters: residualThreshold,
            geometryCache: preparedGeometryCache,
            seedPixel: CGPoint(x: seedX, y: seedY),
            progressHandler: progressHandler
        )
        let contour = contourPoints(
            from: accepted.accepted,
            acceptedPixels: accepted.acceptedPixels,
            width: depthMap.width,
            height: depthMap.height
        )
        let flatness = flatnessScore(
            estimate: estimate,
            residualThresholdMeters: residualThreshold
        )
        let confidence = planeRegionConfidence(
            flatness: flatness,
            estimate: estimate,
            sampleCount: acceptedSamples.count,
            parameters: parameters
        )

        return TAPPlaneRegion(
            seedPixel: CGPoint(x: seedX, y: seedY),
            estimate: estimate,
            pixelRuns: runs,
            gridCells: gridCells,
            contourPoints: contour,
            imageBounds: bounds,
            confidence: confidence,
            flatnessScore: flatness,
            sampleCount: acceptedSamples.count,
            areaSquareMeters: planeAreaSquareMeters(
                samples: acceptedSamples,
                normal: estimate.normal,
                imageBounds: bounds
            )
        )
    }

    static func filteredPlanes(
        _ planes: [TAPDetectedPlane],
        minimumConfidence: Double
    ) -> [TAPDetectedPlane] {
        planes
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.sampleCount > rhs.sampleCount
                }
                return lhs.confidence > rhs.confidence
            }
    }
}
