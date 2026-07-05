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
    let viewMode: DepthAnalysisViewMode
    let image: CGImage
    let imageOrientation: CGImagePropertyOrientation
    let depthMap: TAPMetricDepthMap
    let heatmapImage: CGImage
    let validMaskImage: CGImage
    let heatmapOpacity: Double
    let comparisonPosition: Double?
    let onComparisonPositionChanged: (Double) -> Void
    let planeRegion: TAPPlaneRegion?
    let partialPlaneGridCells: [TAPPlaneGridCell]
    let planeGridProgress: Double?
    let planeSeedPoint: CGPoint?
    let highlightPalette: AnalysisHighlightPalette
    let isPlaneGridAnimationEnabled: Bool
    let metadataSummary: CaptureMetadataSummary?
    let scoreSummary: DepthAnalysisScoreSummary?
    let onSelectionCleared: () -> Void
    let onPlaneSeedSelected: (CGPoint) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            stageContent

            #if DEBUG
            if let metadataSummary {
                CaptureMetadataHUD(
                    summary: metadataSummary,
                    scoreSummary: scoreSummary
                )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            #endif
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch viewMode {
        case .rgb:
            depthImageStage(overlayImage: nil, overlayOpacity: 0)
        case .heatmap:
            depthImageStage(
                overlayImage: heatmapImage,
                overlayOpacity: heatmapOpacity
            )
        case .mask:
            depthImageStage(
                overlayImage: validMaskImage,
                overlayOpacity: 1
            )
        case .planes:
            depthImageStage(
                overlayImage: heatmapImage,
                overlayOpacity: heatmapOpacity,
                planeRegion: planeRegion,
                partialPlaneGridCells: partialPlaneGridCells,
                planeGridProgress: planeGridProgress,
                planeSeedPoint: planeSeedPoint,
                comparisonPosition: comparisonPosition,
                isPointSelectionEnabled: true,
                onPointSelected: onPlaneSeedSelected
            )
        case .pointCloud:
            PointCloudPreview(
                depthMap: depthMap,
                orientation: imageOrientation,
                selection: .constant(nil),
                interactionState: .idle,
                allowsSelection: false,
                onSelectionBegan: { _ in },
                onSelectionChanged: { _ in },
                onSelectionEnded: { _ in },
                onSelectionCleared: onSelectionCleared
            )
            .background(Color.black)
        }
    }

    private func depthImageStage(
        overlayImage: CGImage?,
        overlayOpacity: Double,
        planeRegion: TAPPlaneRegion? = nil,
        partialPlaneGridCells: [TAPPlaneGridCell] = [],
        planeGridProgress: Double? = nil,
        planeSeedPoint: CGPoint? = nil,
        comparisonPosition: Double? = nil,
        isPointSelectionEnabled: Bool = false,
        onPointSelected: ((CGPoint) -> Void)? = nil
    ) -> some View {
        InteractiveDepthImage(
            image: image,
            overlayImage: overlayImage,
            overlayOpacity: overlayOpacity,
            comparisonPosition: comparisonPosition,
            onComparisonPositionChanged: onComparisonPositionChanged,
            orientation: imageOrientation,
            depthSize: CGSize(width: depthMap.width, height: depthMap.height),
            planeOverlays: [],
            planeRegion: planeRegion,
            partialPlaneGridCells: partialPlaneGridCells,
            planeGridProgress: planeGridProgress,
            planeSeedPoint: planeSeedPoint,
            highlightPalette: highlightPalette,
            isPlaneGridAnimationEnabled: isPlaneGridAnimationEnabled,
            isPointSelectionEnabled: isPointSelectionEnabled,
            onSelectionCleared: onSelectionCleared,
            onPointSelected: { depthPoint in
                onPointSelected?(depthPoint)
            }
        )
    }
}
