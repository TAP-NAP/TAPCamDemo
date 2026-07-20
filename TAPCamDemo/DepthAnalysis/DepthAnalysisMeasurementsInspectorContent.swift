//
//  DepthAnalysisMeasurementsInspectorContent.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import SwiftUI

struct MeasurementsInspectorContent: View {
    let stats: TAPDepthRegionStats?
    let planeEstimate: TAPPlaneEstimate?
    let interactionState: AnalysisInteractionState
    let showsInlineHelp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats {
                let presentation = DepthRegionStatsPresentation(stats: stats)
                DepthMetricRow(
                    title: "Median depth",
                    value: presentation.medianDepthText,
                    explanation: "Sort the selected valid depth samples from near to far; this is the value in the middle. It is less sensitive to isolated noisy pixels than an average.",
                    showsHelp: showsInlineHelp
                )
                DepthMetricRow(
                    title: "Range",
                    value: presentation.rangeText,
                    explanation: "The nearest and farthest valid metric depth samples found inside the selection.",
                    showsHelp: showsInlineHelp
                )
                DepthMetricRow(
                    title: "Valid samples",
                    value: presentation.validSamplesText,
                    explanation: "How many pixels in the selected region contain finite positive depth. Plane fitting and point projection ignore invalid samples.",
                    showsHelp: showsInlineHelp
                )
            } else {
                Text(interactionState == .drawingSelection ? "Selecting region..." : "No region selected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Drag on the image to choose a depth region. Measurements update from the finite positive depth samples inside that selection.")
                }
            }

            if let plane = planeEstimate {
                Divider()
                DepthMetricRow(
                    title: "Plane residual",
                    value: String(format: "%.3f m", plane.averageResidualMeters),
                    explanation: "Average distance from inlier points to the fitted plane. Smaller values usually mean the selected surface is flatter.",
                    showsHelp: showsInlineHelp
                )
                DepthMetricRow(
                    title: "Plane inliers",
                    value: "\(Int((plane.inlierRatio * 100).rounded()))%",
                    explanation: "The share of sampled points close enough to the fitted plane to count as inliers.",
                    showsHelp: showsInlineHelp
                )
                DepthMetricRow(
                    title: "Plane normal",
                    value: String(format: "[%.2f, %.2f, %.2f]", plane.normal.x, plane.normal.y, plane.normal.z),
                    explanation: "The fitted plane direction in local camera coordinates. It is useful for comparing orientation, not for world tracking.",
                    showsHelp: showsInlineHelp
                )
            } else {
                Divider()
                Text("No local plane estimate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("A local plane estimate appears after the selected region has enough valid depth points for a stable fit.")
                }
            }
        }
    }
}
