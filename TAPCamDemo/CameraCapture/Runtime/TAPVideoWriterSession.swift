//
//  TAPVideoWriterSession.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

nonisolated final class TAPVideoWriterSession: @unchecked Sendable {
    enum VideoAppendOutcome {
        case appended(startedAt: CMTime?)
        case dropped(startedAt: CMTime?)
        case ignored
        case failed
    }

    enum AudioAppendOutcome {
        case appended(sampleCount: Int)
        case dropped
        case ignored
    }

    enum DepthMetadataDestination {
        case ready(AVAssetWriterInputMetadataAdaptor)
        case backpressured
        case unavailable
    }

    let writerURL: URL
    let recordsAudio: Bool
    let recordsDepth: Bool
    private(set) var didStartWriting = false

    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let metadataInput: AVAssetWriterInput?
    private let metadataAdaptor: AVAssetWriterInputMetadataAdaptor?

    init(
        request: TAPVideoRecordingRequest,
        videoSettings: [String: Any],
        recordsAudio: Bool,
        recordsDepth: Bool
    ) throws {
        writerURL = request.outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(request.outputURL.deletingPathExtension().lastPathComponent)-writing.mp4"
            )
        try Self.prepareOutputURLs(
            writerURL: writerURL,
            finalURL: request.outputURL
        )
        assetWriter = try AVAssetWriter(outputURL: writerURL, fileType: .mp4)

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        videoInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(videoInput) else {
            throw Self.failure("asset writer rejected video input")
        }
        assetWriter.add(videoInput)

        if recordsAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000
                ]
            )
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                audioInput = input
            } else {
                audioInput = nil
            }
        } else {
            audioInput = nil
        }

        if recordsDepth {
            let input = try AVAssetWriterInput(
                mediaType: .metadata,
                outputSettings: nil,
                sourceFormatHint: TAPVideoDepthMetadataEncoder.makeFormatDescription()
            )
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                metadataInput = input
                metadataAdaptor = AVAssetWriterInputMetadataAdaptor(
                    assetWriterInput: input
                )
            } else {
                metadataInput = nil
                metadataAdaptor = nil
            }
        } else {
            metadataInput = nil
            metadataAdaptor = nil
        }

        self.recordsAudio = audioInput != nil
        self.recordsDepth = metadataInput != nil
    }

    var status: AVAssetWriter.Status {
        assetWriter.status
    }

    var error: (any Error)? {
        assetWriter.error
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) -> VideoAppendOutcome {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var startedAt: CMTime?
        if !didStartWriting {
            guard assetWriter.startWriting() else {
                return .failed
            }
            assetWriter.startSession(atSourceTime: presentationTime)
            didStartWriting = true
            startedAt = presentationTime
        }
        guard assetWriter.status == .writing else {
            return assetWriter.status == .failed ? .failed : .ignored
        }
        guard videoInput.isReadyForMoreMediaData else {
            return .dropped(startedAt: startedAt)
        }
        guard videoInput.append(sampleBuffer) else {
            return assetWriter.status == .failed
                ? .failed : .dropped(startedAt: startedAt)
        }
        return .appended(startedAt: startedAt)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) -> AudioAppendOutcome {
        guard didStartWriting,
              let audioInput,
              assetWriter.status == .writing else {
            return .ignored
        }
        guard audioInput.isReadyForMoreMediaData,
              audioInput.append(sampleBuffer) else {
            return .dropped
        }
        return .appended(sampleCount: CMSampleBufferGetNumSamples(sampleBuffer))
    }

    func depthMetadataDestination() -> DepthMetadataDestination {
        guard let metadataInput,
              let metadataAdaptor,
              assetWriter.status == .writing else {
            return .unavailable
        }
        return metadataInput.isReadyForMoreMediaData
            ? .ready(metadataAdaptor) : .backpressured
    }

    func cancelWriting() {
        assetWriter.cancelWriting()
    }

    func finishWriting(completion: @escaping @Sendable () -> Void) {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        metadataInput?.markAsFinished()
        assetWriter.finishWriting(completionHandler: completion)
    }

    func publish(
        manifest: TAPVideoManifest,
        to outputURL: URL
    ) throws -> UInt64 {
        try TAPVideoManifestBox.appendManifest(manifest, toFileAt: writerURL)
        TAPVideoPerformanceTrace.emitManifestAppended(
            byteCount: try TAPBMFFStreamingFile.byteCount(of: writerURL)
        )
        _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: writerURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: writerURL, to: outputURL)
        return try TAPBMFFStreamingFile.byteCount(of: outputURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: writerURL)
    }

    private static func prepareOutputURLs(
        writerURL: URL,
        finalURL: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: writerURL.path) {
            try fileManager.removeItem(at: writerURL)
        }
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
    }

    private static func failure(_ reason: String) -> TAPDepthCaptureError {
        .videoRecordingFailed(reason)
    }
}
