//
//  CaptureJobMetrics.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// Performance and status record for one capture job.
///
/// Debug UI reads these values to show where time is spent across capture,
/// package build, embedded HEIC packaging, and Photos writing.
nonisolated struct CaptureJobMetrics: Identifiable, Equatable, Sendable {
    let id: UUID
    let captureDuration: TimeInterval?
    let packageBuildDuration: TimeInterval?
    let packagingDuration: TimeInterval?
    let packagingMetrics: CapturePackagingMetrics?
    let writeDuration: TimeInterval?
    let totalDuration: TimeInterval
    let queueWaitDuration: TimeInterval?
    let pendingJobCount: Int
    let status: CaptureJobStatus
    let failureReason: String?
    let pairingMode: String?
    let selectedRGBSource: String?
    let selectedDepthSource: String?
    let currentZoomFactor: Double?
    let cropMode: String?
    let cropRectNormalized: CropRectNormalized?
}

/// Fine-grained timings for the embedded HEIC packaging step.
///
/// These fields break down `CaptureJobMetrics.packagingDuration` so Debug can
/// show whether time is spent in HEIC materialization, digest work, App Attest,
/// or XMP metadata insertion.
nonisolated struct CapturePackagingMetrics: Equatable, Sendable {
    var manifestBuildDuration: TimeInterval?
    var baseHEICDuration: TimeInterval?
    var rgbDigestDuration: TimeInterval?
    var depthDigestDuration: TimeInterval?
    var metadataDigestDuration: TimeInterval?
    var appAttestDuration: TimeInterval?
    var xmpInjectDuration: TimeInterval?
    var xmpVerifyDuration: TimeInterval?

    var hasRecordedValue: Bool {
        [
            manifestBuildDuration,
            baseHEICDuration,
            rgbDigestDuration,
            depthDigestDuration,
            metadataDigestDuration,
            appAttestDuration,
            xmpInjectDuration,
            xmpVerifyDuration
        ].contains { $0 != nil }
    }
}

nonisolated enum CaptureJobStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

/// Thread-safe rolling metrics store for Debug diagnostics.
actor MetricsStore {
    private var values: [CaptureJobMetrics] = []
    private let limit: Int

    init(limit: Int = 8) {
        self.limit = limit
    }

    func record(_ metrics: CaptureJobMetrics) {
        values.insert(metrics, at: 0)
        if values.count > limit {
            values.removeLast(values.count - limit)
        }
    }

    func recent() -> [CaptureJobMetrics] {
        values
    }
}
