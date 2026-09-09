//
//  DepthPlaneEstimator+RegionOutput.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import simd

extension TAPPlaneEstimator {
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
        geometryCache: TAPDepthGeometryCache,
        seedPixel: CGPoint? = nil,
        progressHandler: (TAPPlaneGridProgress) -> Void = { _ in }
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
        let progressCellBatchSize = 6

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

        let orderedCells = planeGridCellsOrderedForSeedGrowth(cells, seedPixel: seedPixel)
        publishGridProgressBatches(
            seedPixel: seedPixel,
            cells: orderedCells,
            depthSize: CGSize(width: depthMap.width, height: depthMap.height),
            cellBatchSize: progressCellBatchSize,
            progressHandler: progressHandler
        )
        return orderedCells
    }

    nonisolated static func planeGridCellsOrderedForSeedGrowth(
        _ cells: [TAPPlaneGridCell],
        seedPixel: CGPoint?
    ) -> [TAPPlaneGridCell] {
        guard let seedPixel else {
            return cells
        }
        return cells.sorted { lhs, rhs in
            let lhsDistance = squaredDistanceFromSeed(lhs, seedPixel: seedPixel)
            let rhsDistance = squaredDistanceFromSeed(rhs, seedPixel: seedPixel)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            let lhsAngle = angleFromSeed(lhs, seedPixel: seedPixel)
            let rhsAngle = angleFromSeed(rhs, seedPixel: seedPixel)
            if lhsAngle != rhsAngle {
                return lhsAngle < rhsAngle
            }

            if lhs.row != rhs.row {
                return lhs.row < rhs.row
            }
            return lhs.column < rhs.column
        }
    }

    nonisolated static func publishGridProgressBatches(
        seedPixel: CGPoint?,
        cells: [TAPPlaneGridCell],
        depthSize: CGSize,
        cellBatchSize: Int,
        progressHandler: (TAPPlaneGridProgress) -> Void
    ) {
        guard let seedPixel, !cells.isEmpty else {
            return
        }

        let batchSize = max(cellBatchSize, 1)
        var publishedCount = min(batchSize, cells.count)
        while publishedCount < cells.count {
            let publishedCells = Array(cells.prefix(publishedCount))
            progressHandler(
                TAPPlaneGridProgress(
                    seedPixel: seedPixel,
                    gridCells: publishedCells,
                    progress: gridRevealProgress(
                        for: publishedCells,
                        seedPixel: seedPixel,
                        depthSize: depthSize,
                        isFinal: false
                    )
                )
            )
            publishedCount = min(publishedCount + batchSize, cells.count)
        }

        progressHandler(
            TAPPlaneGridProgress(
                seedPixel: seedPixel,
                gridCells: cells,
                progress: gridRevealProgress(
                    for: cells,
                    seedPixel: seedPixel,
                    depthSize: depthSize,
                    isFinal: true
                )
            )
        )
    }

    nonisolated static func gridRevealProgress(
        for cells: [TAPPlaneGridCell],
        seedPixel: CGPoint,
        depthSize: CGSize,
        isFinal: Bool
    ) -> Double {
        guard !isFinal else {
            return 1
        }
        let diagonal = max(sqrt(depthSize.width * depthSize.width + depthSize.height * depthSize.height), 1)
        let farthestNormalizedDistance = cells
            .map { sqrt(squaredDistanceFromSeed($0, seedPixel: seedPixel)) / diagonal }
            .max() ?? 0
        return min(max(Double(farthestNormalizedDistance) + 0.18, 0), 0.98)
    }

    private nonisolated static func squaredDistanceFromSeed(
        _ cell: TAPPlaneGridCell,
        seedPixel: CGPoint
    ) -> CGFloat {
        let dx = cell.imageBounds.midX - seedPixel.x
        let dy = cell.imageBounds.midY - seedPixel.y
        return dx * dx + dy * dy
    }

    private nonisolated static func angleFromSeed(
        _ cell: TAPPlaneGridCell,
        seedPixel: CGPoint
    ) -> CGFloat {
        atan2(cell.imageBounds.midY - seedPixel.y, cell.imageBounds.midX - seedPixel.x)
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
}
