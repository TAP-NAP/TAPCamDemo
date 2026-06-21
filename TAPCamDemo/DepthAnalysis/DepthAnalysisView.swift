//
//  DepthAnalysisView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import SwiftUI

/// Independent browser/analysis surface for saved TAP Depth HEIC files.
///
/// The camera view links here through a thumbnail only. All depth heatmaps,
/// point-cloud previews, pixel reads, and plane fitting live on this side of
/// the module boundary so the capture UI remains a camera.
struct DepthAnalysisView: View {
    let source: DepthAnalysisSource
    @StateObject private var viewModel = DepthAnalysisViewModel()
    @State private var heatmapOpacity = 0.74
    @State private var panelDestination: AnalysisPanelDestination?
    @State private var buttonHint: AnalysisButtonHint?
    @State private var buttonHintToken = UUID()
    @AppStorage(DepthAnalyzerPreferences.showsAnalysisHelpKey)
    private var isShowingInlineHelp = DepthAnalyzerPreferences.defaultShowsAnalysisHelp

    init(
        assetID: String
    ) {
        self.source = .photosAsset(assetID)
    }

    init(
        pendingCaptureID: String
    ) {
        self.source = .pendingCapture(pendingCaptureID)
    }

    var body: some View {
        Group {
            if let input = viewModel.input {
                analysisContent(input)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    viewModel.errorTitle,
                    systemImage: viewModel.errorSystemImage,
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading depth image...")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if panelDestination != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        clearSelectionAndPanel()
                    }
                    .onTapGesture {
                        panelDestination = nil
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let input = viewModel.input {
                analysisControls(for: input)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.viewMode) { _, viewMode in
            if let inspector = panelDestination?.selectedInspector, !viewMode.inspectors.contains(inspector) {
                panelDestination = nil
            }
        }
        .task {
            await viewModel.load(source: source)
        }
    }

    @ViewBuilder
    private func analysisContent(_ input: TAPDepthAnalysisInput) -> some View {
        DepthAnalysisStageView(
            viewMode: viewModel.viewMode,
            image: input.image,
            imageOrientation: input.imageOrientation,
            depthMap: input.depthMap,
            heatmapImage: input.heatmap.image,
            validMaskImage: input.validMask.image,
            heatmapOpacity: heatmapOpacity,
            selection: $viewModel.regionSelection.selectionRect,
            interactionState: viewModel.regionSelection.interactionState,
            planeRegion: viewModel.planeSelection.selectedRegion,
            planeSeedPoint: viewModel.planeSelection.seedPoint,
            metadataSummary: CaptureMetadataSummary(payload: input.manifest?.payload),
            onSelectionBegan: { depthRect in
                viewModel.beginSelection(depthRect)
            },
            onSelectionChanged: { depthRect in
                viewModel.previewSelection(depthRect)
            },
            onSelectionEnded: { depthRect in
                finishRegionSelection(depthRect)
            },
            onSelectionCleared: {
                clearSelectionAndPanel()
            },
            onPlaneSeedSelected: { depthPoint in
                viewModel.selectPlaneSeed(depthPoint)
                panelDestination = .inspector(.planeFilter)
            }
        )
    }

    private func analysisControls(for input: TAPDepthAnalysisInput) -> some View {
        DepthAnalysisControlsView(
            panelDestination: $panelDestination,
            viewMode: $viewModel.viewMode,
            buttonHint: buttonHint,
            maxPanelHeight: UIScreen.main.bounds.height * 0.32,
            onViewTapped: { viewMode in
                showButtonHint(.view(viewMode))
            },
            panelContent: { destination in
                AnalysisInspectorPanelContent(
                    destination: destination,
                    viewMode: viewModel.viewMode,
                    image: input.image,
                    imageOrientation: input.imageOrientation,
                    depthMap: input.depthMap,
                    depthAccuracy: input.depthAccuracy,
                    depthQuality: input.depthQuality,
                    heatmap: input.heatmap,
                    validMask: input.validMask,
                    regionSelection: viewModel.regionSelection,
                    planeSelection: viewModel.planeSelection,
                    heatmapOpacity: $heatmapOpacity,
                    showsInlineHelp: isShowingInlineHelp,
                    onPlaneStrictnessChanged: { strictness in
                        viewModel.updatePlaneGrowthStrictness(strictness)
                    }
                )
            }
        )
        .animation(.snappy(duration: 0.18), value: isShowingInlineHelp)
    }

    private func clearSelectionAndPanel() {
        viewModel.clearSelection()
        panelDestination = nil
    }

    private func finishRegionSelection(_ depthRect: CGRect) {
        viewModel.finishSelection(depthRect)
        if viewModel.viewMode.inspectors.contains(.region) {
            panelDestination = .inspector(.region)
        }
    }

    private func showButtonHint(_ hint: AnalysisButtonHint) {
        let token = UUID()
        buttonHintToken = token
        withAnimation(.snappy(duration: 0.16)) {
            buttonHint = hint
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard buttonHintToken == token else {
                return
            }
            withAnimation(.snappy(duration: 0.16)) {
                buttonHint = nil
            }
        }
    }

}
