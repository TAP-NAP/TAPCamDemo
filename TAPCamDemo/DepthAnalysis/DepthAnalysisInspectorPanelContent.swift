//
//  DepthAnalysisInspectorPanelContent.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import ImageIO
import SwiftUI

/// Field-level content for the bottom analysis inspector panel.
///
/// This view intentionally receives only loaded image/depth fields and local
/// selection state. Source identifiers, HEIC bytes, manifests, proofs, App
/// Attest key IDs, Photos handles, pending-store handles, and export state stay
/// outside the inspector UI boundary.
struct AnalysisInspectorPanelContent: View {
    let destination: AnalysisPanelDestination
    let viewMode: DepthAnalysisViewMode
    let image: CGImage
    let imageOrientation: CGImagePropertyOrientation
    let depthMap: TAPMetricDepthMap
    let depthAccuracy: String
    let depthQuality: String
    let heatmap: TAPDepthHeatmapVisualization
    let validMask: TAPDepthMaskVisualization
    let regionSelection: DepthAnalysisRegionSelectionState
    let planeSelection: DepthAnalysisPlaneSelectionState
    @Binding var heatmapOpacity: Double
    let showsInlineHelp: Bool
    let onPlaneStrictnessChanged: (Double) -> Void

    var body: some View {
        switch destination {
        case .inspector(let inspector):
            VStack(alignment: .leading, spacing: 10) {
                if showsInlineHelp {
                    InlineHelpText(inspector.detailedExplanation)
                }
                inspectorContent(for: inspector)
            }
        }
    }

    @ViewBuilder
    private func inspectorContent(for inspector: AnalysisInspector) -> some View {
        switch inspector {
        case .measurements:
            MeasurementsInspectorContent(
                stats: regionSelection.regionStats,
                planeEstimate: regionSelection.planeEstimate,
                interactionState: regionSelection.interactionState,
                showsInlineHelp: showsInlineHelp
            )
        case .legend:
            LegendInspectorContent(
                viewMode: viewMode,
                heatmap: heatmap,
                validMask: validMask,
                showsInlineHelp: showsInlineHelp
            )
        case .overlay:
            OverlayInspectorContent(opacity: $heatmapOpacity, showsInlineHelp: showsInlineHelp)
        case .region:
            RegionInspectorContent(
                image: image,
                orientation: imageOrientation,
                depthSize: CGSize(width: depthMap.width, height: depthMap.height),
                selection: regionSelection.selectionRect,
                interactionState: regionSelection.interactionState,
                stats: regionSelection.regionStats,
                planeEstimate: regionSelection.planeEstimate,
                regionHeatmap: regionSelection.regionHeatmap,
                heatmapErrorMessage: DepthAnalysisInspectorErrorMessage.regionHeatmap(
                    regionSelection.regionHeatmapErrorMessage
                ),
                showsInlineHelp: showsInlineHelp
            )
        case .planeFilter:
            PlaneFilterInspectorContent(
                depthMap: depthMap,
                depthAccuracy: depthAccuracy,
                depthQuality: depthQuality,
                selectedPlaneRegion: planeSelection.selectedRegion,
                planeSeedPoint: planeSelection.seedPoint,
                isDetecting: planeSelection.isDetecting,
                errorMessage: DepthAnalysisInspectorErrorMessage.planeSelection(
                    planeSelection.errorMessage
                ),
                strictness: Binding(
                    get: { planeSelection.strictness },
                    set: onPlaneStrictnessChanged
                ),
                showsInlineHelp: showsInlineHelp
            )
        case .cloudInfo:
            CloudInfoInspectorContent(
                depthMap: depthMap,
                orientation: imageOrientation,
                selection: regionSelection.selectionRect,
                interactionState: regionSelection.interactionState,
                showsInlineHelp: showsInlineHelp
            )
        }
    }
}
