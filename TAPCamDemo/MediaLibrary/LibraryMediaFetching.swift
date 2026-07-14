//
//  LibraryMediaFetching.swift
//  TAPCamDemo
//

import Foundation
import OSLog
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
        DepthAlbumThumbnailCacheKey.make(
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
    ) async throws -> MediaFetchPhase<Data, Data>

    func previewPhase(
        for request: LibraryMediaAssetRequest,
        pixelLength: Int,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> MediaFetchPhase<Data, Data>

    func photoOriginalData(
        for request: LibraryMediaAssetRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> Data

    func photoDisplayData(
        for request: LibraryMediaAssetRequest,
        pixelLength: Int,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> Data

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

    fileprivate init(fileURL: URL, directoryURL: URL) {
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

    fileprivate init(_ value: PHLivePhoto) {
        self.value = value
    }
}

actor PhotoKitLibraryMediaFetcher: LibraryMediaFetching, DepthAlbumPhotoCataloging {
    func depthAlbumPhotoCatalogSnapshot(
        exportedAssetLocalIdentifiers: Set<String>
    ) async throws -> DepthAlbumPhotoCatalogSnapshot {
        try Task.checkCancellation()
        try await ensureCatalogReadAuthorization()
        try Task.checkCancellation()

        let albumAssets: [DepthAlbumPhotoAsset]
        if let album = depthAlbumCollection() {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(in: album, options: options)
            var values: [DepthAlbumPhotoAsset] = []
            values.reserveCapacity(result.count)
            for index in 0..<result.count {
                values.append(catalogAsset(from: result.object(at: index)))
            }
            albumAssets = values
        } else {
            albumAssets = []
        }

        let exportedAssets: [DepthAlbumPhotoAsset]
        if exportedAssetLocalIdentifiers.isEmpty {
            exportedAssets = []
        } else {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: exportedAssetLocalIdentifiers.sorted(),
                options: nil
            )
            var values: [DepthAlbumPhotoAsset] = []
            values.reserveCapacity(result.count)
            for index in 0..<result.count {
                values.append(catalogAsset(from: result.object(at: index)))
            }
            exportedAssets = values
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info(
            "depth_album_catalog_snapshot albumCount=\(albumAssets.count, privacy: .public) requestedExportedCount=\(exportedAssetLocalIdentifiers.count, privacy: .public) resolvedExportedCount=\(exportedAssets.count, privacy: .public)"
        )
        #endif
        return DepthAlbumPhotoCatalogSnapshot(
            albumAssets: albumAssets,
            resolvedAssets: exportedAssets
        )
    }

    func mediaKind(for request: LibraryMediaAssetRequest) async throws -> LibraryMediaKind {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        if asset.mediaType == .video {
            return .tapVideo
        }
        return asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
    }

    func posterPhase(
        for request: LibraryMediaPosterRequest,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> MediaFetchPhase<Data, Data> {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        return try await posterPhase(
            for: asset,
            cacheKey: request.cacheKey,
            pixelLength: request.pixelLength,
            allowsNetworkAccess: allowsNetworkAccess,
            progress: progress
        )
    }

    func previewPhase(
        for request: LibraryMediaAssetRequest,
        pixelLength: Int,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> MediaFetchPhase<Data, Data> {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        let cacheKey = DepthAlbumThumbnailCacheKey.make(
            assetLocalIdentifier: asset.localIdentifier,
            pixelLength: max(pixelLength, 1),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            versionDate: asset.modificationDate ?? asset.creationDate ?? .distantPast
        )
        return try await posterPhase(
            for: asset,
            cacheKey: cacheKey,
            pixelLength: max(pixelLength, 1),
            allowsNetworkAccess: allowsNetworkAccess,
            progress: progress
        )
    }

    func photoOriginalData(
        for request: LibraryMediaAssetRequest,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> Data {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { resource in
            resource.type == .photo || resource.type == .fullSizePhoto
        }) else {
            throw MediaFetchFailure.assetRemoved
        }

        let localBridge = PhotoKitResourceDataRequestBridge(
            allowsNetworkAccess: false,
            progress: { _ in }
        )
        do {
            return try await withTaskCancellationHandler {
                try await localBridge.start(resource: resource)
            } onCancel: {
                localBridge.cancel()
            }
        } catch is PhotoKitNetworkAccessRequired {
            try Task.checkCancellation()
            progress(nil)
            let networkBridge = PhotoKitResourceDataRequestBridge(
                allowsNetworkAccess: true,
                progress: progress
            )
            return try await withTaskCancellationHandler {
                try await networkBridge.start(resource: resource)
            } onCancel: {
                networkBridge.cancel()
            }
        }
    }

    func photoDisplayData(
        for request: LibraryMediaAssetRequest,
        pixelLength: Int,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> Data {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        let targetLength = max(pixelLength, 1)
        let localBridge = PhotoKitDisplayImageRequestBridge(
            allowsNetworkAccess: false,
            progress: { _ in }
        )
        do {
            return try await withTaskCancellationHandler {
                try await localBridge.start(asset: asset, pixelLength: targetLength)
            } onCancel: {
                localBridge.cancel()
            }
        } catch is PhotoKitNetworkAccessRequired {
            try Task.checkCancellation()
            progress(nil)
            let networkBridge = PhotoKitDisplayImageRequestBridge(
                allowsNetworkAccess: true,
                progress: progress
            )
            return try await withTaskCancellationHandler {
                try await networkBridge.start(asset: asset, pixelLength: targetLength)
            } onCancel: {
                networkBridge.cancel()
            }
        }
    }

    func videoOriginalFile(
        for request: LibraryMediaAssetRequest,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> LibraryManagedTemporaryFile {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        let resources = PHAssetResource.assetResources(for: asset)
        guard let preferredType = LibraryVideoResourceSelectionPolicy.preferredType(
            in: resources.map(\.type)
        ),
              let resource = resources.first(where: { $0.type == preferredType }) else {
            throw MediaFetchFailure.assetRemoved
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPLibraryVideo-\(UUID().uuidString)", isDirectory: true)
        let originalName = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let filename = originalName.isEmpty ? "tap-video.mp4" : originalName
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            try? FileManager.default.removeItem(at: directoryURL)
            throw MediaFetchFailure.download
        }

        do {
            let localBridge = try PhotoKitResourceFileRequestBridge(
                fileURL: fileURL,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
            do {
                try await withTaskCancellationHandler {
                    try await localBridge.start(resource: resource)
                } onCancel: {
                    localBridge.cancel()
                }
            } catch is PhotoKitNetworkAccessRequired {
                try Task.checkCancellation()
                try? FileManager.default.removeItem(at: fileURL)
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    throw MediaFetchFailure.download
                }
                progress(nil)
                let networkBridge = try PhotoKitResourceFileRequestBridge(
                    fileURL: fileURL,
                    allowsNetworkAccess: true,
                    progress: progress
                )
                try await withTaskCancellationHandler {
                    try await networkBridge.start(resource: resource)
                } onCancel: {
                    networkBridge.cancel()
                }
            }
            try Task.checkCancellation()
            return LibraryManagedTemporaryFile(
                fileURL: fileURL,
                directoryURL: directoryURL
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    func livePhoto(
        for request: LibraryMediaAssetRequest,
        targetSize: CGSize,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> LibraryLivePhoto {
        try Task.checkCancellation()
        let asset = try Self.asset(localIdentifier: request.assetLocalIdentifier)
        guard asset.mediaSubtypes.contains(.photoLive) else {
            throw MediaFetchFailure.assetRemoved
        }
        let bridge = PhotoKitLivePhotoRequestBridge(progress: progress)
        return try await withTaskCancellationHandler {
            try await bridge.start(asset: asset, targetSize: targetSize)
        } onCancel: {
            bridge.cancel()
        }
    }

    /// Keeps `PHAsset` actor-confined. Only JPEG bytes cross this service
    /// boundary; disk-cache actors never receive a Photos framework object.
    private func posterPhase(
        for asset: PHAsset,
        cacheKey: String,
        pixelLength: Int,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> MediaFetchPhase<Data, Data> {
        if let cachedData = await DepthAlbumThumbnailDiskCache.shared.data(for: cacheKey) {
            return .ready(cachedData)
        }
        do {
            let result = try await requestPoster(
                for: asset,
                pixelLength: max(pixelLength, 1),
                allowsNetworkAccess: allowsNetworkAccess,
                progress: progress
            )
            if let finalData = result.finalData {
                await DepthAlbumThumbnailDiskCache.shared.store(finalData, for: cacheKey)
                return .ready(finalData)
            }
            if result.isCloudOnly {
                return .cloudOnly(result.previewData)
            }
            if let previewData = result.previewData {
                return .localPreview(previewData)
            }
            return .failed(nil, reason: .decode, retryable: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let failure = PhotoKitMediaFetchFailure.map(error)
            return .failed(nil, reason: failure, retryable: failure.isRetryable)
        }
    }

    private func requestPoster(
        for asset: PHAsset,
        pixelLength: Int,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> DepthAlbumPhotoKitPosterResult {
        let manager = PHImageManager.default()
        let bridge = DepthAlbumPhotoKitImageRequestBridge(
            manager: manager,
            pixelLength: pixelLength
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                bridge.install(continuation: continuation)
                guard !Task.isCancelled else {
                    bridge.cancel()
                    return
                }
                let options = PHImageRequestOptions()
                options.deliveryMode = allowsNetworkAccess ? .opportunistic : .fastFormat
                options.resizeMode = allowsNetworkAccess ? .exact : .fast
                options.isNetworkAccessAllowed = allowsNetworkAccess
                options.progressHandler = { value, error, _, _ in
                    if error != nil {
                        progress(nil)
                    } else {
                        progress(value.isFinite ? min(max(value, 0), 1) : nil)
                    }
                }
                let requestID = manager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: pixelLength, height: pixelLength),
                    contentMode: .aspectFill,
                    options: options
                ) { image, info in
                    bridge.receive(image: image, info: info)
                }
                bridge.install(requestID: requestID)
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    private nonisolated static func asset(localIdentifier: String) throws -> PHAsset {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw MediaFetchFailure.permission
        }
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        ).firstObject else {
            throw MediaFetchFailure.assetRemoved
        }
        return asset
    }

    private func ensureCatalogReadAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard requested == .authorized || requested == .limited else {
                throw MediaFetchFailure.permission
            }
        case .denied, .restricted:
            throw MediaFetchFailure.permission
        @unknown default:
            throw MediaFetchFailure.permission
        }
    }

    private func depthAlbumCollection() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "title == %@",
            PhotoLibraryWriter.albumName
        )
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        ).firstObject
    }

    private func catalogAsset(from asset: PHAsset) -> DepthAlbumPhotoAsset {
        DepthAlbumPhotoAsset(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isVideo: asset.mediaType == .video
        )
    }
}

nonisolated private final class PhotoKitResourceDataRequestBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let manager = PHAssetResourceManager.default()
    private let allowsNetworkAccess: Bool
    private let progress: @Sendable (Double?) -> Void
    private var requestID = PHInvalidAssetResourceDataRequestID
    private var continuation: CheckedContinuation<Data, any Error>?
    private var result = Data()
    private var cancellationRequested = false
    private var finished = false

    init(
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) {
        self.allowsNetworkAccess = allowsNetworkAccess
        self.progress = progress
    }

    func start(resource: PHAssetResource) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let shouldCancel = cancellationRequested
            lock.unlock()
            guard !shouldCancel else {
                finish(error: CancellationError())
                return
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = allowsNetworkAccess
            options.progressHandler = { [weak self] value in
                self?.receiveProgress(value)
            }
            let requestID = manager.requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { [weak self] chunk in
                    self?.receive(chunk)
                },
                completionHandler: { [weak self] error in
                    self?.finish(error: error)
                }
            )
            install(requestID: requestID)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let requestID = self.requestID
        lock.unlock()
        if requestID != PHInvalidAssetResourceDataRequestID {
            manager.cancelDataRequest(requestID)
        }
        finish(error: CancellationError())
    }

    private func install(requestID: PHAssetResourceDataRequestID) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            manager.cancelDataRequest(requestID)
            return
        }
        self.requestID = requestID
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel {
            manager.cancelDataRequest(requestID)
            finish(error: CancellationError())
        }
    }

    private func receive(_ chunk: Data) {
        lock.lock()
        if !finished, !cancellationRequested {
            result.append(chunk)
        }
        lock.unlock()
    }

    private func receiveProgress(_ value: Double) {
        lock.lock()
        let canReport = !finished && !cancellationRequested
        lock.unlock()
        guard canReport else {
            return
        }
        progress(value.isFinite ? min(max(value, 0), 1) : nil)
    }

    private func finish(error: (any Error)?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let result = self.result
        self.result.removeAll(keepingCapacity: false)
        let wasCancelled = cancellationRequested
        lock.unlock()

        if wasCancelled || error is CancellationError {
            continuation?.resume(throwing: CancellationError())
        } else if let error {
            continuation?.resume(throwing: PhotoKitMediaFetchFailure.resourceError(error))
        } else {
            progress(1)
            continuation?.resume(returning: result)
        }
    }
}

nonisolated private final class PhotoKitResourceFileRequestBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let manager = PHAssetResourceManager.default()
    private let fileURL: URL
    private let allowsNetworkAccess: Bool
    private let progress: @Sendable (Double?) -> Void
    private var fileHandle: FileHandle?
    private var requestID = PHInvalidAssetResourceDataRequestID
    private var continuation: CheckedContinuation<Void, any Error>?
    private var cancellationRequested = false
    private var finished = false

    init(
        fileURL: URL,
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) throws {
        self.fileURL = fileURL
        self.allowsNetworkAccess = allowsNetworkAccess
        self.progress = progress
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
    }

    func start(resource: PHAssetResource) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let shouldCancel = cancellationRequested
            lock.unlock()
            guard !shouldCancel else {
                finish(error: CancellationError())
                return
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = allowsNetworkAccess
            options.progressHandler = { [weak self] value in
                self?.receiveProgress(value)
            }
            let requestID = manager.requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { [weak self] chunk in
                    self?.receive(chunk)
                },
                completionHandler: { [weak self] error in
                    self?.finish(error: error)
                }
            )
            install(requestID: requestID)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let requestID = self.requestID
        lock.unlock()
        if requestID != PHInvalidAssetResourceDataRequestID {
            manager.cancelDataRequest(requestID)
        }
        finish(error: CancellationError())
    }

    private func install(requestID: PHAssetResourceDataRequestID) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            manager.cancelDataRequest(requestID)
            return
        }
        self.requestID = requestID
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel {
            manager.cancelDataRequest(requestID)
            finish(error: CancellationError())
        }
    }

    private func receive(_ chunk: Data) {
        var writeError: (any Error)?
        lock.lock()
        if !finished, !cancellationRequested {
            do {
                try fileHandle?.write(contentsOf: chunk)
            } catch {
                writeError = error
            }
        }
        lock.unlock()
        if let writeError {
            cancelRequestAndFinish(error: writeError)
        }
    }

    private func receiveProgress(_ value: Double) {
        lock.lock()
        let canReport = !finished && !cancellationRequested
        lock.unlock()
        guard canReport else {
            return
        }
        progress(value.isFinite ? min(max(value, 0), 1) : nil)
    }

    private func cancelRequestAndFinish(error: any Error) {
        lock.lock()
        let requestID = self.requestID
        lock.unlock()
        if requestID != PHInvalidAssetResourceDataRequestID {
            manager.cancelDataRequest(requestID)
        }
        finish(error: error)
    }

    private func finish(error: (any Error)?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let fileHandle = self.fileHandle
        self.fileHandle = nil
        let wasCancelled = cancellationRequested
        lock.unlock()

        try? fileHandle?.close()
        if wasCancelled || error is CancellationError {
            try? FileManager.default.removeItem(at: fileURL)
            continuation?.resume(throwing: CancellationError())
        } else if let error {
            try? FileManager.default.removeItem(at: fileURL)
            continuation?.resume(throwing: PhotoKitMediaFetchFailure.resourceError(error))
        } else {
            progress(1)
            continuation?.resume(returning: ())
        }
    }
}

/// Bounded display-image bridge used by the photo viewer. A local-only request
/// is issued first, so the viewer can distinguish a local original from an
/// iCloud download without allowing a probe to start network work.
nonisolated private final class PhotoKitDisplayImageRequestBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let manager = PHImageManager.default()
    private let allowsNetworkAccess: Bool
    private let progress: @Sendable (Double?) -> Void
    private var requestID = PHInvalidImageRequestID
    private var continuation: CheckedContinuation<Data, any Error>?
    private var cancellationRequested = false
    private var finished = false

    init(
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) {
        self.allowsNetworkAccess = allowsNetworkAccess
        self.progress = progress
    }

    func start(asset: PHAsset, pixelLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let shouldCancel = cancellationRequested
            lock.unlock()
            guard !shouldCancel else {
                finish(.failure(CancellationError()))
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = allowsNetworkAccess
            options.progressHandler = { [weak self] value, error, _, _ in
                if let error {
                    self?.finish(.failure(PhotoKitMediaFetchFailure.resourceError(error)))
                } else {
                    self?.receiveProgress(value)
                }
            }
            let targetLength = max(pixelLength, 1)
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: targetLength, height: targetLength),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                self?.receive(image: image, info: info, pixelLength: targetLength)
            }
            install(requestID: requestID)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let requestID = self.requestID
        lock.unlock()
        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        finish(.failure(CancellationError()))
    }

    private func install(requestID: PHImageRequestID) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            manager.cancelImageRequest(requestID)
            return
        }
        self.requestID = requestID
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel {
            manager.cancelImageRequest(requestID)
            finish(.failure(CancellationError()))
        }
    }

    private func receive(
        image: UIImage?,
        info: [AnyHashable: Any]?,
        pixelLength: Int
    ) {
        if info?[PHImageCancelledKey] as? Bool == true {
            finish(.failure(CancellationError()))
            return
        }
        if let error = info?[PHImageErrorKey] as? Error {
            finish(.failure(PhotoKitMediaFetchFailure.resourceError(error)))
            return
        }
        if info?[PHImageResultIsDegradedKey] as? Bool == true {
            return
        }
        if !allowsNetworkAccess,
           info?[PHImageResultIsInCloudKey] as? Bool == true,
           image == nil {
            finish(.failure(PhotoKitNetworkAccessRequired()))
            return
        }
        guard let image,
              let data = DepthAlbumThumbnailJPEGRenderer.data(
                from: image,
                pixelLength: pixelLength
              ) else {
            finish(.failure(MediaFetchFailure.decode))
            return
        }
        finish(.success(data))
    }

    private func receiveProgress(_ value: Double) {
        lock.lock()
        let canReport = !finished && !cancellationRequested
        lock.unlock()
        guard canReport else {
            return
        }
        progress(value.isFinite ? min(max(value, 0), 1) : nil)
    }

    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let wasCancelled = cancellationRequested
        lock.unlock()
        if wasCancelled {
            continuation?.resume(throwing: CancellationError())
            return
        }
        switch result {
        case .success(let data):
            if allowsNetworkAccess {
                progress(1)
            }
            continuation?.resume(returning: data)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

nonisolated private final class PhotoKitLivePhotoRequestBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let manager = PHImageManager.default()
    private let progress: @Sendable (Double?) -> Void
    private var requestID = PHInvalidImageRequestID
    private var continuation: CheckedContinuation<LibraryLivePhoto, any Error>?
    private var cancellationRequested = false
    private var finished = false

    init(progress: @escaping @Sendable (Double?) -> Void) {
        self.progress = progress
    }

    func start(asset: PHAsset, targetSize: CGSize) async throws -> LibraryLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let shouldCancel = cancellationRequested
            lock.unlock()
            guard !shouldCancel else {
                finish(result: .failure(CancellationError()))
                return
            }

            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.progressHandler = { [weak self] value, error, _, _ in
                if let error {
                    self?.finish(result: .failure(PhotoKitMediaFetchFailure.map(error)))
                } else {
                    self?.receiveProgress(value)
                }
            }
            let requestID = manager.requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] livePhoto, info in
                self?.receive(livePhoto: livePhoto, info: info)
            }
            install(requestID: requestID)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let requestID = self.requestID
        lock.unlock()
        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        finish(result: .failure(CancellationError()))
    }

    private func install(requestID: PHImageRequestID) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            manager.cancelImageRequest(requestID)
            return
        }
        self.requestID = requestID
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel {
            manager.cancelImageRequest(requestID)
            finish(result: .failure(CancellationError()))
        }
    }

    private func receive(livePhoto: PHLivePhoto?, info: [AnyHashable: Any]?) {
        if info?[PHImageCancelledKey] as? Bool == true {
            finish(result: .failure(CancellationError()))
            return
        }
        if let error = info?[PHImageErrorKey] as? Error {
            finish(result: .failure(PhotoKitMediaFetchFailure.map(error)))
            return
        }
        let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool == true
        guard !isDegraded else {
            return
        }
        guard let livePhoto else {
            finish(result: .failure(MediaFetchFailure.decode))
            return
        }
        finish(result: .success(LibraryLivePhoto(livePhoto)))
    }

    private func receiveProgress(_ value: Double) {
        lock.lock()
        let canReport = !finished && !cancellationRequested
        lock.unlock()
        guard canReport else {
            return
        }
        progress(value.isFinite ? min(max(value, 0), 1) : nil)
    }

    private func finish(result: Result<LibraryLivePhoto, any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let wasCancelled = cancellationRequested
        lock.unlock()
        if wasCancelled {
            continuation?.resume(throwing: CancellationError())
            return
        }
        switch result {
        case .success(let value):
            progress(1)
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

nonisolated private struct PhotoKitNetworkAccessRequired: Error {}

nonisolated private enum PhotoKitMediaFetchFailure {
    static func resourceError(_ error: Error) -> any Error {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.networkAccessRequired.rawValue {
            return PhotoKitNetworkAccessRequired()
        }
        return map(error)
    }

    static func map(_ error: Error) -> MediaFetchFailure {
        if let failure = error as? MediaFetchFailure {
            return failure
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorTimedOut:
                return .offline
            default:
                return .download
            }
        }
        if nsError.domain == PHPhotosErrorDomain {
            switch nsError.code {
            case PHPhotosError.accessUserDenied.rawValue,
                 PHPhotosError.accessRestricted.rawValue:
                return .permission
            case PHPhotosError.networkError.rawValue,
                 PHPhotosError.libraryVolumeOffline.rawValue:
                return .offline
            case PHPhotosError.identifierNotFound.rawValue,
                 PHPhotosError.missingResource.rawValue:
                return .assetRemoved
            default:
                return .download
            }
        }
        return .download
    }
}
