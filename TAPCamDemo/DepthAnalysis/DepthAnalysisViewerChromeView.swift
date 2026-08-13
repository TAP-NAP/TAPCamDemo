//
//  DepthAnalysisViewerChromeView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/7/5.
//

import SwiftUI

nonisolated enum ViewerToolbarActionIcon: String {
    case shareNetwork = "ViewerShareNetwork"
    case trash = "ViewerTrash"

    var assetName: String {
        rawValue
    }
}

struct DepthAnalysisViewerChromeView: View {
    let selectedTool: AnalysisViewerTool
    @Binding var heatmapOpacity: Double
    let shareSubject: DepthAnalysisShareSubject?
    @ObservedObject var originalResourceOwner: TAPPhotoOriginalResourceOwner
    let topSafeArea: CGFloat
    let bottomSafeArea: CGFloat
    let onBackTapped: () -> Void
    let onToolTapped: (AnalysisViewerTool) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        DepthViewerChromeView(
            selectedModeID: selectedTool.rawValue,
            modeItems: AnalysisViewerTool.allCases.map(\.modeItem),
            overlayOpacity: $heatmapOpacity,
            showsOpacityControl: selectedTool == .twoD,
            shareSubject: shareSubject,
            shareResourceAccess: DepthAnalysisShareResourceAccess(
                isReady: originalResourceOwner.isReady,
                acquire: {
                    originalResourceOwner.acquireLease().map(
                        DepthAnalysisShareOriginalResource.photo
                    )
                }
            ),
            shareAccessibilityLabel: "Share photo",
            deleteAccessibilityLabel: "Delete photo",
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea,
            bottomAccessory: EmptyView(),
            onBackTapped: onBackTapped,
            onModeTapped: { itemID in
                guard let tool = AnalysisViewerTool(rawValue: itemID) else {
                    return
                }
                onToolTapped(tool)
            },
            onDeleteTapped: onDeleteTapped
        )
    }
}

struct DepthViewerChromeView<BottomAccessory: View>: View {
    let selectedModeID: String
    let modeItems: [DepthViewerModeItem]
    @Binding var overlayOpacity: Double
    let showsOpacityControl: Bool
    let shareSubject: DepthAnalysisShareSubject?
    let shareResourceAccess: DepthAnalysisShareResourceAccess?
    let shareAccessibilityLabel: String
    let deleteAccessibilityLabel: String
    let topSafeArea: CGFloat
    let bottomSafeArea: CGFloat
    let bottomAccessory: BottomAccessory
    let onBackTapped: () -> Void
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onBackTapped) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .dynamicTypeSize(.large)
                        .frame(width: 42, height: 42)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to TAP Library")
                .accessibilityIdentifier("tap.viewer.back")
                .help("Back to TAP Library")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, ViewerChromeMetrics.backButtonTopPadding(topSafeArea: topSafeArea))

            Spacer(minLength: 0)

            bottomAccessory

            if showsOpacityControl {
                AnalysisOpacityControl(opacity: $overlayOpacity)
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            DepthViewerToolbar(
                selectedModeID: selectedModeID,
                modeItems: modeItems,
                shareSubject: shareSubject,
                shareResourceAccess: shareResourceAccess,
                shareAccessibilityLabel: shareAccessibilityLabel,
                deleteAccessibilityLabel: deleteAccessibilityLabel,
                onModeTapped: onModeTapped,
                onDeleteTapped: onDeleteTapped
            )
            .padding(.horizontal, DepthViewerToolbarMetrics.horizontalPadding)
            .padding(
                .bottom,
                DepthViewerToolbarMetrics.toolbarBottomPadding(
                    bottomSafeArea: bottomSafeArea
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.18), value: selectedModeID)
        .animation(.snappy(duration: 0.18), value: showsOpacityControl)
        .accessibilityElement(children: .contain)
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

private struct DepthViewerToolbar: View {
    let selectedModeID: String
    let modeItems: [DepthViewerModeItem]
    let shareSubject: DepthAnalysisShareSubject?
    let shareResourceAccess: DepthAnalysisShareResourceAccess?
    let shareAccessibilityLabel: String
    let deleteAccessibilityLabel: String
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            DepthViewerShareControl(
                subject: shareSubject,
                resourceAccess: shareResourceAccess,
                accessibilityLabel: shareAccessibilityLabel
            )

            Spacer(minLength: 0)

            DepthViewerModeCapsule(
                selectedItemID: selectedModeID,
                items: modeItems,
                onItemTapped: onModeTapped
            )

            Spacer(minLength: 0)

            ViewerToolbarIconButton(
                icon: .trash,
                accessibilityLabel: deleteAccessibilityLabel,
                accessibilityIdentifier: "tap.viewer.delete",
                foregroundStyle: .primary,
                action: onDeleteTapped
            )
        }
    }
}

struct ViewerToolbarIconButton: View {
    let icon: ViewerToolbarActionIcon
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let foregroundStyle: Color
    var isEnabled = true
    var accessibilityValue: String?
    var progress: Double?
    let action: () -> Void

    init(
        icon: ViewerToolbarActionIcon,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        foregroundStyle: Color,
        isEnabled: Bool = true,
        accessibilityValue: String? = nil,
        progress: Double? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.foregroundStyle = foregroundStyle
        self.isEnabled = isEnabled
        self.accessibilityValue = accessibilityValue
        self.progress = progress
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(icon.assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(foregroundStyle)
                .frame(
                    width: DepthViewerToolbarMetrics.actionSymbolCanvasSize,
                    height: DepthViewerToolbarMetrics.actionSymbolCanvasSize
                )
                .frame(
                    width: DepthViewerToolbarMetrics.controlHeight,
                    height: DepthViewerToolbarMetrics.controlHeight
                )
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .overlay {
                    if let progress {
                        Circle()
                            .trim(from: 0, to: max(0.02, min(progress, 1)))
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(
                                    lineWidth: DepthViewerToolbarMetrics.progressRingLineWidth,
                                    lineCap: .round
                                )
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(
                                width: DepthViewerToolbarMetrics.controlHeight
                                    + DepthViewerToolbarMetrics.progressRingOutset * 2,
                                height: DepthViewerToolbarMetrics.controlHeight
                                    + DepthViewerToolbarMetrics.progressRingOutset * 2
                            )
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(
            Text(LocalizedStringKey(accessibilityLabel))
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(OptionalAccessibilityValue(value: accessibilityValue))
        .help(Text(LocalizedStringKey(accessibilityLabel)))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

private struct AnalysisOpacityControl: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.caption.weight(.semibold))
                .dynamicTypeSize(.large)
                .symbolRenderingMode(.hierarchical)

            Slider(value: $opacity, in: 0...1)
                .tint(.primary)

            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.caption.monospacedDigit().weight(.semibold))
                .dynamicTypeSize(.large)
                .symbolRenderingMode(.hierarchical)
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
        .accessibilityIdentifier("tap.viewer.opacity")
        .accessibilityValue(
            Text("\(Int((opacity * 100).rounded())) percent")
        )
    }
}
