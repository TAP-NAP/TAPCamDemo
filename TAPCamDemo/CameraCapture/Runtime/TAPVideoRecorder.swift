//
//  TAPVideoRecorder.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import OSLog

nonisolated struct TAPVideoRecordingRequest: Sendable {
    static let defaultMaximumDuration: TimeInterval = 180

    let captureID: String
    let packageID: UUID
    let capturedAt: Date
    let outputURL: URL
    let maximumDuration: TimeInterval
    let videoRotationAngle: CGFloat?
    let isVideoMirrored: Bool
    let recordsAudio: Bool
    let depthFilteringEnabled: Bool

    init(
        captureID: String = UUID().uuidString,
        packageID: UUID = UUID(),
        capturedAt: Date = Date(),
        outputURL: URL,
        maximumDuration: TimeInterval = Self.defaultMaximumDuration,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        recordsAudio: Bool,
        depthFilteringEnabled: Bool = false
    ) {
        self.captureID = captureID
        self.packageID = packageID
        self.capturedAt = capturedAt
        self.outputURL = outputURL
        self.maximumDuration = maximumDuration
        self.videoRotationAngle = videoRotationAngle
        self.isVideoMirrored = isVideoMirrored
        self.recordsAudio = recordsAudio
        self.depthFilteringEnabled = depthFilteringEnabled
    }
}

nonisolated struct TAPVideoRecordingArtifact: Sendable {
    let captureID: String
    let packageID: UUID
    let capturedAt: Date
    let videoURL: URL
    let manifest: TAPVideoManifest
    let location: TAPPendingCaptureLocation?

    var pendingArtifact: TAPPendingVideoCaptureArtifact {
        TAPPendingVideoCaptureArtifact(
            captureID: captureID,
            packageID: packageID,
            capturedAt: capturedAt,
            videoURL: videoURL,
            captureScoreSummary: .unknown,
            location: location
        )
    }
}

nonisolated struct TAPVideoWriterFailure: Equatable, Sendable {
    let captureID: String
    let domain: String
    let code: Int
}

nonisolated final class TAPVideoRecorder: NSObject, @unchecked Sendable {
    private let callbackQueue: DispatchQueue

    private let request: TAPVideoRecordingRequest
    private let sessionConfiguration: SessionConfigurationResult
    private let nominalDepthIntervalSeconds: Double?
    private let location: TAPPendingCaptureLocation?
    private let writerSession: TAPVideoWriterSession
    private let motionRecorder = TAPVideoMotionRecorder()
    private var filtering: TAPVideoCaptureTelemetry.Filtering
    private let writerFailureHandler: @Sendable (TAPVideoWriterFailure) -> Void
    weak var synchronizedVideoOutput: AVCaptureVideoDataOutput?
    weak var synchronizedDepthOutput: AVCaptureDepthDataOutput?
    var metrics = TAPVideoRecordingMetrics()
    var diagnostics: TAPVideoRecorderDiagnostics

    private var isFinishing = false
    private var didReportWriterFailure = false
    private var finishContinuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>?

    init(
        request: TAPVideoRecordingRequest,
        sessionConfiguration: SessionConfigurationResult,
        videoSettings: [String: Any],
        recordsAudio: Bool,
        recordsDepth: Bool,
        location: TAPPendingCaptureLocation?,
        callbackQueue: DispatchQueue,
        writerFailureHandler: @escaping @Sendable (TAPVideoWriterFailure) -> Void
    ) throws {
        self.request = request
        self.filtering = .init(requestedEnabled: request.depthFilteringEnabled)
        self.sessionConfiguration = sessionConfiguration
        let frameRate = sessionConfiguration.device.activeDepthDataFormat?
            .videoSupportedFrameRateRanges.map(\.maxFrameRate).max()
        nominalDepthIntervalSeconds = frameRate.flatMap { $0 > 0 ? 1 / $0 : nil }
        self.location = location
        self.writerFailureHandler = writerFailureHandler
        self.callbackQueue = callbackQueue
        self.diagnostics = TAPVideoRecorderDiagnostics(captureID: request.captureID)
        self.writerSession = try TAPVideoWriterSession(
            request: request,
            videoSettings: videoSettings,
            recordsAudio: recordsAudio,
            recordsDepth: recordsDepth
        )

        super.init()
        TAPVideoPerformanceTrace.emitCaptureStart(
            recordsAudio: writerSession.recordsAudio,
            recordsDepth: writerSession.recordsDepth
        )
        TAPVideoPerformanceTrace.emitRuntimeCheckpoint(stage: "capture-start")
    }

    func useSynchronizedOutputs(
        videoOutput: AVCaptureVideoDataOutput,
        depthOutput: AVCaptureDepthDataOutput
    ) {
        synchronizedVideoOutput = videoOutput
        synchronizedDepthOutput = depthOutput
        metrics.usesSynchronizedRGBDepthOutput = true
        if let videoConnection = videoOutput.connection(with: .video) {
            metrics.appliedVideoRotationAngle = videoConnection.videoRotationAngle
            metrics.appliedVideoMirrored = videoConnection.isVideoMirrored
            metrics.appliedVideoStabilizationMode = videoConnection.activeVideoStabilizationMode
        }
        if let depthConnection = depthOutput.connection(with: .depthData) {
            metrics.observedDepthConnectionConfiguration = true
            metrics.appliedDepthRotationAngle = depthConnection.videoRotationAngle
            metrics.appliedDepthMirrored = depthConnection.isVideoMirrored
        }
    }

    func startMotionRecording(captureClock: CMClock?) {
        motionRecorder.start(captureClock: captureClock)
    }

    func stopMotionRecording(recordingError: Bool = false) {
        motionRecorder.stop(recordingError: recordingError)
    }

    func finish(reason: TAPVideoManifest.StopReason) async throws -> TAPVideoRecordingArtifact {
        motionRecorder.stop()
        return try await withCheckedThrowingContinuation { continuation in
            callbackQueue.async {
                self.finishOnCallbackQueue(reason: reason, continuation: continuation)
            }
        }
    }

    func cancelAfterWriterFailure() async {
        motionRecorder.stop()
        await withCheckedContinuation { continuation in
            callbackQueue.async {
                self.isFinishing = true
                self.writerSession.cancelWriting()
                self.cleanupWriterFile()
                continuation.resume()
            }
        }
    }

    private func finishOnCallbackQueue(
        reason: TAPVideoManifest.StopReason,
        continuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>
    ) {
        guard !isFinishing else {
            continuation.resume(throwing: TAPDepthCaptureError.videoRecordingFailed("finish already requested"))
            return
        }
        isFinishing = true
        metrics.stopReason = reason
        TAPVideoPerformanceTrace.emitCaptureStop(reason: reason.rawValue)
        diagnostics.emitRuntimeCheckpoint(
            stage: "capture-stop-requested",
            metrics: metrics
        )

        guard writerSession.didStartWriting else {
            writerSession.cancelWriting()
            continuation.resume(throwing: TAPDepthCaptureError.videoRecordingFailed("no video samples were recorded"))
            return
        }

        finishContinuation = continuation
        writerSession.finishWriting { [weak self] in
            guard let self else { return }
            self.callbackQueue.async {
                self.completeFinishedWriter()
            }
        }
    }

    private func completeFinishedWriter() {
        guard let continuation = finishContinuation else {
            return
        }
        finishContinuation = nil

        let writerSucceeded = writerSession.status == .completed
        TAPVideoPerformanceTrace.emitWriterFinished(succeeded: writerSucceeded)
        diagnostics.emitRuntimeCheckpoint(
            stage: writerSucceeded ? "writer-finished" : "writer-failed",
            metrics: metrics
        )

        guard writerSucceeded else {
            let reason = writerSession.error.map(TAPDiagnostics.describe)
                ?? "writer status \(writerSession.status.rawValue)"
            cleanupWriterFile()
            continuation.resume(throwing: TAPDepthCaptureError.videoRecordingFailed(reason))
            return
        }

        let finalizeTrace = TAPVideoPerformanceTrace.beginRecordingFinalize()
        // The router has drained and detached this recorder, and the writer
        // is finished. File finalization must not occupy the live RGB/depth
        // callback queue, which also feeds the PRO focus preview.
        Task.detached(priority: .utility) { [self] in
            do {
                let fileFacts = try await TAPMediaTrackFactsReader.read(
                    from: writerSession.writerURL
                )
                finalizeCompletedWriter(
                    continuation: continuation,
                    fileFacts: fileFacts,
                    trace: finalizeTrace
                )
            } catch {
                TAPVideoPerformanceTrace.endRecordingFinalize(
                    finalizeTrace,
                    depthSampleCount: metrics.depthSampleCount,
                    droppedDepthSampleCount: metrics.droppedDepthSampleCount
                )
                cleanupWriterFile()
                continuation.resume(throwing: error)
            }
        }
    }

    private func finalizeCompletedWriter(
        continuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>,
        fileFacts: TAPMediaTrackFacts,
        trace: OSSignpostIntervalState
    ) {
        defer {
            TAPVideoPerformanceTrace.endRecordingFinalize(
                trace,
                depthSampleCount: metrics.depthSampleCount,
                droppedDepthSampleCount: metrics.droppedDepthSampleCount
            )
        }
        do {
            let manifest = try TAPVideoManifestAssembler.make(
                request: request,
                sessionConfiguration: sessionConfiguration,
                fileFacts: fileFacts,
                metrics: metrics,
                nominalDepthIntervalSeconds: nominalDepthIntervalSeconds
            )
            let telemetry = TAPVideoCaptureTelemetry(
                filtering: filtering,
                motion: motionRecorder.snapshot(
                    firstVideoTime: metrics.firstVideoTime,
                    durationSeconds: manifest.payload.container.durationSeconds
                )
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.info("video motion status=\(telemetry.motion.status.rawValue, privacy: .public) samples=\(telemetry.motion.samples.count, privacy: .public) drops=\(telemetry.motion.droppedSampleCount, privacy: .public) errors=\(telemetry.motion.errorCount, privacy: .public)")
            #endif
            let byteCount = try writerSession.publish(
                manifest: manifest,
                telemetry: telemetry,
                to: request.outputURL
            )
            resumeFinishedRecording(
                continuation: continuation,
                manifest: manifest,
                byteCount: byteCount
            )
        } catch {
            cleanupWriterFile()
            try? FileManager.default.removeItem(at: request.outputURL)
            continuation.resume(throwing: error)
        }
    }

    private func cleanupWriterFile() {
        writerSession.cleanup()
    }

    private func resumeFinishedRecording(
        continuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>,
        manifest: TAPVideoManifest,
        byteCount: UInt64
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("video recording finalized captureID=\(self.request.captureID, privacy: .private) bytes=\(byteCount, privacy: .public) duration=\(self.metrics.recordedDurationSeconds, privacy: .public) rgbFrames=\(self.metrics.videoFrameCount, privacy: .public) videoDrops=\(self.metrics.videoDropCount, privacy: .public) audioSamples=\(self.metrics.audioSampleCount, privacy: .public) audioDrops=\(self.metrics.audioDropCount, privacy: .public) depthOutputSamples=\(self.metrics.depthOutputSampleCount, privacy: .public) depthOutputDrops=\(self.metrics.depthOutputDropCount, privacy: .public) depthSamples=\(self.metrics.depthSampleCount, privacy: .public) depthBeforeVideoStart=\(self.metrics.depthSamplesBeforeVideoStart, privacy: .public) depthMetadataDrops=\(self.metrics.depthMetadataDropCount, privacy: .public) depthEncodingDrops=\(self.metrics.depthEncodingDropCount, privacy: .public) stopReason=\(self.metrics.stopReason.rawValue, privacy: .public)")
        #endif
        diagnostics.emitRuntimeCheckpoint(
            stage: "recording-finalized",
            metrics: metrics
        )
        continuation.resume(returning: TAPVideoRecordingArtifact(
            captureID: request.captureID,
            packageID: request.packageID,
            capturedAt: request.capturedAt,
            videoURL: request.outputURL,
            manifest: manifest,
            location: location
        ))
    }

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing else {
            return
        }

        let outcome = writerSession.appendVideo(sampleBuffer)
        if writerSession.didStartWriting,
           metrics.firstVideoFormatDescription == nil {
            metrics.firstVideoFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        }
        switch outcome {
        case .failed:
            isFinishing = true
            reportWriterFailureIfNeeded()
        case .ignored:
            reportWriterFailureIfNeeded()
            return
        case .dropped(let startedAt):
            metrics.firstVideoTime = metrics.firstVideoTime ?? startedAt
            metrics.videoDropCount += 1
        case .appended(let startedAt):
            metrics.firstVideoTime = metrics.firstVideoTime ?? startedAt
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let isFirstRGBFrame = metrics.videoFrameCount == 0
            metrics.videoFrameCount += 1
            metrics.lastVideoTime = presentationTime
            if isFirstRGBFrame {
                let timestampSeconds = CMTimeGetSeconds(presentationTime)
                TAPVideoPerformanceTrace.emitCaptureFirstRGB(
                    timestampSeconds: timestampSeconds.isFinite ? timestampSeconds : -1
                )
                diagnostics.emitRuntimeCheckpoint(
                    stage: "capture-first-rgb",
                    metrics: metrics
                )
            }
        }
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing else {
            return
        }
        switch writerSession.appendAudio(sampleBuffer) {
        case .appended(let sampleCount):
            metrics.audioSampleCount += sampleCount
        case .dropped:
            metrics.audioDropCount += 1
        case .ignored:
            break
        }
    }

    func appendDepthSample(_ depthData: AVDepthData, timestamp: CMTime) {
        guard !isFinishing else {
            return
        }
        metrics.depthOutputSampleCount += 1
        diagnostics.logFirstDepthSampleIfNeeded(
            depthData,
            timestamp: timestamp
        )

        guard writerSession.didStartWriting else {
            metrics.depthSamplesBeforeVideoStart += 1
            return
        }
        metrics.depthDeliveredSampleCount += 1
        if depthData.isDepthDataFiltered {
            filtering.filteredSampleCount += 1
        } else {
            filtering.unfilteredSampleCount += 1
        }

        guard let metadataAdaptor = depthMetadataAdaptor(at: timestamp) else {
            reportWriterFailureIfNeeded()
            return
        }

        do {
            try appendEncodedDepthSample(
                depthData,
                timestamp: timestamp,
                metadataAdaptor: metadataAdaptor
            )
        } catch {
            recordDepthEncodingFailure(error, timestamp: timestamp)
        }
        reportWriterFailureIfNeeded()
    }

    private func reportWriterFailureIfNeeded() {
        guard !didReportWriterFailure,
              writerSession.status == .failed else {
            return
        }
        didReportWriterFailure = true
        isFinishing = true
        motionRecorder.stop()
        let error = writerSession.error as NSError?
        writerFailureHandler(TAPVideoWriterFailure(
            captureID: request.captureID,
            domain: error?.domain ?? AVFoundationErrorDomain,
            code: error?.code ?? AVError.Code.unknown.rawValue
        ))
    }

    private func depthMetadataAdaptor(
        at timestamp: CMTime
    ) -> AVAssetWriterInputMetadataAdaptor? {
        switch writerSession.depthMetadataDestination() {
        case .ready(let adaptor):
            return adaptor
        case .unavailable:
            recordDepthMetadataDestinationDrop(
                reason: "metadata-input-or-writer-not-ready",
                timestamp: timestamp
            )
            return nil
        case .backpressured:
            recordDepthMetadataDestinationDrop(
                reason: "metadata-input-backpressure",
                timestamp: timestamp
            )
            return nil
        }
    }

    private func recordDepthMetadataDestinationDrop(
        reason: String,
        timestamp: CMTime
    ) {
        diagnostics.logDepthMetadataInputUnavailableIfNeeded(
            reason: reason,
            writerSession: writerSession
        )
        metrics.depthMetadataDropCount += 1
        recordDepthGap(reason: .metadataBackpressure, at: timestamp)
    }

    private func appendEncodedDepthSample(
        _ depthData: AVDepthData,
        timestamp: CMTime,
        metadataAdaptor: AVAssetWriterInputMetadataAdaptor
    ) throws {
        guard let firstVideoTime = metrics.firstVideoTime else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "depth timestamp cannot be represented on the capture-relative timeline"
            )
        }
        guard let sample = try TAPVideoDepthMetadataEncoder.append(
            depthData: depthData,
            timestamp: timestamp,
            frameIndex: metrics.depthFrameIndex,
            firstVideoTime: firstVideoTime,
            calibrationTable: metrics.depthCalibrationTable,
            adaptor: metadataAdaptor
        ) else {
            recordDepthMetadataAppendDrop(at: timestamp)
            return
        }

        applyDepthCalibrationMetrics(from: sample)
        applyDepthFormatMetrics(from: sample)
        recordDepthCadence(at: timestamp)
        metrics.lastDepthTime = timestamp
        metrics.depthFrameIndex += 1
        metrics.depthSampleCount += 1
    }

    private func recordDepthMetadataAppendDrop(at timestamp: CMTime) {
        diagnostics.logDepthMetadataAppendFailureIfNeeded(
            writerSession: writerSession
        )
        metrics.depthMetadataDropCount += 1
        recordDepthGap(reason: .metadataBackpressure, at: timestamp)
    }

    private func applyDepthCalibrationMetrics(
        from sample: TAPVideoEncodedDepthSample
    ) {
        metrics.depthCalibrationTable = sample.calibrationTable
        if sample.calibrationIndex != nil {
            metrics.depthSamplesWithCalibrationIndex += 1
        } else if sample.calibration == nil {
            metrics.depthSamplesMissingCalibration += 1
        } else {
            metrics.depthSamplesWithUnindexedCalibration += 1
        }
    }

    private func applyDepthFormatMetrics(
        from sample: TAPVideoEncodedDepthSample
    ) {
        guard let firstDepthFormat = metrics.firstDepthFormat else {
            metrics.firstDepthFormat = sample.format
            return
        }
        if !sample.format.hasSameStoredFrameLayout(as: firstDepthFormat) {
            metrics.depthFormatChanged = true
        }
    }

    private func recordDepthCadence(at timestamp: CMTime) {
        if let lastDepthTime = metrics.lastDepthTime {
            recordDepthInterval(from: lastDepthTime, to: timestamp)
            return
        }
        if let firstVideoTime = metrics.firstVideoTime {
            recordLeadingDepthInterval(from: firstVideoTime, to: timestamp)
        }
    }

    private func recordDepthInterval(from start: CMTime, to end: CMTime) {
        let interval = max(0, CMTimeGetSeconds(CMTimeSubtract(end, start)))
        metrics.maxObservedDepthIntervalSeconds = max(
            metrics.maxObservedDepthIntervalSeconds ?? 0,
            interval
        )
        guard interval > depthCadenceGapThresholdSeconds else {
            return
        }
        // The two delivered depth samples bound the missing interval; neither is missing.
        recordDepthGap(
            reason: .silentCadence,
            start: CMTimeAdd(start, TAPVideoCaptureTimeline.tick),
            end: CMTimeSubtract(end, TAPVideoCaptureTimeline.tick)
        )
    }

    private func recordLeadingDepthInterval(from start: CMTime, to end: CMTime) {
        let interval = max(0, CMTimeGetSeconds(CMTimeSubtract(end, start)))
        guard interval > depthCadenceGapThresholdSeconds else {
            return
        }
        recordDepthGap(
            reason: .silentCadence,
            start: start,
            end: CMTimeSubtract(end, TAPVideoCaptureTimeline.tick),
            nearestStartRGBFrame: metrics.videoFrameCount > 0 ? 0 : nil,
            nearestEndRGBFrame: metrics.videoFrameCount > 0 ? metrics.videoFrameCount - 1 : nil
        )
    }

    private func recordDepthEncodingFailure(_ error: Error, timestamp: CMTime) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.error("video depth sample encode failed captureID=\(self.request.captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
        #endif
        metrics.depthEncodingDropCount += 1
        recordDepthGap(reason: .encodingFailure, at: timestamp)
    }


    func recordDepthGap(
        reason: TAPVideoManifest.DepthGapReason,
        at timestamp: CMTime
    ) {
        recordDepthGap(reason: reason, start: timestamp, end: timestamp)
    }

    func recordDepthGap(
        reason: TAPVideoManifest.DepthGapReason,
        start: CMTime,
        end: CMTime,
        nearestStartRGBFrame: Int? = nil,
        nearestEndRGBFrame: Int? = nil
    ) {
        metrics.recordDepthGap(
            reason: reason,
            start: start,
            end: end,
            nearestStartRGBFrame: nearestStartRGBFrame,
            nearestEndRGBFrame: nearestEndRGBFrame
        )
    }

    private var depthCadenceGapThresholdSeconds: Double {
        max(2 * (nominalDepthIntervalSeconds ?? 0), 0.1)
    }

}


nonisolated extension AVCaptureDevice.Position {
    var tapManifestValue: String {
        switch self {
        case .front:
            return "front"
        case .back:
            return "back"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }
}
