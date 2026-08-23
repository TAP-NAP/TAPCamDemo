//
//  LibraryVideoPosterService.swift
//  TAPCamDemo
//

import Foundation

nonisolated protocol LibraryVideoPosterGenerating: Sendable {
    func posterData(
        for videoURL: URL,
        cacheKey: String,
        pixelLength: Int
    ) async throws -> Data
}

nonisolated struct AVAssetLibraryVideoPosterGenerator: LibraryVideoPosterGenerating {
    func posterData(
        for videoURL: URL,
        cacheKey: String,
        pixelLength: Int = 512
    ) async throws -> Data {
        guard let data = await DepthAlbumThumbnailLoader.shared.videoData(
            for: videoURL,
            cacheKey: cacheKey,
            pixelLength: pixelLength
        ) else {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw MediaFetchFailure.decode
        }
        return data
    }
}

/// Adapter seam for adding persisted `thumbnail.jpg` backfill without coupling
/// the media UI layer to pending-record mutation APIs.
nonisolated struct LibraryVideoPosterBackfillCandidate: Equatable, Sendable {
    let captureID: String
    let videoURL: URL
    let cacheKey: String
}

nonisolated protocol LibraryVideoPosterBackfillSource: Sendable {
    func videosMissingPosters() async throws -> [LibraryVideoPosterBackfillCandidate]
}

nonisolated protocol LibraryVideoPosterPersisting: Sendable {
    func persistPosterData(_ data: Data, captureID: String) async throws
}

actor LibraryVideoPosterBackfillService {
    private let source: any LibraryVideoPosterBackfillSource
    private let persistence: any LibraryVideoPosterPersisting
    private let generator: any LibraryVideoPosterGenerating
    private let pixelLength: Int

    init(
        source: any LibraryVideoPosterBackfillSource,
        persistence: any LibraryVideoPosterPersisting,
        generator: any LibraryVideoPosterGenerating = AVAssetLibraryVideoPosterGenerator(),
        pixelLength: Int = 512
    ) {
        self.source = source
        self.persistence = persistence
        self.generator = generator
        self.pixelLength = max(pixelLength, 1)
    }

    /// Backfill is best-effort per capture. One corrupt video must not prevent
    /// later candidates from receiving a poster.
    func run() async throws {
        let candidates = try await source.videosMissingPosters()
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                let data = try await generator.posterData(
                    for: candidate.videoURL,
                    cacheKey: candidate.cacheKey,
                    pixelLength: pixelLength
                )
                try await persistence.persistPosterData(data, captureID: candidate.captureID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
    }
}

/// Concrete adapters keep the backfill service injectable while letting the
/// app root reuse the existing pending-capture actor. No new global media store
/// is introduced.
nonisolated struct PendingCaptureVideoPosterBackfillSource: LibraryVideoPosterBackfillSource {
    let store: TAPPendingCaptureStore

    func videosMissingPosters() async throws -> [LibraryVideoPosterBackfillCandidate] {
        let records = try await store.tapVideoRecordsMissingPoster()
        var candidates: [LibraryVideoPosterBackfillCandidate] = []
        candidates.reserveCapacity(records.count)
        for record in records {
            try Task.checkCancellation()
            let videoURL = try await store.videoArtifactURL(captureID: record.captureID)
            let revision = "video-poster-v1|\(record.updatedAt.timeIntervalSince1970)"
            candidates.append(LibraryVideoPosterBackfillCandidate(
                captureID: record.captureID,
                videoURL: videoURL,
                cacheKey: DepthAlbumThumbnailCacheKey.make(
                    mediaID: .tapCapture(record.captureID),
                    version: revision,
                    pixelLength: 512
                )
            ))
        }
        return candidates
    }
}

nonisolated struct PendingCaptureVideoPosterPersistence: LibraryVideoPosterPersisting {
    let store: TAPPendingCaptureStore

    func persistPosterData(_ data: Data, captureID: String) async throws {
        _ = try await store.storeVideoPoster(
            data,
            captureID: captureID,
            posterRevision: 1
        )
    }
}

extension LibraryVideoPosterBackfillService {
    static func pendingCaptureStore(
        _ store: TAPPendingCaptureStore,
        generator: any LibraryVideoPosterGenerating = AVAssetLibraryVideoPosterGenerator()
    ) -> LibraryVideoPosterBackfillService {
        LibraryVideoPosterBackfillService(
            source: PendingCaptureVideoPosterBackfillSource(store: store),
            persistence: PendingCaptureVideoPosterPersistence(store: store),
            generator: generator,
            pixelLength: 512
        )
    }
}
