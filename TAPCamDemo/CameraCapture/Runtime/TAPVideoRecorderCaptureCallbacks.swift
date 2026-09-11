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
    private let depthOutput: AVCaptureDepthDataOutput
    private weak var manualFocusPreviewStream: CameraManualFocusPreviewStream?

    /// Accessed only on `callbackQueue`.
    private var recorder: TAPVideoRecorder?
    private var previewHandler: (@Sendable (CMSampleBuffer, AVDepthData) -> Void)?

    init(
        videoOutput: AVCaptureVideoDataOutput,
        depthOutput: AVCaptureDepthDataOutput,
        manualFocusPreviewStream: CameraManualFocusPreviewStream?,
        previewHandler: (@Sendable (CMSampleBuffer, AVDepthData) -> Void)? = nil
    ) {
        self.videoOutput = videoOutput
        self.depthOutput = depthOutput
        self.manualFocusPreviewStream = manualFocusPreviewStream
        self.previewHandler = previewHandler
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

    /// The preview consumer must enqueue bounded work and return promptly;
    /// this queue also owns AVFoundation's synchronized output callbacks.
    func setPreviewHandler(_ handler: (@Sendable (CMSampleBuffer, AVDepthData) -> Void)?) {
        callbackQueue.sync {
            previewHandler = handler
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
            if let previewHandler,
               let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput)
                    as? AVCaptureSynchronizedDepthData,
               !depthData.depthDataWasDropped {
                previewHandler(videoData.sampleBuffer, depthData.depthData)
            }
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
        } else {
            appendDepthSample(depthData.depthData, timestamp: depthData.timestamp)
        }
    }
}
