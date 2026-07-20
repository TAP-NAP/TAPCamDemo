//
//  TAPVideoRecorderCaptureCallbacks.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Adapts AVCapture callbacks into the recorder's serialized append methods.
nonisolated extension TAPVideoRecorder {
    func handleDroppedSampleBuffer(
        _ output: AVCaptureOutput,
        sampleBuffer: CMSampleBuffer,
        connection: AVCaptureConnection
    ) {
        _ = sampleBuffer
        _ = connection
        if output is AVCaptureAudioDataOutput {
            metrics.audioDropCount += 1
        } else {
            metrics.videoDropCount += 1
        }
    }

    func handleOutputSampleBuffer(
        _ output: AVCaptureOutput,
        sampleBuffer: CMSampleBuffer,
        connection: AVCaptureConnection
    ) {
        _ = connection
        if output is AVCaptureAudioDataOutput {
            appendAudioSample(sampleBuffer)
        } else {
            appendVideoSample(sampleBuffer)
        }
    }

    func handleSynchronizedDataCollection(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        _ = synchronizer
        observeSynchronizedPair(in: synchronizedDataCollection)
        appendSynchronizedVideo(in: synchronizedDataCollection)
        appendSynchronizedDepth(in: synchronizedDataCollection)
    }

    func handleDepthData(
        _ output: AVCaptureDepthDataOutput,
        depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        appendDepthSample(depthData, timestamp: timestamp)
    }

    func handleDroppedDepthData(
        _ output: AVCaptureDepthDataOutput,
        depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection,
        reason: AVCaptureOutput.DataDroppedReason
    ) {
        _ = output
        _ = depthData
        _ = connection
        metrics.depthOutputDropCount += 1
        recordDepthGap(reason: .outputDrop, at: timestamp)
        diagnostics.logDepthDropIfNeeded(
            reason: reason,
            dropCount: metrics.depthOutputDropCount
        )
    }

    private func observeSynchronizedPair(
        in collection: AVCaptureSynchronizedDataCollection
    ) {
        guard let synchronizedVideoOutput,
              let synchronizedDepthOutput,
              let videoData = collection.synchronizedData(for: synchronizedVideoOutput)
                as? AVCaptureSynchronizedSampleBufferData,
              let depthData = collection.synchronizedData(for: synchronizedDepthOutput)
                as? AVCaptureSynchronizedDepthData,
              !videoData.sampleBufferWasDropped,
              !depthData.depthDataWasDropped else {
            return
        }
        metrics.observedSynchronizedRGBDepthPair = true
        let videoTime = CMSampleBufferGetPresentationTimeStamp(videoData.sampleBuffer)
        let delta = abs(CMTimeGetSeconds(CMTimeSubtract(depthData.timestamp, videoTime)))
        if delta.isFinite {
            metrics.maxObservedRGBDepthDeltaSeconds = max(
                metrics.maxObservedRGBDepthDeltaSeconds ?? 0,
                delta
            )
        }
    }

    private func appendSynchronizedVideo(
        in collection: AVCaptureSynchronizedDataCollection
    ) {
        guard let synchronizedVideoOutput,
              let videoData = collection.synchronizedData(for: synchronizedVideoOutput)
                as? AVCaptureSynchronizedSampleBufferData else {
            return
        }
        if videoData.sampleBufferWasDropped {
            metrics.videoDropCount += 1
        } else {
            appendVideoSample(videoData.sampleBuffer)
        }
    }

    private func appendSynchronizedDepth(
        in collection: AVCaptureSynchronizedDataCollection
    ) {
        guard let synchronizedDepthOutput,
              let depthData = collection.synchronizedData(for: synchronizedDepthOutput)
                as? AVCaptureSynchronizedDepthData else {
            return
        }
        if depthData.depthDataWasDropped {
            metrics.depthOutputDropCount += 1
            recordDepthGap(reason: .outputDrop, at: depthData.timestamp)
            diagnostics.logDepthDropIfNeeded(
                reason: depthData.droppedReason,
                dropCount: metrics.depthOutputDropCount
            )
        } else {
            appendDepthSample(depthData.depthData, timestamp: depthData.timestamp)
        }
    }
}

nonisolated final class TAPVideoRecorderCallbackRouter: @unchecked Sendable {
    fileprivate weak var recorder: TAPVideoRecorder?

    func bind(to recorder: TAPVideoRecorder) {
        self.recorder = recorder
    }
}

nonisolated final class TAPVideoRecorderOutputDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureDataOutputSynchronizerDelegate,
    AVCaptureDepthDataOutputDelegate,
    @unchecked Sendable {
    private let router: TAPVideoRecorderCallbackRouter

    init(router: TAPVideoRecorderCallbackRouter) {
        self.router = router
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        router.recorder?.handleDroppedSampleBuffer(
            output,
            sampleBuffer: sampleBuffer,
            connection: connection
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        router.recorder?.handleOutputSampleBuffer(
            output,
            sampleBuffer: sampleBuffer,
            connection: connection
        )
    }

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        router.recorder?.handleSynchronizedDataCollection(
            synchronizer,
            synchronizedDataCollection: synchronizedDataCollection
        )
    }

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        router.recorder?.handleDepthData(
            output,
            depthData: depthData,
            timestamp: timestamp,
            connection: connection
        )
    }

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didDrop depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection,
        reason: AVCaptureOutput.DataDroppedReason
    ) {
        router.recorder?.handleDroppedDepthData(
            output,
            depthData: depthData,
            timestamp: timestamp,
            connection: connection,
            reason: reason
        )
    }
}
