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

    var strictness = 0.68
    var seedPoint: CGPoint?
    var selectedRegion: TAPPlaneRegion?
    var isDetecting = false
    var errorMessage: String?

    var hasSeed: Bool {
        seedPoint != nil
    }

    mutating func selectSeed(_ depthPoint: CGPoint, depthMap: TAPMetricDepthMap) {
        seedPoint = clampedPoint(depthPoint, depthMap: depthMap)
    }

    mutating func updateStrictness(_ value: Double) {
        strictness = min(max(value, Self.minimumStrictness), Self.maximumStrictness)
    }

    mutating func startDetection() {
        selectedRegion = nil
        isDetecting = true
        errorMessage = nil
    }

    mutating func finishDetection(_ detection: DepthAnalysisPlaneRegionDetection) {
        selectedRegion = detection.region
        isDetecting = false
        errorMessage = nil
    }

    mutating func finishFailure(_ error: Error) {
        selectedRegion = nil
        isDetecting = false
        // The Plane Filter inspector renders this string directly, so raw
        // detector/localized errors stop at the presentation boundary here.
        errorMessage = DepthAnalysisErrorPresentation.planeSelectionErrorMessage(for: error)
    }

    mutating func cancelDetection() {
        isDetecting = false
    }

    mutating func clearDetection() {
        selectedRegion = nil
        isDetecting = false
        errorMessage = nil
    }

    mutating func clear() {
        seedPoint = nil
        clearDetection()
    }

    private func clampedPoint(_ point: CGPoint, depthMap: TAPMetricDepthMap) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), CGFloat(max(depthMap.width - 1, 0))),
            y: min(max(point.y, 0), CGFloat(max(depthMap.height - 1, 0)))
        )
    }
}
