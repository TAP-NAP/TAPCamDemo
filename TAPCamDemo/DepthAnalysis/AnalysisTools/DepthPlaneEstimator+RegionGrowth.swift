//
//  DepthPlaneEstimator+RegionGrowth.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import simd

extension TAPPlaneEstimator {
    nonisolated static func seedPlane(
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

    nonisolated static func planeModel(
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

    nonisolated static func growMask(
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
        let pixelCount = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(for: depthMap)
        guard seedX >= 0, seedY >= 0, seedX < width, seedY < height else {
            throw TAPPlaneGrowthError.invalidSeed
        }

        var visited = Array(repeating: false, count: pixelCount)
        var accepted = Array(repeating: false, count: pixelCount)
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

    nonisolated static func acceptsPixel(
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

    nonisolated static func localNormal(
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

    nonisolated static func planeSamples(
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

    nonisolated static func checkCancellation(_ shouldCancel: () -> Bool) throws {
        if shouldCancel() {
            throw CancellationError()
        }
    }
}
