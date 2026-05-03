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
/// Reference docs:
/// - https://developer.apple.com/documentation/accelerate/simd
/// - https://developer.apple.com/documentation/arkit/arplaneanchor
nonisolated enum TAPPlaneEstimator {
    private struct PlaneModel {
        let normal: SIMD3<Float>
        let centroid: SIMD3<Float>
        let d: Float
        let residualThresholdMeters: Float
    }

    private struct PlaneGrowthMask {
        let accepted: [Bool]
        /// Accepted pixels are retained separately so later samples, contours,
        /// and bounds do not need to scan the full depth map again.
        let acceptedPixels: [(x: Int, y: Int)]
    }

    private struct SymmetricMatrix3 {
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
        shouldCancel: () -> Bool = { false }
    ) throws -> TAPPlaneRegion {
        let parameters = TAPPlaneGrowthParameters(strictness: strictness)
        guard depthMap.width > 0, depthMap.height > 0 else {
            throw TAPPlaneGrowthError.invalidSeed
        }
        guard depthMap.calibration != nil else {
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
            geometryCache: preparedGeometryCache
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

    private static func estimatePlane(
        from samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        residualThresholdMeters: Float
    ) -> TAPPlaneEstimate? {
        leastSquaresPlaneEstimate(
            from: samples,
            residualThresholdMeters: residualThresholdMeters
        ) ?? ransacPlaneEstimate(
            from: samples,
            residualThresholdMeters: residualThresholdMeters
        )
    }

    private static func ransacPlaneEstimate(
        from samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        residualThresholdMeters: Float
    ) -> TAPPlaneEstimate? {
        guard samples.count >= 3 else {
            return nil
        }

        var bestPlane: (normal: SIMD3<Float>, d: Float)?
        var bestInliers: [Int] = []
        let maxIterations = min(samples.count - 2, 80)

        for offset in 0..<maxIterations {
            let a = vector(samples[offset].point)
            let b = vector(samples[(offset + max(1, samples.count / 3)) % samples.count].point)
            let c = vector(samples[(offset + max(2, samples.count * 2 / 3)) % samples.count].point)
            guard let plane = plane(from: a, b, c) else {
                continue
            }

            let inliers = samples.indices.filter { index in
                residual(point: vector(samples[index].point), normal: plane.normal, d: plane.d) <= residualThresholdMeters
            }

            if inliers.count > bestInliers.count {
                bestPlane = plane
                bestInliers = inliers
            }
        }

        guard let bestPlane, !bestInliers.isEmpty else {
            return nil
        }

        let inlierPoints = bestInliers.map { vector(samples[$0].point) }
        let centroid = inlierPoints.reduce(SIMD3<Float>(repeating: 0), +) / Float(inlierPoints.count)
        let residuals = inlierPoints.map { residual(point: $0, normal: bestPlane.normal, d: bestPlane.d) }
        let averageResidual = residuals.reduce(0, +) / Float(residuals.count)
        let depths = inlierPoints.map(\.z)
        let imagePoints = bestInliers.map { samples[$0].imagePoint }
        let imageBounds = imageBounds(for: imagePoints)

        return TAPPlaneEstimate(
            normal: bestPlane.normal,
            centroid: centroid,
            averageResidualMeters: averageResidual,
            inlierRatio: Double(bestInliers.count) / Double(samples.count),
            depthRangeMeters: (depths.min() ?? 0)...(depths.max() ?? 0),
            imageBounds: imageBounds
        )
    }

    private static func leastSquaresPlaneEstimate(
        from samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        residualThresholdMeters: Float
    ) -> TAPPlaneEstimate? {
        guard samples.count >= 3,
              var model = weightedPlaneModel(from: samples, weights: nil, residualThresholdMeters: residualThresholdMeters) else {
            return nil
        }

        let firstResiduals = residuals(for: samples, model: model)
        let firstThreshold = adaptiveResidualThreshold(
            residuals: firstResiduals,
            baseResidualThresholdMeters: residualThresholdMeters,
            strictness: 0.68
        )
        let inlierSamples = samples.enumerated().compactMap { index, sample in
            firstResiduals[index] <= firstThreshold ? sample : nil
        }
        if inlierSamples.count >= max(3, samples.count / 4),
           let refitModel = weightedPlaneModel(from: inlierSamples, weights: nil, residualThresholdMeters: firstThreshold) {
            model = refitModel
        }

        return estimate(from: samples, model: model)
    }

    static func detectPlanes(
        depthMap: TAPMetricDepthMap,
        residualThresholdMeters: Float = 0.035,
        minimumConfidence: Double = 0.35
    ) -> [TAPDetectedPlane] {
        guard depthMap.width > 0, depthMap.height > 0 else {
            return []
        }

        let columns = depthMap.width >= 96 ? 4 : 3
        let rows = depthMap.height >= 96 ? 4 : 3
        var candidates: [TAPDetectedPlane] = []

        for row in 0..<rows {
            for column in 0..<columns {
                let region = tileRegion(
                    row: row,
                    column: column,
                    rows: rows,
                    columns: columns,
                    width: depthMap.width,
                    height: depthMap.height
                )
                let stats = TAPDepthGeometryProjector.stats(for: depthMap, in: region)
                guard stats.validSampleCount >= 24, stats.validRatio >= 0.18,
                      let estimate = estimatePlane(
                        depthMap: depthMap,
                        region: region,
                        residualThresholdMeters: residualThresholdMeters
                      ) else {
                    continue
                }

                let confidence = planeConfidence(
                    estimate: estimate,
                    stats: stats,
                    residualThresholdMeters: residualThresholdMeters
                )
                guard confidence >= minimumConfidence else {
                    continue
                }

                candidates.append(
                    TAPDetectedPlane(
                        id: "plane-\(row)-\(column)",
                        estimate: estimate,
                        confidence: confidence,
                        sampleCount: stats.validSampleCount
                    )
                )
            }
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.sampleCount > rhs.sampleCount
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(12)
            .map { $0 }
    }

    private static func vector(_ point: TAPPoint3D) -> SIMD3<Float> {
        SIMD3(point.x, point.y, point.z)
    }

    private static func weightedPlaneModel(
        from samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        weights: [Float]?,
        residualThresholdMeters: Float
    ) -> PlaneModel? {
        guard samples.count >= 3 else {
            return nil
        }

        var totalWeight: Float = 0
        var centroid = SIMD3<Float>(repeating: 0)
        for index in samples.indices {
            let weight = weights?[index] ?? 1
            guard weight > 0 else {
                continue
            }
            totalWeight += weight
            centroid += vector(samples[index].point) * weight
        }
        guard totalWeight > 0 else {
            return nil
        }
        centroid /= totalWeight

        var covariance = SymmetricMatrix3()
        for index in samples.indices {
            let weight = Double(weights?[index] ?? 1)
            guard weight > 0 else {
                continue
            }
            let centered = vector(samples[index].point) - centroid
            covariance.m00 += weight * Double(centered.x * centered.x)
            covariance.m01 += weight * Double(centered.x * centered.y)
            covariance.m02 += weight * Double(centered.x * centered.z)
            covariance.m11 += weight * Double(centered.y * centered.y)
            covariance.m12 += weight * Double(centered.y * centered.z)
            covariance.m22 += weight * Double(centered.z * centered.z)
        }

        guard var normal = covariance.smallestEigenVector() else {
            return nil
        }
        if normal.z < 0 {
            normal = -normal
        }
        let d = -simd_dot(normal, centroid)
        let provisional = PlaneModel(
            normal: normal,
            centroid: centroid,
            d: d,
            residualThresholdMeters: residualThresholdMeters
        )
        let threshold = adaptiveResidualThreshold(
            residuals: residuals(for: samples, model: provisional),
            baseResidualThresholdMeters: residualThresholdMeters,
            strictness: 0.68
        )
        return PlaneModel(normal: normal, centroid: centroid, d: d, residualThresholdMeters: threshold)
    }

    private static func estimate(
        from samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        model: PlaneModel
    ) -> TAPPlaneEstimate? {
        let residualValues = residuals(for: samples, model: model)
        let inlierIndices = samples.indices.filter { residualValues[$0] <= model.residualThresholdMeters }
        guard !inlierIndices.isEmpty else {
            return nil
        }

        let inlierPoints = inlierIndices.map { vector(samples[$0].point) }
        let centroid = inlierPoints.reduce(SIMD3<Float>(repeating: 0), +) / Float(inlierPoints.count)
        let inlierResiduals = inlierIndices.map { residualValues[$0] }
        let averageResidual = inlierResiduals.reduce(0, +) / Float(inlierResiduals.count)
        let depths = inlierPoints.map(\.z)
        let imagePoints = inlierIndices.map { samples[$0].imagePoint }

        return TAPPlaneEstimate(
            normal: model.normal,
            centroid: centroid,
            averageResidualMeters: averageResidual,
            inlierRatio: Double(inlierIndices.count) / Double(samples.count),
            depthRangeMeters: (depths.min() ?? 0)...(depths.max() ?? 0),
            imageBounds: imageBounds(for: imagePoints)
        )
    }

    private static func residuals(
        for samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        model: PlaneModel
    ) -> [Float] {
        samples.map { residual(point: vector($0.point), normal: model.normal, d: model.d) }
    }

    private static func seedPlane(
        depthMap: TAPMetricDepthMap,
        seedX: Int,
        seedY: Int,
        parameters: TAPPlaneGrowthParameters,
        geometryCache: TAPDepthGeometryCache,
        shouldCancel: () -> Bool
    ) throws -> PlaneModel? {
        let radii = [
            parameters.seedWindowRadiusPixels,
            parameters.seedWindowRadiusPixels + 4,
            parameters.seedWindowRadiusPixels + 8,
            parameters.seedWindowRadiusPixels + 14
        ]
        var bestModel: PlaneModel?
        var bestScore = Float.greatestFiniteMagnitude

        for radius in radii {
            try checkCancellation(shouldCancel)
            let region = CGRect(
                x: seedX - radius,
                y: seedY - radius,
                width: radius * 2 + 1,
                height: radius * 2 + 1
            )
            let samples = TAPDepthGeometryProjector.sampledPoints(
                from: depthMap,
                in: region,
                maxCount: 600,
                geometryCache: geometryCache
            )
            guard samples.count >= parameters.minimumSeedSamples else {
                continue
            }

            let radiusSquared = Float(max(radius * radius, 1))
            let weights = samples.map { sample -> Float in
                let dx = Float(sample.imagePoint.x) - Float(seedX)
                let dy = Float(sample.imagePoint.y) - Float(seedY)
                return 1 / (1 + (dx * dx + dy * dy) / radiusSquared)
            }
            guard let model = weightedPlaneModel(
                from: samples,
                weights: weights,
                residualThresholdMeters: parameters.residualThresholdMeters
            ) else {
                continue
            }

            let residualValues = residuals(for: samples, model: model)
            let medianResidual = median(residualValues) ?? model.residualThresholdMeters
            let madResidual = medianAbsoluteDeviation(residualValues, around: medianResidual) ?? model.residualThresholdMeters
            let score = medianResidual + madResidual * 1.4826
            if score < bestScore {
                bestScore = score
                bestModel = model
            }
        }

        if let bestModel {
            return bestModel
        }

        for radius in radii {
            try checkCancellation(shouldCancel)
            let region = CGRect(
                x: seedX - radius,
                y: seedY - radius,
                width: radius * 2 + 1,
                height: radius * 2 + 1
            )
            let samples = TAPDepthGeometryProjector.sampledPoints(
                from: depthMap,
                in: region,
                maxCount: 600,
                geometryCache: geometryCache
            )
            guard samples.count >= parameters.minimumSeedSamples,
                  let estimate = ransacPlaneEstimate(
                    from: samples,
                    residualThresholdMeters: parameters.residualThresholdMeters
                  ) else {
                continue
            }
            return planeModel(
                estimate: estimate,
                samples: samples,
                baseResidualThresholdMeters: parameters.residualThresholdMeters,
                parameters: parameters
            )
        }

        return bestModel
    }

    private static func planeModel(
        estimate: TAPPlaneEstimate,
        samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        baseResidualThresholdMeters: Float,
        parameters: TAPPlaneGrowthParameters
    ) -> PlaneModel {
        let provisional = PlaneModel(
            normal: estimate.normal,
            centroid: estimate.centroid,
            d: -simd_dot(estimate.normal, estimate.centroid),
            residualThresholdMeters: baseResidualThresholdMeters
        )
        let threshold = adaptiveResidualThreshold(
            residuals: residuals(for: samples, model: provisional),
            baseResidualThresholdMeters: baseResidualThresholdMeters,
            strictness: parameters.strictness
        )
        return PlaneModel(
            normal: estimate.normal,
            centroid: estimate.centroid,
            d: provisional.d,
            residualThresholdMeters: threshold
        )
    }

    private static func adaptiveResidualThreshold(
        residuals: [Float],
        baseResidualThresholdMeters: Float,
        strictness: Double
    ) -> Float {
        guard !residuals.isEmpty else {
            return baseResidualThresholdMeters
        }

        let normalizedStrictness = min(max((strictness - 0.35) / 0.60, 0), 1)
        let medianResidual = median(residuals) ?? baseResidualThresholdMeters
        let mad = medianAbsoluteDeviation(residuals, around: medianResidual) ?? 0
        let robustSigma = mad * 1.4826
        let robustNoise = medianResidual + robustSigma * Float(3.0 - normalizedStrictness)
        let floor = baseResidualThresholdMeters * Float(0.55 - normalizedStrictness * 0.20)
        let ceiling = baseResidualThresholdMeters * Float(2.75 - normalizedStrictness * 0.85)
        return min(max(max(robustNoise, floor), baseResidualThresholdMeters * 0.30), ceiling)
    }

    private static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else {
            return nil
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func medianAbsoluteDeviation(_ values: [Float], around median: Float) -> Float? {
        self.median(values.map { abs($0 - median) })
    }

    private static func growMask(
        depthMap: TAPMetricDepthMap,
        seedX: Int,
        seedY: Int,
        plane: PlaneModel,
        parameters: TAPPlaneGrowthParameters,
        geometryCache: TAPDepthGeometryCache,
        shouldCancel: () -> Bool
    ) throws -> PlaneGrowthMask {
        let width = depthMap.width
        let height = depthMap.height
        var visited = Array(repeating: false, count: width * height)
        var accepted = Array(repeating: false, count: width * height)
        var queue: [(x: Int, y: Int)] = [(seedX, seedY)]
        var acceptedPixels: [(x: Int, y: Int)] = [(seedX, seedY)]
        var head = 0
        var visitedCount = 0

        visited[index(x: seedX, y: seedY, width: width)] = true
        accepted[index(x: seedX, y: seedY, width: width)] = true

        while head < queue.count, visitedCount < parameters.maximumVisitedPixels {
            if visitedCount.isMultiple(of: 512) {
                try checkCancellation(shouldCancel)
            }

            let current = queue[head]
            head += 1
            visitedCount += 1

            for offsetY in -1...1 {
                for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                    let neighborX = current.x + offsetX
                    let neighborY = current.y + offsetY
                    guard neighborX >= 0, neighborY >= 0, neighborX < width, neighborY < height else {
                        continue
                    }

                    let neighborIndex = index(x: neighborX, y: neighborY, width: width)
                    guard !visited[neighborIndex] else {
                        continue
                    }
                    visited[neighborIndex] = true

                    if acceptsPixel(
                        depthMap: depthMap,
                        x: neighborX,
                        y: neighborY,
                        plane: plane,
                        parameters: parameters,
                        geometryCache: geometryCache
                    ) {
                        accepted[neighborIndex] = true
                        let neighbor = (x: neighborX, y: neighborY)
                        acceptedPixels.append(neighbor)
                        queue.append(neighbor)
                    }
                }
            }
        }

        return PlaneGrowthMask(accepted: accepted, acceptedPixels: acceptedPixels)
    }

    private static func acceptsPixel(
        depthMap: TAPMetricDepthMap,
        x: Int,
        y: Int,
        plane: PlaneModel,
        parameters: TAPPlaneGrowthParameters,
        geometryCache: TAPDepthGeometryCache
    ) -> Bool {
        guard let point = geometryCache.point(x: x, y: y) else {
            return false
        }

        let pointResidual = residual(
            point: vector(point),
            normal: plane.normal,
            d: plane.d
        )
        var effectiveThreshold = plane.residualThresholdMeters

        if parameters.strictness > 0.82,
           let localNormal = geometryCache.localNormal(x: x, y: y, radius: 2)
                ?? localNormal(depthMap: depthMap, x: x, y: y, radius: 2, geometryCache: geometryCache) {
            let cosine = min(max(abs(simd_dot(localNormal, plane.normal)), 0), 1)
            let anglePenalty = 1 - cosine
            let strictnessScale = Float((parameters.strictness - 0.82) / 0.13)
            effectiveThreshold *= max(0.68, 1 - anglePenalty * 0.42 * strictnessScale)
        }

        return pointResidual <= effectiveThreshold
    }

    private static func localNormal(
        depthMap: TAPMetricDepthMap,
        x: Int,
        y: Int,
        radius: Int,
        geometryCache: TAPDepthGeometryCache
    ) -> SIMD3<Float>? {
        guard x >= radius, y >= radius, x < depthMap.width - radius, y < depthMap.height - radius,
              let left = geometryCache.point(x: x - radius, y: y),
              let right = geometryCache.point(x: x + radius, y: y),
              let up = geometryCache.point(x: x, y: y - radius),
              let down = geometryCache.point(x: x, y: y + radius) else {
            return nil
        }

        let dx = vector(right) - vector(left)
        let dy = vector(down) - vector(up)
        let normal = simd_cross(dx, dy)
        let length = simd_length(normal)
        guard length > 0.000001 else {
            return nil
        }
        return normal / length
    }

    private static func planeSamples(
        from acceptedPixels: [(x: Int, y: Int)],
        geometryCache: TAPDepthGeometryCache
    ) -> [(point: TAPPoint3D, imagePoint: CGPoint)] {
        var samples: [(TAPPoint3D, CGPoint)] = []
        samples.reserveCapacity(acceptedPixels.count)

        for pixel in acceptedPixels {
            if let point = geometryCache.point(x: pixel.x, y: pixel.y) {
                samples.append((point, CGPoint(x: pixel.x, y: pixel.y)))
            }
        }

        return samples
    }

    private static func pixelRuns(
        from accepted: [Bool],
        width: Int,
        height: Int,
        imageBounds: CGRect
    ) -> [TAPPlanePixelRun] {
        let minX = max(Int(floor(imageBounds.minX)), 0)
        let minY = max(Int(floor(imageBounds.minY)), 0)
        let maxX = min(Int(ceil(imageBounds.maxX)) + 1, width)
        let maxY = min(Int(ceil(imageBounds.maxY)) + 1, height)
        guard minX < maxX, minY < maxY else {
            return []
        }

        var runs: [TAPPlanePixelRun] = []
        for y in minY..<maxY {
            var x = minX
            while x < maxX {
                let pixelIndex = index(x: x, y: y, width: width)
                if accepted[pixelIndex] {
                    let start = x
                    while x < maxX, accepted[index(x: x, y: y, width: width)] {
                        x += 1
                    }
                    runs.append(TAPPlanePixelRun(y: y, xStart: start, xEndExclusive: x))
                } else {
                    x += 1
                }
            }
        }
        return runs
    }

    private static func contourPoints(
        from accepted: [Bool],
        acceptedPixels: [(x: Int, y: Int)],
        width: Int,
        height: Int
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(min(acceptedPixels.count, 3_000))

        for pixel in acceptedPixels {
            if isBoundaryPixel(x: pixel.x, y: pixel.y, accepted: accepted, width: width, height: height) {
                points.append(CGPoint(x: pixel.x, y: pixel.y))
            }
        }
        return points
    }

    private static func planeGridCells(
        from accepted: [Bool],
        depthMap: TAPMetricDepthMap,
        plane: (normal: SIMD3<Float>, d: Float),
        imageBounds: CGRect,
        residualThresholdMeters: Float,
        geometryCache: TAPDepthGeometryCache
    ) -> [TAPPlaneGridCell] {
        guard imageBounds.width > 0, imageBounds.height > 0 else {
            return []
        }

        let minX = max(Int(floor(imageBounds.minX)), 0)
        let minY = max(Int(floor(imageBounds.minY)), 0)
        let maxX = min(Int(ceil(imageBounds.maxX)) + 1, depthMap.width)
        let maxY = min(Int(ceil(imageBounds.maxY)) + 1, depthMap.height)
        guard minX < maxX, minY < maxY else {
            return []
        }

        let longestSide = max(maxX - minX, maxY - minY)
        let cellSize = min(max(longestSide / 9, 10), 28)
        var cells: [TAPPlaneGridCell] = []

        var row = 0
        var y = minY
        while y < maxY {
            let yEnd = min(y + cellSize, maxY)
            var column = 0
            var x = minX
            while x < maxX {
                let xEnd = min(x + cellSize, maxX)
                let totalPixels = max((xEnd - x) * (yEnd - y), 1)
                var acceptedCount = 0
                var residualSum: Float = 0

                for sampleY in y..<yEnd {
                    for sampleX in x..<xEnd {
                        let pixelIndex = index(x: sampleX, y: sampleY, width: depthMap.width)
                        guard accepted[pixelIndex],
                              let point = geometryCache.point(x: sampleX, y: sampleY) else {
                            continue
                        }

                        acceptedCount += 1
                        residualSum += residual(point: vector(point), normal: plane.normal, d: plane.d)
                    }
                }

                if acceptedCount >= max(4, totalPixels / 10) {
                    let coverage = min(Double(acceptedCount) / Double(totalPixels), 1)
                    let averageResidual = residualSum / Float(acceptedCount)
                    let residualLimit = max(residualThresholdMeters * 1.5, 0.001)
                    let residualScore = 1 - min(Double(averageResidual / residualLimit), 1)
                    let confidence = min(max(coverage * 0.56 + residualScore * 0.44, 0), 1)
                    cells.append(
                        TAPPlaneGridCell(
                            row: row,
                            column: column,
                            imageBounds: CGRect(x: x, y: y, width: xEnd - x, height: yEnd - y),
                            coverage: coverage,
                            averageResidualMeters: averageResidual,
                            confidence: confidence,
                            sampleCount: acceptedCount
                        )
                    )
                }

                x = xEnd
                column += 1
            }
            y = yEnd
            row += 1
        }

        return cells
    }

    private static func isBoundaryPixel(x: Int, y: Int, accepted: [Bool], width: Int, height: Int) -> Bool {
        for offsetY in -1...1 {
            for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                let neighborX = x + offsetX
                let neighborY = y + offsetY
                guard neighborX >= 0, neighborY >= 0, neighborX < width, neighborY < height else {
                    return true
                }
                if !accepted[index(x: neighborX, y: neighborY, width: width)] {
                    return true
                }
            }
        }
        return false
    }

    private static func flatnessScore(
        estimate: TAPPlaneEstimate,
        residualThresholdMeters: Float
    ) -> Double {
        let residualLimit = max(Double(residualThresholdMeters) * 1.5, 0.001)
        let residualScore = 1 - min(Double(estimate.averageResidualMeters) / residualLimit, 1)
        let inlierScore = min(max(estimate.inlierRatio, 0), 1)
        return min(max(residualScore * 0.68 + inlierScore * 0.32, 0), 1)
    }

    private static func planeRegionConfidence(
        flatness: Double,
        estimate: TAPPlaneEstimate,
        sampleCount: Int,
        parameters: TAPPlaneGrowthParameters
    ) -> Double {
        let sizeScore = min(Double(sampleCount) / Double(parameters.minimumRegionSamples * 10), 1)
        let confidence = flatness * 0.72 + min(max(estimate.inlierRatio, 0), 1) * 0.16 + sizeScore * 0.12
        return min(max(confidence, 0), 1)
    }

    private static func planeAreaSquareMeters(
        samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        normal: SIMD3<Float>,
        imageBounds: CGRect
    ) -> Double {
        guard samples.count >= 3, imageBounds.width > 0, imageBounds.height > 0 else {
            return 0
        }

        let reference = abs(normal.z) < 0.92 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let axisA = simd_normalize(simd_cross(normal, reference))
        let axisB = simd_normalize(simd_cross(normal, axisA))

        var minA = Float.greatestFiniteMagnitude
        var maxA = -Float.greatestFiniteMagnitude
        var minB = Float.greatestFiniteMagnitude
        var maxB = -Float.greatestFiniteMagnitude

        for sample in samples {
            let point = vector(sample.point)
            let projectedA = simd_dot(point, axisA)
            let projectedB = simd_dot(point, axisB)
            minA = min(minA, projectedA)
            maxA = max(maxA, projectedA)
            minB = min(minB, projectedB)
            maxB = max(maxB, projectedB)
        }

        let boundingArea = max(Double(maxA - minA), 0) * max(Double(maxB - minB), 0)
        let coverage = min(Double(samples.count) / max(Double(imageBounds.width * imageBounds.height), 1), 1)
        return boundingArea * coverage
    }

    private static func index(x: Int, y: Int, width: Int) -> Int {
        y * width + x
    }

    private static func plane(from a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> (normal: SIMD3<Float>, d: Float)? {
        let normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        guard length > 0.000001 else {
            return nil
        }

        let unitNormal = normal / length
        return (unitNormal, -simd_dot(unitNormal, a))
    }

    private static func residual(point: SIMD3<Float>, normal: SIMD3<Float>, d: Float) -> Float {
        abs(simd_dot(normal, point) + d)
    }

    private static func checkCancellation(_ shouldCancel: () -> Bool) throws {
        if shouldCancel() {
            throw CancellationError()
        }
    }

    private static func imageBounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else {
            return .zero
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func imageBounds(for pixels: [(x: Int, y: Int)]) -> CGRect {
        guard let first = pixels.first else {
            return .zero
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for pixel in pixels.dropFirst() {
            minX = min(minX, pixel.x)
            minY = min(minY, pixel.y)
            maxX = max(maxX, pixel.x)
            maxY = max(maxY, pixel.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func tileRegion(
        row: Int,
        column: Int,
        rows: Int,
        columns: Int,
        width: Int,
        height: Int
    ) -> CGRect {
        let tileWidth = CGFloat(width) / CGFloat(columns)
        let tileHeight = CGFloat(height) / CGFloat(rows)
        let rect = CGRect(
            x: CGFloat(column) * tileWidth,
            y: CGFloat(row) * tileHeight,
            width: tileWidth,
            height: tileHeight
        )
        return rect.insetBy(dx: -tileWidth * 0.08, dy: -tileHeight * 0.08)
    }

    private static func planeConfidence(
        estimate: TAPPlaneEstimate,
        stats: TAPDepthRegionStats,
        residualThresholdMeters: Float
    ) -> Double {
        let residualLimit = max(Double(residualThresholdMeters) * 1.5, 0.001)
        let residualScore = 1 - min(Double(estimate.averageResidualMeters) / residualLimit, 1)
        let inlierScore = min(max(estimate.inlierRatio, 0), 1)
        let validScore = min(max(stats.validRatio, 0), 1)
        let confidence = inlierScore * 0.58 + residualScore * 0.30 + validScore * 0.12
        return min(max(confidence, 0), 1)
    }
}
