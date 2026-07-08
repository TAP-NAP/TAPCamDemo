//
//  DepthPointCloudPreview.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreMotion
import Foundation
import ImageIO
import OSLog
import SceneKit
import simd
import SwiftUI
import UIKit

/// Lightweight SwiftUI preview for camera-coordinate depth points.
///
/// The point cloud preview depends on the same projection math as plane
/// fitting, but it stays a visualization tool: it does not create a mesh,
/// stabilize points in world coordinates, or infer hidden geometry.
struct PointCloudPreview: View {
    var image: CGImage?
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    var selectedPlaneRegion: TAPPlaneRegion?
    var highlightColor: UIColor = .systemYellow
    @Binding var selection: CGRect?
    let interactionState: AnalysisInteractionState
    let allowsSelection: Bool
    var enablesMotionParallax = false
    let onSelectionBegan: (CGRect) -> Void
    let onSelectionChanged: (CGRect) -> Void
    let onSelectionEnded: (CGRect) -> Void
    let onSelectionCleared: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var dragStart: CGPoint?

    private var fullRegion: CGRect {
        CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
    }

    var body: some View {
        if allowsSelection {
            selectableCanvasBody
        } else {
            DepthProjectionSceneView(
                image: image,
                depthMap: depthMap,
                orientation: orientation,
                selectedPlaneRegion: selectedPlaneRegion,
                highlightColor: highlightColor,
                enablesMotionParallax: enablesMotionParallax && !accessibilityReduceMotion
            )
            .accessibilityLabel("3D projection model")
            .background(Color.black)
        }
    }

    private var selectableCanvasBody: some View {
        GeometryReader { proxy in
            let displaySize = TAPImageOrientationMapper.displayedSize(
                nativeSize: CGSize(width: depthMap.width, height: depthMap.height),
                orientation: orientation
            )
            let imageFrame = fittedRect(
                imageSize: displaySize,
                containerSize: proxy.size
            )

            ZStack {
                Color.black

                PointCloudCanvas(
                    depthMap: depthMap,
                    orientation: orientation,
                    region: fullRegion,
                    maxCount: 2_000,
                    parallax: 80
                )
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                if allowsSelection, let selection {
                    let rect = viewRect(for: selection, imageFrame: imageFrame)
                    Rectangle()
                        .stroke(.white, lineWidth: 2)
                        .background(Rectangle().fill(selectionFill))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard allowsSelection else {
                            return
                        }
                        let isBeginning = dragStart == nil
                        if isBeginning {
                            dragStart = value.startLocation
                        }

                        let viewRect = CGRect(
                            x: min(dragStart?.x ?? value.location.x, value.location.x),
                            y: min(dragStart?.y ?? value.location.y, value.location.y),
                            width: abs(value.location.x - (dragStart?.x ?? value.location.x)),
                            height: abs(value.location.y - (dragStart?.y ?? value.location.y))
                        ).insetBy(dx: -14, dy: -14)

                        let depthRect = depthRect(for: viewRect, imageFrame: imageFrame)
                        selection = depthRect
                        if isBeginning {
                            onSelectionBegan(depthRect)
                        } else {
                            onSelectionChanged(depthRect)
                        }
                    }
                    .onEnded { value in
                        guard allowsSelection else {
                            dragStart = nil
                            return
                        }
                        let viewRect = CGRect(
                            x: min(dragStart?.x ?? value.location.x, value.location.x),
                            y: min(dragStart?.y ?? value.location.y, value.location.y),
                            width: abs(value.location.x - (dragStart?.x ?? value.location.x)),
                            height: abs(value.location.y - (dragStart?.y ?? value.location.y))
                        ).insetBy(dx: -14, dy: -14)

                        let depthRect = depthRect(for: viewRect, imageFrame: imageFrame)
                        selection = depthRect
                        onSelectionEnded(depthRect)
                        dragStart = nil
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        guard allowsSelection else {
                            return
                        }
                        dragStart = nil
                        onSelectionCleared()
                    }
            )
        }
        .background(Color.black)
    }

    private var selectionFill: Color {
        switch interactionState {
        case .drawingSelection:
            .white.opacity(0.08)
        case .idle, .regionSelected:
            .white.opacity(0.14)
        }
    }

    private func fittedRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let verticalBias: CGFloat = 0.38
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) * verticalBias,
            width: size.width,
            height: size.height
        )
    }

    private func depthRect(for viewRect: CGRect, imageFrame: CGRect) -> CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return .zero
        }

        let clamped = viewRect.intersection(imageFrame)
        guard !clamped.isNull else {
            return .zero
        }

        let nativeSize = CGSize(width: depthMap.width, height: depthMap.height)
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: nativeSize, orientation: orientation)
        let displayedRect = CGRect(
            x: (clamped.minX - imageFrame.minX) / imageFrame.width * displayedDepthSize.width,
            y: (clamped.minY - imageFrame.minY) / imageFrame.height * displayedDepthSize.height,
            width: max(clamped.width / imageFrame.width * displayedDepthSize.width, 1),
            height: max(clamped.height / imageFrame.height * displayedDepthSize.height, 1)
        )
        return TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedRect,
            nativeSize: nativeSize,
            orientation: orientation
        )
    }

    private func viewRect(for depthRect: CGRect, imageFrame: CGRect) -> CGRect {
        guard depthMap.width > 0, depthMap.height > 0 else {
            return .zero
        }

        let nativeSize = CGSize(width: depthMap.width, height: depthMap.height)
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: nativeSize, orientation: orientation)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: depthRect,
            nativeSize: nativeSize,
            orientation: orientation
        )
        return CGRect(
            x: imageFrame.minX + displayedRect.minX / displayedDepthSize.width * imageFrame.width,
            y: imageFrame.minY + displayedRect.minY / displayedDepthSize.height * imageFrame.height,
            width: displayedRect.width / displayedDepthSize.width * imageFrame.width,
            height: displayedRect.height / displayedDepthSize.height * imageFrame.height
        )
    }
}

private struct PointCloudLoupe: View {
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selection: CGRect

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Cloud loupe")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))

            PointCloudCanvas(
                depthMap: depthMap,
                orientation: orientation,
                region: selection,
                maxCount: 900,
                parallax: 24
            )
                .frame(width: 136, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
        }
        .padding(8)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Selected point cloud loupe")
    }
}

struct PointCloudRegionPreview: View {
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selection: CGRect
    var previewSize = CGSize(width: 136, height: 136)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Local cloud")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))

            PointCloudCanvas(
                depthMap: depthMap,
                orientation: orientation,
                region: selection,
                maxCount: 900,
                parallax: 24
            )
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
        }
        .padding(8)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Selected point cloud preview")
    }
}

nonisolated struct TAPDepthProjectionCameraModel: Equatable, Sendable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let imageWidth: Int
    let imageHeight: Int

    init(
        fx: Float,
        fy: Float,
        cx: Float,
        cy: Float,
        imageWidth: Int,
        imageHeight: Int
    ) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    init?(
        depthMap: TAPMetricDepthMap,
        imageWidth: Int,
        imageHeight: Int
    ) {
        guard imageWidth > 0,
              imageHeight > 0,
              let depthIntrinsics = TAPCameraIntrinsics(
                calibration: depthMap.calibration,
                depthWidth: depthMap.width,
                depthHeight: depthMap.height
              ) else {
            return nil
        }
        let scaleX = Float(imageWidth) / Float(max(depthMap.width, 1))
        let scaleY = Float(imageHeight) / Float(max(depthMap.height, 1))
        self.fx = depthIntrinsics.fx * scaleX
        self.fy = depthIntrinsics.fy * scaleY
        self.cx = depthIntrinsics.cx * scaleX
        self.cy = depthIntrinsics.cy * scaleY
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    func displayOriented(_ orientation: CGImagePropertyOrientation) -> TAPDepthProjectionCameraModel {
        let width = Float(max(imageWidth - 1, 0))
        let height = Float(max(imageHeight - 1, 0))

        switch orientation {
        case .up:
            return self
        case .upMirrored:
            return TAPDepthProjectionCameraModel(
                fx: fx,
                fy: fy,
                cx: width - cx,
                cy: cy,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        case .down:
            return TAPDepthProjectionCameraModel(
                fx: fx,
                fy: fy,
                cx: width - cx,
                cy: height - cy,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        case .downMirrored:
            return TAPDepthProjectionCameraModel(
                fx: fx,
                fy: fy,
                cx: cx,
                cy: height - cy,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        case .right:
            return TAPDepthProjectionCameraModel(
                fx: fy,
                fy: fx,
                cx: height - cy,
                cy: cx,
                imageWidth: imageHeight,
                imageHeight: imageWidth
            )
        case .rightMirrored:
            return TAPDepthProjectionCameraModel(
                fx: fy,
                fy: fx,
                cx: height - cy,
                cy: width - cx,
                imageWidth: imageHeight,
                imageHeight: imageWidth
            )
        case .left:
            return TAPDepthProjectionCameraModel(
                fx: fy,
                fy: fx,
                cx: cy,
                cy: width - cx,
                imageWidth: imageHeight,
                imageHeight: imageWidth
            )
        case .leftMirrored:
            return TAPDepthProjectionCameraModel(
                fx: fy,
                fy: fx,
                cx: cy,
                cy: cx,
                imageWidth: imageHeight,
                imageHeight: imageWidth
            )
        }
    }
}

nonisolated struct TAPDepthDisplayProjectionFrame: Equatable {
    let depthWidth: Int
    let depthHeight: Int
    let rawImageWidth: Int
    let rawImageHeight: Int
    let orientation: CGImagePropertyOrientation
    let cameraModel: TAPDepthProjectionCameraModel

    init?(
        depthMap: TAPMetricDepthMap,
        imageWidth: Int,
        imageHeight: Int,
        orientation: CGImagePropertyOrientation
    ) {
        guard let rawCameraModel = TAPDepthProjectionCameraModel(
            depthMap: depthMap,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        ) else {
            return nil
        }

        self.depthWidth = depthMap.width
        self.depthHeight = depthMap.height
        self.rawImageWidth = imageWidth
        self.rawImageHeight = imageHeight
        self.orientation = orientation
        self.cameraModel = rawCameraModel.displayOriented(orientation)
    }

    func sceneVertex(
        forDepthPoint depthPoint: CGPoint,
        depthMeters: Float
    ) -> SIMD3<Float> {
        let point = displayCameraPoint(forDepthPoint: depthPoint, depthMeters: depthMeters)
        return SIMD3<Float>(point.x, -point.y, -point.z)
    }

    func displayCameraPoint(
        forDepthPoint depthPoint: CGPoint,
        depthMeters: Float
    ) -> TAPPoint3D {
        let displayPoint = displayImagePoint(forDepthPoint: depthPoint)
        let z = max(depthMeters, 0.000_001)
        let x = (Float(displayPoint.x) - cameraModel.cx) / cameraModel.fx * z
        let y = (Float(displayPoint.y) - cameraModel.cy) / cameraModel.fy * z
        return TAPPoint3D(x: x, y: y, z: z)
    }

    func rawImagePoint(forDepthPoint depthPoint: CGPoint) -> CGPoint {
        let x = scaledCoordinate(
            value: depthPoint.x,
            sourceExtent: depthWidth,
            targetExtent: rawImageWidth
        )
        let y = scaledCoordinate(
            value: depthPoint.y,
            sourceExtent: depthHeight,
            targetExtent: rawImageHeight
        )
        return CGPoint(x: x, y: y)
    }

    func displayImagePoint(forDepthPoint depthPoint: CGPoint) -> CGPoint {
        Self.displayImagePoint(
            fromRawImagePoint: rawImagePoint(forDepthPoint: depthPoint),
            rawImageWidth: rawImageWidth,
            rawImageHeight: rawImageHeight,
            orientation: orientation
        )
    }

    static func displayImagePoint(
        fromRawImagePoint rawPoint: CGPoint,
        rawImageWidth: Int,
        rawImageHeight: Int,
        orientation: CGImagePropertyOrientation
    ) -> CGPoint {
        let maxX = CGFloat(max(rawImageWidth - 1, 0))
        let maxY = CGFloat(max(rawImageHeight - 1, 0))

        switch orientation {
        case .up:
            return rawPoint
        case .upMirrored:
            return CGPoint(x: maxX - rawPoint.x, y: rawPoint.y)
        case .down:
            return CGPoint(x: maxX - rawPoint.x, y: maxY - rawPoint.y)
        case .downMirrored:
            return CGPoint(x: rawPoint.x, y: maxY - rawPoint.y)
        case .right:
            return CGPoint(x: maxY - rawPoint.y, y: rawPoint.x)
        case .rightMirrored:
            return CGPoint(x: maxY - rawPoint.y, y: maxX - rawPoint.x)
        case .left:
            return CGPoint(x: rawPoint.y, y: maxX - rawPoint.x)
        case .leftMirrored:
            return CGPoint(x: rawPoint.y, y: rawPoint.x)
        }
    }

    private func scaledCoordinate(
        value: CGFloat,
        sourceExtent: Int,
        targetExtent: Int
    ) -> CGFloat {
        guard sourceExtent > 1, targetExtent > 1 else {
            return 0
        }
        return min(
            max(value / CGFloat(sourceExtent - 1) * CGFloat(targetExtent - 1), 0),
            CGFloat(targetExtent - 1)
        )
    }
}

nonisolated enum TAPDepthProjectionCameraContract {
    static func fittedIntrinsics(
        cameraModel: TAPDepthProjectionCameraModel,
        viewportSize: CGSize
    ) -> (fx: Float, fy: Float, cx: Float, cy: Float) {
        let viewportWidth = max(Float(viewportSize.width), 1)
        let viewportHeight = max(Float(viewportSize.height), 1)
        let imageWidth = max(Float(cameraModel.imageWidth), 1)
        let imageHeight = max(Float(cameraModel.imageHeight), 1)
        let imageAspect = imageWidth / imageHeight
        let viewportAspect = viewportWidth / viewportHeight

        if viewportAspect > imageAspect {
            let fittedWidth = viewportHeight * imageAspect
            let xOffset = (viewportWidth - fittedWidth) / 2
            let scale = fittedWidth / imageWidth
            return (
                fx: cameraModel.fx * scale,
                fy: cameraModel.fy * scale,
                cx: xOffset + cameraModel.cx * scale,
                cy: cameraModel.cy * scale
            )
        }

        let fittedHeight = viewportWidth / imageAspect
        let yOffset = (viewportHeight - fittedHeight) / 2
        let scale = fittedHeight / imageHeight
        return (
            fx: cameraModel.fx * scale,
            fy: cameraModel.fy * scale,
            cx: cameraModel.cx * scale,
            cy: yOffset + cameraModel.cy * scale
        )
    }

    static func projectionMatrix(
        cameraModel: TAPDepthProjectionCameraModel,
        viewportSize: CGSize,
        near: Float,
        far: Float
    ) -> SCNMatrix4 {
        let viewportWidth = max(Float(viewportSize.width), 1)
        let viewportHeight = max(Float(viewportSize.height), 1)
        let fitted = fittedIntrinsics(cameraModel: cameraModel, viewportSize: viewportSize)
        let safeNear = max(near, 0.0001)
        let safeFar = max(far, safeNear + 0.0001)

        return SCNMatrix4(
            m11: 2 * fitted.fx / viewportWidth,
            m12: 0,
            m13: 0,
            m14: 0,
            m21: 0,
            m22: 2 * fitted.fy / viewportHeight,
            m23: 0,
            m24: 0,
            m31: 1 - 2 * fitted.cx / viewportWidth,
            m32: 2 * fitted.cy / viewportHeight - 1,
            m33: -(safeFar + safeNear) / (safeFar - safeNear),
            m34: -1,
            m41: 0,
            m42: 0,
            m43: -2 * safeFar * safeNear / (safeFar - safeNear),
            m44: 0
        )
    }
}

nonisolated enum TAPPlaneRegionHighlightMask {
    static func depthIndexSet(
        for region: TAPPlaneRegion?,
        depthMap: TAPMetricDepthMap
    ) -> Set<Int> {
        guard let region,
              TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap) else {
            return []
        }

        var indexes = Set<Int>()
        indexes.reserveCapacity(max(region.sampleCount, region.pixelRuns.reduce(0) { $0 + $1.width }))
        for run in region.pixelRuns {
            guard run.y >= 0, run.y < depthMap.height else {
                continue
            }
            let startX = min(max(run.xStart, 0), depthMap.width)
            let endX = min(max(run.xEndExclusive, startX), depthMap.width)
            guard startX < endX else {
                continue
            }
            for x in startX..<endX {
                indexes.insert(depthMap.index(x: x, y: run.y))
            }
        }
        return indexes
    }
}

nonisolated enum TAPDepthProjectionInteractionPolicy {
    static let usesSceneKitDefaultCameraControl = false
    static let minimumScale: Float = 0.6
    static let maximumScale: Float = 3.2
    static let motionParallaxPitchScale: Float = 0.06
    static let motionParallaxRollScale: Float = 0.08

    static func interactionPivotPosition(targetDepth: Float) -> SCNVector3 {
        SCNVector3(0, 0, -safeTargetDepth(targetDepth))
    }

    static func geometryCompensationPosition(targetDepth: Float) -> SCNVector3 {
        SCNVector3(0, 0, safeTargetDepth(targetDepth))
    }

    static func clampedScale(_ scale: Float) -> Float {
        min(max(scale, minimumScale), maximumScale)
    }

    static func rollAngle(startAngle: Float, gestureRotation: CGFloat) -> Float {
        startAngle - Float(gestureRotation)
    }

    static func motionParallaxEulerAngles(
        pitch: Double,
        roll: Double,
        baselinePitch: Double,
        baselineRoll: Double
    ) -> SCNVector3 {
        SCNVector3(
            Float(normalizedAngleDelta(pitch - baselinePitch)) * motionParallaxPitchScale,
            Float(normalizedAngleDelta(roll - baselineRoll)) * motionParallaxRollScale,
            0
        )
    }

    static func scenePanOffset(
        forScreenTranslation translation: CGPoint,
        cameraModel: TAPDepthProjectionCameraModel,
        viewportSize: CGSize,
        targetDepth: Float
    ) -> SIMD2<Float> {
        let fitted = TAPDepthProjectionCameraContract.fittedIntrinsics(
            cameraModel: cameraModel,
            viewportSize: viewportSize
        )
        let depth = safeTargetDepth(targetDepth)
        let x = Float(translation.x) * depth / max(fitted.fx, 0.000_001)
        let y = -Float(translation.y) * depth / max(fitted.fy, 0.000_001)
        return SIMD2<Float>(x, y)
    }

    private static func safeTargetDepth(_ targetDepth: Float) -> Float {
        max(targetDepth, 0.25)
    }

    private static func normalizedAngleDelta(_ delta: Double) -> Double {
        atan2(sin(delta), cos(delta))
    }
}

nonisolated enum TAPDepthProjectionSampleFilter {
    static let maximumRenderableDepthMeters: Float = 100

    static func isRenderableDepth(_ depth: Float) -> Bool {
        depth.isFinite && depth > 0 && depth < maximumRenderableDepthMeters
    }

    static func renderableSamples(
        from samples: [(point: TAPPoint3D, imagePoint: CGPoint)]
    ) -> [(point: TAPPoint3D, imagePoint: CGPoint)] {
        samples.filter { isRenderableDepth($0.point.z) }
    }

    static func targetDepth(from depths: [Float]) -> Float {
        let sortedDepths = depths
            .filter(isRenderableDepth)
            .sorted()
        guard !sortedDepths.isEmpty else {
            return 0.25
        }
        return max(sortedDepths[sortedDepths.count / 2], 0.25)
    }
}

nonisolated struct TAPRGBPixelSampler {
    let width: Int
    let height: Int
    private let rgbaPixels: [UInt8]

    init?(image: CGImage) {
        guard image.width > 0, image.height > 0 else {
            return nil
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didRender = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didRender else {
            return nil
        }
        self.width = width
        self.height = height
        self.rgbaPixels = pixels
    }

    func color(
        atDepthPoint depthPoint: CGPoint,
        projectionFrame: TAPDepthDisplayProjectionFrame
    ) -> SIMD4<Float> {
        let point = projectionFrame.rawImagePoint(forDepthPoint: depthPoint)
        let x = min(max(Int(point.x.rounded()), 0), width - 1)
        let y = min(max(Int(point.y.rounded()), 0), height - 1)
        let index = (y * width + x) * 4
        guard index + 3 < rgbaPixels.count else {
            return SIMD4<Float>(1, 1, 1, 1)
        }
        return SIMD4<Float>(
            Float(rgbaPixels[index]) / 255.0,
            Float(rgbaPixels[index + 1]) / 255.0,
            Float(rgbaPixels[index + 2]) / 255.0,
            Float(rgbaPixels[index + 3]) / 255.0
        )
    }
}

fileprivate struct TAPDepthProjectionPayloadBuildRequest: @unchecked Sendable {
    let image: CGImage?
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selectedPlaneRegion: TAPPlaneRegion?
    let highlightColor: UIColor
}

nonisolated struct TAPDepthProjectionScenePayloadData: Sendable {
    let cameraModel: TAPDepthProjectionCameraModel
    let targetDepth: Float
    let stats: TAPDepthProjectionSceneStats
    let baseVertices: [SIMD3<Float>]
    let baseColors: [SIMD4<Float>]
    let highlightVertices: [SIMD3<Float>]
    let highlightColor: SIMD4<Float>
    let pointSize: CGFloat
}

nonisolated struct TAPDepthProjectionSceneStats: Sendable {
    let depthWidth: Int
    let depthHeight: Int
    let rawImageWidth: Int
    let rawImageHeight: Int
    let orientedImageWidth: Int
    let orientedImageHeight: Int
    let cameraFx: Float
    let cameraFy: Float
    let cameraCx: Float
    let cameraCy: Float
    let rawSampleCount: Int
    let sampleCount: Int
    let filteredOutPointCount: Int
    let highlightPointCount: Int
    let depthMin: Float
    let depthMax: Float
    let depthMean: Float
    let vertexMinZ: Float
    let vertexMaxZ: Float
    let targetDepth: Float
    let pointSize: Float
    let hasRGB: Bool
    let hasHighlight: Bool

    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
    func probeFields(orientation: CGImagePropertyOrientation) -> [String: Any] {
        [
            "depthWidth": depthWidth,
            "depthHeight": depthHeight,
            "rawImageWidth": rawImageWidth,
            "rawImageHeight": rawImageHeight,
            "orientedImageWidth": orientedImageWidth,
            "orientedImageHeight": orientedImageHeight,
            "orientation": orientation.rawValue,
            "cameraFx": Double(cameraFx),
            "cameraFy": Double(cameraFy),
            "cameraCx": Double(cameraCx),
            "cameraCy": Double(cameraCy),
            "rawSampleCount": rawSampleCount,
            "sampleCount": sampleCount,
            "filteredOutPointCount": filteredOutPointCount,
            "highlightPointCount": highlightPointCount,
            "depthMin": Double(depthMin),
            "depthMax": Double(depthMax),
            "depthMean": Double(depthMean),
            "vertexMinZ": Double(vertexMinZ),
            "vertexMaxZ": Double(vertexMaxZ),
            "targetDepth": Double(targetDepth),
            "pointSize": Double(pointSize),
            "hasRGB": hasRGB,
            "hasHighlight": hasHighlight
        ]
    }
    #endif
}

nonisolated enum TAPDepthProjectionScenePayloadBuilder {
    static func makePayloadData(
        image: CGImage?,
        depthMap: TAPMetricDepthMap,
        orientation: CGImagePropertyOrientation,
        selectedPlaneRegion: TAPPlaneRegion?,
        highlightColor: UIColor = .systemYellow
    ) -> TAPDepthProjectionScenePayloadData? {
        makePayloadData(
            request: TAPDepthProjectionPayloadBuildRequest(
                image: image,
                depthMap: depthMap,
                orientation: orientation,
                selectedPlaneRegion: selectedPlaneRegion,
                highlightColor: highlightColor
            )
        )
    }

    fileprivate static func makePayloadData(
        request: TAPDepthProjectionPayloadBuildRequest
    ) -> TAPDepthProjectionScenePayloadData? {
        guard !Task.isCancelled else {
            return nil
        }

        let image = request.image
        let depthMap = request.depthMap
        let orientation = request.orientation
        let selectedPlaneRegion = request.selectedPlaneRegion
        let highlightColor = rgbaColor(request.highlightColor)
        let fullRegion = CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
        let samples = TAPDepthGeometryProjector.sampledPoints(
            from: depthMap,
            in: fullRegion,
            maxCount: 12_000
        )
        let rawSampleCount = samples.count
        let renderableSamples = TAPDepthProjectionSampleFilter.renderableSamples(from: samples)
        let filteredOutPointCount = rawSampleCount - renderableSamples.count
        guard !renderableSamples.isEmpty else {
            return nil
        }
        let projectionFrame = TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: image?.width ?? depthMap.width,
            imageHeight: image?.height ?? depthMap.height,
            orientation: orientation
        )
        guard let projectionFrame else {
            return nil
        }

        let rgbSampler = image.flatMap(TAPRGBPixelSampler.init(image:))
        let highlightMask = TAPPlaneRegionHighlightMask.depthIndexSet(
            for: selectedPlaneRegion,
            depthMap: depthMap
        )
        var baseVertices: [SIMD3<Float>] = []
        var baseColors: [SIMD4<Float>] = []
        var highlightVertices: [SIMD3<Float>] = []
        baseVertices.reserveCapacity(renderableSamples.count)
        baseColors.reserveCapacity(renderableSamples.count)

        var depthSum: Float = 0
        var depthMin = Float.greatestFiniteMagnitude
        var depthMax = -Float.greatestFiniteMagnitude
        var vertexMinZ = Float.greatestFiniteMagnitude
        var vertexMaxZ = -Float.greatestFiniteMagnitude
        for (sampleIndex, sample) in renderableSamples.enumerated() {
            if sampleIndex.isMultiple(of: 512), Task.isCancelled {
                return nil
            }

            let vertex = projectionFrame.sceneVertex(
                forDepthPoint: sample.imagePoint,
                depthMeters: sample.point.z
            )
            baseVertices.append(vertex)
            baseColors.append(
                rgbSampler?.color(
                    atDepthPoint: sample.imagePoint,
                    projectionFrame: projectionFrame
                ) ?? fallbackColor(sample: sample)
            )
            depthSum += sample.point.z
            depthMin = min(depthMin, sample.point.z)
            depthMax = max(depthMax, sample.point.z)
            vertexMinZ = min(vertexMinZ, vertex.z)
            vertexMaxZ = max(vertexMaxZ, vertex.z)

            let x = min(max(Int(sample.imagePoint.x.rounded(.down)), 0), max(depthMap.width - 1, 0))
            let y = min(max(Int(sample.imagePoint.y.rounded(.down)), 0), max(depthMap.height - 1, 0))
            if highlightMask.contains(depthMap.index(x: x, y: y)) {
                highlightVertices.append(vertex)
            }
        }
        let targetDepth = TAPDepthProjectionSampleFilter.targetDepth(
            from: renderableSamples.map(\.point.z)
        )
        let basePointSize = pointSize(depthMap: depthMap, sampleCount: baseVertices.count)
        let stats = TAPDepthProjectionSceneStats(
            depthWidth: depthMap.width,
            depthHeight: depthMap.height,
            rawImageWidth: image?.width ?? depthMap.width,
            rawImageHeight: image?.height ?? depthMap.height,
            orientedImageWidth: projectionFrame.cameraModel.imageWidth,
            orientedImageHeight: projectionFrame.cameraModel.imageHeight,
            cameraFx: projectionFrame.cameraModel.fx,
            cameraFy: projectionFrame.cameraModel.fy,
            cameraCx: projectionFrame.cameraModel.cx,
            cameraCy: projectionFrame.cameraModel.cy,
            rawSampleCount: rawSampleCount,
            sampleCount: baseVertices.count,
            filteredOutPointCount: filteredOutPointCount,
            highlightPointCount: highlightVertices.count,
            depthMin: depthMin,
            depthMax: depthMax,
            depthMean: depthSum / Float(renderableSamples.count),
            vertexMinZ: vertexMinZ,
            vertexMaxZ: vertexMaxZ,
            targetDepth: targetDepth,
            pointSize: Float(basePointSize),
            hasRGB: rgbSampler != nil,
            hasHighlight: !highlightVertices.isEmpty
        )
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDepthProjectionProbeReport.writeVertexDump(
            fields: stats.probeFields(orientation: orientation),
            samples: vertexDumpSamples(
                samples: renderableSamples,
                vertices: baseVertices,
                colors: baseColors
            )
        )
        #endif

        return TAPDepthProjectionScenePayloadData(
            cameraModel: projectionFrame.cameraModel,
            targetDepth: targetDepth,
            stats: stats,
            baseVertices: baseVertices,
            baseColors: baseColors,
            highlightVertices: highlightVertices,
            highlightColor: highlightColor,
            pointSize: basePointSize
        )
    }

    private static func fallbackColor(sample: (point: TAPPoint3D, imagePoint: CGPoint)) -> SIMD4<Float> {
        let normalizedZ = min(max(sample.point.z / 5.0, 0), 1)
        let color = TAPDepthHeatmapRenderer.viridisColor(normalized: normalizedZ)
        return SIMD4<Float>(
            Float(color.red) / 255.0,
            Float(color.green) / 255.0,
            Float(color.blue) / 255.0,
            Float(color.alpha) / 255.0
        )
    }

    fileprivate static func rgbaColor(_ color: UIColor) -> SIMD4<Float> {
        var red: CGFloat = 1
        var green: CGFloat = 0.84
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }

    private static func pointSize(depthMap: TAPMetricDepthMap, sampleCount: Int) -> CGFloat {
        let longestEdge = max(depthMap.width, depthMap.height, 1)
        let density = sqrt(Double(max(sampleCount, 1))) / Double(longestEdge)
        return CGFloat(min(max(density * 5.4, 2.4), 5.8))
    }

    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
    private static func vertexDumpSamples(
        samples: [(point: TAPPoint3D, imagePoint: CGPoint)],
        vertices: [SIMD3<Float>],
        colors: [SIMD4<Float>],
        maxCount: Int = 2_048
    ) -> [[String: Double]] {
        guard !samples.isEmpty,
              samples.count == vertices.count,
              samples.count == colors.count else {
            return []
        }
        let step = max(samples.count / max(maxCount, 1), 1)
        var output: [[String: Double]] = []
        output.reserveCapacity(min(samples.count, maxCount))

        for index in stride(from: 0, to: samples.count, by: step) {
            guard output.count < maxCount else {
                break
            }
            let sample = samples[index]
            let vertex = vertices[index]
            let color = colors[index]
            output.append([
                "depthX": Double(sample.imagePoint.x),
                "depthY": Double(sample.imagePoint.y),
                "depthMeters": Double(sample.point.z),
                "cameraX": Double(sample.point.x),
                "cameraY": Double(sample.point.y),
                "cameraZ": Double(sample.point.z),
                "sceneX": Double(vertex.x),
                "sceneY": Double(vertex.y),
                "sceneZ": Double(vertex.z),
                "red": Double(color.x),
                "green": Double(color.y),
                "blue": Double(color.z),
                "alpha": Double(color.w)
            ])
        }
        return output
    }
    #endif
}

private struct DepthProjectionSceneView: UIViewRepresentable {
    let image: CGImage?
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selectedPlaneRegion: TAPPlaneRegion?
    let highlightColor: UIColor
    let enablesMotionParallax: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProjectionSCNView {
        let view = ProjectionSCNView(frame: .zero)
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = TAPDepthProjectionInteractionPolicy.usesSceneKitDefaultCameraControl
        let orbitGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOrbitPan(_:))
        )
        orbitGesture.maximumNumberOfTouches = 1

        let translationGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTranslationPan(_:))
        )
        translationGesture.minimumNumberOfTouches = 2
        translationGesture.maximumNumberOfTouches = 2

        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )

        let rollGesture = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRollRotation(_:))
        )

        let resetGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleResetTap(_:))
        )
        resetGesture.numberOfTapsRequired = 2

        [
            orbitGesture,
            translationGesture,
            pinchGesture,
            rollGesture,
            resetGesture
        ].forEach { gesture in
            gesture.cancelsTouchesInView = true
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = context.coordinator
            context.coordinator.registerProjectionGesture(gesture)
            view.addGestureRecognizer(gesture)
        }
        view.gesturesForAncestorFailure = [
            orbitGesture,
            translationGesture
        ]
        view.onLayout = { [weak view, weak coordinator = context.coordinator] size in
            guard let view else {
                return
            }
            coordinator?.syncProjection(view: view, viewportSize: size)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            if Coordinator.isValidViewportSize(size) {
                coordinator?.logLayout(view: view, viewportSize: size)
            }
            #endif
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        view.onTouchEvent = { [weak view, weak coordinator = context.coordinator] phase, touchCount in
            guard let view else {
                return
            }
            coordinator?.logTouchEvent(phase: phase, view: view, touchCount: touchCount)
        }
        context.coordinator.logViewCreated(view: view)
        #endif
        return view
    }

    func updateUIView(_ view: ProjectionSCNView, context: Context) {
        context.coordinator.update(
            view: view,
            image: image,
            depthMap: depthMap,
            orientation: orientation,
            selectedPlaneRegion: selectedPlaneRegion,
            highlightColor: highlightColor,
            enablesMotionParallax: enablesMotionParallax,
            reduceMotion: accessibilityReduceMotion
        )
    }

    final class ProjectionSCNView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        var gesturesForAncestorFailure: [UIGestureRecognizer] = [] {
            didSet {
                configuredAncestorScrollViewIDs.removeAll()
                requireAncestorScrollViewsToFailProjectionGestures()
            }
        }
        private var configuredAncestorScrollViewIDs: Set<ObjectIdentifier> = []
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        var onTouchEvent: ((String, Int) -> Void)?
        #endif

        override func layoutSubviews() {
            super.layoutSubviews()
            requireAncestorScrollViewsToFailProjectionGestures()
            onLayout?(bounds.size)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            requireAncestorScrollViewsToFailProjectionGestures()
        }

        private func requireAncestorScrollViewsToFailProjectionGestures() {
            guard !gesturesForAncestorFailure.isEmpty else {
                return
            }

            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView {
                    let identifier = ObjectIdentifier(scrollView)
                    if !configuredAncestorScrollViewIDs.contains(identifier) {
                        configuredAncestorScrollViewIDs.insert(identifier)
                        for gesture in gesturesForAncestorFailure {
                            scrollView.panGestureRecognizer.require(toFail: gesture)
                        }
                    }
                }
                candidate = view.superview
            }
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouchEvent?("touchesBegan.before", touches.count)
            super.touchesBegan(touches, with: event)
            onTouchEvent?("touchesBegan.after", touches.count)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            onTouchEvent?("touchesMoved.after", touches.count)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            onTouchEvent?("touchesEnded.after", touches.count)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            onTouchEvent?("touchesCancelled.after", touches.count)
        }
        #endif
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var currentSignature: String?
        private var pendingPayloadSignature: String?
        private var payloadBuildTask: Task<TAPDepthProjectionScenePayloadData?, Never>?
        private let motionManager = CMMotionManager()
        private weak var interactionRootNode: SCNNode?
        private weak var projectionRootNode: SCNNode?
        private weak var highlightNode: SCNNode?
        private weak var cameraNode: SCNNode?
        private var currentCameraModel: TAPDepthProjectionCameraModel?
        private var currentTargetDepth: Float = 0.25
        private let projectionGestures = NSHashTable<UIGestureRecognizer>.weakObjects()
        private var panStartEulerAngles = SCNVector3(0, 0, 0)
        private var translationStartPosition = SCNVector3(0, 0, 0)
        private var pinchStartScale: Float = 1
        private var rollStartAngle: Float = 0
        private var motionParallaxBaseline: MotionParallaxAttitude?
        private var shouldRecenterMotionParallax = true
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        private weak var sceneView: SCNView?
        private var lastLayoutProbeSize: CGSize = .zero
        private var lastStateProbeDate = Date.distantPast
        private var lastMotionProbeDate = Date.distantPast
        private var lastTouchMoveProbeDate = Date.distantPast
        #endif

        deinit {
            payloadBuildTask?.cancel()
            motionManager.stopDeviceMotionUpdates()
        }

        func registerProjectionGesture(_ gesture: UIGestureRecognizer) {
            projectionGestures.add(gesture)
        }

        @objc func handleOrbitPan(_ gesture: UIPanGestureRecognizer) {
            guard let interactionRootNode,
                  let view = gesture.view else {
                return
            }

            switch gesture.state {
            case .began:
                panStartEulerAngles = interactionRootNode.eulerAngles
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "orbitGesture", label: "began")
                #endif
            case .changed:
                let translation = gesture.translation(in: view)
                let width = max(view.bounds.width, 1)
                let height = max(view.bounds.height, 1)
                let yaw = panStartEulerAngles.y + Float(translation.x / width) * .pi
                let pitch = panStartEulerAngles.x + Float(translation.y / height) * .pi * 0.72
                interactionRootNode.eulerAngles.x = min(max(pitch, -.pi / 2), .pi / 2)
                interactionRootNode.eulerAngles.y = yaw
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "orbitGesture", label: "changed")
                #endif
            case .ended:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "orbitGesture", label: "ended")
                #endif
            case .cancelled:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "orbitGesture", label: "cancelled")
                #endif
            default:
                break
            }
        }

        @objc func handleTranslationPan(_ gesture: UIPanGestureRecognizer) {
            guard let interactionRootNode,
                  let currentCameraModel,
                  let view = gesture.view else {
                return
            }

            switch gesture.state {
            case .began:
                translationStartPosition = interactionRootNode.position
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "translationGesture", label: "began")
                #endif
            case .changed:
                let offset = TAPDepthProjectionInteractionPolicy.scenePanOffset(
                    forScreenTranslation: gesture.translation(in: view),
                    cameraModel: currentCameraModel,
                    viewportSize: view.bounds.size,
                    targetDepth: currentTargetDepth
                )
                interactionRootNode.position = SCNVector3(
                    translationStartPosition.x + offset.x,
                    translationStartPosition.y + offset.y,
                    translationStartPosition.z
                )
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "translationGesture", label: "changed")
                #endif
            case .ended:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "translationGesture", label: "ended")
                #endif
            case .cancelled:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logPanGesture(gesture, view: view, event: "translationGesture", label: "cancelled")
                #endif
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let interactionRootNode else {
                return
            }

            switch gesture.state {
            case .began:
                pinchStartScale = interactionRootNode.scale.x
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "pinchGesture", label: "began", valueLabel: "scale", value: gesture.scale)
                #endif
            case .changed:
                let nextScale = TAPDepthProjectionInteractionPolicy.clampedScale(
                    pinchStartScale * Float(gesture.scale)
                )
                interactionRootNode.scale = SCNVector3(nextScale, nextScale, nextScale)
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "pinchGesture", label: "changed", valueLabel: "scale", value: CGFloat(nextScale))
                #endif
            case .ended:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "pinchGesture", label: "ended", valueLabel: "scale", value: CGFloat(interactionRootNode.scale.x))
                #endif
            case .cancelled:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "pinchGesture", label: "cancelled", valueLabel: "scale", value: CGFloat(interactionRootNode.scale.x))
                #endif
            default:
                break
            }
        }

        @objc func handleRollRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let interactionRootNode else {
                return
            }

            switch gesture.state {
            case .began:
                rollStartAngle = interactionRootNode.eulerAngles.z
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "rollGesture", label: "began", valueLabel: "rotation", value: gesture.rotation)
                #endif
            case .changed:
                interactionRootNode.eulerAngles.z = TAPDepthProjectionInteractionPolicy.rollAngle(
                    startAngle: rollStartAngle,
                    gestureRotation: gesture.rotation
                )
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "rollGesture", label: "changed", valueLabel: "rotation", value: gesture.rotation)
                #endif
            case .ended:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "rollGesture", label: "ended", valueLabel: "rotation", value: gesture.rotation)
                #endif
            case .cancelled:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                logScalarGesture(gesture, event: "rollGesture", label: "cancelled", valueLabel: "rotation", value: gesture.rotation)
                #endif
            default:
                break
            }
        }

        @objc func handleResetTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .recognized else {
                return
            }
            resetInteractionTransform(animated: true)
            recenterMotionParallaxBaseline(animated: true)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDepthProjectionProbeReport.append(
                event: "resetGesture",
                fields: [
                    "label": "recognized",
                    "gestureState": gesture.state.rawValue
                ]
            )
            if let sceneView {
                logSceneState(label: "resetGesture", view: sceneView, force: true)
            }
            #endif
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            projectionGestures.contains(gestureRecognizer)
                && projectionGestures.contains(otherGestureRecognizer)
        }

        func update(
            view: SCNView,
            image: CGImage?,
            depthMap: TAPMetricDepthMap,
            orientation: CGImagePropertyOrientation,
            selectedPlaneRegion: TAPPlaneRegion?,
            highlightColor: UIColor,
            enablesMotionParallax: Bool,
            reduceMotion: Bool
        ) {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            sceneView = view
            #endif
            let signature = Self.signature(
                depthMap: depthMap,
                image: image,
                orientation: orientation,
                selectedPlaneRegion: selectedPlaneRegion,
                highlightColor: highlightColor
            )
            if currentSignature != signature {
                currentSignature = signature
                configureSceneAsync(
                    view: view,
                    signature: signature,
                    image: image,
                    depthMap: depthMap,
                    orientation: orientation,
                    selectedPlaneRegion: selectedPlaneRegion,
                    highlightColor: highlightColor,
                    reduceMotion: reduceMotion
                )
            }
            syncMotionParallax(enabled: enablesMotionParallax)
            syncProjection(view: view, viewportSize: view.bounds.size)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            if Self.isValidViewportSize(view.bounds.size) {
                logSceneState(label: "update", view: view)
            }
            #endif
        }

        func syncProjection(view: SCNView, viewportSize: CGSize) {
            guard let cameraNode,
                  let camera = cameraNode.camera,
                  let currentCameraModel,
                  Self.isValidViewportSize(viewportSize) else {
                return
            }
            camera.projectionTransform = TAPDepthProjectionCameraContract.projectionMatrix(
                cameraModel: currentCameraModel,
                viewportSize: viewportSize,
                near: Float(camera.zNear),
                far: Float(camera.zFar)
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            logProjectionSync(view: view, viewportSize: viewportSize, camera: camera)
            #endif
        }

        static func isValidViewportSize(_ size: CGSize) -> Bool {
            size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
        }

        private func configureSceneAsync(
            view: SCNView,
            signature: String,
            image: CGImage?,
            depthMap: TAPMetricDepthMap,
            orientation: CGImagePropertyOrientation,
            selectedPlaneRegion: TAPPlaneRegion?,
            highlightColor: UIColor,
            reduceMotion: Bool
        ) {
            let request = TAPDepthProjectionPayloadBuildRequest(
                image: image,
                depthMap: depthMap,
                orientation: orientation,
                selectedPlaneRegion: selectedPlaneRegion,
                highlightColor: highlightColor
            )
            let depthWidth = depthMap.width
            let depthHeight = depthMap.height
            pendingPayloadSignature = signature
            payloadBuildTask?.cancel()
            let buildTask = Task.detached(priority: .userInitiated) {
                TAPDepthProjectionScenePayloadBuilder.makePayloadData(request: request)
            }
            payloadBuildTask = buildTask

            Task { @MainActor [weak self, weak view] in
                let payloadData = await buildTask.value
                guard let self,
                      let view,
                      self.pendingPayloadSignature == signature else {
                    return
                }
                self.pendingPayloadSignature = nil
                self.payloadBuildTask = nil
                self.configureScene(
                    view: view,
                    payloadData: payloadData,
                    depthWidth: depthWidth,
                    depthHeight: depthHeight,
                    orientation: orientation,
                    reduceMotion: reduceMotion
                )
            }
        }

        @MainActor
        private func configureScene(
            view: SCNView,
            payloadData: TAPDepthProjectionScenePayloadData?,
            depthWidth: Int,
            depthHeight: Int,
            orientation: CGImagePropertyOrientation,
            reduceMotion: Bool
        ) {
            let scene = SCNScene()
            currentCameraModel = payloadData?.cameraModel
            let targetDepth = payloadData?.targetDepth ?? 0.25
            currentTargetDepth = targetDepth

            let interactionNode = SCNNode()
            interactionNode.name = "DepthProjectionInteractionRoot"
            interactionNode.position = TAPDepthProjectionInteractionPolicy.interactionPivotPosition(
                targetDepth: targetDepth
            )
            interactionRootNode = interactionNode

            let motionNode = SCNNode()
            motionNode.name = "DepthProjectionMotionRoot"
            projectionRootNode = motionNode
            interactionNode.addChildNode(motionNode)

            let geometryRootNode = SCNNode()
            geometryRootNode.name = "DepthProjectionGeometryRoot"
            geometryRootNode.position = TAPDepthProjectionInteractionPolicy.geometryCompensationPosition(
                targetDepth: targetDepth
            )
            motionNode.addChildNode(geometryRootNode)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            if let payloadData {
                Self.logPayloadStats(payloadData.stats, orientation: orientation)
            } else {
                TAPDiagnostics.depthAnalysis.warning("projection payload missing label=\("payloadMissing", privacy: .public) depthWidth=\(depthWidth, privacy: .public) depthHeight=\(depthHeight, privacy: .public)")
            }
            #endif

            if let payloadData,
               let geometry = Self.makePointGeometry(
                vertices: payloadData.baseVertices,
                colors: payloadData.baseColors,
                pointSize: payloadData.pointSize
               ) {
                let node = SCNNode(geometry: geometry)
                node.name = "DepthProjectionModel"
                geometryRootNode.addChildNode(node)
            }
            if let payloadData,
               let highlightGeometry = Self.makeHighlightGeometry(
                vertices: payloadData.highlightVertices,
                pointSize: payloadData.pointSize * 1.85,
                color: payloadData.highlightColor
               ) {
                let node = SCNNode(geometry: highlightGeometry)
                node.name = "SelectedPlaneProjection"
                highlightNode = node
                if reduceMotion {
                    node.opacity = 0.88
                } else {
                    node.opacity = 0.55
                    node.runAction(
                        .repeatForever(
                            .sequence([
                                .fadeOpacity(to: 1.0, duration: 0.72),
                                .fadeOpacity(to: 0.42, duration: 0.72)
                            ])
                        )
                    )
                }
                geometryRootNode.addChildNode(node)
            } else {
                highlightNode = nil
            }

            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.zNear = 0.01
            camera.zFar = 100
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 0)
            cameraNode.eulerAngles = SCNVector3(0, 0, 0)
            self.cameraNode = cameraNode

            let ambientNode = SCNNode()
            let ambientLight = SCNLight()
            ambientLight.type = .ambient
            ambientLight.intensity = 800
            ambientNode.light = ambientLight

            scene.rootNode.addChildNode(interactionNode)
            scene.rootNode.addChildNode(cameraNode)
            scene.rootNode.addChildNode(ambientNode)
            view.scene = scene
            view.pointOfView = cameraNode
            if payloadData != nil {
                syncProjection(view: view, viewportSize: view.bounds.size)
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            logSceneState(label: "configureScene", view: view, force: true)
            #endif

            // TODO: keep this renderer boundary replaceable with Metal when
            // point count, splat quality, mesh rendering, or performance needs
            // outgrow SceneKit.
        }

        private func resetInteractionTransform(animated: Bool) {
            guard let interactionRootNode else {
                return
            }

            let updates = {
                interactionRootNode.position = TAPDepthProjectionInteractionPolicy.interactionPivotPosition(
                    targetDepth: self.currentTargetDepth
                )
                interactionRootNode.eulerAngles = SCNVector3(0, 0, 0)
                interactionRootNode.scale = SCNVector3(1, 1, 1)
            }

            guard animated else {
                updates()
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.18
            updates()
            SCNTransaction.commit()
        }

        private func recenterMotionParallaxBaseline(animated: Bool) {
            shouldRecenterMotionParallax = true
            let attitude = currentMotionParallaxAttitude()
            if let attitude {
                motionParallaxBaseline = attitude
                shouldRecenterMotionParallax = false
            }
            applyMotionParallax(attitude: attitude, animated: animated)
        }

        private func syncMotionParallax(enabled: Bool) {
            guard enabled, motionManager.isDeviceMotionAvailable else {
                motionManager.stopDeviceMotionUpdates()
                motionParallaxBaseline = nil
                shouldRecenterMotionParallax = true
                applyMotionParallax(attitude: nil, animated: false)
                return
            }

            guard !motionManager.isDeviceMotionActive else {
                return
            }

            motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self,
                      let motion,
                      let projectionRootNode = self.projectionRootNode else {
                    return
                }

                let attitude = MotionParallaxAttitude(motion: motion)
                if self.motionParallaxBaseline == nil || self.shouldRecenterMotionParallax {
                    self.motionParallaxBaseline = attitude
                    self.shouldRecenterMotionParallax = false
                }
                self.applyMotionParallax(
                    attitude: attitude,
                    projectionRootNode: projectionRootNode,
                    animated: true
                )
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                self.logMotionParallax(
                    pitch: motion.attitude.pitch,
                    roll: motion.attitude.roll
                )
                #endif
            }
        }

        private func currentMotionParallaxAttitude() -> MotionParallaxAttitude? {
            guard let motion = motionManager.deviceMotion else {
                return nil
            }
            return MotionParallaxAttitude(motion: motion)
        }

        private func applyMotionParallax(attitude: MotionParallaxAttitude?, animated: Bool) {
            guard let projectionRootNode else {
                return
            }
            applyMotionParallax(attitude: attitude, projectionRootNode: projectionRootNode, animated: animated)
        }

        private func applyMotionParallax(
            attitude: MotionParallaxAttitude?,
            projectionRootNode: SCNNode,
            animated: Bool
        ) {
            let baseline = motionParallaxBaseline ?? attitude
            let eulerAngles: SCNVector3
            if let attitude, let baseline {
                eulerAngles = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
                    pitch: attitude.pitch,
                    roll: attitude.roll,
                    baselinePitch: baseline.pitch,
                    baselineRoll: baseline.roll
                )
            } else {
                eulerAngles = SCNVector3(0, 0, 0)
            }

            let updates = {
                projectionRootNode.eulerAngles = eulerAngles
            }

            guard animated else {
                updates()
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.08
            updates()
            SCNTransaction.commit()
        }

        private struct MotionParallaxAttitude {
            let pitch: Double
            let roll: Double

            init(motion: CMDeviceMotion) {
                pitch = motion.attitude.pitch
                roll = motion.attitude.roll
            }
        }

        private static func makePointGeometry(
            vertices: [SIMD3<Float>],
            colors: [SIMD4<Float>],
            pointSize: CGFloat
        ) -> SCNGeometry? {
            guard !vertices.isEmpty, vertices.count == colors.count else {
                return nil
            }
            let indices = vertices.indices.map(UInt32.init)
            let vertexSource = SCNGeometrySource(
                data: data(from: vertices),
                semantic: .vertex,
                vectorCount: vertices.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )
            let colorSource = SCNGeometrySource(
                data: data(from: colors),
                semantic: .color,
                vectorCount: colors.count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD4<Float>>.stride
            )
            let element = SCNGeometryElement(
                data: data(from: indices),
                primitiveType: .point,
                primitiveCount: indices.count,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            element.pointSize = pointSize
            element.minimumPointScreenSpaceRadius = 1.1
            element.maximumPointScreenSpaceRadius = 7.5

            let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.white
            material.isDoubleSided = true
            geometry.materials = [material]
            return geometry
        }

        private static func makeHighlightGeometry(
            vertices: [SIMD3<Float>],
            pointSize: CGFloat,
            color: SIMD4<Float>
        ) -> SCNGeometry? {
            guard !vertices.isEmpty else {
                return nil
            }
            let indices = vertices.indices.map(UInt32.init)
            let vertexSource = SCNGeometrySource(
                data: data(from: vertices),
                semantic: .vertex,
                vectorCount: vertices.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )
            let element = SCNGeometryElement(
                data: data(from: indices),
                primitiveType: .point,
                primitiveCount: indices.count,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            element.pointSize = pointSize
            element.minimumPointScreenSpaceRadius = 2.5
            element.maximumPointScreenSpaceRadius = 13

            let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            let uiColor = UIColor(
                red: CGFloat(color.x),
                green: CGFloat(color.y),
                blue: CGFloat(color.z),
                alpha: CGFloat(color.w)
            )
            material.diffuse.contents = uiColor
            material.emission.contents = uiColor.withAlphaComponent(0.72)
            material.isDoubleSided = true
            geometry.materials = [material]
            return geometry
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        func logViewCreated(view: SCNView) {
            TAPDiagnostics.depthAnalysis.info("projection view label=\("makeUIView", privacy: .public) allowsCameraControl=\(view.allowsCameraControl, privacy: .public) inertiaEnabled=\(view.defaultCameraController.inertiaEnabled, privacy: .public) gestureRecognizerCount=\(view.gestureRecognizers?.count ?? 0, privacy: .public)")
            TAPDepthProjectionProbeReport.append(
                event: "makeUIView",
                fields: [
                    "allowsCameraControl": view.allowsCameraControl,
                    "inertiaEnabled": view.defaultCameraController.inertiaEnabled,
                    "gestureRecognizerCount": view.gestureRecognizers?.count ?? 0
                ]
            )
        }

        private func logPanGesture(
            _ gesture: UIPanGestureRecognizer,
            view: UIView,
            event: String,
            label: String
        ) {
            let translation = gesture.translation(in: view)
            TAPDepthProjectionProbeReport.append(
                event: event,
                fields: [
                    "label": label,
                    "gestureState": gesture.state.rawValue,
                    "translationX": Double(translation.x),
                    "translationY": Double(translation.y)
                ]
            )
        }

        private func logScalarGesture(
            _ gesture: UIGestureRecognizer,
            event: String,
            label: String,
            valueLabel: String,
            value: CGFloat
        ) {
            TAPDepthProjectionProbeReport.append(
                event: event,
                fields: [
                    "label": label,
                    "gestureState": gesture.state.rawValue,
                    valueLabel: Double(value)
                ]
            )
        }

        func logLayout(view: SCNView, viewportSize: CGSize) {
            let normalizedSize = CGSize(
                width: max(viewportSize.width, 1),
                height: max(viewportSize.height, 1)
            )
            guard abs(normalizedSize.width - lastLayoutProbeSize.width) >= 1
                    || abs(normalizedSize.height - lastLayoutProbeSize.height) >= 1 else {
                return
            }
            lastLayoutProbeSize = normalizedSize
            logSceneState(label: "layout", view: view, force: true)
        }

        func logTouchEvent(phase: String, view: SCNView, touchCount: Int) {
            if phase == "touchesMoved.after" {
                let now = Date()
                guard now.timeIntervalSince(lastTouchMoveProbeDate) >= 0.25 else {
                    return
                }
                lastTouchMoveProbeDate = now
            }
            TAPDiagnostics.depthAnalysis.info("projection touch label=\(phase, privacy: .public) touchCount=\(touchCount, privacy: .public)")
            TAPDepthProjectionProbeReport.append(
                event: "touch",
                fields: [
                    "label": phase,
                    "touchCount": touchCount
                ]
            )
            logSceneState(label: phase, view: view, force: true)
        }

        private func logProjectionSync(
            view: SCNView,
            viewportSize: CGSize,
            camera: SCNCamera
        ) {
            let normalizedSize = CGSize(
                width: max(viewportSize.width, 1),
                height: max(viewportSize.height, 1)
            )
            guard abs(normalizedSize.width - lastLayoutProbeSize.width) >= 1
                    || abs(normalizedSize.height - lastLayoutProbeSize.height) >= 1 else {
                return
            }
            let matrix = camera.projectionTransform
            TAPDiagnostics.depthAnalysis.info("projection matrix label=\("syncProjection", privacy: .public) viewportWidth=\(Double(normalizedSize.width), privacy: .public) viewportHeight=\(Double(normalizedSize.height), privacy: .public) projectionM11=\(Double(matrix.m11), privacy: .public) projectionM22=\(Double(matrix.m22), privacy: .public) projectionM31=\(Double(matrix.m31), privacy: .public) projectionM32=\(Double(matrix.m32), privacy: .public) projectionM43=\(Double(matrix.m43), privacy: .public)")
            TAPDepthProjectionProbeReport.append(
                event: "syncProjection",
                fields: [
                    "viewportWidth": Double(normalizedSize.width),
                    "viewportHeight": Double(normalizedSize.height),
                    "projectionM11": Double(matrix.m11),
                    "projectionM22": Double(matrix.m22),
                    "projectionM31": Double(matrix.m31),
                    "projectionM32": Double(matrix.m32),
                    "projectionM43": Double(matrix.m43)
                ]
            )
        }

        private func logMotionParallax(pitch: Double, roll: Double) {
            let now = Date()
            guard now.timeIntervalSince(lastMotionProbeDate) >= 1.0 else {
                return
            }
            lastMotionProbeDate = now
            TAPDiagnostics.depthAnalysis.info("projection motion label=\("motionParallax", privacy: .public) motionPitch=\(pitch, privacy: .public) motionRoll=\(roll, privacy: .public)")
            TAPDepthProjectionProbeReport.append(
                event: "motionParallax",
                fields: [
                    "motionPitch": pitch,
                    "motionRoll": roll
                ]
            )
            if let sceneView {
                logSceneState(label: "motionParallax", view: sceneView, force: true)
            }
        }

        private static func logPayloadStats(
            _ stats: TAPDepthProjectionSceneStats,
            orientation: CGImagePropertyOrientation
        ) {
            TAPDiagnostics.depthAnalysis.info("projection payload label=\("payload", privacy: .public) depthWidth=\(stats.depthWidth, privacy: .public) depthHeight=\(stats.depthHeight, privacy: .public) rawImageWidth=\(stats.rawImageWidth, privacy: .public) rawImageHeight=\(stats.rawImageHeight, privacy: .public) orientedImageWidth=\(stats.orientedImageWidth, privacy: .public) orientedImageHeight=\(stats.orientedImageHeight, privacy: .public) orientation=\(orientation.rawValue, privacy: .public) cameraFx=\(Double(stats.cameraFx), privacy: .public) cameraFy=\(Double(stats.cameraFy), privacy: .public) cameraCx=\(Double(stats.cameraCx), privacy: .public) cameraCy=\(Double(stats.cameraCy), privacy: .public) rawSampleCount=\(stats.rawSampleCount, privacy: .public) sampleCount=\(stats.sampleCount, privacy: .public) filteredOutPointCount=\(stats.filteredOutPointCount, privacy: .public) highlightPointCount=\(stats.highlightPointCount, privacy: .public) depthMin=\(Double(stats.depthMin), privacy: .public) depthMax=\(Double(stats.depthMax), privacy: .public) depthMean=\(Double(stats.depthMean), privacy: .public) vertexMinZ=\(Double(stats.vertexMinZ), privacy: .public) vertexMaxZ=\(Double(stats.vertexMaxZ), privacy: .public) targetDepth=\(Double(stats.targetDepth), privacy: .public) pointSize=\(Double(stats.pointSize), privacy: .public) hasRGB=\(stats.hasRGB, privacy: .public) hasHighlight=\(stats.hasHighlight, privacy: .public)")
            TAPDepthProjectionProbeReport.append(
                event: "payload",
                fields: [
                    "depthWidth": stats.depthWidth,
                    "depthHeight": stats.depthHeight,
                    "rawImageWidth": stats.rawImageWidth,
                    "rawImageHeight": stats.rawImageHeight,
                    "orientedImageWidth": stats.orientedImageWidth,
                    "orientedImageHeight": stats.orientedImageHeight,
                    "orientation": orientation.rawValue,
                    "cameraFx": Double(stats.cameraFx),
                    "cameraFy": Double(stats.cameraFy),
                    "cameraCx": Double(stats.cameraCx),
                    "cameraCy": Double(stats.cameraCy),
                    "rawSampleCount": stats.rawSampleCount,
                    "sampleCount": stats.sampleCount,
                    "filteredOutPointCount": stats.filteredOutPointCount,
                    "highlightPointCount": stats.highlightPointCount,
                    "depthMin": Double(stats.depthMin),
                    "depthMax": Double(stats.depthMax),
                    "depthMean": Double(stats.depthMean),
                    "vertexMinZ": Double(stats.vertexMinZ),
                    "vertexMaxZ": Double(stats.vertexMaxZ),
                    "targetDepth": Double(stats.targetDepth),
                    "pointSize": Double(stats.pointSize),
                    "hasRGB": stats.hasRGB,
                    "hasHighlight": stats.hasHighlight
                ]
            )
        }

        private func logSceneState(label: String, view: SCNView, force: Bool = false) {
            if !force {
                let now = Date()
                guard now.timeIntervalSince(lastStateProbeDate) >= 1.0 else {
                    return
                }
                lastStateProbeDate = now
            }
            let pointOfViewNode = view.pointOfView
            let observedCameraNode = pointOfViewNode ?? cameraNode
            let cameraPosition = observedCameraNode?.position ?? SCNVector3(0, 0, 0)
            let cameraEuler = observedCameraNode?.eulerAngles ?? SCNVector3(0, 0, 0)
            let cameraScale = observedCameraNode?.scale ?? SCNVector3(1, 1, 1)
            let interactionPosition = interactionRootNode?.position ?? SCNVector3(0, 0, 0)
            let interactionEuler = interactionRootNode?.eulerAngles ?? SCNVector3(0, 0, 0)
            let interactionScale = interactionRootNode?.scale ?? SCNVector3(1, 1, 1)
            let rootEuler = projectionRootNode?.eulerAngles ?? SCNVector3(0, 0, 0)
            let rootScale = projectionRootNode?.scale ?? SCNVector3(1, 1, 1)
            let target = view.defaultCameraController.target
            let matrix = observedCameraNode?.camera?.projectionTransform ?? SCNMatrix4Identity
            let pointOfViewIsCameraNode: Bool
            if let pointOfViewNode, let cameraNode {
                pointOfViewIsCameraNode = pointOfViewNode === cameraNode
            } else {
                pointOfViewIsCameraNode = false
            }
            TAPDiagnostics.depthAnalysis.info("projection state label=\(label, privacy: .public) viewportWidth=\(Double(view.bounds.width), privacy: .public) viewportHeight=\(Double(view.bounds.height), privacy: .public) pointOfViewIsCameraNode=\(pointOfViewIsCameraNode, privacy: .public) cameraX=\(Double(cameraPosition.x), privacy: .public) cameraY=\(Double(cameraPosition.y), privacy: .public) cameraZ=\(Double(cameraPosition.z), privacy: .public) cameraPitch=\(Double(cameraEuler.x), privacy: .public) cameraYaw=\(Double(cameraEuler.y), privacy: .public) cameraRoll=\(Double(cameraEuler.z), privacy: .public) cameraScaleX=\(Double(cameraScale.x), privacy: .public) cameraScaleY=\(Double(cameraScale.y), privacy: .public) cameraScaleZ=\(Double(cameraScale.z), privacy: .public) interactionX=\(Double(interactionPosition.x), privacy: .public) interactionY=\(Double(interactionPosition.y), privacy: .public) interactionZ=\(Double(interactionPosition.z), privacy: .public) interactionPitch=\(Double(interactionEuler.x), privacy: .public) interactionYaw=\(Double(interactionEuler.y), privacy: .public) interactionRoll=\(Double(interactionEuler.z), privacy: .public) interactionScaleX=\(Double(interactionScale.x), privacy: .public) interactionScaleY=\(Double(interactionScale.y), privacy: .public) interactionScaleZ=\(Double(interactionScale.z), privacy: .public) rootPitch=\(Double(rootEuler.x), privacy: .public) rootYaw=\(Double(rootEuler.y), privacy: .public) rootRoll=\(Double(rootEuler.z), privacy: .public) rootScaleX=\(Double(rootScale.x), privacy: .public) rootScaleY=\(Double(rootScale.y), privacy: .public) rootScaleZ=\(Double(rootScale.z), privacy: .public) controllerTargetX=\(Double(target.x), privacy: .public) controllerTargetY=\(Double(target.y), privacy: .public) controllerTargetZ=\(Double(target.z), privacy: .public) projectionM11=\(Double(matrix.m11), privacy: .public) projectionM22=\(Double(matrix.m22), privacy: .public) projectionM31=\(Double(matrix.m31), privacy: .public) projectionM32=\(Double(matrix.m32), privacy: .public) projectionM43=\(Double(matrix.m43), privacy: .public)")
            TAPDepthProjectionProbeReport.append(
                event: "state",
                fields: [
                    "label": label,
                    "viewportWidth": Double(view.bounds.width),
                    "viewportHeight": Double(view.bounds.height),
                    "pointOfViewIsCameraNode": pointOfViewIsCameraNode,
                    "cameraX": Double(cameraPosition.x),
                    "cameraY": Double(cameraPosition.y),
                    "cameraZ": Double(cameraPosition.z),
                    "cameraPitch": Double(cameraEuler.x),
                    "cameraYaw": Double(cameraEuler.y),
                    "cameraRoll": Double(cameraEuler.z),
                    "cameraScaleX": Double(cameraScale.x),
                    "cameraScaleY": Double(cameraScale.y),
                    "cameraScaleZ": Double(cameraScale.z),
                    "interactionX": Double(interactionPosition.x),
                    "interactionY": Double(interactionPosition.y),
                    "interactionZ": Double(interactionPosition.z),
                    "interactionPitch": Double(interactionEuler.x),
                    "interactionYaw": Double(interactionEuler.y),
                    "interactionRoll": Double(interactionEuler.z),
                    "interactionScaleX": Double(interactionScale.x),
                    "interactionScaleY": Double(interactionScale.y),
                    "interactionScaleZ": Double(interactionScale.z),
                    "rootPitch": Double(rootEuler.x),
                    "rootYaw": Double(rootEuler.y),
                    "rootRoll": Double(rootEuler.z),
                    "rootScaleX": Double(rootScale.x),
                    "rootScaleY": Double(rootScale.y),
                    "rootScaleZ": Double(rootScale.z),
                    "controllerTargetX": Double(target.x),
                    "controllerTargetY": Double(target.y),
                    "controllerTargetZ": Double(target.z),
                    "projectionM11": Double(matrix.m11),
                    "projectionM22": Double(matrix.m22),
                    "projectionM31": Double(matrix.m31),
                    "projectionM32": Double(matrix.m32),
                    "projectionM43": Double(matrix.m43)
                ]
            )
        }
        #endif

        private static func signature(
            depthMap: TAPMetricDepthMap,
            image: CGImage?,
            orientation: CGImagePropertyOrientation,
            selectedPlaneRegion: TAPPlaneRegion?,
            highlightColor: UIColor
        ) -> String {
            let count = depthMap.samples.count
            let sampleIndices = [0, count / 2, max(count - 1, 0)].filter { depthMap.samples.indices.contains($0) }
            let sampleSignature = sampleIndices
                .map { String(format: "%.4f", depthMap.samples[$0]) }
                .joined(separator: ":")
            let planeSignature = selectedPlaneRegion.map { region in
                "\(region.seedPixel.x):\(region.seedPixel.y):\(region.sampleCount):\(region.pixelRuns.count)"
            } ?? "no-plane"
            let imageSignature = image.map { "\($0.width)x\($0.height)" } ?? "no-rgb"
            let color = TAPDepthProjectionScenePayloadBuilder.rgbaColor(highlightColor)
            let colorSignature = String(format: "%.3f:%.3f:%.3f:%.3f", color.x, color.y, color.z, color.w)
            return "\(depthMap.width)x\(depthMap.height)-\(count)-\(imageSignature)-\(orientation.rawValue)-\(sampleSignature)-\(planeSignature)-\(colorSignature)"
        }

        private static func data<T>(from values: [T]) -> Data {
            values.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        }

    }
}

#if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
private enum TAPDepthProjectionProbeReport {
    private static let sessionID = UUID().uuidString
    private static let maxFileSize = 4_000_000

    static func append(event: String, fields: [String: Any]) {
        guard let fileURL else {
            return
        }

        var record = fields
        record["event"] = event
        record["sessionID"] = sessionID
        record["time"] = Date().timeIntervalSince1970

        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
            return
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            rotateIfNeeded(fileURL: fileURL, fileManager: fileManager)
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data([0x0A]))
            handle.closeFile()
        } catch {
            return
        }
    }

    static func writeVertexDump(
        fields: [String: Any],
        samples: [[String: Double]]
    ) {
        guard let dumpURL = diagnosticsDirectory?
            .appendingPathComponent("depth-projection-vertices-latest.json") else {
            return
        }

        var object = fields
        object["event"] = "vertexDump"
        object["sessionID"] = sessionID
        object["time"] = Date().timeIntervalSince1970
        object["dumpedSampleCount"] = samples.count
        object["samples"] = samples

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: dumpURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: dumpURL, options: .atomic)
        } catch {
            return
        }
    }

    private static var fileURL: URL? {
        diagnosticsDirectory?
            .appendingPathComponent("depth-projection-probe.jsonl")
    }

    private static var diagnosticsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static func rotateIfNeeded(fileURL: URL, fileManager: FileManager) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxFileSize else {
            return
        }
        try? fileManager.removeItem(at: fileURL)
    }
}
#endif

private struct PointCloudCanvas: View {
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let region: CGRect
    let maxCount: Int
    let parallax: CGFloat

    var body: some View {
        Canvas { context, size in
            // Cloud preview principle:
            // `TAPDepthGeometryProjector` samples the metric depth map and uses
            // camera calibration intrinsics to create local camera-space points.
            // This Canvas draws a compact 2D preview of those points with a
            // small parallax offset and hue based on depth. It is deliberately
            // native SwiftUI/CoreGraphics UI for v1; a richer interactive cloud
            // can later move to Metal or SceneKit.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let displayRegion = clampedRegion()
            let samples = TAPDepthGeometryProjector.sampledPoints(from: depthMap, in: displayRegion, maxCount: maxCount)
            guard !samples.isEmpty else {
                return
            }
            let displayedRegion = TAPImageOrientationMapper.displayedRect(
                fromNative: displayRegion,
                nativeSize: nativeSize,
                orientation: orientation
            )

            let zValues = samples.map(\.point.z)
            let minZ = zValues.min() ?? 0
            let maxZ = zValues.max() ?? minZ + 1
            let zRange = max(maxZ - minZ, 0.001)

            for sample in samples {
                let displayedPoint = self.displayedPoint(fromNative: sample.imagePoint)
                let px = (displayedPoint.x - displayedRegion.minX) / max(displayedRegion.width, 1)
                let py = (displayedPoint.y - displayedRegion.minY) / max(displayedRegion.height, 1)
                let normalizedZ = CGFloat((sample.point.z - minZ) / zRange)
                let x = px * size.width + (0.5 - normalizedZ) * parallax
                let y = py * size.height - (0.5 - normalizedZ) * parallax * 0.52
                let color = TAPDepthHeatmapRenderer.viridisColor(normalized: Float(normalizedZ)).swiftUIColor
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(color))
            }
        }
        .background(Color.black)
    }

    private var nativeSize: CGSize {
        CGSize(width: depthMap.width, height: depthMap.height)
    }

    private func displayedPoint(fromNative point: CGPoint) -> CGPoint {
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: CGRect(x: point.x, y: point.y, width: 0, height: 0),
            nativeSize: nativeSize,
            orientation: orientation
        )
        return CGPoint(x: displayedRect.midX, y: displayedRect.midY)
    }

    private func clampedRegion() -> CGRect {
        let fullRegion = CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
        let clamped = region.intersection(fullRegion)
        if clamped.isNull || clamped.width <= 0 || clamped.height <= 0 {
            return fullRegion
        }
        return clamped
    }
}

private extension TAPRGBAColor {
    var swiftUIColor: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }
}
