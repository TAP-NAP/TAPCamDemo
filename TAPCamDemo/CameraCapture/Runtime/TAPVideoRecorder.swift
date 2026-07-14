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

    init(
        captureID: String = UUID().uuidString,
        packageID: UUID = UUID(),
        capturedAt: Date = Date(),
        outputURL: URL,
        maximumDuration: TimeInterval = Self.defaultMaximumDuration,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        recordsAudio: Bool
    ) {
        self.captureID = captureID
        self.packageID = packageID
        self.capturedAt = capturedAt
        self.outputURL = outputURL
        self.maximumDuration = maximumDuration
        self.videoRotationAngle = videoRotationAngle
        self.isVideoMirrored = isVideoMirrored
        self.recordsAudio = recordsAudio
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

/// Keeps the signed depth-gap table compact under sustained output pressure.
/// Adjacent gaps with the same cause are coalesced. Once the hard limit is
/// reached, later events extend one conservative fail-closed range instead of
/// growing the manifest without bound.
nonisolated struct TAPDepthGapAccumulator: Sendable {
    static let maximumGapCount = TAPVideoManifest.DepthCoverage.maximumGapCount

    private(set) var gaps: [TAPVideoManifest.DepthGap] = []

    mutating func record(
        _ gap: TAPVideoManifest.DepthGap,
        mergeToleranceSeconds: Double
    ) {
        if let last = gaps.last,
           last.reason == gap.reason,
           Self.canMerge(last, with: gap, toleranceSeconds: mergeToleranceSeconds) {
            gaps[gaps.count - 1] = Self.merged(last, gap, reason: last.reason)
            return
        }

        guard gaps.count >= Self.maximumGapCount else {
            gaps.append(gap)
            return
        }

        let last = gaps[gaps.count - 1]
        gaps[gaps.count - 1] = Self.merged(last, gap, reason: .boundedAggregation)
    }

    private static func canMerge(
        _ lhs: TAPVideoManifest.DepthGap,
        with rhs: TAPVideoManifest.DepthGap,
        toleranceSeconds: Double
    ) -> Bool {
        guard lhs.endPTS.timescale > 0, rhs.startPTS.timescale > 0 else {
            return false
        }
        let lhsEnd = CMTime(value: lhs.endPTS.value, timescale: lhs.endPTS.timescale)
        let rhsStart = CMTime(value: rhs.startPTS.value, timescale: rhs.startPTS.timescale)
        let tolerance = CMTime(
            seconds: max(0, toleranceSeconds),
            preferredTimescale: max(max(lhs.endPTS.timescale, rhs.startPTS.timescale), 600)
        )
        return CMTimeCompare(rhsStart, CMTimeAdd(lhsEnd, tolerance)) <= 0
    }

    private static func merged(
        _ lhs: TAPVideoManifest.DepthGap,
        _ rhs: TAPVideoManifest.DepthGap,
        reason: TAPVideoManifest.DepthGapReason
    ) -> TAPVideoManifest.DepthGap {
        let startPTS = earlier(lhs.startPTS, rhs.startPTS)
        let endPTS = later(lhs.endPTS, rhs.endPTS)
        return TAPVideoManifest.DepthGap(
            reason: reason,
            startPTS: startPTS,
            endPTS: endPTS,
            nearestStartRGBFrame: lhs.nearestStartRGBFrame ?? rhs.nearestStartRGBFrame,
            nearestEndRGBFrame: rhs.nearestEndRGBFrame ?? lhs.nearestEndRGBFrame
        )
    }

    private static func earlier(
        _ lhs: TAPVideoManifest.MediaTime,
        _ rhs: TAPVideoManifest.MediaTime
    ) -> TAPVideoManifest.MediaTime {
        compare(lhs, rhs) <= 0 ? lhs : rhs
    }

    private static func later(
        _ lhs: TAPVideoManifest.MediaTime,
        _ rhs: TAPVideoManifest.MediaTime
    ) -> TAPVideoManifest.MediaTime {
        compare(lhs, rhs) >= 0 ? lhs : rhs
    }

    private static func compare(
        _ lhs: TAPVideoManifest.MediaTime,
        _ rhs: TAPVideoManifest.MediaTime
    ) -> Int32 {
        guard lhs.timescale > 0, rhs.timescale > 0 else {
            if lhs.value == rhs.value { return 0 }
            return lhs.value < rhs.value ? -1 : 1
        }
        return CMTimeCompare(
            CMTime(value: lhs.value, timescale: lhs.timescale),
            CMTime(value: rhs.value, timescale: rhs.timescale)
        )
    }
}

/// Converts capture-device timestamps into the media timeline signed by the
/// TAP manifest and embedded in each KLV frame. AVAssetWriter still receives
/// the original capture timestamp so its inputs stay synchronized; only the
/// persisted contract is rebased to the first stored RGB frame.
nonisolated enum TAPVideoCaptureTimeline {
    static let timescale: CMTimeScale = 600

    static func relativeMediaTime(
        _ timestamp: CMTime,
        from origin: CMTime
    ) -> TAPVideoManifest.MediaTime? {
        guard timestamp.isValid,
              origin.isValid,
              !timestamp.isIndefinite,
              !origin.isIndefinite,
              timestamp.timescale > 0,
              origin.timescale > 0 else {
            return nil
        }
        let delta = CMTimeSubtract(timestamp, origin)
        guard delta.isValid,
              !delta.isIndefinite else {
            return nil
        }
        let nonnegativeDelta = CMTimeCompare(delta, .zero) < 0 ? CMTime.zero : delta
        let normalized = CMTimeConvertScale(
            nonnegativeDelta,
            timescale: timescale,
            method: .default
        )
        guard normalized.isValid,
              !normalized.isIndefinite,
              normalized.timescale > 0 else {
            return nil
        }
        return TAPVideoManifest.MediaTime(
            value: normalized.value,
            timescale: normalized.timescale
        )
    }

    static func depthGap(
        reason: TAPVideoManifest.DepthGapReason,
        start: CMTime,
        end: CMTime,
        relativeTo origin: CMTime,
        nearestStartRGBFrame: Int?,
        nearestEndRGBFrame: Int?
    ) -> TAPVideoManifest.DepthGap? {
        guard start.isValid,
              end.isValid,
              CMTimeCompare(end, start) >= 0,
              let startPTS = relativeMediaTime(start, from: origin),
              let endPTS = relativeMediaTime(end, from: origin),
              CMTimeCompare(
                  CMTime(value: endPTS.value, timescale: endPTS.timescale),
                  CMTime(value: startPTS.value, timescale: startPTS.timescale)
              ) >= 0 else {
            return nil
        }
        return TAPVideoManifest.DepthGap(
            reason: reason,
            startPTS: startPTS,
            endPTS: endPTS,
            nearestStartRGBFrame: nearestStartRGBFrame,
            nearestEndRGBFrame: nearestEndRGBFrame
        )
    }

    static func absoluteMediaEndTime(
        origin: CMTime,
        durationSeconds: Double,
        lastSampleTime: CMTime?
    ) -> CMTime? {
        guard origin.isValid,
              !origin.isIndefinite,
              origin.timescale > 0,
              durationSeconds.isFinite,
              durationSeconds >= 0 else {
            return nil
        }
        let duration = CMTime(
            seconds: durationSeconds,
            preferredTimescale: timescale
        )
        let trackEnd = CMTimeAdd(origin, duration)
        guard trackEnd.isValid,
              !trackEnd.isIndefinite else {
            return nil
        }
        guard let lastSampleTime,
              lastSampleTime.isValid,
              !lastSampleTime.isIndefinite else {
            return trackEnd
        }
        return CMTimeCompare(lastSampleTime, trackEnd) > 0 ? lastSampleTime : trackEnd
    }
}

/// Stable, bounded calibration dictionary referenced by KLV frame indices.
/// Exact equality is intentional: every distinct raw calibration payload that
/// reaches the signed artifact remains independently addressable.
nonisolated struct TAPVideoCalibrationTable: Sendable {
    static let maximumEntryCount = TAPVideoManifest.SpatialRegistration.maximumCalibrationCount

    private(set) var entries: [TAPVideoManifest.CameraCalibration] = []
    private(set) var didOverflow = false

    mutating func index(
        for calibration: TAPVideoManifest.CameraCalibration?
    ) -> UInt32? {
        guard let calibration else {
            return nil
        }
        if let existingIndex = entries.firstIndex(of: calibration) {
            return UInt32(existingIndex)
        }
        guard entries.count < Self.maximumEntryCount else {
            didOverflow = true
            return nil
        }
        entries.append(calibration)
        return UInt32(entries.count - 1)
    }
}

nonisolated final class TAPVideoRecorder: NSObject, @unchecked Sendable {
    private static let depthMetadataIdentifier = AVMetadataIdentifier(rawValue: "mdta/com.tapnap.depth.klv")

    let callbackQueue: DispatchQueue
    private var outputDelegateStorage: TAPVideoRecorderOutputDelegate?
    var outputDelegate: TAPVideoRecorderOutputDelegate {
        guard let outputDelegateStorage else {
            preconditionFailure("TAPVideoRecorder output delegate accessed before initialization completed.")
        }
        return outputDelegateStorage
    }

    private let request: TAPVideoRecordingRequest
    private let sessionConfiguration: SessionConfigurationResult
    private let location: TAPPendingCaptureLocation?
    private let writerURL: URL
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let metadataInput: AVAssetWriterInput?
    private let metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
    private weak var synchronizedVideoOutput: AVCaptureVideoDataOutput?
    private weak var synchronizedDepthOutput: AVCaptureDepthDataOutput?
    private var usesSynchronizedRGBDepthOutput = false
    private var observedSynchronizedRGBDepthPair = false
    private var appliedVideoRotationAngle: CGFloat?
    private var appliedVideoMirrored = false
    private var appliedVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off
    private var observedDepthConnectionConfiguration = false
    private var appliedDepthRotationAngle: CGFloat?
    private var appliedDepthMirrored = false

    private var didStartWriting = false
    private var isFinishing = false
    private var stopReason: TAPVideoManifest.StopReason = .userStop
    private var firstVideoTime: CMTime?
    private var lastVideoTime: CMTime?
    private var firstVideoFormatDescription: CMFormatDescription?
    private var videoFrameCount = 0
    private var videoDropCount = 0
    private var audioSampleCount = 0
    private var audioDropCount = 0
    private var depthOutputSampleCount = 0
    private var depthOutputDropCount = 0
    private var depthSampleCount = 0
    private var depthFrameIndex = 0
    private var depthSamplesBeforeVideoStart = 0
    private var depthMetadataDropCount = 0
    private var depthEncodingDropCount = 0
    private var depthDeliveredSampleCount = 0
    private var hasLoggedFirstDepthSample = false
    private var hasLoggedDepthMetadataInputUnavailable = false
    private var hasLoggedDepthMetadataAppendFailure = false
    private var firstDepthFormat: TAPVideoManifest.DepthFormat?
    private var depthFormatChanged = false
    private var depthCalibrationTable = TAPVideoCalibrationTable()
    private var depthSamplesWithCalibrationIndex = 0
    private var depthSamplesMissingCalibration = 0
    private var depthSamplesWithUnindexedCalibration = 0
    private var depthGapAccumulator = TAPDepthGapAccumulator()
    private var lastDepthTime: CMTime?
    private var maxObservedDepthIntervalSeconds: Double?
    private var maxObservedRGBDepthDeltaSeconds: Double?
    private var finishContinuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>?

    init(
        request: TAPVideoRecordingRequest,
        sessionConfiguration: SessionConfigurationResult,
        videoSettings: [String: Any],
        recordsAudio: Bool,
        recordsDepth: Bool,
        location: TAPPendingCaptureLocation?
    ) throws {
        self.request = request
        self.sessionConfiguration = sessionConfiguration
        self.location = location
        self.callbackQueue = DispatchQueue(label: "tapcam.camera-capture.video-recorder.\(request.captureID)")
        self.writerURL = request.outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(request.outputURL.deletingPathExtension().lastPathComponent)-writing.mp4")

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: writerURL.path) {
            try fileManager.removeItem(at: writerURL)
        }
        if fileManager.fileExists(atPath: request.outputURL.path) {
            try fileManager.removeItem(at: request.outputURL)
        }

        self.assetWriter = try AVAssetWriter(outputURL: writerURL, fileType: .mp4)

        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        self.videoInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(videoInput) else {
            throw TAPDepthCaptureError.videoRecordingFailed("asset writer rejected video input")
        }
        assetWriter.add(videoInput)

        if recordsAudio {
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000
                ]
            )
            audioInput.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
                self.audioInput = audioInput
            } else {
                self.audioInput = nil
            }
        } else {
            self.audioInput = nil
        }

        if recordsDepth {
            let metadataInput = try AVAssetWriterInput(
                mediaType: .metadata,
                outputSettings: nil,
                sourceFormatHint: Self.makeDepthMetadataFormatDescription()
            )
            metadataInput.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(metadataInput) {
                assetWriter.add(metadataInput)
                self.metadataInput = metadataInput
                self.metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
            } else {
                self.metadataInput = nil
                self.metadataAdaptor = nil
            }
        } else {
            self.metadataInput = nil
            self.metadataAdaptor = nil
        }

        super.init()
        self.outputDelegateStorage = TAPVideoRecorderOutputDelegate(recorder: self)
        TAPVideoPerformanceTrace.emitCaptureStart(
            recordsAudio: self.audioInput != nil,
            recordsDepth: self.metadataInput != nil
        )
        TAPVideoPerformanceTrace.emitRuntimeCheckpoint(stage: "capture-start")
    }

    func useSynchronizedOutputs(
        videoOutput: AVCaptureVideoDataOutput,
        depthOutput: AVCaptureDepthDataOutput
    ) {
        synchronizedVideoOutput = videoOutput
        synchronizedDepthOutput = depthOutput
        usesSynchronizedRGBDepthOutput = true
        if let videoConnection = videoOutput.connection(with: .video) {
            appliedVideoRotationAngle = videoConnection.videoRotationAngle
            appliedVideoMirrored = videoConnection.isVideoMirrored
            appliedVideoStabilizationMode = videoConnection.activeVideoStabilizationMode
        }
        if let depthConnection = depthOutput.connection(with: .depthData) {
            observedDepthConnectionConfiguration = true
            appliedDepthRotationAngle = depthConnection.videoRotationAngle
            appliedDepthMirrored = depthConnection.isVideoMirrored
        }
    }

    func finish(reason: TAPVideoManifest.StopReason) async throws -> TAPVideoRecordingArtifact {
        try await withCheckedThrowingContinuation { continuation in
            callbackQueue.async {
                self.finishOnCallbackQueue(reason: reason, continuation: continuation)
            }
        }
    }

    fileprivate func handleDroppedSampleBuffer(
        _ output: AVCaptureOutput,
        sampleBuffer: CMSampleBuffer,
        connection: AVCaptureConnection
    ) {
        _ = sampleBuffer
        _ = connection
        if output is AVCaptureAudioDataOutput {
            audioDropCount += 1
        } else {
            videoDropCount += 1
        }
    }

    fileprivate func handleOutputSampleBuffer(
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

    fileprivate func handleSynchronizedDataCollection(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        _ = synchronizer

        if let synchronizedVideoOutput,
           let synchronizedDepthOutput,
           let videoData = synchronizedDataCollection.synchronizedData(for: synchronizedVideoOutput)
            as? AVCaptureSynchronizedSampleBufferData,
           let depthData = synchronizedDataCollection.synchronizedData(for: synchronizedDepthOutput)
            as? AVCaptureSynchronizedDepthData,
           !videoData.sampleBufferWasDropped,
           !depthData.depthDataWasDropped {
            observedSynchronizedRGBDepthPair = true
            let videoTime = CMSampleBufferGetPresentationTimeStamp(videoData.sampleBuffer)
            let delta = abs(CMTimeGetSeconds(CMTimeSubtract(depthData.timestamp, videoTime)))
            if delta.isFinite {
                maxObservedRGBDepthDeltaSeconds = max(maxObservedRGBDepthDeltaSeconds ?? 0, delta)
            }
        }

        if let synchronizedVideoOutput,
           let videoData = synchronizedDataCollection.synchronizedData(for: synchronizedVideoOutput)
            as? AVCaptureSynchronizedSampleBufferData {
            if videoData.sampleBufferWasDropped {
                videoDropCount += 1
            } else {
                appendVideoSample(videoData.sampleBuffer)
            }
        }

        if let synchronizedDepthOutput,
           let synchronizedDepthData = synchronizedDataCollection.synchronizedData(for: synchronizedDepthOutput)
            as? AVCaptureSynchronizedDepthData {
            if synchronizedDepthData.depthDataWasDropped {
                depthOutputDropCount += 1
                recordDepthGap(reason: .outputDrop, at: synchronizedDepthData.timestamp)
                logDepthDropIfNeeded(reason: synchronizedDepthData.droppedReason)
            } else {
                appendDepthSample(
                    synchronizedDepthData.depthData,
                    timestamp: synchronizedDepthData.timestamp
                )
            }
        }
    }

    fileprivate func handleDepthData(
        _ output: AVCaptureDepthDataOutput,
        depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        appendDepthSample(depthData, timestamp: timestamp)
    }

    fileprivate func handleDroppedDepthData(
        _ output: AVCaptureDepthDataOutput,
        depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection,
        reason: AVCaptureOutput.DataDroppedReason
    ) {
        _ = output
        _ = depthData
        _ = connection
        depthOutputDropCount += 1
        recordDepthGap(reason: .outputDrop, at: timestamp)
        logDepthDropIfNeeded(reason: reason)
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
        stopReason = reason
        TAPVideoPerformanceTrace.emitCaptureStop(reason: reason.rawValue)
        emitRuntimeCheckpoint(stage: "capture-stop-requested")

        guard didStartWriting else {
            assetWriter.cancelWriting()
            continuation.resume(throwing: TAPDepthCaptureError.videoRecordingFailed("no video samples were recorded"))
            return
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        metadataInput?.markAsFinished()
        finishContinuation = continuation

        assetWriter.finishWriting { [weak self] in
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

        let writerSucceeded = assetWriter.status == .completed
        TAPVideoPerformanceTrace.emitWriterFinished(succeeded: writerSucceeded)
        emitRuntimeCheckpoint(
            stage: writerSucceeded ? "writer-finished" : "writer-failed"
        )

        guard writerSucceeded else {
            let reason = assetWriter.error.map(TAPDiagnostics.describe) ?? "writer status \(assetWriter.status.rawValue)"
            cleanupWriterFile()
            continuation.resume(throwing: TAPDepthCaptureError.videoRecordingFailed(reason))
            return
        }

        let finalizeTrace = TAPVideoPerformanceTrace.beginRecordingFinalize()
        Task { [weak self] in
            guard let self else { return }
            do {
                let fileFacts = try await TAPVideoRecordedFileFacts.load(from: self.writerURL)
                self.callbackQueue.async {
                    self.finalizeCompletedWriter(
                        continuation: continuation,
                        fileFacts: fileFacts,
                        trace: finalizeTrace
                    )
                }
            } catch {
                self.callbackQueue.async {
                    TAPVideoPerformanceTrace.endRecordingFinalize(
                        finalizeTrace,
                        depthSampleCount: self.depthSampleCount,
                        droppedDepthSampleCount: self.depthOutputDropCount
                            + self.depthMetadataDropCount
                            + self.depthEncodingDropCount
                    )
                    self.cleanupWriterFile()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func finalizeCompletedWriter(
        continuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>,
        fileFacts: TAPVideoRecordedFileFacts,
        trace: OSSignpostIntervalState
    ) {
        defer {
            TAPVideoPerformanceTrace.endRecordingFinalize(
                trace,
                depthSampleCount: depthSampleCount,
                droppedDepthSampleCount: depthOutputDropCount + depthMetadataDropCount + depthEncodingDropCount
            )
        }
        do {
            let manifest = try makeManifest(fileFacts: fileFacts)
            try TAPVideoManifestBox.appendManifest(manifest, toFileAt: writerURL)
            TAPVideoPerformanceTrace.emitManifestAppended(
                byteCount: try TAPBMFFStreamingFile.byteCount(of: writerURL)
            )
            _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: writerURL)
            if FileManager.default.fileExists(atPath: request.outputURL.path) {
                try FileManager.default.removeItem(at: request.outputURL)
            }
            try FileManager.default.moveItem(at: writerURL, to: request.outputURL)
            let byteCount = try TAPBMFFStreamingFile.byteCount(of: request.outputURL)
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
        try? FileManager.default.removeItem(at: writerURL)
    }

    private func resumeFinishedRecording(
        continuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>,
        manifest: TAPVideoManifest,
        byteCount: UInt64
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("video recording finalized captureID=\(self.request.captureID, privacy: .private) bytes=\(byteCount, privacy: .public) duration=\(self.recordedDurationSeconds, privacy: .public) rgbFrames=\(self.videoFrameCount, privacy: .public) videoDrops=\(self.videoDropCount, privacy: .public) audioSamples=\(self.audioSampleCount, privacy: .public) audioDrops=\(self.audioDropCount, privacy: .public) depthOutputSamples=\(self.depthOutputSampleCount, privacy: .public) depthOutputDrops=\(self.depthOutputDropCount, privacy: .public) depthSamples=\(self.depthSampleCount, privacy: .public) depthBeforeVideoStart=\(self.depthSamplesBeforeVideoStart, privacy: .public) depthMetadataDrops=\(self.depthMetadataDropCount, privacy: .public) depthEncodingDrops=\(self.depthEncodingDropCount, privacy: .public) stopReason=\(self.stopReason.rawValue, privacy: .public)")
        #endif
        emitRuntimeCheckpoint(stage: "recording-finalized")
        continuation.resume(returning: TAPVideoRecordingArtifact(
            captureID: request.captureID,
            packageID: request.packageID,
            capturedAt: request.capturedAt,
            videoURL: request.outputURL,
            manifest: manifest,
            location: location
        ))
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !didStartWriting {
            guard assetWriter.startWriting() else {
                isFinishing = true
                return
            }
            assetWriter.startSession(atSourceTime: presentationTime)
            didStartWriting = true
            firstVideoTime = presentationTime
        }

        if firstVideoFormatDescription == nil {
            firstVideoFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        }

        guard assetWriter.status == .writing else {
            return
        }
        guard videoInput.isReadyForMoreMediaData else {
            videoDropCount += 1
            return
        }

        if videoInput.append(sampleBuffer) {
            let isFirstRGBFrame = videoFrameCount == 0
            videoFrameCount += 1
            lastVideoTime = presentationTime
            if isFirstRGBFrame {
                let timestampSeconds = CMTimeGetSeconds(presentationTime)
                TAPVideoPerformanceTrace.emitCaptureFirstRGB(
                    timestampSeconds: timestampSeconds.isFinite ? timestampSeconds : -1
                )
                emitRuntimeCheckpoint(stage: "capture-first-rgb")
            }
        } else {
            videoDropCount += 1
        }
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing,
              didStartWriting,
              let audioInput,
              assetWriter.status == .writing else {
            return
        }
        guard audioInput.isReadyForMoreMediaData else {
            audioDropCount += 1
            return
        }
        if audioInput.append(sampleBuffer) {
            audioSampleCount += CMSampleBufferGetNumSamples(sampleBuffer)
        } else {
            audioDropCount += 1
        }
    }

    private func appendDepthSample(_ depthData: AVDepthData, timestamp: CMTime) {
        guard !isFinishing else {
            return
        }
        depthOutputSampleCount += 1
        logFirstDepthSampleIfNeeded(depthData, timestamp: timestamp)

        guard didStartWriting else {
            depthSamplesBeforeVideoStart += 1
            return
        }
        depthDeliveredSampleCount += 1

        guard let metadataAdaptor,
              let metadataInput,
              assetWriter.status == .writing else {
            logDepthMetadataInputUnavailableIfNeeded(reason: "metadata-input-or-writer-not-ready")
            depthMetadataDropCount += 1
            recordDepthGap(reason: .metadataBackpressure, at: timestamp)
            return
        }
        guard metadataInput.isReadyForMoreMediaData else {
            logDepthMetadataInputUnavailableIfNeeded(reason: "metadata-input-backpressure")
            depthMetadataDropCount += 1
            recordDepthGap(reason: .metadataBackpressure, at: timestamp)
            return
        }

        do {
            let encodeTrace = TAPVideoPerformanceTrace.beginDepthEncode(frameIndex: depthFrameIndex)
            var tracedCodec = "failed"
            var tracedInputByteCount = 0
            var tracedOutputByteCount = 0
            defer {
                TAPVideoPerformanceTrace.endDepthEncode(
                    encodeTrace,
                    codec: tracedCodec,
                    inputByteCount: tracedInputByteCount,
                    outputByteCount: tracedOutputByteCount
                )
            }
            let packed = try TAPDepthFrameCodec.pack(depthData.depthDataMap)
            let sampleDepthFormat = TAPVideoManifest.DepthFormat(
                kind: packed.kind,
                pixelFormat: packed.pixelFormat,
                width: Int32(packed.width),
                height: Int32(packed.height),
                packedRowStride: packed.packedRowStride,
                sourceRowStride: packed.sourceRowStride,
                bytesPerSample: packed.bytesPerSample,
                uncompressedFrameByteCount: packed.bytes.count
            )
            tracedInputByteCount = packed.bytes.count
            let encodedFrame = try TAPDepthFrameCodec.encode(
                packed.bytes,
                preferredCodec: TAPDepthCompressionProductionPolicy.preferredCodec
            )
            tracedCodec = encodedFrame.codec.rawValue
            tracedOutputByteCount = encodedFrame.payload.count
            let calibration = Self.cameraCalibration(from: depthData.cameraCalibrationData)
            // Reserve against a copy so a metadata append failure cannot
            // consume a calibration-table slot or permanently set overflow.
            var committedCalibrationTable = depthCalibrationTable
            let calibrationIndex = committedCalibrationTable.index(for: calibration)
            guard let relativeTimestamp = firstVideoTime.flatMap({
                TAPVideoCaptureTimeline.relativeMediaTime(timestamp, from: $0)
            }) else {
                throw TAPDepthCaptureError.videoRecordingFailed(
                    "depth timestamp cannot be represented on the capture-relative timeline"
                )
            }
            let encoded = try TAPDepthKLVFrame(
                frameIndex: UInt32(depthFrameIndex),
                timestampValue: relativeTimestamp.value,
                timestampTimescale: relativeTimestamp.timescale,
                compressionCodec: encodedFrame.codec,
                uncompressedByteCount: encodedFrame.uncompressedByteCount,
                calibrationIndex: calibrationIndex,
                payload: encodedFrame.payload
            )
            .encodedData()
            let item = AVMutableMetadataItem()
            item.identifier = Self.depthMetadataIdentifier
            item.dataType = kCMMetadataBaseDataType_RawData as String
            item.value = encoded as NSData
            let group = AVTimedMetadataGroup(
                items: [item],
                timeRange: CMTimeRange(
                    start: timestamp,
                    duration: CMTime(value: 1, timescale: 600)
                )
            )
            guard metadataAdaptor.append(group) else {
                logDepthMetadataAppendFailureIfNeeded()
                depthMetadataDropCount += 1
                recordDepthGap(reason: .metadataBackpressure, at: timestamp)
                return
            }

            depthCalibrationTable = committedCalibrationTable
            if calibrationIndex != nil {
                depthSamplesWithCalibrationIndex += 1
            } else if calibration == nil {
                depthSamplesMissingCalibration += 1
            } else {
                depthSamplesWithUnindexedCalibration += 1
            }

            if let firstDepthFormat {
                if !sampleDepthFormat.hasSameStoredFrameLayout(as: firstDepthFormat) {
                    depthFormatChanged = true
                }
            } else {
                firstDepthFormat = sampleDepthFormat
            }
            if let lastDepthTime {
                let interval = max(0, CMTimeGetSeconds(CMTimeSubtract(timestamp, lastDepthTime)))
                maxObservedDepthIntervalSeconds = max(maxObservedDepthIntervalSeconds ?? 0, interval)
                if interval > depthCadenceGapThresholdSeconds {
                    recordDepthGap(
                        reason: .silentCadence,
                        start: lastDepthTime,
                        end: timestamp
                    )
                }
            } else if let firstVideoTime {
                let leadingInterval = max(
                    0,
                    CMTimeGetSeconds(CMTimeSubtract(timestamp, firstVideoTime))
                )
                if leadingInterval > depthCadenceGapThresholdSeconds {
                    recordDepthGap(
                        reason: .silentCadence,
                        start: firstVideoTime,
                        end: timestamp,
                        nearestStartRGBFrame: videoFrameCount > 0 ? 0 : nil,
                        nearestEndRGBFrame: videoFrameCount > 0 ? videoFrameCount - 1 : nil
                    )
                }
            }
            lastDepthTime = timestamp
            depthFrameIndex += 1
            depthSampleCount += 1
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error("video depth sample encode failed captureID=\(self.request.captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            depthEncodingDropCount += 1
            recordDepthGap(reason: .encodingFailure, at: timestamp)
        }
    }

    private static func makeDepthMetadataFormatDescription() throws -> CMMetadataFormatDescription {
        let item = AVMutableMetadataItem()
        item.identifier = depthMetadataIdentifier
        item.dataType = kCMMetadataBaseDataType_RawData as String
        item.value = Data([0]) as NSData
        let group = AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 600))
        )
        guard let formatDescription = group.copyFormatDescription() else {
            throw TAPDepthCaptureError.videoRecordingFailed("unable to create TAP depth metadata format description")
        }
        return formatDescription
    }

    private func logFirstDepthSampleIfNeeded(_ depthData: AVDepthData, timestamp: CMTime) {
        guard !hasLoggedFirstDepthSample else {
            return
        }
        hasLoggedFirstDepthSample = true
        let timestampSeconds = CMTimeGetSeconds(timestamp)
        TAPVideoPerformanceTrace.emitCaptureFirstDepth(
            timestampSeconds: timestampSeconds.isFinite ? timestampSeconds : -1
        )
        emitRuntimeCheckpoint(stage: "capture-first-depth")
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        let map = depthData.depthDataMap
        TAPDiagnostics.cameraCapture.info("video depth output first sample captureID=\(self.request.captureID, privacy: .private) pixelFormat=\(TAPFourCharCode.string(from: CVPixelBufferGetPixelFormatType(map)), privacy: .public) width=\(CVPixelBufferGetWidth(map), privacy: .public) height=\(CVPixelBufferGetHeight(map), privacy: .public) sourceRowStride=\(CVPixelBufferGetBytesPerRow(map), privacy: .public) timestamp=\(CMTimeGetSeconds(timestamp), privacy: .public) filtered=\(depthData.isDepthDataFiltered, privacy: .public) calibration=\(depthData.cameraCalibrationData != nil, privacy: .public)")
        #endif
    }

    private func emitRuntimeCheckpoint(stage: String) {
        TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
            stage: stage,
            rgbFrames: videoFrameCount,
            videoDrops: videoDropCount,
            audioSamples: audioSampleCount,
            audioDrops: audioDropCount,
            depthDelivered: depthDeliveredSampleCount,
            depthStored: depthSampleCount,
            depthOutputDrops: depthOutputDropCount,
            depthMetadataDrops: depthMetadataDropCount,
            depthEncodingDrops: depthEncodingDropCount
        )
    }

    private func logDepthMetadataInputUnavailableIfNeeded(reason: String) {
        guard !hasLoggedDepthMetadataInputUnavailable else {
            return
        }
        hasLoggedDepthMetadataInputUnavailable = true
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.error("video depth metadata input unavailable captureID=\(self.request.captureID, privacy: .private) reason=\(reason, privacy: .public) writerStatus=\(self.assetWriter.status.rawValue, privacy: .public) writerError=\(self.assetWriter.error.map(TAPDiagnostics.describe) ?? "none", privacy: .public)")
        #endif
    }

    private func logDepthMetadataAppendFailureIfNeeded() {
        guard !hasLoggedDepthMetadataAppendFailure else {
            return
        }
        hasLoggedDepthMetadataAppendFailure = true
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.error("video depth metadata append failed captureID=\(self.request.captureID, privacy: .private) writerStatus=\(self.assetWriter.status.rawValue, privacy: .public) writerError=\(self.assetWriter.error.map(TAPDiagnostics.describe) ?? "none", privacy: .public)")
        #endif
    }

    private func logDepthDropIfNeeded(reason: AVCaptureOutput.DataDroppedReason) {
        guard depthOutputDropCount == 1 || depthOutputDropCount.isMultiple(of: 30) else {
            return
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("video depth output dropped captureID=\(self.request.captureID, privacy: .private) dropCount=\(self.depthOutputDropCount, privacy: .public) reason=\(Self.depthDropReasonDescription(reason), privacy: .public)")
        #endif
    }

    private static func depthDropReasonDescription(_ reason: AVCaptureOutput.DataDroppedReason) -> String {
        switch reason {
        case .none:
            return "none"
        case .lateData:
            return "lateData"
        case .outOfBuffers:
            return "outOfBuffers"
        case .discontinuity:
            return "discontinuity"
        @unknown default:
            return "unknown-\(reason.rawValue)"
        }
    }

    private func recordDepthGap(
        reason: TAPVideoManifest.DepthGapReason,
        at timestamp: CMTime
    ) {
        recordDepthGap(reason: reason, start: timestamp, end: timestamp)
    }

    private func recordDepthGap(
        reason: TAPVideoManifest.DepthGapReason,
        start: CMTime,
        end: CMTime,
        nearestStartRGBFrame: Int? = nil,
        nearestEndRGBFrame: Int? = nil
    ) {
        guard let firstVideoTime else {
            return
        }
        let nearestRGBFrame = videoFrameCount > 0 ? videoFrameCount - 1 : nil
        guard let gap = TAPVideoCaptureTimeline.depthGap(
            reason: reason,
            start: start,
            end: end,
            relativeTo: firstVideoTime,
            nearestStartRGBFrame: nearestStartRGBFrame ?? nearestRGBFrame,
            nearestEndRGBFrame: nearestEndRGBFrame ?? nearestRGBFrame
        ) else {
            return
        }
        depthGapAccumulator.record(
            gap,
            mergeToleranceSeconds: depthCadenceGapThresholdSeconds
        )
    }

    private func finalizedDepthGaps(
        videoDurationSeconds: Double
    ) -> [TAPVideoManifest.DepthGap] {
        guard depthSampleCount > 0,
              let firstVideoTime,
              let lastDepthTime,
              let videoEndTime = TAPVideoCaptureTimeline.absoluteMediaEndTime(
                  origin: firstVideoTime,
                  durationSeconds: videoDurationSeconds,
                  lastSampleTime: lastVideoTime
              ) else {
            return depthGapAccumulator.gaps
        }
        let trailingInterval = max(
            0,
            CMTimeGetSeconds(CMTimeSubtract(videoEndTime, lastDepthTime))
        )
        guard trailingInterval > depthCadenceGapThresholdSeconds,
              let trailingGap = TAPVideoCaptureTimeline.depthGap(
                  reason: .silentCadence,
                  start: lastDepthTime,
                  end: videoEndTime,
                  relativeTo: firstVideoTime,
                  nearestStartRGBFrame: videoFrameCount > 0 ? videoFrameCount - 1 : nil,
                  nearestEndRGBFrame: videoFrameCount > 0 ? videoFrameCount - 1 : nil
              ) else {
            return depthGapAccumulator.gaps
        }
        var accumulator = depthGapAccumulator
        accumulator.record(
            trailingGap,
            mergeToleranceSeconds: depthCadenceGapThresholdSeconds
        )
        return accumulator.gaps
    }

    private var recordedDurationSeconds: Double {
        guard let firstVideoTime, let lastVideoTime else {
            return 0
        }
        return max(0, CMTimeGetSeconds(CMTimeSubtract(lastVideoTime, firstVideoTime)))
    }

    private var depthCadenceGapThresholdSeconds: Double {
        max(2 * (nominalDepthIntervalSeconds ?? 0), 0.1)
    }

    private var nominalDepthIntervalSeconds: Double? {
        guard let frameRate = sessionConfiguration.device.activeDepthDataFormat?
            .videoSupportedFrameRateRanges
            .map(\.maxFrameRate)
            .max(), frameRate > 0 else {
            return nil
        }
        return 1 / frameRate
    }

    private func makeManifest(fileFacts: TAPVideoRecordedFileFacts) throws -> TAPVideoManifest {
        let audioStatus: TAPVideoManifest.AudioStatus
        if fileFacts.audioTrackID != nil {
            audioStatus = .captured
        } else if request.recordsAudio {
            audioStatus = .unavailable
        } else {
            audioStatus = .notCaptured
        }

        let depthGaps = finalizedDepthGaps(
            videoDurationSeconds: fileFacts.videoDurationSeconds
        )
        let depthCoverage: TAPVideoManifest.DepthCoverage
        if depthSampleCount > 0 {
            guard let depthMetadataTrackID = fileFacts.depthMetadataTrackID,
                  let depthMetadataCodec = fileFacts.depthMetadataCodec,
                  let depthMetadataDurationSeconds = fileFacts.depthMetadataDurationSeconds,
                  let depthMetadataTimeScale = fileFacts.depthMetadataTimeScale else {
                throw TAPDepthCaptureError.videoRecordingFailed(
                    "finished MP4 is missing stored depth metadata track facts"
                )
            }
            depthCoverage = TAPVideoManifest.DepthCoverage(
                trackID: depthMetadataTrackID,
                trackCodec: depthMetadataCodec,
                trackDurationSeconds: depthMetadataDurationSeconds,
                trackTimeScale: depthMetadataTimeScale,
                sampleCount: depthSampleCount,
                deliveredSampleCount: depthDeliveredSampleCount,
                outputDropCount: depthOutputDropCount,
                encodingDropCount: depthEncodingDropCount,
                metadataDropCount: depthMetadataDropCount,
                gaps: depthGaps,
                format: firstDepthFormat
            )
        } else {
            let gap: TAPVideoManifest.DepthGap? = {
                guard let firstVideoTime,
                      let videoEndTime = TAPVideoCaptureTimeline.absoluteMediaEndTime(
                          origin: firstVideoTime,
                          durationSeconds: fileFacts.videoDurationSeconds,
                          lastSampleTime: lastVideoTime
                      ) else {
                    return nil
                }
                return TAPVideoCaptureTimeline.depthGap(
                    reason: .silentCadence,
                    start: firstVideoTime,
                    end: videoEndTime,
                    relativeTo: firstVideoTime,
                    nearestStartRGBFrame: videoFrameCount > 0 ? 0 : nil,
                    nearestEndRGBFrame: videoFrameCount > 0 ? videoFrameCount - 1 : nil
                )
            }()
            depthCoverage = TAPVideoManifest.DepthCoverage(
                trackID: nil,
                sampleCount: 0,
                deliveredSampleCount: depthDeliveredSampleCount,
                outputDropCount: depthOutputDropCount,
                encodingDropCount: depthEncodingDropCount,
                metadataDropCount: depthMetadataDropCount,
                gaps: gap.map { depthGaps + [$0] } ?? depthGaps,
                format: nil
            )
        }

        let plan = sessionConfiguration.capturePlan
        return TAPVideoManifest(payload: TAPVideoManifest.Payload(
            id: request.captureID,
            packageID: request.packageID.uuidString,
            capturedAt: TAPDateFormatting.iso8601.string(from: request.capturedAt),
            selectedCameraPlan: TAPVideoManifest.SelectedCameraPlan(
                deviceUniqueID: sessionConfiguration.device.uniqueID,
                deviceType: sessionConfiguration.device.deviceType.rawValue,
                localizedName: sessionConfiguration.device.localizedName,
                position: sessionConfiguration.device.position.tapManifestValue,
                requestedFocalLengthLabel: plan.requestedFocalLengthLabel.label,
                resolvedFocalLengthLabel: sessionConfiguration.selectionContext.selectedFocalLengthLabel,
                resolvedZoomFactor: plan.zoom?.rawVideoZoomFactor,
                depthCapable: sessionConfiguration.depthDeliverySupported
            ),
            container: TAPVideoManifest.Container(
                fileType: "mp4",
                mediaType: "video/mp4",
                durationSeconds: fileFacts.durationSeconds,
                timeScale: fileFacts.timeScale,
                trackCount: fileFacts.trackCount
            ),
            rgbTrack: TAPVideoManifest.RGBTrack(
                trackID: fileFacts.videoTrackID,
                codec: fileFacts.videoCodec,
                width: fileFacts.videoWidth,
                height: fileFacts.videoHeight,
                durationSeconds: fileFacts.videoDurationSeconds,
                timeScale: fileFacts.videoTimeScale,
                nominalFrameRate: fileFacts.nominalFrameRate,
                frameCount: videoFrameCount,
                transform: transformDescription()
            ),
            audioTrack: TAPVideoManifest.AudioTrack(
                status: audioStatus,
                trackID: fileFacts.audioTrackID,
                codec: fileFacts.audioCodec,
                durationSeconds: fileFacts.audioDurationSeconds,
                timeScale: fileFacts.audioTimeScale,
                sampleRate: fileFacts.audioSampleRate,
                channelCount: fileFacts.audioChannelCount
            ),
            depthCoverage: depthCoverage,
            spatialRegistration: spatialRegistration(fileFacts: fileFacts),
            synchronization: TAPVideoManifest.Synchronization(
                timing: "capture-output-presentation-timestamps",
                rgbToDepthMapping: depthSampleCount > 0 ? "independent-timed-metadata" : "no-depth-samples",
                maxObservedDeltaSeconds: maxObservedRGBDepthDeltaSeconds,
                maxObservedDepthIntervalSeconds: maxObservedDepthIntervalSeconds,
                nominalDepthIntervalSeconds: nominalDepthIntervalSeconds
            ),
            stop: TAPVideoManifest.Stop(
                reason: stopReason,
                recordedDurationSeconds: fileFacts.durationSeconds
            ),
            software: .current
        ))
    }

    private func videoDimensions() -> CMVideoDimensions {
        if let firstVideoFormatDescription {
            return CMVideoFormatDescriptionGetDimensions(firstVideoFormatDescription)
        }
        return CMVideoFormatDescriptionGetDimensions(sessionConfiguration.device.activeFormat.formatDescription)
    }

    private func nominalFrameRate() -> Double? {
        sessionConfiguration.device.activeFormat.videoSupportedFrameRateRanges
            .map(\.maxFrameRate)
            .max()
    }

    private func transformDescription() -> String? {
        let angle = appliedVideoRotationAngle ?? request.videoRotationAngle
        guard let angle else {
            return nil
        }
        return appliedVideoMirrored
            ? "rotation:\(Int(angle));mirrored"
            : "rotation:\(Int(angle))"
    }

    private func spatialRegistration(
        fileFacts: TAPVideoRecordedFileFacts
    ) -> TAPVideoManifest.SpatialRegistration {
        guard depthSampleCount > 0,
              let depthFormat = firstDepthFormat,
              let videoFormat = firstVideoFormatDescription else {
            return .unavailable
        }
        let calibration = depthCalibrationTable.entries.first
        let calibrationCoverage = TAPVideoManifest.CalibrationCoverage(
            indexedSampleCount: depthSamplesWithCalibrationIndex,
            missingCalibrationSampleCount: depthSamplesMissingCalibration,
            overflowUnindexedSampleCount: depthSamplesWithUnindexedCalibration,
            tableOverflowed: depthCalibrationTable.didOverflow
        )
        let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(
            videoFormat,
            originIsAtTopLeft: true
        )
        let encodedDimensions = TAPVideoManifest.Dimensions(
            width: Double(fileFacts.videoWidth),
            height: Double(fileFacts.videoHeight)
        )
        let normalizedRotation = Self.normalizedQuarterTurn(appliedVideoRotationAngle)
        let alignedDimensions: TAPVideoManifest.Dimensions
        if normalizedRotation == 90 || normalizedRotation == 270 {
            alignedDimensions = TAPVideoManifest.Dimensions(
                width: encodedDimensions.height,
                height: encodedDimensions.width
            )
        } else {
            alignedDimensions = encodedDimensions
        }
        let depthDimensions = TAPVideoManifest.Dimensions(
            width: Double(depthFormat.width),
            height: Double(depthFormat.height)
        )
        let cleanApertureValue = TAPVideoManifest.Rect(
            x: cleanAperture.origin.x,
            y: cleanAperture.origin.y,
            width: cleanAperture.width,
            height: cleanAperture.height
        )
        let connectionTransform = appliedVideoMirrored
            ? "rotation:\(normalizedRotation);mirrored"
            : "rotation:\(normalizedRotation);not-mirrored"

        var registrationFailures: [String] = []
        if !usesSynchronizedRGBDepthOutput { registrationFailures.append("not-synchronized") }
        if !observedSynchronizedRGBDepthPair { registrationFailures.append("no-rgb-depth-pair") }
        if maxObservedRGBDepthDeltaSeconds == nil { registrationFailures.append("missing-sync-delta") }
        if depthFormatChanged { registrationFailures.append("depth-format-changed") }
        if !observedDepthConnectionConfiguration { registrationFailures.append("depth-connection-unobserved") }
        if normalizedRotation < 0 { registrationFailures.append("unsupported-rgb-rotation") }
        if appliedDepthMirrored { registrationFailures.append("depth-mirrored") }
        if Self.normalizedQuarterTurn(appliedDepthRotationAngle) != 0 {
            registrationFailures.append("depth-rotated")
        }
        if appliedVideoStabilizationMode != .off { registrationFailures.append("rgb-stabilized") }
        if cleanAperture.width <= 0 || cleanAperture.height <= 0 {
            registrationFailures.append("invalid-clean-aperture")
        }
        if !Self.isValidDimensions(encodedDimensions) {
            registrationFailures.append("invalid-encoded-dimensions")
        }
        if !Self.isValidDimensions(alignedDimensions) {
            registrationFailures.append("invalid-aligned-dimensions")
        }
        if !Self.isValidDimensions(depthDimensions) {
            registrationFailures.append("invalid-depth-dimensions")
        }
        if !Self.isContained(cleanApertureValue, in: encodedDimensions) {
            registrationFailures.append("clean-aperture-outside-rgb")
        }
        if !Self.hasMatchingAspectRatio(depthDimensions, alignedDimensions) {
            registrationFailures.append("rgb-depth-aspect-mismatch")
        }

        guard registrationFailures.isEmpty else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error(
                "video 2D registration unavailable captureID=\(self.request.captureID, privacy: .private) reasons=\(registrationFailures.joined(separator: ","), privacy: .public)"
            )
            #endif
            return TAPVideoManifest.SpatialRegistration(
                status: .unavailable,
                mapping: "avdepthdata-registration-prerequisites-unavailable:"
                    + registrationFailures.joined(separator: ","),
                rgbReferenceDimensions: alignedDimensions,
                depthReferenceDimensions: depthDimensions,
                rgbCleanAperture: cleanApertureValue,
                recordedTransform: transformDescription() ?? connectionTransform,
                calibration: calibration,
                calibrationTable: depthCalibrationTable.entries,
                calibrationCoverage: calibrationCoverage,
                descriptor: nil
            )
        }

        let scaleX = alignedDimensions.width / depthDimensions.width
        let scaleY = alignedDimensions.height / depthDimensions.height
        let descriptor = TAPVideoManifest.RegistrationDescriptor(
            alignedRGBCodedDimensions: alignedDimensions,
            encodedRGBCodedDimensions: encodedDimensions,
            depthDimensions: depthDimensions,
            depthToAlignedRGBPixelCenterAffine: [
                scaleX, 0, 0.5 * scaleX - 0.5,
                0, scaleY, 0.5 * scaleY - 0.5
            ],
            connectionTransform: connectionTransform,
            isEncodedHorizontallyMirrored: appliedVideoMirrored,
            rgbCleanAperture: cleanApertureValue,
            videoStabilizationMode: "off"
        )
        return TAPVideoManifest.SpatialRegistration(
            status: .registered,
            mapping: TAPVideoManifest.RegistrationDescriptor.schemaID,
            rgbReferenceDimensions: alignedDimensions,
            depthReferenceDimensions: depthDimensions,
            rgbCleanAperture: cleanApertureValue,
            recordedTransform: connectionTransform,
            calibration: calibration,
            calibrationTable: depthCalibrationTable.entries,
            calibrationCoverage: calibrationCoverage,
            descriptor: descriptor
        )
    }

    private static func normalizedQuarterTurn(_ angle: CGFloat?) -> Int {
        guard let angle, angle.isFinite else {
            return 0
        }
        let normalized = ((Int(angle.rounded()) % 360) + 360) % 360
        return [0, 90, 180, 270].contains(normalized) ? normalized : -1
    }

    private static func isValidDimensions(_ dimensions: TAPVideoManifest.Dimensions) -> Bool {
        dimensions.width.isFinite
            && dimensions.height.isFinite
            && dimensions.width > 0
            && dimensions.height > 0
    }

    private static func isContained(
        _ rect: TAPVideoManifest.Rect,
        in dimensions: TAPVideoManifest.Dimensions
    ) -> Bool {
        rect.x.isFinite
            && rect.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.x >= 0
            && rect.y >= 0
            && rect.width > 0
            && rect.height > 0
            && rect.x + rect.width <= dimensions.width + 0.001
            && rect.y + rect.height <= dimensions.height + 0.001
    }

    private static func hasMatchingAspectRatio(
        _ lhs: TAPVideoManifest.Dimensions,
        _ rhs: TAPVideoManifest.Dimensions
    ) -> Bool {
        let lhsAspect = lhs.width / lhs.height
        let rhsAspect = rhs.width / rhs.height
        return abs(lhsAspect - rhsAspect) / max(lhsAspect, rhsAspect) <= 0.005
    }

    private static func cameraCalibration(
        from calibration: AVCameraCalibrationData?
    ) -> TAPVideoManifest.CameraCalibration? {
        guard let calibration else {
            return nil
        }
        let intrinsic = calibration.intrinsicMatrix
        let extrinsic = calibration.extrinsicMatrix
        return TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [
                intrinsic.columns.0.x, intrinsic.columns.0.y, intrinsic.columns.0.z,
                intrinsic.columns.1.x, intrinsic.columns.1.y, intrinsic.columns.1.z,
                intrinsic.columns.2.x, intrinsic.columns.2.y, intrinsic.columns.2.z
            ],
            intrinsicMatrixReferenceDimensions: TAPVideoManifest.Dimensions(
                width: calibration.intrinsicMatrixReferenceDimensions.width,
                height: calibration.intrinsicMatrixReferenceDimensions.height
            ),
            extrinsicMatrix: [
                extrinsic.columns.0.x, extrinsic.columns.0.y, extrinsic.columns.0.z,
                extrinsic.columns.1.x, extrinsic.columns.1.y, extrinsic.columns.1.z,
                extrinsic.columns.2.x, extrinsic.columns.2.y, extrinsic.columns.2.z,
                extrinsic.columns.3.x, extrinsic.columns.3.y, extrinsic.columns.3.z
            ],
            pixelSizeMillimeters: calibration.pixelSize,
            lensDistortionCenter: TAPVideoManifest.Point(
                x: calibration.lensDistortionCenter.x,
                y: calibration.lensDistortionCenter.y
            ),
            lensDistortionLookupTable: calibration.lensDistortionLookupTable,
            inverseLensDistortionLookupTable: calibration.inverseLensDistortionLookupTable
        )
    }
}

nonisolated private struct TAPVideoRecordedFileFacts: Sendable {
    let durationSeconds: Double
    let timeScale: Int32
    let trackCount: Int
    let videoTrackID: Int32
    let videoCodec: String
    let videoWidth: Int32
    let videoHeight: Int32
    let videoDurationSeconds: Double
    let videoTimeScale: Int32
    let nominalFrameRate: Double?
    let audioTrackID: Int32?
    let audioCodec: String?
    let audioDurationSeconds: Double?
    let audioTimeScale: Int32?
    let audioSampleRate: Double?
    let audioChannelCount: Int?
    let depthMetadataTrackID: Int32?
    let depthMetadataCodec: String?
    let depthMetadataDurationSeconds: Double?
    let depthMetadataTimeScale: Int32?

    static func load(from fileURL: URL) async throws -> Self {
        let asset = AVURLAsset(url: fileURL)
        async let loadedTracks = asset.load(.tracks)
        async let videoTracks = asset.loadTracks(withMediaType: .video)
        async let audioTracks = asset.loadTracks(withMediaType: .audio)
        async let metadataTracks = asset.loadTracks(withMediaType: .metadata)
        async let loadedDuration = asset.load(.duration)

        let tracks = try await loadedTracks
        let resolvedVideoTracks = try await videoTracks
        let resolvedAudioTracks = try await audioTracks
        let resolvedMetadataTracks = try await metadataTracks
        guard let videoTrack = resolvedVideoTracks.first else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "finished MP4 is missing its video track"
            )
        }
        let duration = try await loadedDuration
        let videoTrackID = videoTrack.trackID
        let metadataTrackID = resolvedMetadataTracks.first?.trackID
        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let videoDescription = videoDescriptions.first else {
            throw TAPDepthCaptureError.videoRecordingFailed("finished MP4 video format is unavailable")
        }
        let videoDimensions = CMVideoFormatDescriptionGetDimensions(videoDescription)
        let videoCodec = TAPFourCharCode.string(
            from: CMFormatDescriptionGetMediaSubType(videoDescription)
        )
        let videoTiming = try await trackTiming(videoTrack)
        let nominalFrameRate = Double(try await videoTrack.load(.nominalFrameRate))

        let audioTrackID: Int32?
        let audioDescription: CMFormatDescription?
        let audioTiming: TAPVideoTrackTiming?
        if let audioTrack = resolvedAudioTracks.first {
            audioTrackID = audioTrack.trackID
            let descriptions = try await audioTrack.load(.formatDescriptions)
            audioDescription = descriptions.first
            audioTiming = try await trackTiming(audioTrack)
        } else {
            audioTrackID = nil
            audioDescription = nil
            audioTiming = nil
        }
        let audioCodec = audioDescription.map {
            TAPFourCharCode.string(from: CMFormatDescriptionGetMediaSubType($0))
        }
        let audioStreamDescription = audioDescription.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }

        let metadataCodec: String?
        let metadataTiming: TAPVideoTrackTiming?
        if let metadataTrack = resolvedMetadataTracks.first {
            let metadataDescriptions = try await metadataTrack.load(.formatDescriptions)
            metadataCodec = metadataDescriptions.first.map {
                TAPFourCharCode.string(from: CMFormatDescriptionGetMediaSubType($0))
            }
            metadataTiming = try await trackTiming(metadataTrack)
        } else {
            metadataCodec = nil
            metadataTiming = nil
        }

        return Self(
            durationSeconds: max(0, CMTimeGetSeconds(duration)),
            timeScale: duration.timescale,
            trackCount: tracks.count,
            videoTrackID: videoTrackID,
            videoCodec: videoCodec,
            videoWidth: videoDimensions.width,
            videoHeight: videoDimensions.height,
            videoDurationSeconds: videoTiming.durationSeconds,
            videoTimeScale: videoTiming.timeScale,
            nominalFrameRate: nominalFrameRate > 0 ? nominalFrameRate : nil,
            audioTrackID: audioTrackID,
            audioCodec: audioCodec,
            audioDurationSeconds: audioTiming?.durationSeconds,
            audioTimeScale: audioTiming?.timeScale,
            audioSampleRate: audioStreamDescription?.mSampleRate,
            audioChannelCount: audioStreamDescription.map { Int($0.mChannelsPerFrame) },
            depthMetadataTrackID: metadataTrackID,
            depthMetadataCodec: metadataCodec,
            depthMetadataDurationSeconds: metadataTiming?.durationSeconds,
            depthMetadataTimeScale: metadataTiming?.timeScale
        )
    }

    private static func trackTiming(_ track: AVAssetTrack) async throws -> TAPVideoTrackTiming {
        async let loadedTimeRange = track.load(.timeRange)
        async let loadedNaturalTimeScale = track.load(.naturalTimeScale)
        let timeRange = try await loadedTimeRange
        let naturalTimeScale = try await loadedNaturalTimeScale
        let durationSeconds = CMTimeGetSeconds(timeRange.duration)
        let timeScale = naturalTimeScale > 0 ? naturalTimeScale : timeRange.duration.timescale
        guard durationSeconds.isFinite,
              durationSeconds >= 0,
              timeScale > 0 else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "finished MP4 track timing is invalid"
            )
        }
        return TAPVideoTrackTiming(
            durationSeconds: durationSeconds,
            timeScale: timeScale
        )
    }
}

nonisolated private struct TAPVideoTrackTiming: Sendable {
    let durationSeconds: Double
    let timeScale: Int32
}

nonisolated final class TAPVideoRecorderOutputDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureDataOutputSynchronizerDelegate,
    AVCaptureDepthDataOutputDelegate,
    @unchecked Sendable {
    private weak var recorder: TAPVideoRecorder?

    init(recorder: TAPVideoRecorder) {
        self.recorder = recorder
        super.init()
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

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        recorder?.handleSynchronizedDataCollection(
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
        recorder?.handleDepthData(
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
        recorder?.handleDroppedDepthData(
            output,
            depthData: depthData,
            timestamp: timestamp,
            connection: connection,
            reason: reason
        )
    }
}

nonisolated private extension AVCaptureDevice.Position {
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

nonisolated private extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    mutating func appendInt32BE(_ value: Int32) {
        appendUInt32BE(UInt32(bitPattern: value))
    }

    mutating func appendInt64BE(_ value: Int64) {
        let rawValue = UInt64(bitPattern: value)
        append(contentsOf: [
            UInt8((rawValue >> 56) & 0xff),
            UInt8((rawValue >> 48) & 0xff),
            UInt8((rawValue >> 40) & 0xff),
            UInt8((rawValue >> 32) & 0xff),
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ])
    }
}
