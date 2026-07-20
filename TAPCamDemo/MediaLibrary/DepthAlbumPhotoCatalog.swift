//
//  DepthAlbumPhotoCatalog.swift
//  TAPCamDemo
//

import Foundation

/// A lightweight, Sendable Photos asset value used for catalog ordering,
/// identity, routing, and tests. PhotoKit objects never cross this boundary.
nonisolated struct DepthAlbumPhotoAsset: Equatable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let isLivePhoto: Bool
    let isVideo: Bool

    init(
        localIdentifier: String,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        isLivePhoto: Bool = false,
        isVideo: Bool = false
    ) {
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isLivePhoto = isLivePhoto
        self.isVideo = isVideo
    }
}

/// One actor-produced view of the TAP album and every exported asset needed
/// to reconcile app-owned records. Album membership and exported lookup are
/// intentionally fetched together so the MainActor never performs per-record
/// PhotoKit queries.
nonisolated struct DepthAlbumPhotoCatalogSnapshot: Equatable, Sendable {
    let albumAssets: [DepthAlbumPhotoAsset]
    let assetsByLocalIdentifier: [String: DepthAlbumPhotoAsset]

    init(
        albumAssets: [DepthAlbumPhotoAsset],
        resolvedAssets: [DepthAlbumPhotoAsset] = []
    ) {
        self.albumAssets = albumAssets
        var assetsByLocalIdentifier: [String: DepthAlbumPhotoAsset] = [:]
        assetsByLocalIdentifier.reserveCapacity(albumAssets.count + resolvedAssets.count)
        for asset in albumAssets + resolvedAssets {
            assetsByLocalIdentifier[asset.localIdentifier] = asset
        }
        self.assetsByLocalIdentifier = assetsByLocalIdentifier
    }

    static let empty = DepthAlbumPhotoCatalogSnapshot(albumAssets: [])
}

nonisolated protocol DepthAlbumPhotoCataloging: Sendable {
    func depthAlbumPhotoCatalogSnapshot(
        exportedAssetLocalIdentifiers: Set<String>
    ) async throws -> DepthAlbumPhotoCatalogSnapshot
}
