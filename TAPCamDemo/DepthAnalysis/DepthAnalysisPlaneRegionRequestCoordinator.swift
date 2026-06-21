//
//  DepthAnalysisPlaneRegionRequestCoordinator.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import CoreGraphics
import Foundation

/// Main-actor events emitted by the async Planes request coordinator.
enum DepthAnalysisPlaneRegionRequestEvent {
    case started
    case succeeded(DepthAnalysisPlaneRegionDetection)
    case failed(Error)
    case cancelled
}

/// Owns Planes-mode async request freshness and reusable geometry cache state.
///
/// The coordinator receives only already-loaded depth maps and depth-space seed
/// points. It does not read Photos or pending storage, inspect manifests or
/// proofs, write exports, or change App Attest state.
@MainActor
final class DepthAnalysisPlaneRegionRequestCoordinator {
    typealias EventHandler = @MainActor (DepthAnalysisPlaneRegionRequestEvent) -> Void

    private let detector: DepthAnalysisPlaneRegionDetector
    private var regionTask: Task<Void, Never>?
    private var regionRequestID = UUID()
    private var regionEventHandler: EventHandler?

    // Image-level geometry shared by Planes taps. It is prewarmed after load and
    // can also be built by the first tap if prewarm has not finished yet.
    private var geometryCache: TAPDepthGeometryCache?
    private var geometryTask: Task<Void, Never>?
    private var geometryRequestID = UUID()

    init(detector: DepthAnalysisPlaneRegionDetector = DepthAnalysisPlaneRegionDetector()) {
        self.detector = detector
    }

    deinit {
        regionTask?.cancel()
        geometryTask?.cancel()
    }

    func resetForNewInput() {
        cancelRegionRequest()
        geometryTask?.cancel()
        geometryTask = nil
        geometryRequestID = UUID()
        geometryCache = nil
    }

    func cancelRegionRequest() {
        regionTask?.cancel()
        regionTask = nil
        regionRequestID = UUID()
        regionEventHandler = nil
    }

    func prewarmGeometry(for depthMap: TAPMetricDepthMap) {
        let requestID = UUID()
        geometryTask?.cancel()
        geometryRequestID = requestID
        geometryCache = nil
        let detector = detector

        // This shifts the image-level projection/normal work out of the first
        // tap whenever the user pauses briefly after choosing a photo.
        geometryTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let cache = try detector.prewarmGeometry(for: depthMap)
                try Task.checkCancellation()
                await self?.finishGeometryPrewarm(requestID, cache: cache)
            } catch is CancellationError {
                await self?.finishGeometryPrewarm(requestID, cache: nil)
            } catch {
                await self?.finishGeometryPrewarm(requestID, cache: nil)
            }
        }
    }

    func requestRegion(
        depthMap: TAPMetricDepthMap,
        seed: CGPoint,
        strictness: Double,
        debounceNanoseconds: UInt64 = 0,
        eventHandler: @escaping EventHandler
    ) {
        let requestID = UUID()
        let preparedGeometryCache = geometryCache
        let detector = detector

        regionTask?.cancel()
        regionRequestID = requestID
        regionEventHandler = eventHandler

        if preparedGeometryCache == nil {
            // The tap now owns cache construction; cancel utility prewarm so the
            // same camera-space points are not computed twice.
            geometryTask?.cancel()
            geometryTask = nil
            geometryRequestID = UUID()
        }

        eventHandler(.started)
        regionTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if debounceNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                }

                let detection = try detector.detectRegion(
                    depthMap: depthMap,
                    seed: seed,
                    strictness: strictness,
                    geometryCache: preparedGeometryCache
                )
                try Task.checkCancellation()
                await self?.finishRegionRequest(requestID, result: .success(detection))
            } catch is CancellationError {
                await self?.finishCancelledRegionRequest(requestID)
            } catch let error as TAPPlaneGrowthError {
                await self?.finishRegionRequest(requestID, result: .failure(error))
            } catch {
                await self?.finishRegionRequest(requestID, result: .failure(error))
            }
        }
    }

    private func finishGeometryPrewarm(_ requestID: UUID, cache: TAPDepthGeometryCache?) {
        guard geometryRequestID == requestID else {
            return
        }

        geometryTask = nil
        geometryCache = cache
    }

    private func finishRegionRequest(_ requestID: UUID, result: Result<DepthAnalysisPlaneRegionDetection, Error>) {
        guard regionRequestID == requestID else {
            return
        }

        regionTask = nil
        switch result {
        case .success(let detection):
            if let geometryCache = detection.geometryCache {
                self.geometryCache = geometryCache
            }
            regionEventHandler?(.succeeded(detection))
        case .failure(let error):
            regionEventHandler?(.failed(error))
        }
        regionEventHandler = nil
    }

    private func finishCancelledRegionRequest(_ requestID: UUID) {
        guard regionRequestID == requestID else {
            return
        }

        regionTask = nil
        regionEventHandler?(.cancelled)
        regionEventHandler = nil
    }
}
