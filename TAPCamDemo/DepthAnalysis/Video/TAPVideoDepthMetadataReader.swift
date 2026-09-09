//
//  TAPVideoDepthMetadataReader.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import ImageIO

nonisolated struct TAPVideoPlaybackPresentation {
    let depthFrameOrientation: CGImagePropertyOrientation
    let registrationDescriptor: TAPVideoDepthRegistrationDescriptor?
    let depthFormat: TAPVideoManifest.DepthFormat?
    let depthTrackID: CMPersistentTrackID?
}

nonisolated enum TAPVideoDepthMetadataReaderResult {
    case frame(TAPDecodedDepthVideoFrame)
    case noSample
}

nonisolated struct TAPVideoDepthMetadataReaderFailure: Error {
    let reason: TAPVideoDepthPipelineDecodeFailureReason
}

nonisolated enum TAPVideoDepthMetadataReader {
    private struct ReadContext {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let window: TAPVideoDepthMetadataProbePolicy.Window
    }

    private struct Candidates {
        var items: [AVMetadataItem] = []
        var timestamps: [Double] = []
    }

    private static let metadataIdentifier = AVMetadataIdentifier(
        rawValue: "mdta/com.tapnap.depth.klv"
    )

    static func presentation(
        for fileURL: URL,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting
    ) async -> TAPVideoPlaybackPresentation {
        await Task.detached(priority: .utility) {
            do {
                let manifest = try TAPVideoManifestBox.decodedManifest(fromFileAt: fileURL)
                return TAPVideoPlaybackPresentation(
                    depthFrameOrientation: TAPVideoDepthDisplayOrientation.cgImageOrientation(
                        from: manifest.payload.rgbTrack.transform
                    ),
                    registrationDescriptor: registrationAdapter.registrationDescriptor(for: manifest),
                    depthFormat: manifest.payload.depthCoverage.format,
                    depthTrackID: manifest.payload.depthCoverage.trackID
                )
            } catch {
                return TAPVideoPlaybackPresentation(
                    depthFrameOrientation: .up,
                    registrationDescriptor: nil,
                    depthFormat: nil,
                    depthTrackID: nil
                )
            }
        }.value
    }

    static func readNearestFrame(
        fileURL: URL,
        trackID: CMPersistentTrackID,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        shouldContinue: @escaping @Sendable () -> Bool
    ) async throws -> TAPVideoDepthMetadataReaderResult {
        let context = try await readContext(
            fileURL: fileURL,
            trackID: trackID,
            playbackTimeSeconds: playbackTimeSeconds,
            staleToleranceSeconds: staleToleranceSeconds,
            leadToleranceSeconds: leadToleranceSeconds,
            shouldContinue: shouldContinue
        )
        guard let context else {
            return .noSample
        }
        guard let candidate = try await nearestCandidate(
            in: context,
            playbackTimeSeconds: playbackTimeSeconds,
            shouldContinue: shouldContinue
        ) else {
            return .noSample
        }
        do {
            return .frame(try TAPDepthFrameDecoder.decode(
                candidate.data,
                presentationTimeSeconds: candidate.timestamp,
                depthFormat: depthFormat,
                displayOrientation: displayOrientation,
                shouldContinue: shouldContinue
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TAPVideoDepthMetadataReaderFailure(reason: .decode)
        }
    }

    private static func readContext(
        fileURL: URL,
        trackID: CMPersistentTrackID,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double,
        shouldContinue: @escaping @Sendable () -> Bool
    ) async throws -> ReadContext? {
        try checkCancellation(shouldContinue)
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        guard let window = TAPVideoDepthMetadataProbePolicy.window(
            playbackTimeSeconds: playbackTimeSeconds,
            staleToleranceSeconds: staleToleranceSeconds,
            leadToleranceSeconds: leadToleranceSeconds,
            assetDurationSeconds: CMTimeGetSeconds(duration)
        ) else {
            return nil
        }
        let tracks = try await asset.loadTracks(withMediaType: .metadata)
        try checkCancellation(shouldContinue)
        guard let track = tracks.first(where: { $0.trackID == trackID }) else {
            return nil
        }
        return ReadContext(asset: asset, track: track, window: window)
    }

    private static func nearestCandidate(
        in context: ReadContext,
        playbackTimeSeconds: Double,
        shouldContinue: @escaping @Sendable () -> Bool
    ) async throws -> (data: Data, timestamp: Double)? {
        let reader = try makeReader(for: context)
        let output = AVAssetReaderTrackOutput(track: context.track, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
        }
        reader.add(output)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        guard reader.startReading() else {
            throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
        }
        defer {
            if reader.status == .reading {
                reader.cancelReading()
            }
        }
        let candidates = try collectCandidates(
            from: adaptor,
            window: context.window,
            shouldContinue: shouldContinue
        )
        guard reader.status != .failed else {
            throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
        }
        try checkCancellation(shouldContinue)
        guard let index = TAPVideoDepthMetadataProbePolicy.nearestCandidateIndex(
            timestamps: candidates.timestamps,
            playbackTimeSeconds: playbackTimeSeconds,
            window: context.window
        ) else {
            return nil
        }
        let data = try await loadData(from: candidates.items[index])
        return (data, candidates.timestamps[index])
    }

    private static func makeReader(for context: ReadContext) throws -> AVAssetReader {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: context.asset)
        } catch {
            throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
        }
        let scale: CMTimeScale = 600
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: context.window.startSeconds, preferredTimescale: scale),
            end: CMTime(seconds: context.window.endSeconds, preferredTimescale: scale)
        )
        return reader
    }

    private static func collectCandidates(
        from adaptor: AVAssetReaderOutputMetadataAdaptor,
        window: TAPVideoDepthMetadataProbePolicy.Window,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> Candidates {
        var candidates = Candidates()
        candidates.items.reserveCapacity(16)
        candidates.timestamps.reserveCapacity(16)
        var groupCount = 0
        while let group = adaptor.nextTimedMetadataGroup() {
            try checkCancellation(shouldContinue)
            groupCount += 1
            guard groupCount <= TAPVideoDepthMetadataProbePolicy.maximumMetadataGroupCount else {
                throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
            }
            let timestamp = CMTimeGetSeconds(group.timeRange.start)
            guard timestamp.isFinite,
                  timestamp >= window.startSeconds,
                  timestamp <= window.endSeconds,
                  let item = group.items.first(where: { $0.identifier == metadataIdentifier }) else {
                continue
            }
            candidates.timestamps.append(timestamp)
            candidates.items.append(item)
        }
        return candidates
    }

    private static func loadData(from item: AVMetadataItem) async throws -> Data {
        do {
            guard let data = try await item.load(.dataValue) else {
                throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as TAPVideoDepthMetadataReaderFailure {
            throw failure
        } catch {
            throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
        }
    }

    private static func checkCancellation(
        _ shouldContinue: @escaping @Sendable () -> Bool
    ) throws {
        guard shouldContinue() else {
            throw CancellationError()
        }
    }
}
