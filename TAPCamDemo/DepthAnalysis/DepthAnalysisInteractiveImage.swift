//
//  DepthAnalysisInteractiveImage.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import ImageIO
import SwiftUI

/// Renders the analysis image and translates display-space gestures back into
/// native depth-map coordinates.
struct InteractiveDepthImage: View {
    let image: CGImage
    let overlayImage: CGImage?
    let overlayOpacity: Double
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    @Binding var selection: CGRect?
    let interactionState: AnalysisInteractionState
    let planeOverlays: [TAPDetectedPlane]
    let planeRegion: TAPPlaneRegion?
    let planeSeedPoint: CGPoint?
    let isSelectionEnabled: Bool
    let isPointSelectionEnabled: Bool
    let onSelectionBegan: (CGRect) -> Void
    let onSelectionChanged: (CGRect) -> Void
    let onSelectionEnded: (CGRect) -> Void
    let onSelectionCleared: () -> Void
    let onPointSelected: (CGPoint) -> Void

    @State private var dragStart: CGPoint?
    @State private var lastClearDate = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
            // ImageIO returns raw pixels and a separate EXIF/CGImage orientation.
            // SwiftUI renders the pixels with that orientation applied, so the
            // fitted display rect must use the orientation-adjusted dimensions.
            let imageSize = TAPImageOrientationMapper.displayedSize(
                nativeSize: CGSize(width: image.width, height: image.height),
                orientation: orientation
            )
            let imageFrame = fittedRect(imageSize: imageSize, containerSize: proxy.size)

            ZStack {
                Color.black

                Image(decorative: image, scale: 1, orientation: orientation.swiftUIImageOrientation)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                if let overlayImage {
                    Image(decorative: overlayImage, scale: 1, orientation: orientation.swiftUIImageOrientation)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                        .opacity(overlayOpacity)
                }

                ForEach(planeOverlays) { plane in
                    let rect = viewRect(for: plane.imageBounds, imageFrame: imageFrame)
                    if rect.width > 8, rect.height > 8 {
                        PlaneOverlayMarker(plane: plane)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }

                if let planeRegion {
                    PlaneRegionOverlay(
                        region: planeRegion,
                        depthSize: depthSize,
                        orientation: orientation,
                        imageFrame: imageFrame
                    )

                    let rect = viewRect(for: planeRegion.imageBounds, imageFrame: imageFrame)
                    if rect.width > 8, rect.height > 8 {
                        PlaneRegionBadge(region: planeRegion)
                            .position(x: rect.minX + 44, y: max(rect.minY + 16, imageFrame.minY + 16))
                    }
                }

                if let planeSeedPoint {
                    let seedRect = viewRect(
                        for: CGRect(x: planeSeedPoint.x - 2, y: planeSeedPoint.y - 2, width: 4, height: 4),
                        imageFrame: imageFrame
                    )
                    PlaneSeedMarker()
                        .position(x: seedRect.midX, y: seedRect.midY)
                }

                if isSelectionEnabled, let selection {
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
                        guard isSelectionEnabled else {
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
                        guard isSelectionEnabled else {
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
                        dragStart = nil
                        lastClearDate = Date()
                        onSelectionCleared()
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1)
                    .onEnded { value in
                        guard isPointSelectionEnabled,
                              Date().timeIntervalSince(lastClearDate) > 0.25,
                              let depthPoint = depthPoint(for: value.location, imageFrame: imageFrame) else {
                            return
                        }
                        onPointSelected(depthPoint)
                    }
            )
        }
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

        // The user drags in oriented display coordinates. Plane fitting and
        // depth statistics operate on the native depth-map pixel grid, so we
        // first scale into the displayed depth plane and then invert the
        // orientation transform.
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedX = (clamped.minX - imageFrame.minX) / imageFrame.width * displayedDepthSize.width
        let displayedY = (clamped.minY - imageFrame.minY) / imageFrame.height * displayedDepthSize.height
        let displayedWidth = clamped.width / imageFrame.width * displayedDepthSize.width
        let displayedHeight = clamped.height / imageFrame.height * displayedDepthSize.height
        let displayedRect = CGRect(
            x: displayedX,
            y: displayedY,
            width: max(displayedWidth, 1),
            height: max(displayedHeight, 1)
        )
        return TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedRect,
            nativeSize: depthSize,
            orientation: orientation
        )
    }

    private func viewRect(for depthRect: CGRect, imageFrame: CGRect) -> CGRect {
        guard depthSize.width > 0, depthSize.height > 0 else {
            return .zero
        }

        // Selection state is stored as a native depth-map rect because that is
        // what `TAPDepthGeometryProjector` and `TAPPlaneEstimator` consume. This
        // converts it back into oriented display coordinates for the overlay.
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: depthRect,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGRect(
            x: imageFrame.minX + displayedRect.minX / displayedDepthSize.width * imageFrame.width,
            y: imageFrame.minY + displayedRect.minY / displayedDepthSize.height * imageFrame.height,
            width: displayedRect.width / displayedDepthSize.width * imageFrame.width,
            height: displayedRect.height / displayedDepthSize.height * imageFrame.height
        )
    }

    private func depthPoint(for location: CGPoint, imageFrame: CGRect) -> CGPoint? {
        guard imageFrame.contains(location), imageFrame.width > 0, imageFrame.height > 0 else {
            return nil
        }

        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedPointRect = CGRect(
            x: (location.x - imageFrame.minX) / imageFrame.width * displayedDepthSize.width,
            y: (location.y - imageFrame.minY) / imageFrame.height * displayedDepthSize.height,
            width: 1,
            height: 1
        )
        let nativeRect = TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedPointRect,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGPoint(
            x: min(max(nativeRect.midX, 0), max(depthSize.width - 1, 0)),
            y: min(max(nativeRect.midY, 0), max(depthSize.height - 1, 0))
        )
    }
}

private struct PlaneRegionOverlay: View {
    let region: TAPPlaneRegion
    let depthSize: CGSize
    let orientation: CGImagePropertyOrientation
    let imageFrame: CGRect

    var body: some View {
        Canvas { context, _ in
            for cell in region.gridCells {
                let rect = viewRect(for: cell.imageBounds).insetBy(dx: 0.8, dy: 0.8)
                context.fill(Path(rect), with: .color(cellFillColor(cell)))
                context.stroke(Path(rect), with: .color(cellEdgeColor(cell)), lineWidth: 1.15)
            }

            let stride = max(region.contourPoints.count / 2_500, 1)
            for (index, point) in region.contourPoints.enumerated() where index.isMultiple(of: stride) {
                let rect = viewRect(for: CGRect(x: point.x, y: point.y, width: 1, height: 1))
                    .insetBy(dx: -1.2, dy: -1.2)
                context.fill(Path(ellipseIn: rect), with: .color(edgeColor))
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Selected plane region")
    }

    private func cellFillColor(_ cell: TAPPlaneGridCell) -> Color {
        let confidence = min(max(cell.confidence, 0), 1)
        return Color(
            red: 1.0 - 0.26 * confidence,
            green: 0.58 + 0.38 * confidence,
            blue: 0.22 + 0.14 * confidence
        )
        .opacity(0.16 + 0.18 * confidence)
    }

    private func cellEdgeColor(_ cell: TAPPlaneGridCell) -> Color {
        let confidence = min(max(cell.confidence, 0), 1)
        return Color(
            red: 1.0 - 0.30 * confidence,
            green: 0.72 + 0.28 * confidence,
            blue: 0.24 + 0.16 * confidence
        )
        .opacity(0.42 + 0.42 * confidence)
    }

    private var edgeColor: Color {
        Color(red: 0.78, green: 1.0, blue: 0.42).opacity(0.92)
    }

    private func viewRect(for depthRect: CGRect) -> CGRect {
        guard depthSize.width > 0, depthSize.height > 0 else {
            return .zero
        }

        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: depthRect,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGRect(
            x: imageFrame.minX + displayedRect.minX / displayedDepthSize.width * imageFrame.width,
            y: imageFrame.minY + displayedRect.minY / displayedDepthSize.height * imageFrame.height,
            width: max(displayedRect.width / displayedDepthSize.width * imageFrame.width, 1),
            height: max(displayedRect.height / displayedDepthSize.height * imageFrame.height, 1)
        )
    }
}

private struct PlaneRegionBadge: View {
    let region: TAPPlaneRegion

    var body: some View {
        Text("\(Int((region.confidence * 100).rounded()))%")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(red: 0.78, green: 1.0, blue: 0.42), in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel("Selected plane region \(Int((region.confidence * 100).rounded())) percent confidence")
    }
}

private struct PlaneSeedMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.78), lineWidth: 5)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(Color(red: 0.78, green: 1.0, blue: 0.42), lineWidth: 3)
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color(red: 0.78, green: 1.0, blue: 0.42))
                .frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.32), radius: 4, y: 2)
        .accessibilityLabel("Plane seed point")
    }
}

private struct PlaneOverlayMarker: View {
    let plane: TAPDetectedPlane

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(markerColor, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(markerColor.opacity(0.13))
                )

            Text("\(Int((plane.confidence * 100).rounded()))%")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(markerColor, in: Capsule())
                .padding(5)
        }
        .accessibilityLabel("Detected plane \(Int((plane.confidence * 100).rounded())) percent confidence")
    }

    private var markerColor: Color {
        if plane.confidence >= 0.82 {
            return Color(red: 0.70, green: 0.95, blue: 0.30)
        }
        if plane.confidence >= 0.68 {
            return Color(red: 0.98, green: 0.78, blue: 0.22)
        }
        return Color(red: 1.0, green: 0.48, blue: 0.28)
    }
}
