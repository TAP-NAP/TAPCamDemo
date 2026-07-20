//
//  DepthAnalysisLegendInspectorContent.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import SwiftUI

struct LegendInspectorContent: View {
    let viewMode: DepthAnalysisViewMode
    let heatmap: TAPDepthHeatmapVisualization
    let validMask: TAPDepthMaskVisualization
    let showsInlineHelp: Bool

    var body: some View {
        switch viewMode {
        case .rgb:
            VStack(alignment: .leading, spacing: 6) {
                Text("No generated legend.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText(viewMode.legendDescription)
                }
            }
        case .heatmap, .planes:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Global depth legend")
                        .font(.caption.weight(.semibold))
                        .help(viewMode.legendDescription)
                    Spacer(minLength: 8)
                    Text(globalHeatmapRangeText(heatmap))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if showsInlineHelp {
                    InlineHelpText(viewMode.legendDescription)
                }
                DepthLegendView(stops: heatmap.legendStops)
            }
        case .mask:
            VStack(alignment: .leading, spacing: 8) {
                Text("Mask legend")
                    .font(.caption.weight(.semibold))
                    .help(viewMode.legendDescription)
                if showsInlineHelp {
                    InlineHelpText(viewMode.legendDescription)
                }
                SwatchLegendView(stops: validMask.legendStops)
                Text("\(Int((validMask.validRatio * 100).rounded()))% valid depth coverage")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Coverage is the share of depth pixels that can contribute to statistics, plane fitting, and point projection.")
                }
            }
        case .pointCloud:
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud legend")
                    .font(.caption.weight(.semibold))
                    .help(viewMode.legendDescription)
                if showsInlineHelp {
                    InlineHelpText(viewMode.legendDescription)
                }
                DepthLegendView(stops: cloudLegendStops)
            }
        }
    }

    private func globalHeatmapRangeText(_ heatmap: TAPDepthHeatmapVisualization) -> String {
        String(format: "%.2f...%.2f m", heatmap.rangeMeters.lowerBound, heatmap.rangeMeters.upperBound)
    }

    private var cloudLegendStops: [TAPDepthLegendStop] {
        [
            TAPDepthLegendStop(position: 0, label: "Near points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 0)),
            TAPDepthLegendStop(position: 1, label: "Far points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 1))
        ]
    }
}
