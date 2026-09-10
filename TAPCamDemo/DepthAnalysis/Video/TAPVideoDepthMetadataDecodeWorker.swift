//
//  TAPVideoDepthMetadataDecodeWorker.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import ImageIO

/// Pure async decoding stages shared by bounded probes and pushed metadata.
/// Admission ownership and MainActor delivery remain with the output adapter.
nonisolated enum TAPVideoDepthMetadataDecodeWorker {
    static func probePayload(
        fileURL: URL,
        trackID: CMPersistentTrackID,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        rendersHeatmap: Bool,
        decodeAdmission: TAPVideoDepthDecodeAdmission,
        token: TAPVideoDepthDecodeAdmission.Token
    ) async -> TAPVideoDepthPipelineEvent.Payload? {
        do {
            let result = try await TAPVideoDepthMetadataReader.readNearestFrame(
                fileURL: fileURL,
                trackID: trackID,
                playbackTimeSeconds: playbackTimeSeconds,
                staleToleranceSeconds: staleToleranceSeconds,
                leadToleranceSeconds: leadToleranceSeconds,
                depthFormat: depthFormat,
                displayOrientation: displayOrientation,
                rendersHeatmap: rendersHeatmap,
                shouldContinue: {
                    !Task.isCancelled && decodeAdmission.isCurrent(token)
                }
            )
            switch result {
            case .frame(let frame):
                return .frame(frame)
            case .noSample:
                return .noSample(playbackTimeSeconds: playbackTimeSeconds)
            }
        } catch is CancellationError {
            return nil
        } catch let failure as TAPVideoDepthMetadataReaderFailure {
            return .decodeFailed(
                reason: failure.reason,
                presentationTimeSeconds: playbackTimeSeconds
            )
        } catch {
            return .decodeFailed(
                reason: .metadataRead,
                presentationTimeSeconds: playbackTimeSeconds
            )
        }
    }

    static func pushedPayload(
        item: AVMetadataItem,
        presentationTimeSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        rendersHeatmap: Bool,
        decodeAdmission: TAPVideoDepthDecodeAdmission,
        token: TAPVideoDepthDecodeAdmission.Token
    ) async -> TAPVideoDepthPipelineEvent.Payload? {
        let data: Data
        do {
            guard let loadedData = try await item.load(.dataValue) else {
                throw TAPVideoDepthMetadataReaderFailure(reason: .metadataRead)
            }
            data = loadedData
        } catch {
            return .decodeFailed(
                reason: .metadataRead,
                presentationTimeSeconds: presentationTimeSeconds
            )
        }
        guard decodeAdmission.isCurrent(token) else {
            return nil
        }
        do {
            return .frame(try TAPDepthFrameDecoder.decode(
                data,
                presentationTimeSeconds: presentationTimeSeconds,
                depthFormat: depthFormat,
                displayOrientation: displayOrientation,
                rendersHeatmap: rendersHeatmap,
                shouldContinue: { decodeAdmission.isCurrent(token) }
            ))
        } catch is CancellationError {
            return nil
        } catch {
            return .decodeFailed(
                reason: .decode,
                presentationTimeSeconds: presentationTimeSeconds
            )
        }
    }
}
