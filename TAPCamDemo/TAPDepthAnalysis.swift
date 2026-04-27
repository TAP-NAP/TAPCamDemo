//
//  TAPDepthAnalysis.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import simd

/// Canonical in-memory form used by the analysis module.
///
/// The capture module stores Apple's auxiliary depth/disparity attachment as
/// the source of truth. Analysis starts by converting that attachment into a
/// dense Float32 depth map whose samples are meters from the camera. The RGB
/// image, XMP manifest, and calibration are kept beside it so downstream tools
/// do not need to reach back into Photos or ImageIO.
nonisolated struct TAPDepthAnalysisInput {
    let manifest: TAPDepthManifest?
    let image: CGImage
    let imageOrientation: CGImagePropertyOrientation
    let depthMap: TAPMetricDepthMap
    let heatmap: CGImage
    let validMask: CGImage
}

/// A row-major metric depth map. Invalid, zero, infinite, or NaN samples are
/// preserved in `samples` but ignored by statistics and plane fitting.
nonisolated struct TAPMetricDepthMap: Equatable {
    let width: Int
    let height: Int
    let samples: [Float]
    let calibration: TAPDepthManifest.CameraCalibration?

    func index(x: Int, y: Int) -> Int {
        y * width + x
    }

    func sample(x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }

        let value = samples[index(x: x, y: y)]
        return value.isFinite && value > 0 ? value : nil
    }
}

nonisolated struct TAPDepthRegionStats: Equatable {
    let validSampleCount: Int
    let totalSampleCount: Int
    let minimumDepthMeters: Float?
    let maximumDepthMeters: Float?
    let medianDepthMeters: Float?
    let validRatio: Double
}

nonisolated struct TAPPoint3D: Equatable {
    let x: Float
    let y: Float
    let z: Float
}

nonisolated struct TAPPlaneEstimate: Equatable {
    let normal: SIMD3<Float>
    let centroid: SIMD3<Float>
    let averageResidualMeters: Float
    let inlierRatio: Double
    let depthRangeMeters: ClosedRange<Float>
    let imageBounds: CGRect
}

/// Reads a TAP Depth HEIC or any Apple depth HEIC into analysis-ready objects.
///
/// This type belongs to the analysis module: it does not know about live camera
/// configuration, lens selection, or UI state. It accepts final file bytes and
/// reconstructs everything from the persisted image container.
///
/// Principle:
/// - RGB pixels come from the primary HEIC image item via ImageIO.
/// - Depth pixels come from Apple's auxiliary depth/disparity attachment and
///   are rebuilt as `AVDepthData`.
/// - Disparity is normalized into metric depth with
///   `AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)`.
///
/// Functions enabled by this reader:
/// - Depth: colorized depth heatmap for visual inspection.
/// - Mask: valid/invalid depth coverage map.
/// - Planes: region statistics and plane fitting from metric depth samples.
/// - Cloud: camera-coordinate point preview using calibration intrinsics.
///
/// Data dependencies:
/// - `CGImageSourceCreateImageAtIndex` for the visible RGB image.
/// - `CGImageSourceCopyAuxiliaryDataInfoAtIndex` inside `TAPDepthHEICReader`
///   for `kCGImageAuxiliaryDataTypeDepth` / `kCGImageAuxiliaryDataTypeDisparity`.
/// - `AVDepthData.depthDataMap` for the `CVPixelBuffer` depth samples.
/// - `AVDepthData.cameraCalibrationData`, mirrored into the TAP manifest, for
///   projection from depth pixels to camera-space points.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/imageio/cgimagesource
/// - https://developer.apple.com/documentation/avfoundation/avdepthdata
/// - https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata
nonisolated enum TAPDepthMapReader {
    static func analysisInput(from heicData: Data) throws -> TAPDepthAnalysisInput {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TAPDepthAnalysisError.missingPrimaryImage
        }
        let imageOrientation = imageOrientation(from: source)

        guard let depthData = try TAPDepthHEICReader.depthData(from: heicData) else {
            throw TAPDepthAnalysisError.missingDepthData
        }

        let manifest = try? TAPDepthHEICReader.decodedManifest(from: heicData)
        let metricDepth = try metricDepthMap(from: depthData, manifest: manifest)
        let heatmap = try TAPDepthVisualizationRenderer.heatmap(for: metricDepth)
        let validMask = try TAPDepthVisualizationRenderer.validMask(for: metricDepth)

        return TAPDepthAnalysisInput(
            manifest: manifest,
            image: image,
            imageOrientation: imageOrientation,
            depthMap: metricDepth,
            heatmap: heatmap,
            validMask: validMask
        )
    }

    static func metricDepthMap(from depthData: AVDepthData, manifest: TAPDepthManifest?) throws -> TAPMetricDepthMap {
        let metricDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let pixelBuffer = metricDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TAPDepthAnalysisError.unreadableDepthMap
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var samples = [Float]()
        samples.reserveCapacity(width * height)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                samples.append(row[x])
            }
        }

        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: samples,
            calibration: manifest?.payload.depth.cameraCalibration
        )
    }

    private static func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) else {
            return .up
        }

        return orientation
    }
}

/// Converts metric depth pixels into displayable images without changing the
/// source depth map. The heatmap is intentionally diagnostic: consumers should
/// use `TAPMetricDepthMap.samples` for measurements, not colors.
///
/// Depth mode principle:
/// Each valid metric depth sample is min/max normalized across the current map
/// and mapped to a visible false-color ramp. Near/far colors are only a display
/// aid; the actual distance remains the Float32 meter value in `samples`.
///
/// Mask mode principle:
/// A sample is considered valid when it is finite and greater than zero. The
/// renderer outputs white for valid samples and black for invalid samples so a
/// user can immediately see where plane fitting and point reads have usable
/// depth data.
///
/// Called APIs and data:
/// - `CVPixelBuffer` samples are already copied into `TAPMetricDepthMap` by
///   `TAPDepthMapReader`.
/// - `CGImage` is created with a `CGDataProvider` so SwiftUI can show the
///   diagnostic images without introducing a Metal dependency in v1.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/corevideo/cvpixelbuffer
/// - https://developer.apple.com/documentation/coregraphics/cgimage
nonisolated enum TAPDepthVisualizationRenderer {
    static func heatmap(for depthMap: TAPMetricDepthMap) throws -> CGImage {
        let validSamples = depthMap.samples.filter { $0.isFinite && $0 > 0 }
        guard let minDepth = validSamples.min(), let maxDepth = validSamples.max() else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }

        let range = max(maxDepth - minDepth, 0.001)
        let pixels = depthMap.samples.flatMap { value -> [UInt8] in
            guard value.isFinite && value > 0 else {
                return [0, 0, 0, 255]
            }
            let normalized = min(max((value - minDepth) / range, 0), 1)
            return jetColor(normalized: normalized)
        }

        return try rgbaImage(pixels: pixels, width: depthMap.width, height: depthMap.height)
    }

    static func validMask(for depthMap: TAPMetricDepthMap) throws -> CGImage {
        let pixels = depthMap.samples.flatMap { value -> [UInt8] in
            value.isFinite && value > 0 ? [255, 255, 255, 255] : [0, 0, 0, 255]
        }

        return try rgbaImage(pixels: pixels, width: depthMap.width, height: depthMap.height)
    }

    private static func jetColor(normalized: Float) -> [UInt8] {
        let t = Double(normalized)
        let red = UInt8((min(max(1.5 - abs(4.0 * t - 3.0), 0), 1) * 255).rounded())
        let green = UInt8((min(max(1.5 - abs(4.0 * t - 2.0), 0), 1) * 255).rounded())
        let blue = UInt8((min(max(1.5 - abs(4.0 * t - 1.0), 0), 1) * 255).rounded())
        return [red, green, blue, 255]
    }

    private static func rgbaImage(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TAPDepthAnalysisError.imageRenderFailed
        }

        return image
    }
}

/// Camera-coordinate geometry helpers for single-photo RGB-D analysis.
///
/// Coordinates are local to the capture camera. A single HEIC does not contain
/// a stable world coordinate system, so this projector deliberately avoids
/// naming results "world" points. Future AR capture can add world transforms.
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

/// Maps rectangles between the orientation-corrected display plane and the
/// native pixel plane stored in the HEIC. ImageIO returns the primary `CGImage`
/// pixels without applying EXIF orientation, while SwiftUI displays them with an
/// orientation transform. Selection rectangles therefore need the inverse
/// transform before sampling the depth map.
nonisolated enum TAPImageOrientationMapper {
    static func displayedSize(nativeSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.rotatesDimensions
            ? CGSize(width: nativeSize.height, height: nativeSize.width)
            : nativeSize
    }

    static func nativeRect(fromDisplayed rect: CGRect, nativeSize: CGSize, orientation: CGImagePropertyOrientation) -> CGRect {
        switch orientation {
        case .up:
            return rect
        case .upMirrored:
            return CGRect(x: nativeSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        case .down:
            return CGRect(x: nativeSize.width - rect.maxX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .downMirrored:
            return CGRect(x: rect.minX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .right:
            return CGRect(x: rect.minY, y: nativeSize.height - rect.maxX, width: rect.height, height: rect.width)
        case .rightMirrored:
            return CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        case .left:
            return CGRect(x: nativeSize.width - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case .leftMirrored:
            return CGRect(x: nativeSize.width - rect.maxY, y: nativeSize.height - rect.maxX, width: rect.height, height: rect.width)
        }
    }

    static func displayedRect(fromNative rect: CGRect, nativeSize: CGSize, orientation: CGImagePropertyOrientation) -> CGRect {
        switch orientation {
        case .up:
            return rect
        case .upMirrored:
            return CGRect(x: nativeSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        case .down:
            return CGRect(x: nativeSize.width - rect.maxX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .downMirrored:
            return CGRect(x: rect.minX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .right:
            return CGRect(x: nativeSize.height - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case .rightMirrored:
            return CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        case .left:
            return CGRect(x: rect.minY, y: nativeSize.width - rect.maxX, width: rect.height, height: rect.width)
        case .leftMirrored:
            return CGRect(x: nativeSize.height - rect.maxY, y: nativeSize.width - rect.maxX, width: rect.height, height: rect.width)
        }
    }
}

extension CGImagePropertyOrientation {
    nonisolated var rotatesDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            true
        default:
            false
        }
    }
}

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

enum TAPDepthAnalysisError: LocalizedError {
    case missingPrimaryImage
    case missingDepthData
    case unreadableDepthMap
    case noValidDepthSamples
    case imageRenderFailed
    case assetNotFound

    var errorDescription: String? {
        switch self {
        case .missingPrimaryImage:
            "The selected file does not contain a readable primary image."
        case .missingDepthData:
            "The selected image does not contain Apple auxiliary depth or disparity data."
        case .unreadableDepthMap:
            "The depth pixel buffer could not be read."
        case .noValidDepthSamples:
            "The depth map does not contain valid metric depth samples."
        case .imageRenderFailed:
            "Unable to render the depth visualization."
        case .assetNotFound:
            "The selected Photos asset could not be found."
        }
    }
}
