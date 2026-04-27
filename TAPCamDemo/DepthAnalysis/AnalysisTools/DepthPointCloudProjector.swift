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
///
/// Data dependencies:
/// - `TAPMetricDepthMap.samples` for `Z`.
/// - `TAPDepthManifest.CameraCalibration.intrinsicMatrix` for `fx/fy/cx/cy`.
/// - `intrinsicMatrixReferenceDimensions` to scale intrinsics into the depth
///   map's actual pixel resolution.
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
        guard let depth = depthMap.sample(x: x, y: y),
              let intrinsics = TAPCameraIntrinsics(calibration: depthMap.calibration, depthWidth: depthMap.width, depthHeight: depthMap.height) else {
            return nil
        }

        let cameraX = (Float(x) - intrinsics.cx) / intrinsics.fx * depth
        let cameraY = (Float(y) - intrinsics.cy) / intrinsics.fy * depth
        return TAPPoint3D(x: cameraX, y: cameraY, z: depth)
    }

    static func sampledPoints(
        from depthMap: TAPMetricDepthMap,
        in region: CGRect,
        maxCount: Int = 1_200
    ) -> [(point: TAPPoint3D, imagePoint: CGPoint)] {
        guard maxCount > 0 else {
            return []
        }

        let bounds = pixelBounds(region, width: depthMap.width, height: depthMap.height)
        let area = max(bounds.width * bounds.height, 1)
        let step = max(Int(sqrt(Double(area) / Double(maxCount))), 1)
        var result: [(TAPPoint3D, CGPoint)] = []

        for y in stride(from: bounds.minY, to: bounds.maxY, by: step) {
            for x in stride(from: bounds.minX, to: bounds.maxX, by: step) {
                if let point = point(depthMap: depthMap, x: x, y: y) {
                    result.append((point, CGPoint(x: x, y: y)))
                }
            }
        }

        return result
    }

    static func stats(for depthMap: TAPMetricDepthMap, in region: CGRect) -> TAPDepthRegionStats {
        let bounds = pixelBounds(region, width: depthMap.width, height: depthMap.height)
        var values: [Float] = []
        values.reserveCapacity(max(bounds.width * bounds.height, 0))

        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                if let value = depthMap.sample(x: x, y: y) {
                    values.append(value)
                }
            }
        }

        values.sort()
        let total = max(bounds.width * bounds.height, 0)
        let median = values.isEmpty ? nil : values[values.count / 2]
        return TAPDepthRegionStats(
            validSampleCount: values.count,
            totalSampleCount: total,
            minimumDepthMeters: values.first,
            maximumDepthMeters: values.last,
            medianDepthMeters: median,
            validRatio: total == 0 ? 0 : Double(values.count) / Double(total)
        )
    }

    private static func pixelBounds(_ region: CGRect, width: Int, height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int) {
        let minX = min(max(Int(region.minX.rounded(.down)), 0), width)
        let minY = min(max(Int(region.minY.rounded(.down)), 0), height)
        let maxX = min(max(Int(region.maxX.rounded(.up)), minX), width)
        let maxY = min(max(Int(region.maxY.rounded(.up)), minY), height)
        return (minX, minY, maxX, maxY, maxX - minX, maxY - minY)
    }
}

nonisolated struct TAPCameraIntrinsics: Equatable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float

    init?(calibration: TAPDepthManifest.CameraCalibration?, depthWidth: Int, depthHeight: Int) {
        guard let calibration,
              calibration.intrinsicMatrix.count == 9,
              calibration.intrinsicMatrixReferenceWidth > 0,
              calibration.intrinsicMatrixReferenceHeight > 0 else {
            return nil
        }

        let scaleX = Float(Double(depthWidth) / calibration.intrinsicMatrixReferenceWidth)
        let scaleY = Float(Double(depthHeight) / calibration.intrinsicMatrixReferenceHeight)
        self.fx = calibration.intrinsicMatrix[0] * scaleX
        self.fy = calibration.intrinsicMatrix[4] * scaleY
        self.cx = calibration.intrinsicMatrix[6] * scaleX
        self.cy = calibration.intrinsicMatrix[7] * scaleY
    }
}
