//
//  DepthAnalysisControlsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

/// Bottom controls for the Photos-style analysis browser.
///
/// The controls own no loaded image or depth data. They only expose the
/// centered raw/2D/3D tool switcher.
struct DepthAnalysisControlsView: View {
    let selectedTool: AnalysisViewerTool
    let onToolTapped: (AnalysisViewerTool) -> Void

    var body: some View {
        AnalysisBottomNavBar(
            selectedTool: selectedTool,
            onToolTapped: onToolTapped
        )
        .frame(maxWidth: 640, alignment: .center)
        .animation(.snappy(duration: 0.18), value: selectedTool)
    }
}

private struct AnalysisBottomNavBar: View {
    let selectedTool: AnalysisViewerTool
    let onToolTapped: (AnalysisViewerTool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AnalysisViewerTool.allCases) { tool in
                Button {
                    onToolTapped(tool)
                } label: {
                    toolLabel(tool)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.accessibilityLabel)
                .help(tool.accessibilityLabel)
            }
        }
        .padding(5)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .padding(.vertical, 6)
    }

    private func toolLabel(_ tool: AnalysisViewerTool) -> some View {
        Text(tool.title)
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(width: 58, height: 36)
            .background(toolBackground(isSelected: selectedTool == tool), in: Capsule())
            .contentShape(Capsule())
    }

    private func toolBackground(isSelected: Bool) -> Color {
        isSelected ? Color.primary.opacity(0.16) : Color.clear
    }
}
