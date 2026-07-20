//
//  PhotoKitLibraryMediaFetcher.swift
//  TAPCamDemo
//

import Foundation
@preconcurrency import Photos
import UIKit

actor PhotoKitLibraryMediaFetcher: LibraryMediaFetching, DepthAlbumPhotoCataloging {
    func depthAlbumPhotoCatalogSnapshot(
        exportedAssetLocalIdentifiers: Set<String>
    ) async throws -> DepthAlbumPhotoCatalogSnapshot {
        try Task.checkCancellation()
        try requireCatalogReadAuthorization()
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

        logDepthAlbumPhotoCatalogSnapshot(
            albumCount: albumAssets.count,
            requestedExportedCount: exportedAssetLocalIdentifiers.count,
            resolvedExportedCount: exportedAssets.count
        )
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

        let localBridge = PhotoKitResourceRequestBridge(
            sink: PhotoKitResourceDataSink(),
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
            let networkBridge = PhotoKitResourceRequestBridge(
                sink: PhotoKitResourceDataSink(),
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
            let localBridge = PhotoKitResourceRequestBridge(
                sink: try PhotoKitResourceFileSink(fileURL: fileURL),
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
                let networkBridge = PhotoKitResourceRequestBridge(
                    sink: try PhotoKitResourceFileSink(fileURL: fileURL),
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
                    contentMode: .aspectFit,
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

    /// Catalog reads must never own the system permission prompt. During
    /// first-run setup, that prompt belongs to the explicit setup action;
    /// background cover refreshes only consume an already-granted state.
    private nonisolated func requireCatalogReadAuthorization() throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined, .denied, .restricted:
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
