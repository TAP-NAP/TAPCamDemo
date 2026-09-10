//
//  TAPVideoPlaybackResourceLoader.swift
//  TAPCamDemo
//

import Foundation
import UIKit

/// Private route provenance for the exact video original retained by a Viewer
/// session. `LibraryMediaID` keeps one TAP capture stable across export, while
/// this value also binds an owned capture to the Photos asset that supplied the
/// current bytes.
nonisolated enum TAPVideoOriginalResourceOrigin: Equatable, Sendable {
    case pendingCapture(captureID: String)
    case ownedPhotosAsset(captureID: String, assetID: String)
    case photosAsset(assetID: String)
    case debugFixture
}

nonisolated enum TAPVideoOriginalResourceError: Error, Equatable, Sendable {
    case unavailableVideo
}

/// Owns one complete, stable video original for the current Viewer session.
///
/// Photos resources and pending captures are materialized into an app-owned
/// temporary file before this owner is published. A playback session may drop
/// its reference while Share still holds a lease; the temporary directory is
/// removed only after the last owner/lease reference is released.
nonisolated final class TAPVideoOriginalResourceOwner: @unchecked Sendable {
    let mediaID: LibraryMediaID
    let origin: TAPVideoOriginalResourceOrigin
    let fileURL: URL
    let selectedSignedVideo: Bool?

    private let managedTemporaryFile: LibraryManagedTemporaryFile?

    init(
        mediaID: LibraryMediaID,
        origin: TAPVideoOriginalResourceOrigin,
        fileURL: URL,
        managedTemporaryFile: LibraryManagedTemporaryFile? = nil,
        selectedSignedVideo: Bool? = nil
    ) throws {
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        ), values.isRegularFile == true,
              (values.fileSize ?? 0) > 0,
              FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw TAPVideoOriginalResourceError.unavailableVideo
        }

        self.mediaID = mediaID
        self.origin = origin
        self.fileURL = fileURL
        self.managedTemporaryFile = managedTemporaryFile
        self.selectedSignedVideo = selectedSignedVideo
    }

    func acquireLease() -> TAPVideoOriginalResourceLease {
        TAPVideoOriginalResourceLease(owner: self)
    }
}

/// A short-lived capability for reading one stable original video. Consumers
/// pass this object, rather than a detached URL, across asynchronous playback,
/// local-integrity validation, and Share preparation boundaries.
nonisolated final class TAPVideoOriginalResourceLease: @unchecked Sendable {
    fileprivate let owner: TAPVideoOriginalResourceOwner

    fileprivate init(owner: TAPVideoOriginalResourceOwner) {
        self.owner = owner
    }

    /// Valid only while this lease is retained. Share code must retain the
    /// lease for the full asynchronous operation and must not persist this URL.
    var fileURL: URL {
        owner.fileURL
    }

    var mediaID: LibraryMediaID {
        owner.mediaID
    }

    var origin: TAPVideoOriginalResourceOrigin {
        owner.origin
    }

    var selectedSignedVideo: Bool? {
        owner.selectedSignedVideo
    }
}

nonisolated struct TAPVideoLocalIntegrityResult: Equatable, Sendable {
    let captureID: String
    let packageID: UUID
}

nonisolated enum TAPVideoLocalIntegrityError: Error, Equatable, Sendable {
    case missingEmbeddedIdentity
    case expectedCaptureIDMismatch
    case expectedPackageIDMismatch
}

/// Recomputes the TAP Video proof/content binding over the exact bytes retained
/// by a Viewer lease. It never contacts the TAP verification backend.
///
/// Photos-only assets may self-describe their identity from the embedded
/// manifest after the Pending Capture Queue record has been cleaned up. When a
/// route or queue record supplies an expected identity, a mismatch fails closed
/// before the byte-binding validator runs.
nonisolated struct TAPVideoLocalIntegrityValidator: Sendable {
    private let provenanceWriter: TAPCaptureProvenanceWriter

    init(provenanceWriter: TAPCaptureProvenanceWriter = .init()) {
        self.provenanceWriter = provenanceWriter
    }

    func validate(
        _ resource: TAPVideoOriginalResourceLease,
        expectedCaptureID: String? = nil,
        expectedPackageID: UUID? = nil
    ) async throws -> TAPVideoLocalIntegrityResult {
        try Task<Never, Never>.checkCancellation()
        let input = try TAPVideoValidationInput(fileURL: resource.fileURL)
        let manifest = input.manifestDocument.manifest
        try Task<Never, Never>.checkCancellation()
        guard !manifest.payload.id.isEmpty,
              let embeddedPackageID = UUID(uuidString: manifest.payload.packageID) else {
            throw TAPVideoLocalIntegrityError.missingEmbeddedIdentity
        }
        if let expectedCaptureID,
           expectedCaptureID != manifest.payload.id {
            throw TAPVideoLocalIntegrityError.expectedCaptureIDMismatch
        }
        if let expectedPackageID,
           expectedPackageID != embeddedPackageID {
            throw TAPVideoLocalIntegrityError.expectedPackageIDMismatch
        }

        _ = try await provenanceWriter.validateSignedExportVideoFile(
            input,
            expectedCaptureID: expectedCaptureID ?? manifest.payload.id,
            expectedPackageID: expectedPackageID ?? embeddedPackageID,
            validatesDepthTrack: false
        )
        try Task<Never, Never>.checkCancellation()
        return TAPVideoLocalIntegrityResult(
            captureID: manifest.payload.id,
            packageID: embeddedPackageID
        )
    }
}

@MainActor
struct TAPVideoPlaybackResolvedResource {
    let owner: TAPVideoOriginalResourceOwner

    var fileURL: URL {
        owner.fileURL
    }

    func acquireLease() -> TAPVideoOriginalResourceLease {
        owner.acquireLease()
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
            return try await pendingResource(
                captureID: captureID,
                mediaID: source.libraryMediaID,
                origin: .pendingCapture(captureID: captureID),
                progress: progress
            )
        case .ownedCapture(let captureID, let assetID):
            // Once Photos owns the capture, do not bind playback to an
            // unleased pending-store URL that the export worker may clean up.
            return try await photoResource(
                assetID: assetID,
                mediaID: source.libraryMediaID,
                origin: .ownedPhotosAsset(
                    captureID: captureID,
                    assetID: assetID
                ),
                requestKey: requestKey,
                mediaFetcher: mediaFetcher,
                progress: progress
            )
        case .photosAsset(let assetID):
            return try await photoResource(
                assetID: assetID,
                mediaID: source.libraryMediaID,
                origin: .photosAsset(assetID: assetID),
                requestKey: requestKey,
                mediaFetcher: mediaFetcher,
                progress: progress
            )
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            // The fixture harness owns this reusable artifact.
            return try localResource(
                fileURL,
                mediaID: source.libraryMediaID,
                origin: .debugFixture
            )
        #endif
        }
    }

    static func loadingPreviewImage(
        source: TAPVideoPlaybackSource,
        originalRequestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching
    ) async -> UIImage? {
        switch source {
        case .pendingCapture(let captureID):
            if let data = try? await TAPPendingCaptureStore.shared
                .thumbnailData(captureID: captureID) {
                return await DepthAlbumThumbnailDecoder.image(data: data)
            }
            guard let fileURL = try? await TAPPendingCaptureStore.shared
                .bestAvailableVideoURL(captureID: captureID) else {
                return nil
            }
            return await videoPreviewImage(fileURL: fileURL, source: source)
        case .ownedCapture(let captureID, let assetID):
            if let data = try? await TAPPendingCaptureStore.shared
                .thumbnailData(captureID: captureID) {
                return await DepthAlbumThumbnailDecoder.image(data: data)
            }
            return await photoPreviewImage(
                assetID: assetID,
                originalRequestKey: originalRequestKey,
                mediaFetcher: mediaFetcher
            )
        case .photosAsset(let assetID):
            return await photoPreviewImage(
                assetID: assetID,
                originalRequestKey: originalRequestKey,
                mediaFetcher: mediaFetcher
            )
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            return await videoPreviewImage(fileURL: fileURL, source: source)
        #endif
        }
    }

    /// Resolves only work that is safe to associate with an uncommitted
    /// adjacent page. In particular, a pending video without a stored
    /// thumbnail must not start an AVAssetImageGenerator task that can outlive
    /// a quickly cancelled page drag.
    static func adjacentPreviewImage(
        source: TAPVideoPlaybackSource,
        originalRequestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching
    ) async -> UIImage? {
        switch source {
        case .pendingCapture(let captureID):
            guard let data = try? await TAPPendingCaptureStore.shared
                .thumbnailData(captureID: captureID) else { return nil }
            return await DepthAlbumThumbnailDecoder.image(data: data)
        case .ownedCapture(let captureID, let assetID):
            if let data = try? await TAPPendingCaptureStore.shared
                .thumbnailData(captureID: captureID) {
                return await DepthAlbumThumbnailDecoder.image(data: data)
            }
            return await photoPreviewImage(
                assetID: assetID,
                originalRequestKey: originalRequestKey,
                mediaFetcher: mediaFetcher
            )
        case .photosAsset(let assetID):
            return await photoPreviewImage(
                assetID: assetID,
                originalRequestKey: originalRequestKey,
                mediaFetcher: mediaFetcher
            )
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            return await videoPreviewImage(fileURL: fileURL, source: source)
        #endif
        }
    }

    private static func localResource(
        _ fileURL: URL,
        mediaID: LibraryMediaID,
        origin: TAPVideoOriginalResourceOrigin
    ) throws -> TAPVideoPlaybackResolvedResource {
        TAPVideoPlaybackResolvedResource(
            owner: try TAPVideoOriginalResourceOwner(
                mediaID: mediaID,
                origin: origin,
                fileURL: fileURL
            )
        )
    }

    private static func pendingResource(
        captureID: String,
        mediaID: LibraryMediaID,
        origin: TAPVideoOriginalResourceOrigin,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TAPVideoPlaybackResolvedResource {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TAPLibraryPendingVideo-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            let snapshot = try await TAPPendingCaptureStore.shared
                .snapshotVideoPlaybackResource(
                    captureID: captureID,
                    to: directoryURL,
                    progressHandler: { _ in }
                )
            let managedFile = LibraryManagedTemporaryFile(
                fileURL: snapshot.videoURL,
                directoryURL: directoryURL
            )
            return TAPVideoPlaybackResolvedResource(
                owner: try TAPVideoOriginalResourceOwner(
                    mediaID: mediaID,
                    origin: origin,
                    fileURL: managedFile.fileURL,
                    managedTemporaryFile: managedFile,
                    selectedSignedVideo: snapshot.selectedSignedVideo
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    private static func photoResource(
        assetID: String,
        mediaID: LibraryMediaID,
        origin: TAPVideoOriginalResourceOrigin,
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
            owner: try TAPVideoOriginalResourceOwner(
                mediaID: mediaID,
                origin: origin,
                fileURL: file.fileURL,
                managedTemporaryFile: file
            )
        )
    }

    private static func videoPreviewImage(
        fileURL: URL,
        source: TAPVideoPlaybackSource
    ) async -> UIImage? {
        guard let data = await DepthAlbumThumbnailLoader.shared.videoData(
            for: fileURL,
            cacheKey: DepthAlbumThumbnailCacheKey.make(
                mediaID: source.libraryMediaID,
                version: "video-viewer-preview-v1",
                pixelLength: loadingPreviewPixelLength
            ),
            pixelLength: loadingPreviewPixelLength
        ) else { return nil }
        return await DepthAlbumThumbnailDecoder.image(data: data)
    }

    private static func photoPreviewImage(
        assetID: String,
        originalRequestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching
    ) async -> UIImage? {
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
            return phase.previewOrReadyValue?.image
        } catch {
            return nil
        }
    }
}
