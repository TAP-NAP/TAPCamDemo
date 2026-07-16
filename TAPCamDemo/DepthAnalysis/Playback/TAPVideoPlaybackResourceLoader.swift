//
//  TAPVideoPlaybackResourceLoader.swift
//  TAPCamDemo
//

import Foundation

@MainActor
struct TAPVideoPlaybackResolvedResource {
    let fileURL: URL
    let temporaryDirectoryURL: URL?
    let managedTemporaryFile: LibraryManagedTemporaryFile?

    func cleanup() {
        managedTemporaryFile?.cleanup()
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }
}

@MainActor
enum TAPVideoPlaybackResourceLoader {
    private static let loadingPreviewPixelLength = 640

    static func resolve(
        source: TAPVideoPlaybackSource,
        requestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TAPVideoPlaybackResolvedResource {
        switch source {
        case .pendingCapture(let captureID):
            let fileURL = try await TAPPendingCaptureStore.shared
                .bestAvailableVideoURL(captureID: captureID)
            return localResource(fileURL)
        case .ownedCapture(let captureID, let assetID):
            do {
                let fileURL = try await TAPPendingCaptureStore.shared
                    .bestAvailableVideoURL(captureID: captureID)
                return localResource(fileURL)
            } catch {
                return try await photoResource(
                    assetID: assetID,
                    requestKey: requestKey,
                    mediaFetcher: mediaFetcher,
                    progress: progress
                )
            }
        case .photosAsset(let assetID):
            return try await photoResource(
                assetID: assetID,
                requestKey: requestKey,
                mediaFetcher: mediaFetcher,
                progress: progress
            )
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            // The fixture harness owns this reusable artifact.
            return localResource(fileURL)
        #endif
        }
    }

    static func loadingPreviewData(
        source: TAPVideoPlaybackSource,
        originalRequestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching
    ) async -> Data? {
        switch source {
        case .pendingCapture(let captureID):
            if let data = try? await TAPPendingCaptureStore.shared
                .thumbnailData(captureID: captureID) {
                return data
            }
            guard let fileURL = try? await TAPPendingCaptureStore.shared
                .bestAvailableVideoURL(captureID: captureID) else {
                return nil
            }
            return await videoPreviewData(fileURL: fileURL, source: source)
        case .ownedCapture(let captureID, let assetID):
            if let data = try? await TAPPendingCaptureStore.shared
                .thumbnailData(captureID: captureID) {
                return data
            }
            return await photoPreviewData(
                assetID: assetID,
                originalRequestKey: originalRequestKey,
                mediaFetcher: mediaFetcher
            )
        case .photosAsset(let assetID):
            return await photoPreviewData(
                assetID: assetID,
                originalRequestKey: originalRequestKey,
                mediaFetcher: mediaFetcher
            )
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            return await videoPreviewData(fileURL: fileURL, source: source)
        #endif
        }
    }

    private static func localResource(_ fileURL: URL) -> TAPVideoPlaybackResolvedResource {
        TAPVideoPlaybackResolvedResource(
            fileURL: fileURL,
            temporaryDirectoryURL: nil,
            managedTemporaryFile: nil
        )
    }

    private static func photoResource(
        assetID: String,
        requestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TAPVideoPlaybackResolvedResource {
        let request = LibraryMediaAssetRequest(
            key: requestKey,
            assetLocalIdentifier: assetID
        )
        let file = try await mediaFetcher.videoOriginalFile(
            for: request,
            progress: progress
        )
        return TAPVideoPlaybackResolvedResource(
            fileURL: file.fileURL,
            temporaryDirectoryURL: nil,
            managedTemporaryFile: file
        )
    }

    private static func videoPreviewData(
        fileURL: URL,
        source: TAPVideoPlaybackSource
    ) async -> Data? {
        await DepthAlbumThumbnailLoader.shared.videoData(
            for: fileURL,
            cacheKey: DepthAlbumThumbnailCacheKey.make(
                mediaID: source.libraryMediaID,
                version: "video-viewer-preview-v1",
                pixelLength: loadingPreviewPixelLength
            ),
            pixelLength: loadingPreviewPixelLength
        )
    }

    private static func photoPreviewData(
        assetID: String,
        originalRequestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching
    ) async -> Data? {
        let request = LibraryMediaAssetRequest(
            key: MediaFetchRequestKey(
                itemID: originalRequestKey.itemID,
                generation: originalRequestKey.generation,
                purpose: .gridPoster
            ),
            assetLocalIdentifier: assetID
        )
        do {
            let phase = try await mediaFetcher.previewPhase(
                for: request,
                pixelLength: loadingPreviewPixelLength,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
            try Task.checkCancellation()
            return phase.previewOrReadyValue
        } catch {
            return nil
        }
    }
}
