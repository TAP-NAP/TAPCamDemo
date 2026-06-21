//
//  DepthAnalysisControlsView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

/// Bottom controls for analysis mode switching and inspector presentation.
///
/// The controls own no loaded image or depth data. Panel body content is passed
/// as a closure so routing and presentation stay here while field-level
/// inspector inputs stay in `AnalysisInspectorPanelContent`.
struct DepthAnalysisControlsView<PanelContent: View>: View {
    @Binding var panelDestination: AnalysisPanelDestination?
    @Binding var viewMode: DepthAnalysisViewMode
    let buttonHint: AnalysisButtonHint?
    let maxPanelHeight: CGFloat
    let onViewTapped: (DepthAnalysisViewMode) -> Void
    let panelContent: (AnalysisPanelDestination) -> PanelContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let destination = panelDestination {
                AnalysisPanelLayer(destination: $panelDestination, maxHeight: maxPanelHeight) {
                    panelContent(destination)
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }

            AnalysisInspectorStrip(
                panelDestination: $panelDestination,
                viewMode: $viewMode,
                inspectors: viewMode.inspectors,
                buttonHint: buttonHint,
                onViewTapped: onViewTapped
            )
        }
        .frame(maxWidth: 560, alignment: .leading)
        .animation(.snappy(duration: 0.18), value: panelDestination)
        .animation(.snappy(duration: 0.18), value: viewMode)
    }
}
