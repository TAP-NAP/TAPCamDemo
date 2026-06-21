//
//  DepthAnalysisInspectorStrip.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

struct AnalysisInspectorStrip: View {
    @Binding var panelDestination: AnalysisPanelDestination?
    @Binding var viewMode: DepthAnalysisViewMode
    let inspectors: [AnalysisInspector]
    let buttonHint: AnalysisButtonHint?
    let onViewTapped: (DepthAnalysisViewMode) -> Void
    let onVerifySignatureTapped: () -> Void
    @State private var viewScrollPosition: String? = DepthAnalysisViewMode.rgb.id
    @State private var inspectorScrollPosition: String?
    private static let verifyScrollID = "analysis-signature-verification"

    init(
        panelDestination: Binding<AnalysisPanelDestination?>,
        viewMode: Binding<DepthAnalysisViewMode>,
        inspectors: [AnalysisInspector],
        buttonHint: AnalysisButtonHint?,
        onViewTapped: @escaping (DepthAnalysisViewMode) -> Void,
        onVerifySignatureTapped: @escaping () -> Void
    ) {
        _panelDestination = panelDestination
        _viewMode = viewMode
        self.inspectors = inspectors
        self.buttonHint = buttonHint
        self.onViewTapped = onViewTapped
        self.onVerifySignatureTapped = onVerifySignatureTapped
    }

    private static var visibleViewModes: [DepthAnalysisViewMode] {
        #if DEBUG
        return DepthAnalysisViewMode.allCases
        #else
        return DepthAnalysisViewMode.allCases.filter { !$0.isDebugOnlyAnalysisButton }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PinnedStripRow(
                systemImage: "eye",
                accessibilityLabel: "Views",
                helpText: "Views",
                scrollPosition: $viewScrollPosition
            ) {
                viewModeTabs
            }

            PinnedStripRow(
                systemImage: "scope",
                accessibilityLabel: "Inspectors",
                helpText: "Inspectors",
                scrollPosition: $inspectorScrollPosition
            ) {
                inspectorTabs
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            if let buttonHint {
                AnalysisButtonBubble(hint: buttonHint)
                    .offset(y: -38)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear {
            syncViewScrollPosition()
            syncInspectorScrollPosition()
        }
        .onChange(of: viewMode) { _, newValue in
            viewScrollPosition = newValue.id
            syncInspectorScrollPosition()
        }
        .onChange(of: inspectors) { _, _ in
            syncInspectorScrollPosition()
        }
        .onChange(of: panelDestination) { _, _ in
            syncViewScrollPosition()
            syncInspectorScrollPosition()
        }
        .animation(.snappy(duration: 0.18), value: buttonHint)
    }

    @ViewBuilder
    private var viewModeTabs: some View {
        ForEach(Self.visibleViewModes) { item in
            Button {
                onViewTapped(item)
                viewScrollPosition = item.id
                viewMode = item
            } label: {
                iconButton(
                    systemImage: item.systemImage,
                    isSelected: item == viewMode,
                    isDebugHighlighted: item.isDebugOnlyAnalysisButton
                )
            }
            .id(item.id)
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .help(item.detailedExplanation)
        }

        verifyButton
    }

    @ViewBuilder
    private var inspectorTabs: some View {
        ForEach(inspectors) { inspector in
            Button {
                inspectorScrollPosition = inspector.id
                toggle(.inspector(inspector))
            } label: {
                iconButton(
                    systemImage: inspector.systemImage,
                    isSelected: panelDestination?.selectedInspector == inspector
                )
            }
            .id(inspector.id)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(inspector.title)
            .help(inspector.title)
        }
    }

    private var verifyButton: some View {
        Button {
            viewScrollPosition = Self.verifyScrollID
            onVerifySignatureTapped()
        } label: {
            iconButton(
                systemImage: "checkmark.shield",
                isSelected: panelDestination == .signatureVerification
            )
        }
        .id(Self.verifyScrollID)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Verify signature")
        .help("Verify the saved photo's App Attest proof.")
    }

    private func iconButton(systemImage: String, isSelected: Bool, isDebugHighlighted: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 34, height: 32)
            .foregroundStyle(.primary)
            .background(
                iconBackground(isSelected: isSelected, isDebugHighlighted: isDebugHighlighted),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func toggle(_ destination: AnalysisPanelDestination) {
        if panelDestination == destination {
            panelDestination = nil
        } else {
            panelDestination = destination
        }
    }

    private func iconBackground(isSelected: Bool, isDebugHighlighted: Bool = false) -> Color {
        if isDebugHighlighted {
            return isSelected ? AnalysisDebugHighlight.selectedBackground : AnalysisDebugHighlight.restingBackground
        }
        if isSelected {
            return Color.primary.opacity(0.16)
        }
        return Color.primary.opacity(0.06)
    }

    private func syncViewScrollPosition() {
        if panelDestination == .signatureVerification {
            viewScrollPosition = Self.verifyScrollID
        } else {
            viewScrollPosition = viewMode.id
        }
    }

    private func syncInspectorScrollPosition() {
        if let inspector = panelDestination?.selectedInspector, inspectors.contains(inspector) {
            inspectorScrollPosition = inspector.id
        } else if inspectorScrollPosition == nil || !isValidInspectorScrollID(inspectorScrollPosition) {
            inspectorScrollPosition = inspectors.first?.id
        }
    }

    private func isValidInspectorScrollID(_ id: String?) -> Bool {
        guard let id else {
            return false
        }
        return inspectors.contains { $0.id == id }
    }
}

private struct PinnedStripRow<Content: View>: View {
    let systemImage: String
    let accessibilityLabel: String
    let helpText: String
    @Binding var scrollPosition: String?
    let content: Content

    init(
        systemImage: String,
        accessibilityLabel: String,
        helpText: String,
        scrollPosition: Binding<String?>,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.helpText = helpText
        _scrollPosition = scrollPosition
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 32)
                .accessibilityLabel(accessibilityLabel)
                .help(helpText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition, anchor: .center)
        }
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
