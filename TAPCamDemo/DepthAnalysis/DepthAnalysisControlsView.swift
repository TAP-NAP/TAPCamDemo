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
/// centered raw/2D/3D tool switcher; global actions live in the viewer chrome.
struct DepthAnalysisControlsView: View {
    let selectedTool: AnalysisViewerTool
    let onToolTapped: (AnalysisViewerTool) -> Void

    var body: some View {
        AnalysisBottomNavBar(
            selectedTool: selectedTool,
            onToolTapped: onToolTapped
        )
        .animation(.snappy(duration: 0.18), value: selectedTool)
    }
}

private struct AnalysisBottomNavBar: View {
    let selectedTool: AnalysisViewerTool
    let onToolTapped: (AnalysisViewerTool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AnalysisViewerTool.allCases) { tool in
                iconButton(
                    systemImage: tool.systemImage,
                    accessibilityLabel: tool.accessibilityLabel,
                    isSelected: selectedTool == tool,
                    action: {
                        onToolTapped(tool)
                    }
                )
            }
        }
        .padding(5)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    private func iconButton(
        systemImage: String,
        accessibilityLabel: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 42, height: 36)
                .background(toolBackground(isSelected: isSelected), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func toolBackground(isSelected: Bool) -> Color {
        isSelected ? Color.primary.opacity(0.16) : Color.clear
    }
}
