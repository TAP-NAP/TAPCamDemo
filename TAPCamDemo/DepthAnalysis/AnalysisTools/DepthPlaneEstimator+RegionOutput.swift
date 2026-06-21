//
//  DepthPlaneEstimator+RegionOutput.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import simd

extension TAPPlaneEstimator {
    nonisolated static func detectPlanes(
        depthMap: TAPMetricDepthMap,
        residualThresholdMeters: Float = 0.035,
        minimumConfidence: Double = 0.35
    ) -> [TAPDetectedPlane] {
        guard TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap) else {
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

    nonisolated static func pixelRuns(
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

    nonisolated static func contourPoints(
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

    nonisolated static func planeGridCells(
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

    nonisolated static func isBoundaryPixel(x: Int, y: Int, accepted: [Bool], width: Int, height: Int) -> Bool {
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

    nonisolated static func flatnessScore(
        estimate: TAPPlaneEstimate,
        residualThresholdMeters: Float
    ) -> Double {
        let residualLimit = max(Double(residualThresholdMeters) * 1.5, 0.001)
        let residualScore = 1 - min(Double(estimate.averageResidualMeters) / residualLimit, 1)
        let inlierScore = min(max(estimate.inlierRatio, 0), 1)
        return min(max(residualScore * 0.68 + inlierScore * 0.32, 0), 1)
    }

    nonisolated static func planeRegionConfidence(
        flatness: Double,
        estimate: TAPPlaneEstimate,
        sampleCount: Int,
        parameters: TAPPlaneGrowthParameters
    ) -> Double {
        let sizeScore = min(Double(sampleCount) / Double(parameters.minimumRegionSamples * 10), 1)
        let confidence = flatness * 0.72 + min(max(estimate.inlierRatio, 0), 1) * 0.16 + sizeScore * 0.12
        return min(max(confidence, 0), 1)
    }

    nonisolated static func planeAreaSquareMeters(
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

    nonisolated static func index(x: Int, y: Int, width: Int) -> Int {
        y * width + x
    }

    nonisolated static func imageBounds(for points: [CGPoint]) -> CGRect {
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

    nonisolated static func imageBounds(for pixels: [(x: Int, y: Int)]) -> CGRect {
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

    nonisolated static func tileRegion(
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

    nonisolated static func planeConfidence(
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
