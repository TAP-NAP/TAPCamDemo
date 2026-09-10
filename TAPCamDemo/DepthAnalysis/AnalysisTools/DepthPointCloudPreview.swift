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
    var enablesMotionParallax = false

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
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
    static let minimumScale: Float = 0.1
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
        relativePitch: Double,
        relativeRoll: Double
    ) -> SCNVector3 {
        SCNVector3(
            Float(normalizedAngleDelta(relativePitch)) * motionParallaxPitchScale,
            Float(normalizedAngleDelta(relativeRoll)) * motionParallaxRollScale,
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

nonisolated struct TAPDepthProjectionPayloadBuildRequest: @unchecked Sendable {
    let image: CGImage?
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selectedPlaneRegion: TAPPlaneRegion?
    let highlightColor: UIColor
}

nonisolated struct TAPDepthProjectionScenePayloadData: Sendable {
    let cameraModel: TAPDepthProjectionCameraModel
    let targetDepth: Float
    let baseVertices: [SIMD3<Float>]
    let baseColors: [SIMD4<Float>]
    let highlightVertices: [SIMD3<Float>]
    let highlightColor: SIMD4<Float>
    let pointSize: CGFloat
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

    @concurrent
    static func makePayloadDataAsync(
        request: TAPDepthProjectionPayloadBuildRequest
    ) async -> TAPDepthProjectionScenePayloadData? {
        makePayloadData(request: request)
    }

    static func makePayloadData(
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
        let renderableSamples = TAPDepthProjectionSampleFilter.renderableSamples(from: samples)
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
        return TAPDepthProjectionScenePayloadData(
            cameraModel: projectionFrame.cameraModel,
            targetDepth: targetDepth,
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
}

struct DepthProjectionSceneView: UIViewRepresentable {
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
        view.onLayout = { [weak coordinator = context.coordinator] size in
            coordinator?.syncProjection(viewportSize: size)
        }
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

    static func dismantleUIView(_ view: ProjectionSCNView, coordinator: Coordinator) {
        coordinator.dismantle()
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
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private struct HighlightSelection: Equatable {
            let pixelRuns: [TAPPlanePixelRun]
            let color: SIMD4<Float>
        }

        private var currentHighlightSelection: HighlightSelection?
        private var reduceMotion = false
        private(set) var payloadBuildTask: Task<Void, Never>?
        private let payloadBuilder: @Sendable (TAPDepthProjectionPayloadBuildRequest) async -> TAPDepthProjectionScenePayloadData?
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

        init(
            payloadBuilder: @escaping @Sendable (TAPDepthProjectionPayloadBuildRequest) async -> TAPDepthProjectionScenePayloadData? = TAPDepthProjectionScenePayloadBuilder.makePayloadDataAsync
        ) {
            self.payloadBuilder = payloadBuilder
            super.init()
        }

        deinit {
            payloadBuildTask?.cancel()
            motionManager.stopDeviceMotionUpdates()
        }

        fileprivate func dismantle() {
            payloadBuildTask?.cancel()
            payloadBuildTask = nil
            syncMotionParallax(enabled: false)
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
            case .changed:
                let translation = gesture.translation(in: view)
                let width = max(view.bounds.width, 1)
                let height = max(view.bounds.height, 1)
                let yaw = panStartEulerAngles.y + Float(translation.x / width) * .pi
                let pitch = panStartEulerAngles.x + Float(translation.y / height) * .pi * 0.72
                interactionRootNode.eulerAngles.x = min(max(pitch, -.pi / 2), .pi / 2)
                interactionRootNode.eulerAngles.y = yaw
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
            case .changed:
                let nextScale = TAPDepthProjectionInteractionPolicy.clampedScale(
                    pinchStartScale * Float(gesture.scale)
                )
                interactionRootNode.scale = SCNVector3(nextScale, nextScale, nextScale)
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
            case .changed:
                interactionRootNode.eulerAngles.z = TAPDepthProjectionInteractionPolicy.rollAngle(
                    startAngle: rollStartAngle,
                    gestureRotation: gesture.rotation
                )
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
            if self.reduceMotion != reduceMotion {
                self.reduceMotion = reduceMotion
                updateHighlightAnimation()
            }
            // The owning photo slot recreates this view only for a new input.
            let selection = HighlightSelection(
                pixelRuns: selectedPlaneRegion?.pixelRuns ?? [],
                color: TAPDepthProjectionScenePayloadBuilder.rgbaColor(highlightColor)
            )
            if currentHighlightSelection != selection {
                currentHighlightSelection = selection
                configureSceneAsync(
                    view: view,
                    image: image,
                    depthMap: depthMap,
                    orientation: orientation,
                    selectedPlaneRegion: selectedPlaneRegion,
                    highlightColor: highlightColor
                )
            }
            syncMotionParallax(enabled: enablesMotionParallax)
            syncProjection(viewportSize: view.bounds.size)
        }

        func syncProjection(viewportSize: CGSize) {
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
        }

        static func isValidViewportSize(_ size: CGSize) -> Bool {
            size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
        }

        private func configureSceneAsync(
            view: SCNView,
            image: CGImage?,
            depthMap: TAPMetricDepthMap,
            orientation: CGImagePropertyOrientation,
            selectedPlaneRegion: TAPPlaneRegion?,
            highlightColor: UIColor
        ) {
            let request = TAPDepthProjectionPayloadBuildRequest(
                image: image,
                depthMap: depthMap,
                orientation: orientation,
                selectedPlaneRegion: selectedPlaneRegion,
                highlightColor: highlightColor
            )
            payloadBuildTask?.cancel()
            payloadBuildTask = Task(priority: .userInitiated) { @MainActor [weak self, weak view, payloadBuilder] in
                let payloadData = await payloadBuilder(request)
                guard !Task.isCancelled,
                      let self,
                      let view else {
                    return
                }
                self.payloadBuildTask = nil
                self.configureScene(
                    view: view,
                    payloadData: payloadData
                )
            }
        }

        @MainActor
        private func configureScene(
            view: SCNView,
            payloadData: TAPDepthProjectionScenePayloadData?
        ) {
            guard let payloadData else {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.depthAnalysis.warning("projection payload missing label=payloadMissing")
                #endif
                return
            }
            if interactionRootNode != nil {
                updateHighlight(payloadData: payloadData)
                return
            }
            let scene = SCNScene()
            currentCameraModel = payloadData.cameraModel
            let targetDepth = payloadData.targetDepth
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
            if let geometry = Self.makePointGeometry(
                vertices: payloadData.baseVertices,
                colors: payloadData.baseColors,
                pointSize: payloadData.pointSize
               ) {
                let node = SCNNode(geometry: geometry)
                node.name = "DepthProjectionModel"
                geometryRootNode.addChildNode(node)
            }
            let highlightNode = SCNNode()
            highlightNode.name = "SelectedPlaneProjection"
            geometryRootNode.addChildNode(highlightNode)
            self.highlightNode = highlightNode
            updateHighlight(payloadData: payloadData)

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
            syncProjection(viewportSize: view.bounds.size)

            // TODO: keep this renderer boundary replaceable with Metal when
            // point count, splat quality, mesh rendering, or performance needs
            // outgrow SceneKit.
        }

        private func updateHighlight(payloadData: TAPDepthProjectionScenePayloadData) {
            highlightNode?.geometry = Self.makeHighlightGeometry(
                vertices: payloadData.highlightVertices,
                pointSize: payloadData.pointSize * 1.85,
                color: payloadData.highlightColor
            )
            updateHighlightAnimation()
        }

        private func updateHighlightAnimation() {
            guard let highlightNode else {
                return
            }
            highlightNode.removeAllActions()
            guard highlightNode.geometry != nil else {
                return
            }
            if reduceMotion {
                highlightNode.opacity = 0.88
            } else {
                highlightNode.opacity = 0.55
                highlightNode.runAction(
                    .repeatForever(
                        .sequence([
                            .fadeOpacity(to: 1.0, duration: 0.72),
                            .fadeOpacity(to: 0.42, duration: 0.72)
                        ])
                    )
                )
            }
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
            motionManager.startDeviceMotionUpdates(
                using: .xArbitraryZVertical,
                to: .main
            ) { [weak self] motion, _ in
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
                let relativeTilt = attitude.relativeTilt(to: baseline)
                eulerAngles = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
                    relativePitch: relativeTilt.pitch,
                    relativeRoll: relativeTilt.roll
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
            private let value: CMAttitude

            init(motion: CMDeviceMotion) {
                value = Self.copy(motion.attitude)
            }

            func relativeTilt(to baseline: MotionParallaxAttitude) -> MotionParallaxTilt {
                let relativeValue = Self.copy(value)
                relativeValue.multiply(byInverseOf: baseline.value)
                return Self.shortestArcTilt(from: relativeValue.quaternion)
            }

            private static func copy(_ attitude: CMAttitude) -> CMAttitude {
                guard let copiedAttitude = attitude.copy() as? CMAttitude else {
                    preconditionFailure("CMAttitude copy returned an unexpected type")
                }
                return copiedAttitude
            }

            private static func shortestArcTilt(from quaternion: CMQuaternion) -> MotionParallaxTilt {
                let magnitude = sqrt(
                    quaternion.x * quaternion.x
                        + quaternion.y * quaternion.y
                        + quaternion.z * quaternion.z
                        + quaternion.w * quaternion.w
                )
                guard magnitude.isFinite, magnitude > 0 else {
                    return MotionParallaxTilt(pitch: 0, roll: 0)
                }

                let direction = quaternion.w < 0 ? -1.0 : 1.0
                let x = quaternion.x / magnitude * direction
                let y = quaternion.y / magnitude * direction
                let z = quaternion.z / magnitude * direction
                let w = quaternion.w / magnitude * direction
                let vectorMagnitude = sqrt(x * x + y * y + z * z)
                let rotationScale: Double
                if vectorMagnitude < 0.000_001 {
                    rotationScale = 2
                } else {
                    rotationScale = 2 * atan2(vectorMagnitude, w) / vectorMagnitude
                }

                return MotionParallaxTilt(
                    pitch: x * rotationScale,
                    roll: y * rotationScale
                )
            }
        }

        private struct MotionParallaxTilt {
            let pitch: Double
            let roll: Double
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

        private static func data<T>(from values: [T]) -> Data {
            values.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        }

    }
}
