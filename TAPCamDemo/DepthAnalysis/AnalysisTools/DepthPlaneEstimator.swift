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
/// The selected image region is sampled into camera-space points, then a small
/// deterministic RANSAC-style loop proposes candidate planes from point triples.
/// The best plane is the one with the most points whose perpendicular distance
/// is below `residualThresholdMeters`. The output describes approximate
/// coplanarity: normal, centroid, average residual, inlier ratio, depth range,
/// and image-space bounds.
///
/// Function and limits:
/// - Useful for asking "are these visible pixels roughly on the same plane?"
/// - Not equivalent to ARKit `ARPlaneAnchor`: there is no temporal tracking,
///   no world transform, and no system-level semantic plane classification.
///
/// Data dependencies:
/// - `TAPDepthGeometryProjector.sampledPoints` for camera-space points.
/// - `simd_cross`, `simd_dot`, and `simd_length` for plane equations and point
///   residuals.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/accelerate/simd
/// - https://developer.apple.com/documentation/arkit/arplaneanchor
nonisolated enum TAPPlaneEstimator {
    static func estimatePlane(
        depthMap: TAPMetricDepthMap,
        region: CGRect,
        residualThresholdMeters: Float = 0.035
    ) -> TAPPlaneEstimate? {
        let samples = TAPDepthGeometryProjector.sampledPoints(from: depthMap, in: region)
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

    private static func vector(_ point: TAPPoint3D) -> SIMD3<Float> {
        SIMD3(point.x, point.y, point.z)
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
}
