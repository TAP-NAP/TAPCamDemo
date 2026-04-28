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
        VStack(alignment: .leading, spacing: 4) {
            Text("Pending \(pendingJobCount)")
                .font(.caption2.weight(.semibold))

            ForEach(metrics.prefix(3)) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(metric.status.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(metric.status == .succeeded ? .green : .yellow)
                        Text("total \(format(metric.totalDuration))")
                        Text("capture \(format(metric.captureDuration))")
                        Text("write \(format(metric.writeDuration))")
                    }
                    HStack(spacing: 8) {
                        Text(metric.pairingMode ?? "-")
                        Text(metric.selectedRGBSource ?? "-")
                        Text(metric.selectedDepthSource ?? "-")
                        Text(metric.currentZoomFactor.map { "\($0)x" } ?? "-")
                    }
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.white.opacity(0.86))
    }

    private func format(_ value: TimeInterval?) -> String {
        guard let value else {
            return "-"
        }
        return "\(Int(value * 1_000))ms"
    }
}

#endif
