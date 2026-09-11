//
//  LibraryMediaFetching.swift
//  TAPCamDemo
//

import Foundation
@preconcurrency import Photos
import UIKit

nonisolated enum LibraryVideoResourceSelectionPolicy {
    static func preferredType(
        in resourceTypes: [PHAssetResourceType]
    ) -> PHAssetResourceType? {
        if resourceTypes.contains(.video) {
            return .video
        }
        if resourceTypes.contains(.fullSizeVideo) {
            return .fullSizeVideo
        }
        return nil
    }
}

nonisolated struct LibraryMediaPosterRequest: Equatable, Hashable, Sendable {
    let itemID: LibraryMediaID
    let assetLocalIdentifier: String
    let posterRevision: String
    let pixelLength: Int

    init?(
        summary: LibraryMediaSummary,
        pixelLength: Int
    ) {
        let assetLocalIdentifier: String
        switch summary.source {
        case .pending:
            return nil
        case .ownedPhotosAsset(_, let assetID), .photosOnly(let assetID):
            assetLocalIdentifier = assetID
        }
        self.itemID = summary.id
        self.assetLocalIdentifier = assetLocalIdentifier
        self.posterRevision = summary.version.posterRevision
        self.pixelLength = max(pixelLength, 1)
    }

    var cacheKey: String {
        LibraryThumbnailCacheKey.make(
            mediaID: itemID,
            version: posterRevision,
            pixelLength: pixelLength
        )
    }
}

nonisolated protocol LibraryMediaFetching: Sendable {
    func mediaKind(for request: LibraryMediaAssetRequest) async throws -> LibraryMediaKind

    func posterPhase(
        for request: LibraryMediaPosterRequest,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> MediaFetchPhase<MediaPoster, MediaPoster>

    func previewPhase(
        for request: LibraryMediaAssetRequest,
        pixelLength: Int,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> MediaFetchPhase<MediaPoster, MediaPoster>

    func photoDisplayImage(
        for request: LibraryMediaAssetRequest,
        pixelLength: Int,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> UIImage

    func videoOriginalFile(
        for request: LibraryMediaAssetRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> LibraryManagedTemporaryFile

    func livePhoto(
        for request: LibraryMediaAssetRequest,
        targetSize: CGSize,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> LibraryLivePhoto
}

nonisolated struct LibraryMediaAssetRequest: Equatable, Hashable, Sendable {
    let key: MediaFetchRequestKey
    let assetLocalIdentifier: String
}

/// Owns a streamed Photos resource and removes its private temporary directory
/// when the viewer releases it. Callers never own a partial or staging URL.
nonisolated final class LibraryManagedTemporaryFile: @unchecked Sendable {
    let fileURL: URL

    private let lock = NSLock()
    private var directoryURL: URL?

    init(fileURL: URL, directoryURL: URL) {
        self.fileURL = fileURL
        self.directoryURL = directoryURL
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        lock.lock()
        let directoryURL = self.directoryURL
        self.directoryURL = nil
        lock.unlock()
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }
}

/// Photos framework presentation values are deliberately wrapped at the
/// service boundary. `PHAsset` itself never leaves `PhotoKitLibraryMediaFetcher`.
nonisolated final class LibraryLivePhoto: @unchecked Sendable {
    let value: PHLivePhoto

    init(_ value: PHLivePhoto) {
        self.value = value
    }
}
