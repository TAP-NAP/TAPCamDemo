//
//  TAPVideoRecorderDiagnostics.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        let captureID = captureID
        let map = depthData.depthDataMap
        TAPDiagnostics.cameraCapture.info("video depth output first sample captureID=\(captureID, privacy: .private) pixelFormat=\(TAPFourCharCode.string(from: CVPixelBufferGetPixelFormatType(map)), privacy: .public) width=\(CVPixelBufferGetWidth(map), privacy: .public) height=\(CVPixelBufferGetHeight(map), privacy: .public) sourceRowStride=\(CVPixelBufferGetBytesPerRow(map), privacy: .public) timestamp=\(CMTimeGetSeconds(timestamp), privacy: .public) filtered=\(depthData.isDepthDataFiltered, privacy: .public) calibration=\(depthData.cameraCalibrationData != nil, privacy: .public)")
        #endif
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        let captureID = captureID
        TAPDiagnostics.cameraCapture.error("video depth metadata append failed captureID=\(captureID, privacy: .private) writerStatus=\(writerSession.status.rawValue, privacy: .public) writerError=\(writerSession.error.map(TAPDiagnostics.describe) ?? "none", privacy: .public)")
        #endif
    }

    func logDepthDropIfNeeded(
        reason: AVCaptureOutput.DataDroppedReason,
        dropCount: Int
    ) {
        guard dropCount == 1 || dropCount.isMultiple(of: 30) else {
            return
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("video depth output dropped captureID=\(self.captureID, privacy: .private) dropCount=\(dropCount, privacy: .public) reason=\(Self.depthDropReasonDescription(reason), privacy: .public)")
        #endif
    }

    private static func depthDropReasonDescription(
        _ reason: AVCaptureOutput.DataDroppedReason
    ) -> String {
        switch reason {
        case .none: "none"
        case .lateData: "lateData"
        case .outOfBuffers: "outOfBuffers"
        case .discontinuity: "discontinuity"
        @unknown default: "unknown-\(reason.rawValue)"
        }
    }
}
