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
    let debugDepthPreviewURL: URL?
    let maximumDuration: TimeInterval
    let videoRotationAngle: CGFloat?
    let isVideoMirrored: Bool
    let recordsAudio: Bool

    init(
        captureID: String = UUID().uuidString,
        packageID: UUID = UUID(),
        capturedAt: Date = Date(),
        outputURL: URL,
        debugDepthPreviewURL: URL? = nil,
        maximumDuration: TimeInterval = Self.defaultMaximumDuration,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool,
        recordsAudio: Bool
    ) {
        self.captureID = captureID
        self.packageID = packageID
        self.capturedAt = capturedAt
        self.outputURL = outputURL
        self.debugDepthPreviewURL = debugDepthPreviewURL
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
    let unsignedVideoURL: URL
    let debugDepthPreviewVideoURL: URL?
    let manifest: TAPVideoManifest
    let location: TAPPendingCaptureLocation?

    var pendingArtifact: TAPPendingVideoCaptureArtifact {
        TAPPendingVideoCaptureArtifact(
            captureID: captureID,
            packageID: packageID,
            capturedAt: capturedAt,
            unsignedVideoURL: unsignedVideoURL,
            debugDepthPreviewVideoURL: debugDepthPreviewVideoURL,
            captureScoreSummary: .unknown,
            location: location
        )
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
    private let depthPreviewSidecar: TAPDepthPreviewSidecarWriter?
    private weak var synchronizedVideoOutput: AVCaptureVideoDataOutput?
    private weak var synchronizedDepthOutput: AVCaptureDepthDataOutput?

    private var didStartWriting = false
    private var isFinishing = false
    private var stopReason: TAPVideoManifest.StopReason = .userStop
    private var firstVideoTime: CMTime?
    private var lastVideoTime: CMTime?
    private var firstVideoFormatDescription: CMFormatDescription?
    private var videoFrameCount = 0
    private var videoDropCount = 0
    private var audioSampleCount = 0
    private var depthOutputSampleCount = 0
    private var depthOutputDropCount = 0
    private var depthSampleCount = 0
    private var depthFrameIndex = 0
    private var depthSamplesBeforeVideoStart = 0
    private var depthMetadataDropCount = 0
    private var depthPreviewSampleCount = 0
    private var depthPreviewDropCount = 0
    private var hasLoggedFirstDepthSample = false
    private var hasLoggedDepthMetadataInputUnavailable = false
    private var hasLoggedDepthMetadataAppendFailure = false
    private var hasLoggedDepthPreviewAppendFailure = false
    private var firstDepthFormat: TAPVideoManifest.DepthFormat?
    private var lastDepthTime: CMTime?
    private var maxObservedDepthIntervalSeconds: Double?
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

        if recordsDepth, let debugDepthPreviewURL = request.debugDepthPreviewURL {
            self.depthPreviewSidecar = try TAPDepthPreviewSidecarWriter(outputURL: debugDepthPreviewURL)
        } else {
            self.depthPreviewSidecar = nil
        }

        super.init()
        self.outputDelegateStorage = TAPVideoRecorderOutputDelegate(recorder: self)
    }

    func useSynchronizedOutputs(
        videoOutput: AVCaptureVideoDataOutput,
        depthOutput: AVCaptureDepthDataOutput
    ) {
        synchronizedVideoOutput = videoOutput
        synchronizedDepthOutput = depthOutput
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
        _ = output
        _ = sampleBuffer
        _ = connection
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
        _ = timestamp
        _ = connection
        depthOutputDropCount += 1
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

        guard assetWriter.status == .completed else {
            let reason = assetWriter.error.map(TAPDiagnostics.describe) ?? "writer status \(assetWriter.status.rawValue)"
            cleanupWriterFile()
            continuation.resume(throwing: TAPDepthCaptureError.videoRecordingFailed(reason))
            return
        }

        do {
            let baseData = try Data(contentsOf: writerURL)
            let manifest = try makeManifest(baseData: baseData)
            let dataWithManifest = try TAPVideoManifestBox.appendingManifest(manifest, to: baseData)
            let unsignedData = try TAPProofSlot.ensuringEmptyBMFFSlot(in: dataWithManifest)
            try unsignedData.write(to: request.outputURL, options: .atomic)
            cleanupWriterFile()
            finishDepthPreviewSidecar { [weak self] debugDepthPreviewVideoURL in
                guard let self else { return }
                self.resumeFinishedRecording(
                    continuation: continuation,
                    manifest: manifest,
                    unsignedByteCount: unsignedData.count,
                    debugDepthPreviewVideoURL: debugDepthPreviewVideoURL
                )
            }
        } catch {
            cleanupWriterFile()
            depthPreviewSidecar?.cancel()
            try? FileManager.default.removeItem(at: request.outputURL)
            continuation.resume(throwing: error)
        }
    }

    private func cleanupWriterFile() {
        try? FileManager.default.removeItem(at: writerURL)
    }

    private func finishDepthPreviewSidecar(_ completion: @escaping (URL?) -> Void) {
        guard let depthPreviewSidecar else {
            completion(nil)
            return
        }
        depthPreviewSidecar.finish { [weak self] result in
            guard let self else { return }
            self.callbackQueue.async {
                switch result {
                case .success(let url):
                    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                    let byteCount = url.flatMap { try? Data(contentsOf: $0).count } ?? 0
                    TAPDiagnostics.cameraCapture.info("video depth preview sidecar finalized captureID=\(self.request.captureID, privacy: .private) saved=\(url != nil, privacy: .public) frames=\(self.depthPreviewSampleCount, privacy: .public) bytes=\(byteCount, privacy: .public)")
                    #endif
                    completion(url)
                case .failure(let error):
                    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                    TAPDiagnostics.cameraCapture.error("video depth preview sidecar failed captureID=\(self.request.captureID, privacy: .private) frames=\(self.depthPreviewSampleCount, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                    #endif
                    completion(nil)
                }
            }
        }
    }

    private func resumeFinishedRecording(
        continuation: CheckedContinuation<TAPVideoRecordingArtifact, any Error>,
        manifest: TAPVideoManifest,
        unsignedByteCount: Int,
        debugDepthPreviewVideoURL: URL?
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("video recording finalized captureID=\(self.request.captureID, privacy: .private) bytes=\(unsignedByteCount, privacy: .public) duration=\(self.recordedDurationSeconds, privacy: .public) rgbFrames=\(self.videoFrameCount, privacy: .public) videoDrops=\(self.videoDropCount, privacy: .public) audioSamples=\(self.audioSampleCount, privacy: .public) depthOutputSamples=\(self.depthOutputSampleCount, privacy: .public) depthOutputDrops=\(self.depthOutputDropCount, privacy: .public) depthSamples=\(self.depthSampleCount, privacy: .public) depthBeforeVideoStart=\(self.depthSamplesBeforeVideoStart, privacy: .public) depthMetadataDrops=\(self.depthMetadataDropCount, privacy: .public) depthPreviewSamples=\(self.depthPreviewSampleCount, privacy: .public) depthPreviewDrops=\(self.depthPreviewDropCount, privacy: .public) hasDepthPreviewSidecar=\(debugDepthPreviewVideoURL != nil, privacy: .public) stopReason=\(self.stopReason.rawValue, privacy: .public)")
        #endif
        continuation.resume(returning: TAPVideoRecordingArtifact(
            captureID: request.captureID,
            packageID: request.packageID,
            capturedAt: request.capturedAt,
            unsignedVideoURL: request.outputURL,
            debugDepthPreviewVideoURL: debugDepthPreviewVideoURL,
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

        guard videoInput.isReadyForMoreMediaData,
              assetWriter.status == .writing else {
            return
        }

        if videoInput.append(sampleBuffer) {
            videoFrameCount += 1
            lastVideoTime = presentationTime
        }
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinishing,
              didStartWriting,
              let audioInput,
              audioInput.isReadyForMoreMediaData,
              assetWriter.status == .writing else {
            return
        }
        if audioInput.append(sampleBuffer) {
            audioSampleCount += CMSampleBufferGetNumSamples(sampleBuffer)
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

        appendDepthPreviewSample(depthData, timestamp: timestamp)

        guard let metadataAdaptor,
              let metadataInput,
              assetWriter.status == .writing else {
            logDepthMetadataInputUnavailableIfNeeded(reason: "metadata-input-or-writer-not-ready")
            depthMetadataDropCount += 1
            return
        }
        guard metadataInput.isReadyForMoreMediaData else {
            logDepthMetadataInputUnavailableIfNeeded(reason: "metadata-input-backpressure")
            depthMetadataDropCount += 1
            return
        }

        do {
            let encoded = try TAPDepthVideoSampleEncoder.encode(
                depthData: depthData,
                frameIndex: depthFrameIndex,
                timestamp: timestamp
            )
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
                return
            }

            if firstDepthFormat == nil {
                firstDepthFormat = TAPDepthVideoSampleEncoder.depthFormat(from: depthData)
            }
            if let lastDepthTime {
                let interval = max(0, CMTimeGetSeconds(CMTimeSubtract(timestamp, lastDepthTime)))
                maxObservedDepthIntervalSeconds = max(maxObservedDepthIntervalSeconds ?? 0, interval)
            }
            lastDepthTime = timestamp
            depthFrameIndex += 1
            depthSampleCount += 1
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error("video depth sample encode failed captureID=\(self.request.captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            depthMetadataDropCount += 1
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        let format = TAPDepthVideoSampleEncoder.depthFormat(from: depthData)
        TAPDiagnostics.cameraCapture.info("video depth output first sample captureID=\(self.request.captureID, privacy: .private) kind=\(format.kind, privacy: .public) pixelFormat=\(format.pixelFormat, privacy: .public) width=\(format.width, privacy: .public) height=\(format.height, privacy: .public) rowStride=\(format.rowStride, privacy: .public) timestamp=\(CMTimeGetSeconds(timestamp), privacy: .public) filtered=\(depthData.isDepthDataFiltered, privacy: .public) calibration=\(depthData.cameraCalibrationData != nil, privacy: .public)")
        #endif
    }

    private func appendDepthPreviewSample(_ depthData: AVDepthData, timestamp: CMTime) {
        guard let depthPreviewSidecar else {
            return
        }
        do {
            if try depthPreviewSidecar.append(depthData: depthData, timestamp: timestamp) {
                depthPreviewSampleCount += 1
            } else {
                logDepthPreviewAppendFailureIfNeeded(reason: "depth-preview-writer-backpressure")
                depthPreviewDropCount += 1
            }
        } catch {
            depthPreviewDropCount += 1
            logDepthPreviewAppendFailureIfNeeded(reason: TAPDiagnostics.describe(error))
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.cameraCapture.error("video depth preview sample failed captureID=\(self.request.captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
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

    private func logDepthPreviewAppendFailureIfNeeded(reason: String) {
        guard !hasLoggedDepthPreviewAppendFailure else {
            return
        }
        hasLoggedDepthPreviewAppendFailure = true
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.error("video depth preview append failed captureID=\(self.request.captureID, privacy: .private) reason=\(reason, privacy: .public)")
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

    private var recordedDurationSeconds: Double {
        guard let firstVideoTime, let lastVideoTime else {
            return 0
        }
        return max(0, CMTimeGetSeconds(CMTimeSubtract(lastVideoTime, firstVideoTime)))
    }

    private func makeManifest(baseData: Data) throws -> TAPVideoManifest {
        let dimensions = videoDimensions()
        let audioStatus: TAPVideoManifest.AudioStatus
        if audioSampleCount > 0 {
            audioStatus = .captured
        } else if request.recordsAudio {
            audioStatus = .unavailable
        } else {
            audioStatus = .notCaptured
        }

        let depthCoverage: TAPVideoManifest.DepthCoverage
        if depthSampleCount > 0 {
            depthCoverage = TAPVideoManifest.DepthCoverage(
                track: "tap-depth-klv",
                sampleCount: depthSampleCount,
                gaps: [],
                format: firstDepthFormat
            )
        } else {
            let gap = TAPVideoManifest.DepthGap(
                startTime: "0",
                endTime: String(format: "%.6f", recordedDurationSeconds),
                nearestStartRGBFrame: nil,
                nearestEndRGBFrame: videoFrameCount > 0 ? max(videoFrameCount - 1, 0) : nil
            )
            depthCoverage = TAPVideoManifest.DepthCoverage(
                track: nil,
                sampleCount: 0,
                gaps: recordedDurationSeconds > 0 ? [gap] : [],
                format: nil
            )
        }

        let trackCount = 1 + (audioSampleCount > 0 ? 1 : 0) + (depthSampleCount > 0 ? 1 : 0)
        let plan = sessionConfiguration.capturePlan
        return TAPVideoManifest(payload: TAPVideoManifest.Payload(
            id: request.captureID,
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
                durationSeconds: recordedDurationSeconds,
                timeScale: 600,
                trackCount: trackCount
            ),
            rgbTrack: TAPVideoManifest.RGBTrack(
                trackID: nil,
                codec: "h264",
                width: dimensions.width,
                height: dimensions.height,
                nominalFrameRate: nominalFrameRate(),
                frameCount: videoFrameCount,
                transform: transformDescription()
            ),
            audioTrack: TAPVideoManifest.AudioTrack(
                status: audioStatus,
                trackID: nil,
                codec: audioSampleCount > 0 ? "aac" : nil,
                sampleRate: audioSampleCount > 0 ? 44_100 : nil,
                channelCount: audioSampleCount > 0 ? 1 : nil
            ),
            depthCoverage: depthCoverage,
            synchronization: TAPVideoManifest.Synchronization(
                timing: "capture-output-presentation-timestamps",
                rgbToDepthMapping: depthSampleCount > 0 ? "independent-timed-metadata" : "no-depth-samples",
                maxObservedDeltaSeconds: maxObservedDepthIntervalSeconds
            ),
            stop: TAPVideoManifest.Stop(
                reason: stopReason,
                recordedDurationSeconds: recordedDurationSeconds
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
        guard let angle = request.videoRotationAngle else {
            return nil
        }
        return request.isVideoMirrored
            ? "rotation:\(Int(angle));mirrored"
            : "rotation:\(Int(angle))"
    }
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

nonisolated private final class TAPDepthPreviewSidecarWriter: @unchecked Sendable {
    private let outputURL: URL
    private let writerURL: URL
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var didStartWriting = false
    private var frameCount = 0

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        self.writerURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent)-writing.mp4")

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        if fileManager.fileExists(atPath: writerURL.path) {
            try fileManager.removeItem(at: writerURL)
        }
    }

    func append(depthData: AVDepthData, timestamp: CMTime) throws -> Bool {
        let previewDepthData = try Self.previewDepthData(from: depthData)
        let sourceBuffer = previewDepthData.depthDataMap
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        if assetWriter == nil {
            try configureWriter(width: width, height: height)
        }

        guard let assetWriter,
              let videoInput,
              let pixelBufferAdaptor else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth preview writer is not configured")
        }

        if !didStartWriting {
            guard assetWriter.startWriting() else {
                throw TAPDepthCaptureError.videoRecordingFailed(
                    assetWriter.error.map(TAPDiagnostics.describe) ?? "depth preview writer did not start"
                )
            }
            assetWriter.startSession(atSourceTime: timestamp)
            didStartWriting = true
        }

        guard videoInput.isReadyForMoreMediaData else {
            return false
        }

        let pixelBuffer = try Self.makePreviewPixelBuffer(from: previewDepthData.depthDataMap)
        guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: timestamp) else {
            if assetWriter.status == .failed {
                throw TAPDepthCaptureError.videoRecordingFailed(
                    assetWriter.error.map(TAPDiagnostics.describe) ?? "depth preview writer append failed"
                )
            }
            return false
        }
        frameCount += 1
        return true
    }

    func finish(completion: @escaping (Result<URL?, Error>) -> Void) {
        guard frameCount > 0,
              let assetWriter,
              let videoInput else {
            cleanupWriterFile()
            completion(.success(nil))
            return
        }

        videoInput.markAsFinished()
        assetWriter.finishWriting { [weak self, writerURL, outputURL] in
            guard let self else {
                completion(.success(nil))
                return
            }
            guard self.assetWriter?.status == .completed else {
                let reason = self.assetWriter?.error.map(TAPDiagnostics.describe)
                    ?? "depth preview writer status \(self.assetWriter?.status.rawValue ?? -1)"
                try? FileManager.default.removeItem(at: writerURL)
                completion(.failure(TAPDepthCaptureError.videoRecordingFailed(reason)))
                return
            }

            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: writerURL, to: outputURL)
                completion(.success(outputURL))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func cancel() {
        assetWriter?.cancelWriting()
        cleanupWriterFile()
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func configureWriter(width: Int, height: Int) throws {
        let assetWriter = try AVAssetWriter(outputURL: writerURL, fileType: .mp4)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(500_000, width * height * 4),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(videoInput) else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth preview writer rejected video input")
        }
        assetWriter.add(videoInput)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attributes
        )
    }

    private func cleanupWriterFile() {
        try? FileManager.default.removeItem(at: writerURL)
    }

    private static func previewDepthData(from depthData: AVDepthData) throws -> AVDepthData {
        switch depthData.depthDataType {
        case kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32:
            return depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        default:
            return depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }
    }

    private static func makePreviewPixelBuffer(from sourceBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        var outputBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &outputBuffer
        )
        guard status == kCVReturnSuccess, let outputBuffer else {
            throw TAPDepthCaptureError.videoRecordingFailed("unable to allocate depth preview pixel buffer")
        }

        try fillPreviewPixelBuffer(outputBuffer, from: sourceBuffer)
        return outputBuffer
    }

    private static func fillPreviewPixelBuffer(
        _ outputBuffer: CVPixelBuffer,
        from sourceBuffer: CVPixelBuffer
    ) throws {
        guard CVPixelBufferGetPixelFormatType(sourceBuffer) == kCVPixelFormatType_DepthFloat32
                || CVPixelBufferGetPixelFormatType(sourceBuffer) == kCVPixelFormatType_DisparityFloat32 else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth preview source is not Float32")
        }

        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
            CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
        }

        guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(sourceBuffer),
              let outputBaseAddress = CVPixelBufferGetBaseAddress(outputBuffer) else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth preview pixel buffer base address missing")
        }

        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)
        let outputBytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude

        for y in 0..<height {
            let sourceRow = sourceBaseAddress
                .advanced(by: y * sourceBytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                let value = sourceRow[x]
                if value.isFinite {
                    minimum = min(minimum, value)
                    maximum = max(maximum, value)
                }
            }
        }

        let hasUsableRange = minimum.isFinite && maximum.isFinite && maximum > minimum
        for y in 0..<height {
            let sourceRow = sourceBaseAddress
                .advanced(by: y * sourceBytesPerRow)
                .assumingMemoryBound(to: Float.self)
            let outputRow = outputBaseAddress
                .advanced(by: y * outputBytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let value = sourceRow[x]
                let gray: UInt8
                if hasUsableRange, value.isFinite {
                    let normalized = max(0, min(1, (value - minimum) / (maximum - minimum)))
                    gray = UInt8((normalized * 255).rounded())
                } else {
                    gray = 0
                }
                let offset = x * 4
                outputRow[offset] = gray
                outputRow[offset + 1] = gray
                outputRow[offset + 2] = gray
                outputRow[offset + 3] = 255
            }
        }
    }
}

nonisolated private enum TAPDepthVideoSampleEncoder {
    static func encode(depthData: AVDepthData, frameIndex: Int, timestamp: CMTime) throws -> Data {
        let map = depthData.depthDataMap
        let pixelBytes = try copyPixelBytes(from: map)
        let format = depthFormat(from: depthData)
        var frameData = Data()
        frameData.appendUInt32BE(UInt32(frameIndex))

        var timestampData = Data()
        timestampData.appendInt64BE(timestamp.value)
        timestampData.appendInt32BE(timestamp.timescale)

        var dimensionsData = Data()
        dimensionsData.appendInt32BE(format.width)
        dimensionsData.appendInt32BE(format.height)

        var rowStrideData = Data()
        rowStrideData.appendUInt32BE(UInt32(format.rowStride))

        return TAPDepthKLV.encode([
            TAPDepthKLV.Record(key: .schemaVersion, payload: Data([0, 0, 0, 1])),
            TAPDepthKLV.Record(key: .frameIndex, payload: frameData),
            TAPDepthKLV.Record(key: .presentationTime, payload: timestampData),
            TAPDepthKLV.Record(key: .depthKind, payload: Data(format.kind.utf8)),
            TAPDepthKLV.Record(key: .pixelFormat, payload: Data(format.pixelFormat.utf8)),
            TAPDepthKLV.Record(key: .dimensions, payload: dimensionsData),
            TAPDepthKLV.Record(key: .rowStride, payload: rowStrideData),
            TAPDepthKLV.Record(key: .compression, payload: Data(format.compression.utf8)),
            TAPDepthKLV.Record(key: .calibrationReference, payload: Data((format.calibrationReference ?? "none").utf8)),
            TAPDepthKLV.Record(key: .depthPayload, payload: pixelBytes)
        ])
    }

    static func depthFormat(from depthData: AVDepthData) -> TAPVideoManifest.DepthFormat {
        let map = depthData.depthDataMap
        return TAPVideoManifest.DepthFormat(
            kind: depthKind(for: depthData.depthDataType),
            pixelFormat: TAPFourCharCode.string(from: CVPixelBufferGetPixelFormatType(map)),
            width: Int32(CVPixelBufferGetWidth(map)),
            height: Int32(CVPixelBufferGetHeight(map)),
            rowStride: CVPixelBufferGetBytesPerRow(map),
            compression: "none",
            calibrationReference: depthData.cameraCalibrationData == nil
                ? nil
                : "AVCameraCalibrationData-present"
        )
    }

    private static func depthKind(for pixelFormat: OSType) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32:
            return "depth"
        case kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32:
            return "disparity"
        default:
            return "unknown"
        }
    }

    private static func copyPixelBytes(from pixelBuffer: CVPixelBuffer) throws -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            var data = Data()
            for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
                guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
                    throw TAPDepthCaptureError.videoRecordingFailed("depth pixel buffer plane base address missing")
                }
                let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                for row in 0..<height {
                    data.append(
                        baseAddress.advanced(by: row * bytesPerRow)
                            .assumingMemoryBound(to: UInt8.self),
                        count: bytesPerRow
                    )
                }
            }
            return data
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TAPDepthCaptureError.videoRecordingFailed("depth pixel buffer base address missing")
        }
        return Data(bytes: baseAddress, count: CVPixelBufferGetDataSize(pixelBuffer))
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
