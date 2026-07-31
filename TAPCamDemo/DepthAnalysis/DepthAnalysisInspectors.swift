//
//  DepthAnalysisInspectors.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import SwiftUI

/// Shared building blocks for Depth Analysis inspector panels.
///
/// Concrete inspector bodies live in focused sibling files:
/// `DepthAnalysisMeasurementsInspectorContent.swift`,
/// `DepthAnalysisLegendInspectorContent.swift`,
/// `DepthAnalysisRegionInspectorContent.swift`,
/// `DepthAnalysisPlaneFilterInspectorContent.swift`, and
/// `DepthAnalysisOverlayCloudInspectors.swift`.
struct InlineHelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // This component accepts product-authored static copy only. Runtime
        // errors and measured values use separate verbatim presentation paths.
        Text(LocalizedStringKey(text))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

enum DepthLegendLabelStyle {
    case metricDepth
    case localizedKey
}

struct DepthLegendView: View {
    let stops: [TAPDepthLegendStop]
    var labelStyle = DepthLegendLabelStyle.metricDepth

    var body: some View {
        VStack(spacing: 5) {
            LinearGradient(
                stops: stops.map { Gradient.Stop(color: $0.color.swiftUIColor, location: $0.position) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 9)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.primary.opacity(0.14), lineWidth: 1)
            }

            HStack {
                endpointLabel(stops.first?.label, endpoint: .near)
                Spacer(minLength: 8)
                endpointLabel(stops.last?.label, endpoint: .far)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func endpointLabel(
        _ label: String?,
        endpoint: DepthLegendEndpoint
    ) -> some View {
        if let label {
            switch labelStyle {
            case .metricDepth:
                metricEndpointLabel(label, endpoint: endpoint)
            case .localizedKey:
                Text(LocalizedStringKey(label))
            }
        } else {
            switch endpoint {
            case .near:
                Text("Near")
            case .far:
                Text("Far")
            }
        }
    }

    private func metricEndpointLabel(
        _ label: String,
        endpoint: DepthLegendEndpoint
    ) -> Text {
        let prefix = endpoint == .near ? "Near " : "Far "
        guard label.hasPrefix(prefix) else {
            return Text(verbatim: label)
        }

        let measurement = Text(verbatim: String(label.dropFirst(prefix.count)))
        switch endpoint {
        case .near:
            return Text("Near \(measurement)")
        case .far:
            return Text("Far \(measurement)")
        }
    }
}

private enum DepthLegendEndpoint {
    case near
    case far
}

struct SwatchLegendView: View {
    let stops: [TAPDepthLegendStop]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(stops) { stop in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stop.color.swiftUIColor)
                        .frame(width: 18, height: 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(.primary.opacity(0.16), lineWidth: 1)
                        }

                    // Swatch labels are product-authored semantic categories;
                    // unlike metric depth labels, they contain no runtime value.
                    Text(LocalizedStringKey(stop.label))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

nonisolated struct DepthRegionStatsPresentation: Equatable, Sendable {
    static let noValidDepthText = "No valid depth"

    let medianDepthText: String
    let rangeText: String
    let validSamplesText: String

    init(stats: TAPDepthRegionStats) {
        medianDepthText = Self.depthText(stats.medianDepthMeters)
        rangeText = Self.rangeText(
            minimumDepthMeters: stats.minimumDepthMeters,
            maximumDepthMeters: stats.maximumDepthMeters
        )
        validSamplesText = Self.validSamplesText(
            validSampleCount: stats.validSampleCount,
            totalSampleCount: stats.totalSampleCount,
            validRatio: stats.validRatio
        )
    }

    private static func depthText(_ depthMeters: Float?) -> String {
        guard let depthMeters else {
            return noValidDepthText
        }

        return String(format: "%.2f m", depthMeters)
    }

    private static func rangeText(minimumDepthMeters: Float?, maximumDepthMeters: Float?) -> String {
        guard let minimumDepthMeters, let maximumDepthMeters else {
            return noValidDepthText
        }

        return String(format: "%.2f...%.2f m", minimumDepthMeters, maximumDepthMeters)
    }

    private static func validSamplesText(
        validSampleCount: Int,
        totalSampleCount: Int,
        validRatio: Double
    ) -> String {
        "\(validSampleCount)/\(totalSampleCount) · \(Int((validRatio * 100).rounded()))%"
    }
}

struct DepthMetricRow: View {
    let title: String
    let value: String
    let explanation: String
    var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help(Text(LocalizedStringKey(explanation)))
                Spacer(minLength: 8)
                // Measurements, counts, and device metadata are intentionally
                // verbatim and must not be interpreted as catalog keys.
                Text(value)
                    .fontDesign(.monospaced)
            }
            if showsHelp {
                InlineHelpText(explanation)
            }
        }
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
