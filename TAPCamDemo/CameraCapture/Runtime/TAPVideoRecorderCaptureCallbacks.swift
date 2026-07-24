//
//  TAPVideoRecorderCaptureCallbacks.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Keeps one already-committed RGB/depth graph and callback queue flowing from
/// VIDEO warmup through recording.
///
/// `AVCaptureDataOutputSynchronizer` overrides the delegates of its data
/// outputs. Replacing its delegate and callback queue while the graph is live
/// can strand the first recording without samples. This router remains the
/// synchronizer delegate for the graph's entire lifetime and switches only its
/// software consumer. When PRO shares the MF RGB output, it also fans the RGB
/// sample back to the loupe renderer.
nonisolated final class TAPVideoGraphOutputRouter: NSObject,
    AVCaptureDataOutputSynchronizerDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    let callbackQueue: DispatchQueue

    private let videoOutput: AVCaptureVideoDataOutput
    private weak var manualFocusPreviewStream: CameraManualFocusPreviewStream?

    /// Accessed only on `callbackQueue`.
    private var recorder: TAPVideoRecorder?

    init(
        videoOutput: AVCaptureVideoDataOutput,
        manualFocusPreviewStream: CameraManualFocusPreviewStream?
    ) {
        self.videoOutput = videoOutput
        self.manualFocusPreviewStream = manualFocusPreviewStream
        callbackQueue = manualFocusPreviewStream?.sharedVideoCallbackQueue
            ?? DispatchQueue(
                label: "tapcam.camera-capture.video-graph-router",
                qos: .userInitiated
            )
        super.init()
    }

    /// Ordered behind any already-delivered warmup callbacks so the first
    /// callback after this method returns belongs to the recorder.
    func activate(_ recorder: TAPVideoRecorder) {
        callbackQueue.sync {
            self.recorder = recorder
        }
    }

    /// Drains all callbacks already enqueued for the recorder before teardown.
    func deactivateRecorder() {
        callbackQueue.sync {
            recorder = nil
        }
    }

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        if let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput)
            as? AVCaptureSynchronizedSampleBufferData,
           !videoData.sampleBufferWasDropped {
            manualFocusPreviewStream?.consumeSharedVideoSample(videoData.sampleBuffer)
        }
        recorder?.handleSynchronizedDataCollection(
            synchronizer,
            synchronizedDataCollection: synchronizedDataCollection
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        recorder?.handleOutputSampleBuffer(
            output,
            sampleBuffer: sampleBuffer,
            connection: connection
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        recorder?.handleDroppedSampleBuffer(
            output,
            sampleBuffer: sampleBuffer,
            connection: connection
        )
    }
}

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
