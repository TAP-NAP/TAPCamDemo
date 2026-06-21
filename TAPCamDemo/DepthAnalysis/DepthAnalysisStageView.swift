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
/// user gestures. It does not receive source identifiers, HEIC bytes, manifests,
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
    @Binding var selection: CGRect?
    let interactionState: AnalysisInteractionState
    let planeRegion: TAPPlaneRegion?
    let planeSeedPoint: CGPoint?
    let metadataSummary: CaptureMetadataSummary?
    let onSelectionBegan: (CGRect) -> Void
    let onSelectionChanged: (CGRect) -> Void
    let onSelectionEnded: (CGRect) -> Void
    let onSelectionCleared: () -> Void
    let onPlaneSeedSelected: (CGPoint) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            stageContent

            #if DEBUG
            if let metadataSummary {
                CaptureMetadataHUD(summary: metadataSummary)
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
            depthImageStage(overlayImage: heatmapImage, overlayOpacity: heatmapOpacity)
        case .mask:
            depthImageStage(overlayImage: validMaskImage, overlayOpacity: 1)
        case .planes:
            depthImageStage(
                overlayImage: heatmapImage,
                overlayOpacity: heatmapOpacity,
                planeRegion: planeRegion,
                planeSeedPoint: planeSeedPoint,
                isSelectionEnabled: false,
                isPointSelectionEnabled: true,
                onPointSelected: onPlaneSeedSelected
            )
        case .pointCloud:
            PointCloudPreview(
                depthMap: depthMap,
                orientation: imageOrientation,
                selection: $selection,
                interactionState: interactionState,
                onSelectionBegan: onSelectionBegan,
                onSelectionChanged: onSelectionChanged,
                onSelectionEnded: onSelectionEnded,
                onSelectionCleared: onSelectionCleared
            )
            .background(Color.black)
        }
    }

    private func depthImageStage(
        overlayImage: CGImage?,
        overlayOpacity: Double,
        planeRegion: TAPPlaneRegion? = nil,
        planeSeedPoint: CGPoint? = nil,
        isSelectionEnabled: Bool = true,
        isPointSelectionEnabled: Bool = false,
        onPointSelected: ((CGPoint) -> Void)? = nil
    ) -> some View {
        InteractiveDepthImage(
            image: image,
            overlayImage: overlayImage,
            overlayOpacity: overlayOpacity,
            orientation: imageOrientation,
            depthSize: CGSize(width: depthMap.width, height: depthMap.height),
            selection: $selection,
            interactionState: interactionState,
            planeOverlays: [],
            planeRegion: planeRegion,
            planeSeedPoint: planeSeedPoint,
            isSelectionEnabled: isSelectionEnabled,
            isPointSelectionEnabled: isPointSelectionEnabled,
            onSelectionBegan: onSelectionBegan,
            onSelectionChanged: onSelectionChanged,
            onSelectionEnded: onSelectionEnded,
            onSelectionCleared: onSelectionCleared,
            onPointSelected: { depthPoint in
                onPointSelected?(depthPoint)
            }
        )
    }
}
