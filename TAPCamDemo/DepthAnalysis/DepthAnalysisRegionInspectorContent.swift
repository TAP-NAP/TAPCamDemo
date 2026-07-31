//
//  DepthAnalysisRegionInspectorContent.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

struct RegionInspectorContent: View {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    let selection: CGRect?
    let interactionState: AnalysisInteractionState
    let stats: TAPDepthRegionStats?
    let planeEstimate: TAPPlaneEstimate?
    let regionHeatmap: TAPDepthHeatmapVisualization?
    let heatmapErrorMessage: DepthAnalysisInspectorErrorMessage
    let showsInlineHelp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Region")
                    .font(.caption.weight(.semibold))
                    .help("Drag on the image to choose a region. The region heatmap uses only the selected valid depth samples to recalculate its color range.")
                Spacer(minLength: 8)
                Text(LocalizedStringKey(stateText))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if showsInlineHelp {
                InlineHelpText("Drag on the image to choose a region. The region heatmap uses only the selected valid depth samples to recalculate its color range.")
            }

            if interactionState == .drawingSelection {
                Label("Selecting region...", systemImage: "hand.draw")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Release your drag to finish the selection and calculate local depth statistics.")
                }
            } else if let selection, interactionState.showsRegionInspector {
                if let regionHeatmap {
                    HStack(alignment: .top, spacing: 12) {
                        AnalysisLoupe(
                            image: image,
                            overlayImage: regionHeatmap.image,
                            overlayOpacity: 0.92,
                            orientation: orientation,
                            depthSize: depthSize,
                            selection: selection,
                            title: "Local heatmap",
                            previewSize: CGSize(width: 154, height: 154)
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(localRangeText(regionHeatmap))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if showsInlineHelp {
                                InlineHelpText("Local range is recalculated from this selection, so it can show subtle depth changes inside the crop.")
                            }
                            DepthLegendView(stops: regionHeatmap.legendStops)
                        }
                    }
                } else {
                    Label(heatmapErrorMessage.text, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if showsInlineHelp {
                        InlineHelpText("The local heatmap needs enough finite positive depth pixels inside the selected region.")
                    }
                }

                regionSummary
            } else {
                Label("No region selected.", systemImage: "viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Select a rectangular area on the image to inspect local depth, range, and plane fit values.")
                }
            }
        }
    }

    @ViewBuilder
    private var regionSummary: some View {
        if let stats {
            let presentation = DepthRegionStatsPresentation(stats: stats)
            VStack(alignment: .leading, spacing: 7) {
                DepthMetricRow(
                    title: "Median depth",
                    value: presentation.medianDepthText,
                    explanation: "Sort the selected valid depth samples from near to far; this is the value in the middle.",
                    showsHelp: showsInlineHelp
                )
                DepthMetricRow(
                    title: "Range",
                    value: presentation.rangeText,
                    explanation: "The selected region's nearest and farthest valid depth samples.",
                    showsHelp: showsInlineHelp
                )
                DepthMetricRow(
                    title: "Valid samples",
                    value: presentation.validSamplesText,
                    explanation: "How many selected pixels contain finite positive depth.",
                    showsHelp: showsInlineHelp
                )

                if let planeEstimate {
                    DepthMetricRow(
                        title: "Plane inliers",
                        value: "\(Int((planeEstimate.inlierRatio * 100).rounded()))%",
                        explanation: "The share of selected depth points that match the fitted local plane.",
                        showsHelp: showsInlineHelp
                    )
                }
            }
        }
    }

    private var stateText: String {
        switch interactionState {
        case .idle:
            "No local region"
        case .drawingSelection:
            "Selecting"
        case .regionSelected:
            "Selected"
        }
    }

    private func localRangeText(_ heatmap: TAPDepthHeatmapVisualization) -> String {
        String(format: "Local range %.2f...%.2f m", heatmap.rangeMeters.lowerBound, heatmap.rangeMeters.upperBound)
    }
}

private struct AnalysisLoupe: View {
    let image: CGImage
    let overlayImage: CGImage?
    let overlayOpacity: Double
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    let selection: CGRect
    var title = "Loupe"
    var previewSize = CGSize(width: 136, height: 136)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))

            ZStack {
                Color.black
                magnifiedImage(image, opacity: 1)

                if let overlayImage {
                    magnifiedImage(overlayImage, opacity: overlayOpacity)
                }
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
        }
        .padding(8)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Selected area loupe")
    }

    private func magnifiedImage(_ image: CGImage, opacity: Double) -> some View {
        GeometryReader { proxy in
            let normalizedCenter = normalizedSelectionCenter()
            let zoom = zoomScale()

            Image(decorative: image, scale: 1, orientation: orientation.swiftUIImageOrientation)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(
                    x: (0.5 - normalizedCenter.x) * proxy.size.width * zoom,
                    y: (0.5 - normalizedCenter.y) * proxy.size.height * zoom
                )
                .opacity(opacity)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }

    private func normalizedSelectionCenter() -> CGPoint {
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        guard displayedDepthSize.width > 0, displayedDepthSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: selection,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGPoint(
            x: min(max(displayedRect.midX / displayedDepthSize.width, 0), 1),
            y: min(max(displayedRect.midY / displayedDepthSize.height, 0), 1)
        )
    }

    private func zoomScale() -> CGFloat {
        guard selection.width > 0, selection.height > 0 else {
            return 2.4
        }

        let widthRatio = depthSize.width / selection.width
        let heightRatio = depthSize.height / selection.height
        return min(max(min(widthRatio, heightRatio), 2.2), 5.2)
    }
}
