//
//  DepthAnalysisControlsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

/// Bottom controls for the Photos-style analysis browser.
///
/// The controls own no loaded image or depth data. They only expose the fixed
/// share/delete edges and the center capsule tool bar; the scroll detail page
/// decides what each selected tool renders.
struct DepthAnalysisControlsView: View {
    let selectedTool: AnalysisDrawerTool?
    let buttonHint: AnalysisButtonHint?
    let onToolTapped: (AnalysisDrawerTool) -> Void
    let onShareTapped: () -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        AnalysisBottomNavBar(
            selectedTool: selectedTool,
            buttonHint: buttonHint,
            onShareTapped: onShareTapped,
            onToolTapped: onToolTapped,
            onDeleteTapped: onDeleteTapped
        )
        .frame(maxWidth: 640, alignment: .center)
        .animation(.snappy(duration: 0.18), value: selectedTool)
    }
}

private struct AnalysisBottomNavBar: View {
    let selectedTool: AnalysisDrawerTool?
    let buttonHint: AnalysisButtonHint?
    let onShareTapped: () -> Void
    let onToolTapped: (AnalysisDrawerTool) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iconActionButton(
                systemImage: "square.and.arrow.up",
                accessibilityLabel: "Share",
                action: onShareTapped
            )

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(AnalysisDrawerTool.allCases) { tool in
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

            Spacer(minLength: 0)

            iconActionButton(
                systemImage: "trash",
                accessibilityLabel: "Delete",
                role: .destructive,
                isDestructive: true,
                action: onDeleteTapped
            )
        }
        .overlay(alignment: .top) {
            if let buttonHint {
                AnalysisButtonBubble(hint: buttonHint)
                    .offset(y: -42)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func toolLabel(_ tool: AnalysisDrawerTool) -> some View {
        Image(systemName: tool.systemImage)
            .font(.callout.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .frame(width: 42, height: 36)
            .background(toolBackground(isSelected: selectedTool == tool), in: Capsule())
            .contentShape(Capsule())
    }

    private func iconActionButton(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 42, height: 42)
                .foregroundStyle(isDestructive ? .red : .primary)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func toolBackground(isSelected: Bool) -> Color {
        isSelected ? Color.primary.opacity(0.16) : Color.clear
    }
}

private struct AnalysisButtonBubble: View {
    let hint: AnalysisButtonHint

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hint.systemImage)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(hint.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}
