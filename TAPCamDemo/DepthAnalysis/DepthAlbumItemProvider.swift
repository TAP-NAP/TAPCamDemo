//
//  DepthAlbumItemProvider.swift
//  TAPCamDemo
//

import Foundation
import OSLog

/// Snapshot of the TAP Library grid after pending records and Photos assets are
/// reconciled.
nonisolated struct DepthAlbumItemSnapshot {
    let items: [TAPLibraryItem]
    let photoAssetsError: Error?

    var summaries: [LibraryMediaSummary] {
        items.map(\.summary)
    }
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
    typealias PhotoCatalogLoader = (Set<String>) async throws -> DepthAlbumPhotoCatalogSnapshot
    typealias ExportedRecordRemover = (String) async throws -> Void
    typealias DateProvider = () -> Date

    nonisolated private static let missingExportedAssetGraceInterval: TimeInterval = 60

    private let pendingRecordsLoader: PendingRecordsLoader
    private let exportedRecordsLoader: ExportedRecordsLoader
    private let photoCatalogLoader: PhotoCatalogLoader
    private let exportedRecordRemover: ExportedRecordRemover
    private let dateProvider: DateProvider
    private let missingExportedAssetGraceInterval: TimeInterval

    init(
        pendingRecordsLoader: @escaping PendingRecordsLoader = {
            try TAPPendingCaptureStore.shared.visiblePendingRecords()
        },
        exportedRecordsLoader: @escaping ExportedRecordsLoader = {
            try TAPPendingCaptureStore.shared.exportedRecords()
        },
        photoCatalog: any DepthAlbumPhotoCataloging = PhotoKitLibraryMediaFetcher(),
        exportedRecordRemover: @escaping ExportedRecordRemover = { captureID in
            try TAPPendingCaptureStore.shared.removeRecord(captureID: captureID)
        },
        dateProvider: @escaping DateProvider = Date.init,
        missingExportedAssetGraceInterval: TimeInterval = Self.missingExportedAssetGraceInterval
    ) {
        self.pendingRecordsLoader = pendingRecordsLoader
        self.exportedRecordsLoader = exportedRecordsLoader
        self.photoCatalogLoader = { exportedAssetLocalIdentifiers in
            try await photoCatalog.depthAlbumPhotoCatalogSnapshot(
                exportedAssetLocalIdentifiers: exportedAssetLocalIdentifiers
            )
        }
        self.exportedRecordRemover = exportedRecordRemover
        self.dateProvider = dateProvider
        self.missingExportedAssetGraceInterval = missingExportedAssetGraceInterval
    }

    /// Closure-based catalog injection keeps deterministic tests lightweight
    /// without reintroducing PhotoKit objects or synchronous per-item lookup.
    init(
        pendingRecordsLoader: @escaping PendingRecordsLoader,
        exportedRecordsLoader: @escaping ExportedRecordsLoader,
        photoCatalogLoader: @escaping PhotoCatalogLoader,
        exportedRecordRemover: @escaping ExportedRecordRemover = { _ in },
        dateProvider: @escaping DateProvider = Date.init,
        missingExportedAssetGraceInterval: TimeInterval = Self.missingExportedAssetGraceInterval
    ) {
        self.pendingRecordsLoader = pendingRecordsLoader
        self.exportedRecordsLoader = exportedRecordsLoader
        self.photoCatalogLoader = photoCatalogLoader
        self.exportedRecordRemover = exportedRecordRemover
        self.dateProvider = dateProvider
        self.missingExportedAssetGraceInterval = missingExportedAssetGraceInterval
    }

    func loadSnapshot() async throws -> DepthAlbumItemSnapshot {
        let pendingRecords = try await pendingRecordsLoader()
        let exportedRecords = try await exportedRecordsLoader()

        let photoCatalogSnapshot: DepthAlbumPhotoCatalogSnapshot
        let photoAssetsError: Error?
        let reconciledExportedRecords: [TAPPendingCaptureRecord]
        do {
            let exportedAssetLocalIdentifiers = Set(
                (pendingRecords + exportedRecords).compactMap(\.assetLocalIdentifier)
            )
            photoCatalogSnapshot = try await photoCatalogLoader(exportedAssetLocalIdentifiers)
            photoAssetsError = nil
            reconciledExportedRecords = await reconcileExportedRecords(
                exportedRecords,
                resolvedAssetLocalIdentifiers: Set(
                    photoCatalogSnapshot.assetsByLocalIdentifier.keys
                )
            )
        } catch {
            photoCatalogSnapshot = .empty
            photoAssetsError = error
            reconciledExportedRecords = exportedRecords
        }

        let items = TAPLibraryItem.merged(
            pendingRecords: pendingRecords,
            exportedRecords: reconciledExportedRecords,
            photoAssets: photoCatalogSnapshot.albumAssets,
            photoAssetsByLocalIdentifier: photoCatalogSnapshot.assetsByLocalIdentifier
        )
        LockedCameraDiagnostics.logger.info(
            "tap_library_snapshot_loaded visiblePendingCount=\(pendingRecords.count, privacy: .public) exportedRecordCount=\(exportedRecords.count, privacy: .public) photoAssetCount=\(photoCatalogSnapshot.albumAssets.count, privacy: .public) itemCount=\(items.count, privacy: .public) itemSources=\(Self.itemSourceCountsDescription(items), privacy: .public) latestPending=\(Self.pendingRecordsDescription(pendingRecords), privacy: .public) photoAssetsErrorPresent=\(photoAssetsError != nil, privacy: .public)"
        )
        return DepthAlbumItemSnapshot(items: items, photoAssetsError: photoAssetsError)
    }

    /// A successful PhotoKit catalog read is authoritative for old exported
    /// records. Recently exported records keep a short grace window for the
    /// Photos change journal to settle; older missing assets are orphaned local
    /// bundles left behind by an external or legacy delete.
    private func reconcileExportedRecords(
        _ records: [TAPPendingCaptureRecord],
        resolvedAssetLocalIdentifiers: Set<String>
    ) async -> [TAPPendingCaptureRecord] {
        let cutoff = dateProvider().addingTimeInterval(-missingExportedAssetGraceInterval)
        var retained: [TAPPendingCaptureRecord] = []
        retained.reserveCapacity(records.count)

        for record in records {
            guard let assetID = record.assetLocalIdentifier,
                  !resolvedAssetLocalIdentifiers.contains(assetID),
                  record.updatedAt <= cutoff else {
                retained.append(record)
                continue
            }

            do {
                try await exportedRecordRemover(record.captureID)
            } catch {
                let nsError = error as NSError
                LockedCameraDiagnostics.logger.error(
                    "tap_library_orphan_cleanup_failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                )
            }
        }
        return retained
    }

    private static func pendingRecordsDescription(_ records: [TAPPendingCaptureRecord]) -> String {
        let value = records
            .prefix(6)
            .map { "\($0.captureID):\($0.status.rawValue)" }
            .joined(separator: "|")
        return value.isEmpty ? "none" : value
    }

    private static func itemSourceCountsDescription(_ items: [TAPLibraryItem]) -> String {
        var pendingCount = 0
        var ownedPhotoCount = 0
        var photosCount = 0
        for item in items {
            switch item.source {
            case .pending:
                pendingCount += 1
            case .ownedPhoto:
                ownedPhotoCount += 1
            case .photos:
                photosCount += 1
            }
        }
        return "pending:\(pendingCount)|owned:\(ownedPhotoCount)|photos:\(photosCount)"
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
    let mediaID: LibraryMediaID
    let source: Source
    let capturedAt: Date
    let routeAnchor: CameraRouteAlbumAnchor

    var id: String {
        mediaID.storageValue
    }

    var summary: LibraryMediaSummary {
        LibraryMediaSummary(
            id: mediaID,
            capturedAt: capturedAt,
            kind: mediaKind,
            source: mediaSource,
            version: mediaVersion
        )
    }

    func thumbnailCacheKey(pixelLength: Int) -> String {
        DepthAlbumThumbnailCacheKey.make(
            mediaID: mediaID,
            version: mediaVersion.posterRevision,
            pixelLength: pixelLength
        )
    }

    private init?(mediaID: LibraryMediaID, source: Source, capturedAt: Date) {
        let routeAnchor: CameraRouteAlbumAnchor?
        switch source {
        case .pending(let record):
            routeAnchor = CameraRouteAlbumAnchor(
                itemID: mediaID.storageValue,
                captureID: record.captureID
            )
        case .ownedPhoto(let record, let asset):
            routeAnchor = CameraRouteAlbumAnchor(
                itemID: mediaID.storageValue,
                captureID: record.captureID,
                assetLocalIdentifier: asset.localIdentifier
            )
        case .photos(let asset):
            routeAnchor = CameraRouteAlbumAnchor(
                itemID: mediaID.storageValue,
                assetLocalIdentifier: asset.localIdentifier
            )
        }

        guard let routeAnchor else {
            return nil
        }

        self.mediaID = mediaID
        self.source = source
        self.capturedAt = capturedAt
        self.routeAnchor = routeAnchor
    }

    static func merged(
        pendingRecords: [TAPPendingCaptureRecord],
        exportedRecords: [TAPPendingCaptureRecord],
        photoAssets: [DepthAlbumPhotoAsset],
        photoAssetsByLocalIdentifier: [String: DepthAlbumPhotoAsset] = [:]
    ) -> [TAPLibraryItem] {
        var resolvedPhotoAssetsByID: [String: DepthAlbumPhotoAsset] = [:]
        resolvedPhotoAssetsByID.reserveCapacity(
            photoAssets.count + photoAssetsByLocalIdentifier.count
        )
        for asset in photoAssets {
            resolvedPhotoAssetsByID[asset.localIdentifier] = asset
        }
        resolvedPhotoAssetsByID.merge(photoAssetsByLocalIdentifier) { _, catalogAsset in
            catalogAsset
        }

        let pendingItems = pendingRecords
            .filter(\.isVisiblePendingItem)
            .compactMap { record in
                TAPLibraryItem(
                    mediaID: .tapCapture(record.captureID),
                    source: .pending(record),
                    capturedAt: record.capturedAt
                )
            }

        let ownedPhotoItems = exportedRecords.compactMap { record -> TAPLibraryItem? in
            guard let assetID = record.assetLocalIdentifier else {
                return nil
            }

            // Photos can be temporarily unavailable while authorization,
            // iCloud, or its change journal settles. Keep the app-owned scalar
            // identity in the canonical catalog instead of making the item
            // disappear until Photos catalog resolution succeeds.
            let asset = resolvedPhotoAssetsByID[assetID] ?? DepthAlbumPhotoAsset(
                localIdentifier: assetID,
                creationDate: record.capturedAt,
                modificationDate: record.updatedAt,
                isLivePhoto: record.artifactKind != .tapVideo && record.pairedVideoFilename != nil,
                isVideo: record.artifactKind == .tapVideo
            )

            return TAPLibraryItem(
                mediaID: .tapCapture(record.captureID),
                source: .ownedPhoto(record, asset),
                capturedAt: record.capturedAt
            )
        }
        // A Photos commit can succeed before readback validation finishes. In
        // that window (and after a terminal readback failure), the visible
        // pending record already owns a Photos asset identifier. Exclude every
        // app-owned asset from the Photos-only lane so one capture never gains
        // a second `.photosAsset` identity while its canonical `.tapCapture`
        // item is still pending.
        let ownedAssetIDs = Set(
            (pendingRecords + exportedRecords).compactMap(\.assetLocalIdentifier)
        )

        let photoItems = photoAssets
            .filter { !ownedAssetIDs.contains($0.localIdentifier) }
            .compactMap { asset in
                TAPLibraryItem(
                    mediaID: .photosAsset(asset.localIdentifier),
                    source: .photos(asset),
                    capturedAt: asset.creationDate ?? .distantPast
                )
            }

        var itemsByID: [LibraryMediaID: TAPLibraryItem] = [:]
        for item in pendingItems + ownedPhotoItems + photoItems where itemsByID[item.mediaID] == nil {
            itemsByID[item.mediaID] = item
        }
        return itemsByID.values.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }
            return lhs.id < rhs.id
        }
    }

    private var assetLocalIdentifier: String? {
        switch source {
        case .photos(let asset), .ownedPhoto(_, let asset):
            asset.localIdentifier
        case .pending:
            nil
        }
    }

    private var mediaKind: LibraryMediaKind {
        if isVideo {
            return .tapVideo
        }
        return isLivePhoto ? .livePhoto : .photo
    }

    private var mediaSource: LibraryMediaSource {
        switch source {
        case .pending(let record):
            return .pending(captureID: record.captureID)
        case .ownedPhoto(let record, let asset):
            return .ownedPhotosAsset(captureID: record.captureID, assetID: asset.localIdentifier)
        case .photos(let asset):
            return .photosOnly(assetID: asset.localIdentifier)
        }
    }

    private var mediaVersion: LibraryMediaVersion {
        switch source {
        case .pending(let record):
            let content = [
                record.artifactKind.rawValue,
                record.signedPhotoFilename ?? record.unsignedPhotoFilename ?? "no-photo",
                record.videoArtifactFilename ?? "no-video",
                String(record.updatedAt.timeIntervalSince1970)
            ].joined(separator: "|")
            let poster = [
                record.thumbnailFilename ?? "no-thumbnail",
                String(record.updatedAt.timeIntervalSince1970)
            ].joined(separator: "|")
            return LibraryMediaVersion(contentRevision: content, posterRevision: poster)
        case .ownedPhoto(let record, let asset):
            let assetVersion = asset.modificationDate ?? asset.creationDate ?? record.capturedAt
            return LibraryMediaVersion(
                contentRevision: [
                    record.artifactKind.rawValue,
                    String(assetVersion.timeIntervalSince1970),
                    "\(asset.pixelWidth)x\(asset.pixelHeight)"
                ].joined(separator: "|"),
                posterRevision: [
                    record.thumbnailFilename ?? "no-thumbnail",
                    String(record.updatedAt.timeIntervalSince1970),
                    String(assetVersion.timeIntervalSince1970)
                ].joined(separator: "|")
            )
        case .photos(let asset):
            let versionDate = asset.modificationDate ?? asset.creationDate ?? .distantPast
            let version = [
                String(versionDate.timeIntervalSince1970),
                "\(asset.pixelWidth)x\(asset.pixelHeight)",
                asset.isVideo ? "video" : "photo",
                asset.isLivePhoto ? "live" : "still"
            ].joined(separator: "|")
            return LibraryMediaVersion(contentRevision: version, posterRevision: version)
        }
    }
}

nonisolated extension TAPLibraryItem {
    var isLivePhoto: Bool {
        switch source {
        case .photos(let asset):
            return asset.isLivePhoto && !asset.isVideo
        case .ownedPhoto(let record, let asset):
            return record.artifactKind != .tapVideo
                && (asset.isLivePhoto || record.pairedVideoFilename != nil)
        case .pending(let record):
            return record.artifactKind != .tapVideo && record.pairedVideoFilename != nil
        }
    }

    var isVideo: Bool {
        switch source {
        case .photos(let asset):
            return asset.isVideo
        case .ownedPhoto(let record, let asset):
            return record.artifactKind == .tapVideo || asset.isVideo
        case .pending(let record):
            return record.artifactKind == .tapVideo
        }
    }

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
        case .failedTerminal:
            return "FAILED"
        case .exported:
            return nil
        }
    }

    var accessibilityLabel: String {
        switch source {
        case .photos, .ownedPhoto:
            if isVideo {
                return "Open saved TAP video"
            }
            if isLivePhoto {
                return "Open saved Live Photo"
            }
            return "Open saved depth photo"
        case .pending(let record):
            if isVideo {
                return "Open pending TAP video, \(record.status.rawValue)"
            }
            if isLivePhoto {
                return "Open pending Live Photo, \(record.status.rawValue)"
            }
            return "Open pending depth photo, \(record.status.rawValue)"
        }
    }
}
