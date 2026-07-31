//
//  DepthAnalysisPlaneFilterInspectorContent.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation
import SwiftUI

struct PlaneFilterInspectorContent: View {
    let depthMap: TAPMetricDepthMap
    let depthAccuracy: String
    let depthQuality: String
    let selectedPlaneRegion: TAPPlaneRegion?
    let planeSeedPoint: CGPoint?
    let isDetecting: Bool
    let errorMessage: DepthAnalysisInspectorErrorMessage?
    @Binding var strictness: Double
    let showsInlineHelp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Plane region")
                    .font(.caption.weight(.semibold))
                    .help("Tap a surface point in Planes view. The analyzer grows a connected camera-coordinate plane region from that seed.")
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if showsInlineHelp {
                InlineHelpText("Tap a surface point in Planes view. The analyzer grows a connected camera-coordinate plane region from that seed.")
            }

            HStack(spacing: 8) {
                Text("Strictness")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Higher strictness keeps only pixels that fit the seed plane more tightly.")
                Slider(value: $strictness, in: 0.35...0.95)
                    .tint(.primary)
                Text("\(Int((strictness * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            if showsInlineHelp {
                InlineHelpText("Higher strictness keeps only pixels that fit the seed plane more tightly.")
            }

            if isDetecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Detecting plane region...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if showsInlineHelp {
                    InlineHelpText("You can tap another surface point while this runs; the analyzer keeps the newest point.")
                }
            } else if let selectedPlaneRegion {
                planeRegionMetrics(selectedPlaneRegion)
            } else if let errorMessage {
                Label(errorMessage.text, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Try a nearby textured surface point with valid depth if the seed cannot grow a stable plane.")
                }
            } else if depthMap.calibration == nil {
                Label("Camera calibration missing.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Plane fitting needs camera intrinsics to project depth pixels into local camera coordinates.")
                }
            } else if planeSeedPoint == nil {
                Label("Tap a surface point to grow a plane region.", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("Plane selection starts from one tapped depth point, then grows to neighboring pixels that fit the same surface.")
                }
            } else {
                Label("No stable plane region found from this point.", systemImage: "square.dashed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if showsInlineHelp {
                    InlineHelpText("A stable plane needs enough nearby samples with similar camera-coordinate depth geometry.")
                }
            }

            HStack(spacing: 12) {
                PlaneLegendSwatch(color: Color(red: 0.74, green: 0.96, blue: 0.36), text: "High-fit cell")
                PlaneLegendSwatch(color: Color(red: 1.0, green: 0.62, blue: 0.24), text: "Lower-fit cell")
            }
            if showsInlineHelp {
                InlineHelpText("Plane cell colors summarize local fit quality inside the grown region.")
            }

            Divider()

            depthMetadata
        }
    }

    @ViewBuilder
    private func planeRegionMetrics(_ selectedPlaneRegion: TAPPlaneRegion) -> some View {
        DepthMetricRow(
            title: "Confidence",
            value: "\(Int((selectedPlaneRegion.confidence * 100).rounded()))%",
            explanation: "Combined score from flatness, inlier ratio, and selected plane size.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Plane cells",
            value: "\(selectedPlaneRegion.gridCells.count)",
            explanation: "Grid cells inside the grown region that contain enough pixels fitting the selected plane.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Area",
            value: areaText(selectedPlaneRegion.areaSquareMeters),
            explanation: "Approximate visible surface area in camera coordinates.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Flatness",
            value: "\(Int((selectedPlaneRegion.flatnessScore * 100).rounded()))%",
            explanation: "How tightly the grown region fits a single local plane. Higher is flatter.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Residual",
            value: String(format: "%.3f m", selectedPlaneRegion.estimate.averageResidualMeters),
            explanation: "Average distance from inlier points to the selected plane.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Inliers",
            value: "\(Int((selectedPlaneRegion.estimate.inlierRatio * 100).rounded()))% · \(selectedPlaneRegion.sampleCount)",
            explanation: "Share and count of grown points that match the fitted plane.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Normal",
            value: String(format: "[%.2f, %.2f, %.2f]", selectedPlaneRegion.estimate.normal.x, selectedPlaneRegion.estimate.normal.y, selectedPlaneRegion.estimate.normal.z),
            explanation: "Selected plane direction in local camera coordinates.",
            showsHelp: showsInlineHelp
        )
    }

    @ViewBuilder
    private var depthMetadata: some View {
        DepthMetricRow(
            title: "Depth size",
            value: "\(depthMap.width)x\(depthMap.height)",
            explanation: "Native auxiliary depth-map resolution used for camera-coordinate plane fitting.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Calibration",
            value: depthMap.calibration == nil ? "Missing" : "Available",
            explanation: "Camera intrinsics used to project depth pixels into local camera coordinates.",
            showsHelp: showsInlineHelp
        )
        DepthMetricRow(
            title: "Depth quality",
            value: "\(depthAccuracy) / \(depthQuality)",
            explanation: "Apple depth accuracy and quality metadata for this captured photo.",
            showsHelp: showsInlineHelp
        )
    }

    private var statusText: String {
        if isDetecting {
            return "Detecting"
        }
        if let selectedPlaneRegion {
            return "\(selectedPlaneRegion.gridCells.count) cells"
        }
        return "No seed"
    }

    private func areaText(_ area: Double) -> String {
        if area < 0.01 {
            return String(format: "%.1f sq cm", area * 10_000)
        }
        return String(format: "%.3f sq m", area)
    }
}

private struct PlaneLegendSwatch: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 12)
            Text(LocalizedStringKey(text))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
