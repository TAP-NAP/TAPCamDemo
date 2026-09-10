//
//  DepthAnalysisStageView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import ImageIO
import SwiftUI

/// The central visual stage for one loaded depth-analysis input.
///
/// `DepthAnalysisView` owns loading and source routing. This stage receives only
/// display-ready image/depth fields, local selection bindings, and callbacks for
/// user gestures. It does not receive source identifiers, photo bytes, manifests,
/// proofs, App Attest key IDs, Photos handles, pending-store handles, geometry
/// caches, or export state.
struct DepthAnalysisStageView: View {
    let image: CGImage
    let imageOrientation: CGImagePropertyOrientation
    let depthMap: TAPMetricDepthMap
    let heatmapImage: CGImage
    let heatmapOpacity: Double
    let comparisonPosition: Double?
    let onComparisonPositionChanged: (Double) -> Void
    let planeRegion: TAPPlaneRegion?
    let partialPlaneGridCells: [TAPPlaneGridCell]
    let planeGridProgress: Double?
    let planeSeedPoint: CGPoint?
    let highlightPalette: AnalysisHighlightPalette

    let onSelectionCleared: () -> Void
    let onPlaneSeedSelected: (CGPoint) -> Void

    var body: some View {
        InteractiveDepthImage(
            image: image,
            overlayImage: heatmapImage,
            overlayOpacity: heatmapOpacity,
            comparisonPosition: comparisonPosition,
            onComparisonPositionChanged: onComparisonPositionChanged,
            orientation: imageOrientation,
            depthSize: CGSize(width: depthMap.width, height: depthMap.height),
            planeRegion: planeRegion,
            partialPlaneGridCells: partialPlaneGridCells,
            planeGridProgress: planeGridProgress,
            planeSeedPoint: planeSeedPoint,
            highlightPalette: highlightPalette,

            onSelectionCleared: onSelectionCleared,
            onPointSelected: onPlaneSeedSelected
        )
    }
}
