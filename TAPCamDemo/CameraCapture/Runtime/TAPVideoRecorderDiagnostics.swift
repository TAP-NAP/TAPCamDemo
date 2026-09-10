//
//  TAPVideoRecorderDiagnostics.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import OSLog

nonisolated struct TAPVideoRecorderDiagnostics {
    private let captureID: String
    private var hasLoggedFirstDepthSample = false
    private var hasLoggedDepthMetadataInputUnavailable = false
    private var hasLoggedDepthMetadataAppendFailure = false

    init(captureID: String) {
        self.captureID = captureID
    }

    mutating func logFirstDepthSampleIfNeeded(
        _ depthData: AVDepthData,
        timestamp: CMTime
    ) {
        guard !hasLoggedFirstDepthSample else {
            return
        }
        hasLoggedFirstDepthSample = true
        let timestampSeconds = CMTimeGetSeconds(timestamp)
        TAPVideoPerformanceTrace.emitCaptureFirstDepth(
            timestampSeconds: timestampSeconds.isFinite ? timestampSeconds : -1
        )
        TAPVideoPerformanceTrace.emitRuntimeCheckpoint(stage: "capture-first-depth")
    }

    func emitRuntimeCheckpoint(
        stage: String,
        metrics: TAPVideoRecordingMetrics
    ) {
        TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
            stage: stage,
            rgbFrames: metrics.videoFrameCount,
            videoDrops: metrics.videoDropCount,
            audioSamples: metrics.audioSampleCount,
            audioDrops: metrics.audioDropCount,
            depthDelivered: metrics.depthDeliveredSampleCount,
            depthStored: metrics.depthSampleCount,
            depthOutputDrops: metrics.depthOutputDropCount,
            depthMetadataDrops: metrics.depthMetadataDropCount,
            depthEncodingDrops: metrics.depthEncodingDropCount
        )
    }

    mutating func logDepthMetadataInputUnavailableIfNeeded(
        reason: String,
        writerSession: TAPVideoWriterSession
    ) {
        guard !hasLoggedDepthMetadataInputUnavailable else {
            return
        }
        hasLoggedDepthMetadataInputUnavailable = true
        #if DEBUG
        let captureID = captureID
        TAPDiagnostics.cameraCapture.error("video depth metadata input unavailable captureID=\(captureID, privacy: .private) reason=\(reason, privacy: .public) writerStatus=\(writerSession.status.rawValue, privacy: .public) writerError=\(writerSession.error.map(TAPDiagnostics.describe) ?? "none", privacy: .public)")
        #endif
    }

    mutating func logDepthMetadataAppendFailureIfNeeded(
        writerSession: TAPVideoWriterSession
    ) {
        guard !hasLoggedDepthMetadataAppendFailure else {
            return
        }
        hasLoggedDepthMetadataAppendFailure = true
        #if DEBUG
        let captureID = captureID
        TAPDiagnostics.cameraCapture.error("video depth metadata append failed captureID=\(captureID, privacy: .private) writerStatus=\(writerSession.status.rawValue, privacy: .public) writerError=\(writerSession.error.map(TAPDiagnostics.describe) ?? "none", privacy: .public)")
        #endif
    }
}
