//
//  DepthAnalysisPanelLayer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import SwiftUI

nonisolated struct AnalysisPanelLayoutMetrics: Equatable, Sendable {
    private static let panelChromeHeight: CGFloat = 78
    private static let minimumContentMaxHeight: CGFloat = 72
    private static let unmeasuredViewportHeight: CGFloat = 1
    private static let scrollOverflowTolerance: CGFloat = 1

    let maxHeight: CGFloat
    let measuredContentHeight: CGFloat

    var contentMaxHeight: CGFloat {
        max(Self.minimumContentMaxHeight, maxHeight - Self.panelChromeHeight)
    }

    var contentViewportHeight: CGFloat {
        guard measuredContentHeight > 0 else {
            return Self.unmeasuredViewportHeight
        }
        return min(measuredContentHeight, contentMaxHeight)
    }

    var showsScrollIndicators: Bool {
        measuredContentHeight > contentMaxHeight + Self.scrollOverflowTolerance
    }
}

struct AnalysisPanelLayer<Content: View>: View {
    @Binding var destination: AnalysisPanelDestination?
    let maxHeight: CGFloat
    let content: Content
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredPanelHeight: CGFloat = 0

    init(destination: Binding<AnalysisPanelDestination?>, maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        _destination = destination
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: titleIcon)
                    .font(.headline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    destination = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close analysis panel")
                .help("Close this analysis panel.")
            }

            Divider()

            adaptivePanelContent
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: AnalysisPanelHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(AnalysisPanelContentHeightKey.self) { height in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                measuredContentHeight = height
            }
            logPanelLayout(contentHeight: height, panelHeight: measuredPanelHeight)
        }
        .onPreferenceChange(AnalysisPanelHeightKey.self) { height in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                measuredPanelHeight = height
            }
            logPanelLayout(contentHeight: measuredContentHeight, panelHeight: height)
        }
        .onChange(of: destination) { _, _ in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                measuredContentHeight = 0
                measuredPanelHeight = 0
            }
        }
    }

    private var adaptivePanelContent: some View {
        ScrollView(.vertical, showsIndicators: layoutMetrics.showsScrollIndicators) {
            measuredPanelContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: layoutMetrics.contentViewportHeight, alignment: .top)
        .clipped()
    }

    private var measuredPanelContent: some View {
        panelContent
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: AnalysisPanelContentHeightKey.self, value: proxy.size.height)
                }
            }
    }

    private var panelContent: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutMetrics: AnalysisPanelLayoutMetrics {
        AnalysisPanelLayoutMetrics(
            maxHeight: maxHeight,
            measuredContentHeight: measuredContentHeight
        )
    }

    private func logPanelLayout(contentHeight: CGFloat, panelHeight: CGFloat) {
        #if DEBUG
        guard contentHeight > 0 || panelHeight > 0 else {
            return
        }
        let metrics = AnalysisPanelLayoutMetrics(
            maxHeight: maxHeight,
            measuredContentHeight: contentHeight
        )
        print(
            "[DepthAnalysisPanel] title=\(title) content=\(String(format: "%.1f", contentHeight)) " +
            "panel=\(String(format: "%.1f", panelHeight)) contentMax=\(String(format: "%.1f", metrics.contentMaxHeight)) " +
            "scroll=\(metrics.showsScrollIndicators)"
        )
        #endif
    }

    private var title: String {
        guard let inspector = destination?.selectedInspector else {
            return "Analysis"
        }

        return inspector.title
    }

    private var titleIcon: String {
        guard let inspector = destination?.selectedInspector else {
            return "scope"
        }

        return inspector.systemImage
    }
}

private struct AnalysisPanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AnalysisPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
