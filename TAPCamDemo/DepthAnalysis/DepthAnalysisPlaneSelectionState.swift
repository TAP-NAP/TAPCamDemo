//
//  DepthAnalysisPlaneSelectionState.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation

/// Planes-mode seed selection and synchronous UI state.
///
/// This model owns only local UI state for an already-loaded depth map. It does
/// not build geometry caches, run async detector tasks, read Photos or pending
/// storage, inspect manifests/proofs, or write export state.
nonisolated struct DepthAnalysisPlaneSelectionState {
    static let minimumStrictness = 0.35
    static let maximumStrictness = 0.95
    static let defaultStrictness = 0.68

    var strictness = Self.defaultStrictness
    var generationID = 0
    var seedPoint: CGPoint?
    var selectedRegion: TAPPlaneRegion?
    var partialGridCells: [TAPPlaneGridCell] = []
    var gridProgress: Double?
    var completedGridToastID: UUID?
    var isDetecting = false
    var errorMessage: String?

    var hasSeed: Bool {
        seedPoint != nil
    }

    @discardableResult
    mutating func selectSeed(_ depthPoint: CGPoint, depthMap: TAPMetricDepthMap) -> Int {
        generationID += 1
        seedPoint = clampedPoint(depthPoint, depthMap: depthMap)
        selectedRegion = nil
        partialGridCells = []
        gridProgress = nil
        completedGridToastID = nil
        isDetecting = true
        errorMessage = nil
        return generationID
    }

    mutating func updateStrictness(_ value: Double) {
        strictness = min(max(value, Self.minimumStrictness), Self.maximumStrictness)
    }

    mutating func startDetection(generationID eventGenerationID: Int) {
        guard eventGenerationID == generationID else {
            return
        }
        selectedRegion = nil
        partialGridCells = []
        gridProgress = nil
        completedGridToastID = nil
        isDetecting = true
        errorMessage = nil
    }

    mutating func applyPartialGrid(_ progress: TAPPlaneGridProgress, generationID eventGenerationID: Int) {
        guard eventGenerationID == generationID,
              isDetecting,
              selectedRegion == nil else {
            return
        }
        partialGridCells = progress.gridCells
        gridProgress = min(max(progress.progress, 0), 1)
        errorMessage = nil
    }

    mutating func finishDetection(
        _ detection: DepthAnalysisPlaneRegionDetection,
        generationID eventGenerationID: Int
    ) {
        guard eventGenerationID == generationID else {
            return
        }
        selectedRegion = detection.region
        partialGridCells = []
        gridProgress = 1
        completedGridToastID = UUID()
        isDetecting = false
        errorMessage = nil
    }

    mutating func finishFailure(_ error: Error, generationID eventGenerationID: Int) {
        guard eventGenerationID == generationID else {
            return
        }
        selectedRegion = nil
        partialGridCells = []
        gridProgress = nil
        completedGridToastID = nil
        isDetecting = false
        // The Plane Filter inspector renders this string directly, so raw
        // detector/localized errors stop at the presentation boundary here.
        errorMessage = DepthAnalysisErrorPresentation.planeSelectionErrorMessage(for: error)
    }

    mutating func cancelDetection(generationID eventGenerationID: Int? = nil) {
        if let eventGenerationID, eventGenerationID != generationID {
            return
        }
        isDetecting = false
    }

    mutating func clearDetection() {
        selectedRegion = nil
        partialGridCells = []
        gridProgress = nil
        completedGridToastID = nil
        isDetecting = false
        errorMessage = nil
    }

    mutating func clear() {
        generationID += 1
        seedPoint = nil
        clearDetection()
    }

    mutating func dismissCompletedGridToast(_ toastID: UUID) {
        guard completedGridToastID == toastID else {
            return
        }
        completedGridToastID = nil
    }

    private func clampedPoint(_ point: CGPoint, depthMap: TAPMetricDepthMap) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), CGFloat(max(depthMap.width - 1, 0))),
            y: min(max(point.y, 0), CGFloat(max(depthMap.height - 1, 0)))
        )
    }
}
