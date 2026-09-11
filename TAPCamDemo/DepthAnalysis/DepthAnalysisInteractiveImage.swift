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
    let planeRegion: TAPPlaneRegion?
    let partialPlaneGridCells: [TAPPlaneGridCell]
    let planeGridProgress: Double?
    let planeSeedPoint: CGPoint?
    let highlightPalette: AnalysisHighlightPalette

    let onSelectionCleared: () -> Void
    let onPointSelected: (CGPoint) -> Void

    @State private var lastClearDate = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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

                if let planeRegion {
                    PlaneRegionOverlay(
                        gridCells: planeRegion.gridCells,
                        contourPoints: planeRegion.contourPoints,
                        seedPixel: planeRegion.seedPixel,
                        progress: 1,
                        animationID: "final-\(planeRegion.seedPixel.x)-\(planeRegion.seedPixel.y)-\(planeRegion.gridCells.count)",
                        isFinal: true,
                        depthSize: depthSize,
                        orientation: orientation,
                        imageFrame: imageFrame,
                        highlightPalette: highlightPalette,
                        reduceMotion: accessibilityReduceMotion
                    )

                    #if DEBUG
                    let rect = viewRect(for: planeRegion.imageBounds, imageFrame: imageFrame)
                    if rect.width > 8, rect.height > 8 {
                        PlaneRegionBadge(region: planeRegion, highlightPalette: highlightPalette)
                            .position(x: rect.minX + 44, y: max(rect.minY + 16, imageFrame.minY + 16))
                    }
                    #endif
                } else if let planeSeedPoint, !partialPlaneGridCells.isEmpty {
                    PlaneRegionOverlay(
                        gridCells: partialPlaneGridCells,
                        contourPoints: [],
                        seedPixel: planeSeedPoint,
                        progress: planeGridProgress ?? 0.18,
                        animationID: "partial-\(planeSeedPoint.x)-\(planeSeedPoint.y)-\(partialPlaneGridCells.count)",
                        isFinal: false,
                        depthSize: depthSize,
                        orientation: orientation,
                        imageFrame: imageFrame,
                        highlightPalette: highlightPalette,
                        reduceMotion: accessibilityReduceMotion
                    )
                }

                if let planeSeedPoint {
                    let seedRect = viewRect(
                        for: CGRect(x: planeSeedPoint.x - 2, y: planeSeedPoint.y - 2, width: 4, height: 4),
                        imageFrame: imageFrame
                    )
                    PlaneSeedMarker(highlightPalette: highlightPalette)
                        .position(x: seedRect.midX, y: seedRect.midY)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        lastClearDate = Date()
                        onSelectionCleared()
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1)
                    .onEnded { value in
                        guard Date().timeIntervalSince(lastClearDate) > 0.25,
                              let depthPoint = depthPoint(for: value.location, imageFrame: imageFrame) else {
                            return
                        }
                        onPointSelected(depthPoint)
                    }
            )
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

    private func viewRect(for depthRect: CGRect, imageFrame: CGRect) -> CGRect {
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
    let gridCells: [TAPPlaneGridCell]
    let contourPoints: [CGPoint]
    let seedPixel: CGPoint
    let progress: Double
    let animationID: String
    let isFinal: Bool
    let depthSize: CGSize
    let orientation: CGImagePropertyOrientation
    let imageFrame: CGRect
    let highlightPalette: AnalysisHighlightPalette
    let reduceMotion: Bool

    @State private var displayedProgress: Double = 0

    var body: some View {
        Canvas { context, _ in
            for cell in gridCells {
                let visibility = cellVisibility(cell)
                guard visibility > 0 else {
                    continue
                }
                let rect = viewRect(for: cell.imageBounds).insetBy(dx: 0.8, dy: 0.8)
                context.fill(Path(rect), with: .color(cellFillColor(cell).opacity(visibility)))
                context.stroke(Path(rect), with: .color(cellEdgeColor(cell).opacity(visibility)), lineWidth: 1.15)
            }

            let stride = max(contourPoints.count / 2_500, 1)
            for (index, point) in contourPoints.enumerated() where index.isMultiple(of: stride) {
                let rect = viewRect(for: CGRect(x: point.x, y: point.y, width: 1, height: 1))
                    .insetBy(dx: -1.2, dy: -1.2)
                context.fill(Path(ellipseIn: rect), with: .color(edgeColor))
            }
        }
        .onAppear {
            resetDisplayedProgress()
        }
        .onChange(of: animationID) { _, _ in
            resetDisplayedProgress()
        }
        .onChange(of: progress) { _, newValue in
            animateDisplayedProgress(to: newValue)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(isFinal ? "Selected plane region" : "Growing plane region")
    }

    private func cellFillColor(_ cell: TAPPlaneGridCell) -> Color {
        highlightPalette.gridFill(confidence: cell.confidence)
    }

    private func cellEdgeColor(_ cell: TAPPlaneGridCell) -> Color {
        highlightPalette.gridStroke(confidence: cell.confidence)
    }

    private var edgeColor: Color {
        highlightPalette.contour
    }

    private func resetDisplayedProgress() {
        if isFinal || reduceMotion {
            displayedProgress = progress
        } else {
            displayedProgress = 0
            animateDisplayedProgress(to: progress)
        }
    }

    private func animateDisplayedProgress(to value: Double) {
        let clamped = min(max(value, 0), 1)
        if isFinal || reduceMotion {
            displayedProgress = clamped
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                displayedProgress = clamped
            }
        }
    }

    private func cellVisibility(_ cell: TAPPlaneGridCell) -> Double {
        // The completed result owns the full grid, independently of a new
        // overlay's animation state or whether its appearance callback ran.
        guard !isFinal, !reduceMotion else {
            return 1
        }
        let normalizedDistance = cellDistanceFromSeed(cell)
        let reveal = (displayedProgress - normalizedDistance) / 0.18
        return min(max(reveal, 0), 1)
    }

    private func cellDistanceFromSeed(_ cell: TAPPlaneGridCell) -> Double {
        let center = CGPoint(x: cell.imageBounds.midX, y: cell.imageBounds.midY)
        let dx = center.x - seedPixel.x
        let dy = center.y - seedPixel.y
        let distance = sqrt(dx * dx + dy * dy)
        let maxDistance = max(
            sqrt(depthSize.width * depthSize.width + depthSize.height * depthSize.height),
            1
        )
        return min(max(Double(distance / maxDistance), 0), 1)
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
    let highlightPalette: AnalysisHighlightPalette

    var body: some View {
        Text(region.confidence, format: .percent.precision(.fractionLength(0)))
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(highlightPalette.badgeForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(highlightPalette.badgeBackground, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel("Selected plane region \(Int((region.confidence * 100).rounded())) percent confidence")
    }
}

private struct PlaneSeedMarker: View {
    let highlightPalette: AnalysisHighlightPalette

    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.78), lineWidth: 5)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(highlightPalette.seedStroke, lineWidth: 3)
                .frame(width: 18, height: 18)
            Circle()
                .fill(highlightPalette.seedFill)
                .frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.32), radius: 4, y: 2)
        .accessibilityLabel("Plane seed point")
    }
}
