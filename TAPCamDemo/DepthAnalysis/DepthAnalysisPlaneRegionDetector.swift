//
//  DepthAnalysisPlaneRegionDetector.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation

/// Result of a seed-plane request.
///
/// The detector returns the geometry cache it used so `DepthAnalysisViewModel`
/// can keep tap-time cache construction reusable without knowing how the cache
/// is built.
nonisolated struct DepthAnalysisPlaneRegionDetection {
    let region: TAPPlaneRegion
    let geometryCache: TAPDepthGeometryCache?
}

/// Builds the reusable camera-space geometry and grows a plane region.
///
/// This type is intentionally analysis-only. It does not read Photos, write
/// exports, validate provenance, or change App Attest state. Callers provide a
/// loaded `TAPMetricDepthMap` and receive local analysis products.
nonisolated struct DepthAnalysisPlaneRegionDetector {
    typealias GeometryCacheBuilder = (TAPMetricDepthMap, () -> Bool) throws -> TAPDepthGeometryCache?
    typealias PlaneRegionGrower = (
        TAPMetricDepthMap,
        CGPoint,
        Double,
        TAPDepthGeometryCache?,
        () -> Bool,
        (TAPPlaneGridProgress) -> Void
    ) throws -> TAPPlaneRegion

    private let geometryCacheBuilder: GeometryCacheBuilder
    private let planeRegionGrower: PlaneRegionGrower

    init(
        geometryCacheBuilder: @escaping GeometryCacheBuilder = { depthMap, shouldCancel in
            try TAPDepthGeometryProjector.geometryCache(
                for: depthMap,
                shouldCancel: shouldCancel
            )
        },
        planeRegionGrower: @escaping PlaneRegionGrower = { depthMap, seed, strictness, geometryCache, shouldCancel, progressHandler in
            try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: seed,
                strictness: strictness,
                geometryCache: geometryCache,
                shouldCancel: shouldCancel,
                progressHandler: progressHandler
            )
        }
    ) {
        self.geometryCacheBuilder = geometryCacheBuilder
        self.planeRegionGrower = planeRegionGrower
    }

    func prewarmGeometry(for depthMap: TAPMetricDepthMap) throws -> TAPDepthGeometryCache? {
        try geometryCacheBuilder(depthMap, { Task.isCancelled })
    }

    func detectRegion(
        depthMap: TAPMetricDepthMap,
        seed: CGPoint,
        strictness: Double,
        geometryCache: TAPDepthGeometryCache?,
        progressHandler: @escaping (TAPPlaneGridProgress) -> Void = { _ in }
    ) throws -> DepthAnalysisPlaneRegionDetection {
        let preparedGeometryCache = try preparedGeometryCache(
            for: depthMap,
            preferredGeometryCache: geometryCache
        )
        let region = try planeRegionGrower(
            depthMap,
            seed,
            strictness,
            preparedGeometryCache,
            { Task.isCancelled },
            progressHandler
        )
        return DepthAnalysisPlaneRegionDetection(
            region: region,
            geometryCache: preparedGeometryCache
        )
    }

    private func preparedGeometryCache(
        for depthMap: TAPMetricDepthMap,
        preferredGeometryCache: TAPDepthGeometryCache?
    ) throws -> TAPDepthGeometryCache? {
        if let preferredGeometryCache, preferredGeometryCache.matches(depthMap: depthMap) {
            return preferredGeometryCache
        }

        return try geometryCacheBuilder(depthMap, { Task.isCancelled })
    }
}
