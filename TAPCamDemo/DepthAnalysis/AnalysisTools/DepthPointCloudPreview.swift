//
//  DepthPointCloudPreview.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import ImageIO
import SwiftUI

/// Lightweight SwiftUI preview for camera-coordinate depth points.
///
/// The point cloud preview depends on the same projection math as plane
/// fitting, but it stays a visualization tool: it does not create a mesh,
/// stabilize points in world coordinates, or infer hidden geometry.
struct PointCloudPreview: View {
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    @Binding var selection: CGRect?
    let interactionState: AnalysisInteractionState
    let onSelectionBegan: (CGRect) -> Void
    let onSelectionChanged: (CGRect) -> Void
    let onSelectionEnded: (CGRect) -> Void
    let onSelectionCleared: () -> Void

    @State private var dragStart: CGPoint?

    private var fullRegion: CGRect {
        CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
    }

    var body: some View {
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

                if let selection {
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
