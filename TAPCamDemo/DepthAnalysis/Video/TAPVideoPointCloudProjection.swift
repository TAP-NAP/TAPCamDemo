// Camera-local, display-only geometry. No source sample or artifact is rewritten.
import CoreGraphics
import Foundation
import ImageIO
import simd

nonisolated struct TAPVideoPointCloudCalibration {
    let value: TAPVideoManifest.CameraCalibration
    let inverseDistortion: [Float]

    init?(_ value: TAPVideoManifest.CameraCalibration) {
        let dimensions = value.intrinsicMatrixReferenceDimensions
        guard value.intrinsicMatrix.count == 9,
              value.intrinsicMatrix.allSatisfy(\.isFinite),
              value.intrinsicMatrix[0] > 0, value.intrinsicMatrix[4] > 0,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width >= 1, dimensions.height >= 1,
              Float(dimensions.width).isFinite, Float(dimensions.height).isFinite,
              value.lensDistortionCenter.x.isFinite, value.lensDistortionCenter.y.isFinite,
              (0...dimensions.width).contains(value.lensDistortionCenter.x),
              (0...dimensions.height).contains(value.lensDistortionCenter.y),
              let data = value.inverseLensDistortionLookupTable,
              data.count >= 8, data.count <= 16_384, data.count.isMultiple(of: 4) else { return nil }
        let table = data.withUnsafeBytes { bytes in
            stride(from: 0, to: data.count, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
        guard table.allSatisfy({ $0.isFinite && $0 > -1 }) else { return nil }
        self.value = value
        // Finite magnifications can still fold outer pixels back toward the center.
        // Check d[r * (1 + m(r))]/dr at both ends of every linear LUT segment
        // over the reference image radius. A fold uses the photo viewer's
        // pinhole approximation for the whole frame, avoiding a discontinuous seam.
        let monotonic = (0..<(table.count - 1)).allSatisfy { index in
            let difference = Double(table[index + 1]) - Double(table[index])
            return 1 + Double(table[index]) + Double(index) * difference > 0
                && 1 + Double(table[index + 1]) + Double(index + 1) * difference > 0
        }
        inverseDistortion = monotonic ? table : []
    }

    /// Apple's reference mapping uses the inverse table for a distorted input point
    /// to its rectilinear location (AVCameraCalibrationData.h).
    func rectifiedPoint(x: Double, y: Double, width: Int, height: Int) -> CGPoint {
        let size = value.intrinsicMatrixReferenceDimensions
        let point = CGPoint(
            x: (x + 0.5) * size.width / Double(width) - 0.5,
            y: (y + 0.5) * size.height / Double(height) - 0.5
        )
        guard !inverseDistortion.isEmpty else { return point }
        let center = value.lensDistortionCenter
        let dx = point.x - center.x
        let dy = point.y - center.y
        let maximumRadius = hypot(max(center.x, size.width - center.x), max(center.y, size.height - center.y))
        let position = min(hypot(dx, dy) / maximumRadius, 1) * Double(inverseDistortion.count - 1)
        let lower = min(Int(position), inverseDistortion.count - 2)
        let fraction = Float(position - Double(lower))
        let magnification = inverseDistortion[lower] * (1 - fraction) + inverseDistortion[lower + 1] * fraction
        return CGPoint(x: center.x + dx * Double(1 + magnification), y: center.y + dy * Double(1 + magnification))
    }

    func vertex(x: Int, y: Int, width: Int, height: Int, depth: Float, rotation: Int, mirrored: Bool) -> SIMD3<Float> {
        let point = rectifiedPoint(x: Double(x), y: Double(y), width: width, height: height)
        let matrix = value.intrinsicMatrix
        let cameraX = (Float(point.x) - matrix[6]) / matrix[0] * depth
        let cameraY = (Float(point.y) - matrix[7]) / matrix[4] * depth
        let oriented: SIMD2<Float>
        switch rotation {
        case 90: oriented = SIMD2(-cameraY, cameraX)
        case 180: oriented = SIMD2(-cameraX, -cameraY)
        case 270: oriented = SIMD2(cameraY, -cameraX)
        default: oriented = SIMD2(cameraX, cameraY)
        }
        return SIMD3(mirrored ? -oriented.x : oriented.x, -oriented.y, -depth)
    }
}

nonisolated struct TAPVideoPointCloudPayload: Sendable {
    let presentationTimeSeconds: Double
    let vertices: [SIMD3<Float>]
    let colors: [SIMD4<Float>]
    let cameraModel: TAPDepthProjectionCameraModel
    // Raw samples are consumed by registration before the payload reaches the view.
    var rawSamples: [TAPVideoPointCloudRegistrationFrame.Sample] = []
    var cameraToAnchor = matrix_identity_float4x4
    var historicalFrames: [TAPVideoPointCloudKeyframe] = []
}

nonisolated enum TAPVideoPointCloudProjection {
    static let maximumPointCount = 12_000
    static let maximumRGBDimension = 640

    static func metricSample(_ frame: TAPDecodedDepthVideoFrame, index: Int) -> Float {
        let bytesPerSample: Int
        switch frame.pixelFormat {
        case "hdep", "hdis": bytesPerSample = 2
        case "fdep", "fdis": bytesPerSample = 4
        default: return .nan
        }
        guard index >= 0, index < frame.packedDepth.count / bytesPerSample else { return .nan }
        let half = bytesPerSample == 2
        let offset = index * bytesPerSample
        let raw: Float = frame.packedDepth.withUnsafeBytes { bytes in
            if half {
                return Float(Float16(bitPattern: UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))))
            }
            return Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }
        guard raw.isFinite, raw > 0 else { return .nan }
        let depth = frame.pixelFormat.hasSuffix("dis") ? 1 / raw : raw
        return depth.isFinite && depth < 100 ? depth : .nan
    }

    static func make(
        frame: TAPDecodedDepthVideoFrame,
        calibration: TAPVideoPointCloudCalibration,
        descriptor: TAPVideoDepthRegistrationDescriptor,
        image: CGImage
    ) throws -> TAPVideoPointCloudPayload? {
        guard let projection = descriptor.projection,
              let colors = RGBColors(image: image),
              let model = cameraModel(calibration.value, projection: projection) else { return nil }
        var vertices: [SIMD3<Float>] = []
        var rgb: [SIMD4<Float>] = []
        var rawSamples: [TAPVideoPointCloudRegistrationFrame.Sample] = []
        let count = frame.width * frame.height
        let step = max(1, (count + maximumPointCount - 1) / maximumPointCount)
        vertices.reserveCapacity(min(count, maximumPointCount))
        rgb.reserveCapacity(min(count, maximumPointCount))
        rawSamples.reserveCapacity(min(count, maximumPointCount))
        for index in stride(from: 0, to: count, by: step) {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let depth = metricSample(frame, index: index)
            guard depth.isFinite else { continue }
            let x = index % frame.width
            let y = index / frame.width
            guard let projected = projection.projectDepthPixelCenter(x: Double(x), y: Double(y)),
                  let color = colors.color(at: projected, descriptor: descriptor) else { continue }
            let vertex = calibration.vertex(
                x: x, y: y, width: frame.width, height: frame.height, depth: depth,
                rotation: projection.connectionRotationDegrees, mirrored: projection.isEncodedHorizontallyMirrored
            )
            guard vertex.x.isFinite, vertex.y.isFinite, vertex.z.isFinite else { continue }
            vertices.append(vertex)
            rgb.append(color)
            rawSamples.append(.init(position: vertex, imagePoint: SIMD2(
                Float((projected.x + 0.5) / Double(descriptor.rgbPresentationWidth)),
                Float((projected.y + 0.5) / Double(descriptor.rgbPresentationHeight))
            )))
        }
        guard !vertices.isEmpty else { return nil }
        return TAPVideoPointCloudPayload(presentationTimeSeconds: frame.presentationTimeSeconds,
            vertices: vertices, colors: rgb, cameraModel: model, rawSamples: rawSamples)
    }

    static func cameraModel(_ calibration: TAPVideoManifest.CameraCalibration, projection: TAPVideoRegistrationProjection) -> TAPDepthProjectionCameraModel? {
        let reference = calibration.intrinsicMatrixReferenceDimensions
        let matrix = calibration.intrinsicMatrix
        let scaleX = Float(projection.alignedRGBWidth) / Float(reference.width)
        let scaleY = Float(projection.alignedRGBHeight) / Float(reference.height)
        let model = TAPDepthProjectionCameraModel(
            fx: matrix[0] * scaleX, fy: matrix[4] * scaleY,
            cx: (matrix[6] + 0.5) * scaleX - 0.5, cy: (matrix[7] + 0.5) * scaleY - 0.5,
            imageWidth: projection.alignedRGBWidth, imageHeight: projection.alignedRGBHeight
        )
        let orientation: CGImagePropertyOrientation
        switch projection.connectionRotationDegrees {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }
        let rotated = model.displayOriented(orientation)
        let centerX = projection.isEncodedHorizontallyMirrored ? Float(rotated.imageWidth - 1) - rotated.cx : rotated.cx
        let crop = projection.rgbCleanAperture
        let result = TAPDepthProjectionCameraModel(
            fx: rotated.fx, fy: rotated.fy, cx: centerX - Float(crop.x), cy: rotated.cy - Float(crop.y),
            imageWidth: Int(crop.width), imageHeight: Int(crop.height)
        )
        guard result.fx.isFinite, result.fy.isFinite, result.cx.isFinite, result.cy.isFinite,
              result.fx > 0, result.fy > 0 else { return nil }
        return result
    }

    private struct RGBColors {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        init?(image: CGImage) {
            guard image.width > 0, image.height > 0,
                  image.width <= maximumRGBDimension, image.height <= maximumRGBDimension else { return nil }
            width = image.width
            height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let success = data.withUnsafeMutableBytes { storage -> Bool in
                guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard success else { return nil }
            bytes = data
        }
        func color(at point: CGPoint, descriptor: TAPVideoDepthRegistrationDescriptor) -> SIMD4<Float>? {
            guard point.x >= 0, point.y >= 0,
                  point.x < Double(descriptor.rgbPresentationWidth), point.y < Double(descriptor.rgbPresentationHeight) else { return nil }
            let x = min(width - 1, Int((point.x + 0.5) * Double(width) / Double(descriptor.rgbPresentationWidth)))
            let y = min(height - 1, Int((point.y + 0.5) * Double(height) / Double(descriptor.rgbPresentationHeight)))
            let index = (y * width + x) * 4
            return SIMD4(Float(bytes[index]) / 255, Float(bytes[index + 1]) / 255, Float(bytes[index + 2]) / 255, 1)
        }
    }
}
