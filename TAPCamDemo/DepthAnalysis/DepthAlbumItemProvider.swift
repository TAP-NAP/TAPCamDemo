//
//  DepthAlbumItemProvider.swift
//  TAPCamDemo
//

import Foundation
import Photos

/// Snapshot of the TAP Library grid after pending records and Photos assets are
/// reconciled.
nonisolated struct DepthAlbumItemSnapshot {
    let items: [TAPLibraryItem]
    let photoAssetsError: Error?
}

/// Reads the sources that can appear in the TAP Library grid.
///
/// The provider keeps partial Photos failures out of the SwiftUI view model:
/// pending captures can still be shown even when the Photos album cannot be
/// read. The view decides whether that partial failure should be surfaced.
@MainActor
struct DepthAlbumItemProvider {
    typealias PendingRecordsLoader = () async throws -> [TAPPendingCaptureRecord]
    typealias ExportedRecordsLoader = () async throws -> [TAPPendingCaptureRecord]
    typealias PhotoAssetsLoader = () async throws -> [DepthAlbumPhotoAsset]
    typealias ExportedAssetResolver = (String) -> DepthAlbumPhotoAsset?

    private let pendingRecordsLoader: PendingRecordsLoader
    private let exportedRecordsLoader: ExportedRecordsLoader
    private let photoAssetsLoader: PhotoAssetsLoader
    private let exportedAssetResolver: ExportedAssetResolver

    init(
        pendingRecordsLoader: @escaping PendingRecordsLoader = {
            try TAPPendingCaptureStore.shared.visiblePendingRecords()
        },
        exportedRecordsLoader: @escaping ExportedRecordsLoader = {
            try TAPPendingCaptureStore.shared.exportedRecords()
        },
        photoAssetsLoader: @escaping PhotoAssetsLoader = {
            let assets = try await PhotoLibraryWriter.depthAlbumAssets()
            return assets.map { asset in
                DepthAlbumPhotoAsset(asset: asset)
            }
        },
        exportedAssetResolver: @escaping ExportedAssetResolver = { assetID in
            guard let asset = PhotoLibraryWriter.asset(localIdentifier: assetID) else {
                return nil
            }
            return DepthAlbumPhotoAsset(asset: asset)
        }
    ) {
        self.pendingRecordsLoader = pendingRecordsLoader
        self.exportedRecordsLoader = exportedRecordsLoader
        self.photoAssetsLoader = photoAssetsLoader
        self.exportedAssetResolver = exportedAssetResolver
    }

    func loadSnapshot() async throws -> DepthAlbumItemSnapshot {
        let pendingRecords = try await pendingRecordsLoader()
        let exportedRecords = try await exportedRecordsLoader()

        let photoAssets: [DepthAlbumPhotoAsset]
        let photoAssetsError: Error?
        do {
            photoAssets = try await photoAssetsLoader()
            photoAssetsError = nil
        } catch {
            photoAssets = []
            photoAssetsError = error
        }

        let items = TAPLibraryItem.merged(
            pendingRecords: pendingRecords,
            exportedRecords: exportedRecords,
            photoAssets: photoAssets,
            exportedAssetResolver: exportedAssetResolver
        )
        return DepthAlbumItemSnapshot(items: items, photoAssetsError: photoAssetsError)
    }
}

/// A lightweight Photos asset reference for album ordering, identity, and tests.
///
/// Real UI paths keep the underlying `PHAsset` for thumbnail requests. Tests can
/// build this value without Photos by leaving `phAsset` nil.
nonisolated struct DepthAlbumPhotoAsset {
    let localIdentifier: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let phAsset: PHAsset?

    init(asset: PHAsset) {
        self.localIdentifier = asset.localIdentifier
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.phAsset = asset
    }

    init(
        localIdentifier: String,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        phAsset: PHAsset? = nil
    ) {
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.phAsset = phAsset
    }
}

nonisolated struct TAPLibraryItem: Identifiable {
    enum Source {
        case pending(TAPPendingCaptureRecord)
        case ownedPhoto(TAPPendingCaptureRecord, DepthAlbumPhotoAsset)
        case photos(DepthAlbumPhotoAsset)
    }

    /// SwiftUI list identity for the current in-memory album snapshot.
    ///
    /// This value can contain Photos or pending capture identifiers. Treat it as
    /// private input for UI diffing and route-token derivation, not as a public
    /// log field, filename, or persisted payload.
    let id: String
    let source: Source
    let capturedAt: Date
    let routeAnchor: CameraRouteAlbumAnchor

    func thumbnailCacheKey(pixelLength: Int) -> String {
        switch source {
        case .photos(let asset), .ownedPhoto(_, let asset):
            DepthAlbumThumbnailCacheKey.make(
                assetLocalIdentifier: asset.localIdentifier,
                pixelLength: pixelLength,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                versionDate: asset.modificationDate ?? asset.creationDate ?? .distantPast
            )
        case .pending(let record):
            DepthAlbumThumbnailCacheKey.makePending(
                captureID: record.captureID,
                pixelLength: pixelLength,
                capturedAt: record.capturedAt,
                thumbnailFilename: record.thumbnailFilename
            )
        }
    }

    private init?(id: String, source: Source, capturedAt: Date) {
        let routeAnchor: CameraRouteAlbumAnchor?
        switch source {
        case .pending(let record):
            routeAnchor = CameraRouteAlbumAnchor(
                itemID: id,
                captureID: record.captureID
            )
        case .ownedPhoto(let record, let asset):
            routeAnchor = CameraRouteAlbumAnchor(
                itemID: id,
                captureID: record.captureID,
                assetLocalIdentifier: asset.localIdentifier
            )
        case .photos(let asset):
            routeAnchor = CameraRouteAlbumAnchor(
                itemID: id,
                assetLocalIdentifier: asset.localIdentifier
            )
        }

        guard let routeAnchor else {
            return nil
        }

        self.id = id
        self.source = source
        self.capturedAt = capturedAt
        self.routeAnchor = routeAnchor
    }

    static func merged(
        pendingRecords: [TAPPendingCaptureRecord],
        exportedRecords: [TAPPendingCaptureRecord],
        photoAssets: [DepthAlbumPhotoAsset],
        exportedAssetResolver: (String) -> DepthAlbumPhotoAsset?
    ) -> [TAPLibraryItem] {
        let pendingItems = pendingRecords
            .filter(\.isVisiblePendingItem)
            .compactMap { record in
                TAPLibraryItem(
                    id: "pending:\(record.captureID)",
                    source: .pending(record),
                    capturedAt: record.capturedAt
                )
            }

        let ownedPhotoItems = exportedRecords.compactMap { record -> TAPLibraryItem? in
            guard let assetID = record.assetLocalIdentifier,
                  let asset = exportedAssetResolver(assetID) else {
                return nil
            }

            return TAPLibraryItem(
                id: "owned:\(asset.localIdentifier)",
                source: .ownedPhoto(record, asset),
                capturedAt: asset.creationDate ?? record.capturedAt
            )
        }
        let ownedAssetIDs = Set(ownedPhotoItems.compactMap(\.assetLocalIdentifier))

        let photoItems = photoAssets
            .filter { !ownedAssetIDs.contains($0.localIdentifier) }
            .compactMap { asset in
                TAPLibraryItem(
                    id: "photos:\(asset.localIdentifier)",
                    source: .photos(asset),
                    capturedAt: asset.creationDate ?? .distantPast
                )
            }

        return (pendingItems + ownedPhotoItems + photoItems).sorted { $0.capturedAt > $1.capturedAt }
    }

    private var assetLocalIdentifier: String? {
        switch source {
        case .photos(let asset), .ownedPhoto(_, let asset):
            asset.localIdentifier
        case .pending:
            nil
        }
    }
}

extension TAPLibraryItem {
    var pendingBadge: String? {
        guard case .pending(let record) = source else {
            return nil
        }

        switch record.status {
        case .pending:
            return "PENDING"
        case .waitingNetwork:
            return "WAIT"
        case .signing:
            return "SIGN"
        case .signed:
            return "SIGNED"
        case .exporting:
            return "SAVE"
        case .failedRetryable:
            return "RETRY"
        case .exported:
            return nil
        }
    }

    var accessibilityLabel: String {
        switch source {
        case .photos, .ownedPhoto:
            return "Open saved depth photo"
        case .pending(let record):
            return "Open pending depth photo, \(record.status.rawValue)"
        }
    }
}
