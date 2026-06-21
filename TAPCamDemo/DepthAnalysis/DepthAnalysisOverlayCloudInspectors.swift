//
//  DepthAnalysisOverlayCloudInspectors.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import ImageIO
import SwiftUI

struct OverlayInspectorContent: View {
    @Binding var opacity: Double
    let showsInlineHelp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Overlay opacity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Opacity controls the global overlay on the main image. It does not change local region heatmap colors.")
                Slider(value: $opacity, in: 0.2...1.0)
                    .tint(.primary)
                Text("\(Int((opacity * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            if showsInlineHelp {
                InlineHelpText("Opacity controls the global overlay on the main image. It does not change local region heatmap colors.")
            }
        }
    }
}

struct CloudInfoInspectorContent: View {
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selection: CGRect?
    let interactionState: AnalysisInteractionState
    let showsInlineHelp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloud")
                .font(.caption.weight(.semibold))
                .help("This is a local camera-coordinate point cloud preview. It is not cloud storage, cloud compute, or a semantic word cloud.")
            if showsInlineHelp {
                InlineHelpText("This is a local camera-coordinate point cloud preview. It is not cloud storage, cloud compute, or a semantic word cloud.")
            }
            DepthLegendView(stops: [
                TAPDepthLegendStop(position: 0, label: "Near points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 0)),
                TAPDepthLegendStop(position: 1, label: "Far points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 1))
            ])
            if showsInlineHelp {
                InlineHelpText("Point colors map near-to-far depth so the preview stays comparable to the depth legend.")
            }
            Text("\(sampleCount(in: fullRegion)) sampled points")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if showsInlineHelp {
                InlineHelpText("Sampled points are valid depth pixels projected through camera intrinsics for a lightweight preview.")
            }

            if let selection, interactionState.showsRegionInspector {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    PointCloudRegionPreview(
                        depthMap: depthMap,
                        orientation: orientation,
                        selection: selection,
                        previewSize: CGSize(width: 154, height: 154)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(sampleCount(in: selection)) selected points")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if showsInlineHelp {
                            InlineHelpText("Selected points use the same projection, limited to the active rectangular region.")
                        }
                    }
                }
            }
        }
    }

    private var fullRegion: CGRect {
        CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
    }

    private func sampleCount(in region: CGRect) -> Int {
        TAPDepthGeometryProjector.sampledPoints(from: depthMap, in: region, maxCount: 900).count
    }
}
