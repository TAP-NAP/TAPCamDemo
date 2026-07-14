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
        DepthViewerModeCapsule(
            selectedItemID: selectedTool.rawValue,
            items: AnalysisViewerTool.allCases.map(\.modeItem),
            onItemTapped: { itemID in
                guard let tool = AnalysisViewerTool(rawValue: itemID) else {
                    return
                }
                onToolTapped(tool)
            }
        )
        .animation(.snappy(duration: 0.18), value: selectedTool)
    }
}

nonisolated struct DepthViewerModeItem: Identifiable, Equatable {
    let id: String
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let isEnabled: Bool
    let accessibilityValue: String?

    nonisolated init(
        id: String,
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil,
        isEnabled: Bool = true,
        accessibilityValue: String? = nil
    ) {
        self.id = id
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isEnabled = isEnabled
        self.accessibilityValue = accessibilityValue
    }
}

struct DepthViewerModeCapsule: View {
    let selectedItemID: String
    let items: [DepthViewerModeItem]
    let onItemTapped: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                iconButton(
                    item: item,
                    isSelected: selectedItemID == item.id,
                    action: {
                        onItemTapped(item.id)
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
        .animation(.snappy(duration: 0.18), value: selectedItemID)
    }

    @ViewBuilder
    private func iconButton(
        item: DepthViewerModeItem,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: item.systemImage)
                .font(.callout.weight(.semibold))
                .dynamicTypeSize(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 42, height: 36)
                .background(toolBackground(isSelected: isSelected), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.35)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(accessibilityValue(for: item, isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(item.accessibilityLabel)

        if let accessibilityIdentifier = item.accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }

    private func toolBackground(isSelected: Bool) -> Color {
        isSelected ? Color.primary.opacity(0.16) : Color.clear
    }

    private func accessibilityValue(
        for item: DepthViewerModeItem,
        isSelected: Bool
    ) -> String {
        if let accessibilityValue = item.accessibilityValue {
            return accessibilityValue
        }
        if !item.isEnabled {
            return "Unavailable"
        }
        return isSelected ? "Selected" : ""
    }
}

extension AnalysisViewerTool {
    var modeItem: DepthViewerModeItem {
        DepthViewerModeItem(
            id: rawValue,
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: modeAccessibilityIdentifier
        )
    }

    private var modeAccessibilityIdentifier: String {
        switch self {
        case .raw:
            "tap.viewer.mode.raw"
        case .twoD:
            "tap.viewer.mode.2d"
        case .threeD:
            "tap.viewer.mode.3d"
        }
    }
}
