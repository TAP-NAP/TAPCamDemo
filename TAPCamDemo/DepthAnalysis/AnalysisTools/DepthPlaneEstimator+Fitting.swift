//
//  DepthPlaneEstimator+Fitting.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import simd

extension TAPPlaneEstimator {
    nonisolated static func estimatePlane(
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

    nonisolated static func ransacPlaneEstimate(
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

    nonisolated static func leastSquaresPlaneEstimate(
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

    nonisolated static func vector(_ point: TAPPoint3D) -> SIMD3<Float> {
        SIMD3(point.x, point.y, point.z)
    }

    nonisolated static func weightedPlaneModel(
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

    nonisolated static func estimate(
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

    nonisolated static func residuals(
        for samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        model: PlaneModel
    ) -> [Float] {
        samples.map { residual(point: vector($0.point), normal: model.normal, d: model.d) }
    }

    nonisolated static func adaptiveResidualThreshold(
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

    nonisolated static func median(_ values: [Float]) -> Float? {
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

    nonisolated static func medianAbsoluteDeviation(_ values: [Float], around median: Float) -> Float? {
        self.median(values.map { abs($0 - median) })
    }

    nonisolated static func plane(from a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> (normal: SIMD3<Float>, d: Float)? {
        let normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        guard length > 0.000001 else {
            return nil
        }

        let unitNormal = normal / length
        return (unitNormal, -simd_dot(unitNormal, a))
    }

    nonisolated static func residual(point: SIMD3<Float>, normal: SIMD3<Float>, d: Float) -> Float {
        abs(simd_dot(normal, point) + d)
    }
}
