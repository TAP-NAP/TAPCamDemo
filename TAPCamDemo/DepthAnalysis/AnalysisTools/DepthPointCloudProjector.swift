//
//  DepthPointCloudProjector.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics
import simd

/// Camera-coordinate geometry helpers for single-photo RGB-D analysis.
///
/// Coordinates are local to the capture camera. A single HEIC does not contain
/// a stable world coordinate system, so this projector deliberately avoids
/// naming results "world" points. AR/world transforms belong outside this
/// single-photo projection step.
///
/// Cloud mode principle:
/// A depth image is a 2D grid of distances. To preview a point cloud, the module
/// treats each valid depth pixel `(u, v)` as a ray through the camera intrinsics
/// and computes a camera-space point:
///
/// `X = (u - cx) / fx * Z`
/// `Y = (v - cy) / fy * Z`
/// `Z = depthMeters`
///
/// This is enough to compare visible surfaces in the photo, but it is not a
/// mesh, not a world-space reconstruction, and not ARKit plane tracking.
/// Plane Filter uses the same projection math, but repeated seed taps should not
/// reproject the whole depth image. `geometryCache(for:)` builds per-image
/// camera-space points and local normals once so tap-time growth can reuse them.
///
/// Data dependencies:
/// - `TAPMetricDepthMap.samples` for `Z`.
/// - `TAPDepthManifest.CameraCalibration.intrinsicMatrix` for `fx/fy/cx/cy`.
/// - `intrinsicMatrixReferenceDimensions` to scale intrinsics into the depth
///   map's actual pixel resolution.
/// - `TAPDepthGeometryCache` when the caller can share projected points across
///   multiple Planes seed selections.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata/intrinsicmatrix
/// - https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth
nonisolated enum TAPDepthGeometryProjector {
    static func point(
        depthMap: TAPMetricDepthMap,
        x: Int,
        y: Int
    ) -> TAPPoint3D? {
        guard TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap),
              let depth = depthMap.sample(x: x, y: y),
              let intrinsics = TAPCameraIntrinsics(calibration: depthMap.calibration, depthWidth: depthMap.width, depthHeight: depthMap.height) else {
            return nil
        }

        return point(depth: depth, x: x, y: y, intrinsics: intrinsics)
    }

    /// Builds reusable geometry for one loaded depth map.
    ///
    /// The work is intentionally cancellation-aware because the view model can
    /// prewarm this at utility priority, then abandon it when the user switches
    /// photos or taps before prewarm finishes.
    static func geometryCache(
        for depthMap: TAPMetricDepthMap,
        shouldCancel: () -> Bool = { false }
    ) throws -> TAPDepthGeometryCache? {
        let pixelCount = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(for: depthMap)
        guard let intrinsics = TAPCameraIntrinsics(
            calibration: depthMap.calibration,
            depthWidth: depthMap.width,
            depthHeight: depthMap.height
        ) else {
            return nil
        }

        var points = Array<TAPPoint3D?>(repeating: nil, count: pixelCount)
        var validPointCount = 0

        for y in 0..<depthMap.height {
            if shouldCancel() {
                throw CancellationError()
            }

            for x in 0..<depthMap.width {
                guard let depth = depthMap.sample(x: x, y: y) else {
                    continue
                }

                points[depthMap.index(x: x, y: y)] = point(
                    depth: depth,
                    x: x,
                    y: y,
                    intrinsics: intrinsics
                )
                validPointCount += 1
            }
        }

        let localNormalRadius = 2
        var localNormals = Array<SIMD3<Float>?>(repeating: nil, count: pixelCount)
        if depthMap.width > localNormalRadius * 2, depthMap.height > localNormalRadius * 2 {
            for y in localNormalRadius..<(depthMap.height - localNormalRadius) {
                if shouldCancel() {
                    throw CancellationError()
                }

                for x in localNormalRadius..<(depthMap.width - localNormalRadius) {
                    localNormals[depthMap.index(x: x, y: y)] = localNormal(
                        points: points,
                        width: depthMap.width,
                        height: depthMap.height,
                        x: x,
                        y: y,
                        radius: localNormalRadius
                    )
                }
            }
        }

        return TAPDepthGeometryCache(
            width: depthMap.width,
            height: depthMap.height,
            points: points,
            localNormalRadius: localNormalRadius,
            localNormals: localNormals,
            validPointCount: validPointCount
        )
    }

    private static func point(depth: Float, x: Int, y: Int, intrinsics: TAPCameraIntrinsics) -> TAPPoint3D {
        let cameraX = (Float(x) - intrinsics.cx) / intrinsics.fx * depth
        let cameraY = (Float(y) - intrinsics.cy) / intrinsics.fy * depth
        return TAPPoint3D(x: cameraX, y: cameraY, z: depth)
    }

    private static func localNormal(
        points: [TAPPoint3D?],
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        radius: Int
    ) -> SIMD3<Float>? {
        guard x >= radius, y >= radius, x < width - radius, y < height - radius,
              let left = points[y * width + x - radius],
              let right = points[y * width + x + radius],
              let up = points[(y - radius) * width + x],
              let down = points[(y + radius) * width + x] else {
            return nil
        }

        let dx = SIMD3(right.x - left.x, right.y - left.y, right.z - left.z)
        let dy = SIMD3(down.x - up.x, down.y - up.y, down.z - up.z)
        let normal = simd_cross(dx, dy)
        let length = simd_length(normal)
        guard length > 0.000001 else {
            return nil
        }
        return normal / length
    }

    static func sampledPoints(
        from depthMap: TAPMetricDepthMap,
        in region: CGRect,
        maxCount: Int = 1_200,
        geometryCache: TAPDepthGeometryCache? = nil
    ) -> [(point: TAPPoint3D, imagePoint: CGPoint)] {
        guard maxCount > 0,
              TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap),
              TAPDepthAnalysisInputValidation.isFiniteRegion(region) else {
            return []
        }

        let bounds = pixelBounds(region, width: depthMap.width, height: depthMap.height)
        let area = max(bounds.width * bounds.height, 1)
        let step = max(Int(sqrt(Double(area) / Double(maxCount))), 1)
        let usableGeometryCache = geometryCache?.matches(depthMap: depthMap) == true ? geometryCache : nil
        var result: [(TAPPoint3D, CGPoint)] = []

        for y in stride(from: bounds.minY, to: bounds.maxY, by: step) {
            for x in stride(from: bounds.minX, to: bounds.maxX, by: step) {
                let projectedPoint = usableGeometryCache?.point(x: x, y: y)
                    ?? point(depthMap: depthMap, x: x, y: y)
                if let point = projectedPoint {
                    result.append((point, CGPoint(x: x, y: y)))
                }
            }
        }

        return result
    }

    private static func pixelBounds(_ region: CGRect, width: Int, height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int) {
        guard width >= 0, height >= 0, TAPDepthAnalysisInputValidation.isFiniteRegion(region) else {
            return (0, 0, 0, 0, 0, 0)
        }

        let minX = min(max(Int(region.minX.rounded(.down)), 0), width)
        let minY = min(max(Int(region.minY.rounded(.down)), 0), height)
        let maxX = min(max(Int(region.maxX.rounded(.up)), minX), width)
        let maxY = min(max(Int(region.maxY.rounded(.up)), minY), height)
        return (minX, minY, maxX, maxY, maxX - minX, maxY - minY)
    }
}

/// Per-depth-map geometry shared across repeated Planes seed taps.
///
/// It stores camera-space points for valid depth samples plus radius-specific
/// local normals used by high-strictness acceptance. The cache is image-local:
/// callers must use `matches(depthMap:)` before reusing it.
nonisolated struct TAPDepthGeometryCache {
    let width: Int
    let height: Int
    fileprivate let points: [TAPPoint3D?]
    fileprivate let localNormalRadius: Int
    fileprivate let localNormals: [SIMD3<Float>?]
    let validPointCount: Int

    func matches(depthMap: TAPMetricDepthMap) -> Bool {
        width == depthMap.width
            && height == depthMap.height
            && TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap)
            && points.count == depthMap.samples.count
            && localNormals.count == depthMap.samples.count
    }

    func point(x: Int, y: Int) -> TAPPoint3D? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }

        let sampleIndex = y * width + x
        guard sampleIndex < points.count else {
            return nil
        }
        return points[sampleIndex]
    }

    func localNormal(x: Int, y: Int, radius: Int) -> SIMD3<Float>? {
        guard radius == localNormalRadius,
              x >= 0, y >= 0, x < width, y < height else {
            return nil
        }

        let sampleIndex = y * width + x
        guard sampleIndex < localNormals.count else {
            return nil
        }
        return localNormals[sampleIndex]
    }
}

nonisolated struct TAPCameraIntrinsics: Equatable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float

    init?(calibration: TAPDepthManifest.CameraCalibration?, depthWidth: Int, depthHeight: Int) {
        guard let intrinsics = TAPDepthAnalysisInputValidation.scaledIntrinsics(
            calibration: calibration,
            depthWidth: depthWidth,
            depthHeight: depthHeight
        ) else {
            return nil
        }
        self.fx = intrinsics.fx
        self.fy = intrinsics.fy
        self.cx = intrinsics.cx
        self.cy = intrinsics.cy
    }
}
