//
//  DepthAnalysisRegionSelectionState.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation

/// Rectangular region-selection state and its synchronous analysis products.
///
/// This model is deliberately local to already-loaded depth data. It does not
/// read Photos, pending capture storage, manifests, proofs, or export state.
nonisolated struct DepthAnalysisRegionSelectionState {
    var selectionRect: CGRect?
    var interactionState: AnalysisInteractionState = .idle
    var regionStats: TAPDepthRegionStats?
    var regionHeatmap: TAPDepthHeatmapVisualization?
    var regionHeatmapErrorMessage: String?
    var planeEstimate: TAPPlaneEstimate?

    mutating func beginSelection(_ depthRect: CGRect, depthMap: TAPMetricDepthMap?) {
        selectionRect = clampedSelection(depthRect, depthMap: depthMap)
        interactionState = .drawingSelection
        clearProducts()
    }

    mutating func previewSelection(_ depthRect: CGRect, depthMap: TAPMetricDepthMap?) {
        selectionRect = clampedSelection(depthRect, depthMap: depthMap)
        interactionState = .drawingSelection
    }

    mutating func finishSelection(_ depthRect: CGRect, depthMap: TAPMetricDepthMap?) {
        let rect = clampedSelection(depthRect, depthMap: depthMap)
        selectionRect = rect
        interactionState = .regionSelected
        updateProducts(rect, depthMap: depthMap)
    }

    mutating func clear() {
        selectionRect = nil
        interactionState = .idle
        clearProducts()
    }

    private mutating func clearProducts() {
        regionStats = nil
        planeEstimate = nil
        regionHeatmap = nil
        regionHeatmapErrorMessage = nil
    }

    private mutating func updateProducts(_ depthRect: CGRect, depthMap: TAPMetricDepthMap?) {
        guard let depthMap else {
            clearProducts()
            return
        }

        regionStats = TAPDepthGeometryProjector.stats(for: depthMap, in: depthRect)
        planeEstimate = TAPPlaneEstimator.estimatePlane(depthMap: depthMap, region: depthRect)

        do {
            regionHeatmap = try TAPDepthHeatmapRenderer.heatmap(for: depthMap, region: depthRect)
            regionHeatmapErrorMessage = nil
        } catch {
            regionHeatmap = nil
            regionHeatmapErrorMessage = DepthAnalysisErrorPresentation.regionHeatmapErrorMessage
        }
    }

    private func clampedSelection(_ rect: CGRect, depthMap: TAPMetricDepthMap?) -> CGRect {
        guard let depthMap else {
            return rect
        }

        let fullRect = CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
        let clamped = rect.intersection(fullRect)
        if clamped.isNull || clamped.width <= 0 || clamped.height <= 0 {
            return CGRect(x: 0, y: 0, width: min(1, depthMap.width), height: min(1, depthMap.height))
        }
        return clamped
    }
}
