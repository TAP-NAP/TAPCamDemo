//
//  PerformancePanelView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

#if DEBUG
import Foundation
import SwiftUI

/// Debug metrics overlay for recent asynchronous capture jobs.
///
/// It reads product-level metrics recorded by the capture pipeline; it is not
/// tied to temporary FOV diagnostic logging.
struct PerformancePanelView: View {
    let metrics: [CaptureJobMetrics]
    let pendingJobCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let latest = metrics.first {
                timingRows(for: latest)

                if let failureReason = latest.failureReason {
                    Text(failureReason)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .lineLimit(2)
                }

                recentRows(after: latest.id)
            } else {
                Text("No captures yet")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .foregroundStyle(.white.opacity(0.86))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Pending \(pendingJobCount)")
                .font(.caption2.weight(.semibold))

            Spacer(minLength: 4)

            if let latest = metrics.first {
                Text(latest.status.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(latest.status == .succeeded ? .green : .yellow)
            }
        }
    }

    @ViewBuilder
    private func timingRows(for metric: CaptureJobMetrics) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metricRow("queue", metric.queueWaitDuration)
            metricRow("capture", metric.captureDuration)
            metricRow("package", metric.packageBuildDuration)
            metricRow("embed", metric.packagingDuration)
            metricRow("storage", metric.writeDuration)
            metricRow("total", metric.totalDuration)
        }
        .font(.caption2.monospacedDigit())
    }

    @ViewBuilder
    private func recentRows(after latestID: UUID) -> some View {
        let previousMetrics = metrics
            .filter { $0.id != latestID }
            .prefix(2)

        if previousMetrics.isEmpty == false {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))

                ForEach(Array(previousMetrics)) { metric in
                    HStack(spacing: 7) {
                        Text(metric.status.rawValue)
                            .foregroundStyle(metric.status == .succeeded ? .green : .yellow)
                        Text("total \(format(metric.totalDuration))")
                        Text("capture \(format(metric.captureDuration))")
                        Text("storage \(format(metric.writeDuration))")
                    }
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }
            }
        }
    }

    private func metricRow(_ title: String, _ value: TimeInterval?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 54, alignment: .leading)

            Text(format(value))
                .fontWeight(.semibold)

            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func metricRow(_ title: String, _ value: TimeInterval) -> some View {
        metricRow(title, Optional(value))
    }

    private func format(_ value: TimeInterval?) -> String {
        guard let value else {
            return "-"
        }
        return "\(Int(value * 1_000))ms"
    }
}

#endif
