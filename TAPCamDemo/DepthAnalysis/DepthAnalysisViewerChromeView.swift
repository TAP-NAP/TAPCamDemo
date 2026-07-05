//
//  DepthAnalysisViewerChromeView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/7/5.
//

import SwiftUI

struct DepthAnalysisViewerChromeView: View {
    let selectedTool: AnalysisViewerTool
    @Binding var heatmapOpacity: Double
    let topSafeArea: CGFloat
    let bottomSafeArea: CGFloat
    let onBackTapped: () -> Void
    let onShareTapped: () -> Void
    let onToolTapped: (AnalysisViewerTool) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onBackTapped) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to TAP Library")
                .help("Back to TAP Library")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, ViewerChromeMetrics.backButtonTopPadding(topSafeArea: topSafeArea))

            Spacer(minLength: 0)

            if selectedTool == .twoD {
                AnalysisOpacityControl(opacity: $heatmapOpacity)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 12) {
                chromeActionButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: "Share photo",
                    foregroundStyle: .primary,
                    action: onShareTapped
                )

                Spacer(minLength: 0)

                DepthAnalysisControlsView(
                    selectedTool: selectedTool,
                    onToolTapped: onToolTapped
                )

                Spacer(minLength: 0)

                chromeActionButton(
                    systemImage: "trash",
                    accessibilityLabel: "Delete photo",
                    foregroundStyle: .red,
                    action: onDeleteTapped
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, max(12, bottomSafeArea + 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.18), value: selectedTool)
        .accessibilityElement(children: .contain)
    }

    private func chromeActionButton(
        systemImage: String,
        accessibilityLabel: String,
        foregroundStyle: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foregroundStyle)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}

private enum ViewerChromeMetrics {
    static let backButtonSize: CGFloat = 42
    static let inlineNavigationBarHeight: CGFloat = 44
    static let fallbackBackButtonTopPadding: CGFloat = 58

    static func backButtonTopPadding(topSafeArea: CGFloat) -> CGFloat {
        guard topSafeArea > 0 else {
            return fallbackBackButtonTopPadding
        }
        return topSafeArea + (inlineNavigationBarHeight - backButtonSize) * 0.5
    }
}

private struct AnalysisOpacityControl: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)

            Slider(value: $opacity, in: 0...1)
                .tint(.primary)

            Text("\(Int((opacity * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("2D overlay opacity")
        .accessibilityValue("\(Int((opacity * 100).rounded())) percent")
    }
}
