//
//  DepthAnalysisControlsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

nonisolated enum DepthViewerToolbarMetrics {
    static let controlHeight: CGFloat = 42
    static let modeButtonWidth: CGFloat = 42
    static let modeButtonHeight: CGFloat = 36
    static let modeHitTargetSize: CGFloat = 44
    static let modeCapsuleHorizontalInset: CGFloat = 4
    static let actionSymbolCanvasSize: CGFloat = 20
    static let horizontalPadding: CGFloat = 16
    static let progressRingOutset: CGFloat = 3
    static let progressRingLineWidth: CGFloat = 3
    static let homeGestureClearance: CGFloat = 16
    static let fallbackBottomPadding: CGFloat = 25

    static func toolbarBottomPadding(bottomSafeArea: CGFloat) -> CGFloat {
        max(fallbackBottomPadding, bottomSafeArea + homeGestureClearance)
    }
}

/// Bottom controls for the Photos-style analysis browser.
///
/// The controls own no loaded image or depth data. They only expose the
/// centered raw/2D/3D tool switcher; global actions live in the viewer toolbar.
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
        HStack(spacing: 0) {
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
        .padding(.horizontal, DepthViewerToolbarMetrics.modeCapsuleHorizontalInset)
        .frame(
            minHeight: DepthViewerToolbarMetrics.controlHeight,
            maxHeight: DepthViewerToolbarMetrics.controlHeight
        )
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
            ZStack {
                Capsule()
                    .fill(toolBackground(isSelected: isSelected))
                    .frame(
                        width: DepthViewerToolbarMetrics.modeButtonWidth,
                        height: DepthViewerToolbarMetrics.modeButtonHeight
                    )

                Image(systemName: item.systemImage)
                    .font(.callout.weight(.semibold))
                    .dynamicTypeSize(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
            .frame(
                width: DepthViewerToolbarMetrics.modeHitTargetSize,
                height: DepthViewerToolbarMetrics.modeHitTargetSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.35)
        .accessibilityLabel(
            Text(LocalizedStringKey(item.accessibilityLabel))
        )
        .accessibilityValue(
            Text(LocalizedStringKey(
                accessibilityValue(for: item, isSelected: isSelected)
            ))
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(Text(LocalizedStringKey(item.accessibilityLabel)))

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
