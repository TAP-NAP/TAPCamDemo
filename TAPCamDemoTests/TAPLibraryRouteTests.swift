//
//  TAPLibraryRouteTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPLibraryRouteTests {
    @Test @MainActor func cameraRouteStoreDefaultsToCamera() throws {
        let routeStore = try Self.makeRouteStore()

        #expect(routeStore.destination == .camera)
        #expect(!routeStore.isLibraryPresented)
        #expect(routeStore.libraryRestoreAnchorID == nil)
    }

    @Test @MainActor func cameraRouteStoreReturnsToCameraWithoutDroppingAlbumAnchor() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.presentLibrary()
        routeStore.openLibraryItem(id: "owned:asset-1")
        routeStore.returnToCamera()

        #expect(routeStore.destination == .camera)
        #expect(!routeStore.isLibraryPresented)
        #expect(routeStore.albumState.selectedItemID == "owned:asset-1")
        #expect(routeStore.libraryRestoreAnchorID == "owned:asset-1")
    }

    @Test @MainActor func cameraRouteStoreRestoresCameraOnForeground() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.presentLibrary()
        routeStore.restoreCameraOnForeground()

        #expect(routeStore.destination == .camera)
        #expect(!routeStore.isLibraryPresented)
    }

    @Test @MainActor func cameraRouteStoreTracksVisibleAndSelectedAlbumAnchors() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.recordVisibleLibraryItem(id: "photos:visible")
        #expect(routeStore.albumState.scrollAnchorItemID == "photos:visible")
        #expect(routeStore.libraryRestoreAnchorID == "photos:visible")

        routeStore.openLibraryItem(id: "pending:selected")
        #expect(routeStore.albumState.selectedItemID == "pending:selected")
        #expect(routeStore.albumState.scrollAnchorItemID == "pending:selected")
        #expect(routeStore.libraryRestoreAnchorID == "pending:selected")
    }

    @Test @MainActor func cameraRouteStoreUsesLatestVisibleAlbumAnchorForRestore() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.openLibraryItem(id: "owned:opened")
        routeStore.recordVisibleLibraryItem(id: "photos:visible-after-open")

        #expect(routeStore.albumState.selectedItemID == "owned:opened")
        #expect(routeStore.albumState.scrollAnchorItemID == "photos:visible-after-open")
        #expect(routeStore.libraryRestoreAnchorID == "photos:visible-after-open")
    }

    @Test @MainActor func cameraRouteStoreValidatesAlbumAnchorAgainstAvailableItems() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.openLibraryItem(id: "owned:asset-1")

        #expect(routeStore.validLibraryRestoreAnchorID(availableItemIDs: Set(["owned:asset-1"])) == "owned:asset-1")
        #expect(routeStore.validLibraryRestoreAnchorID(availableItemIDs: Set(["owned:asset-2"])) == nil)
    }

    @Test @MainActor func cameraRouteStorePersistsAlbumAnchorsAcrossInstances() throws {
        let contextStore = try Self.makeRouteContextStore()
        let routeStore = CameraRouteStore(contextStore: contextStore)
        let selectedAnchor = Self.sampleAlbumAnchor(
            itemID: "owned:asset-1",
            captureID: "capture-1",
            assetLocalIdentifier: "asset-1"
        )

        routeStore.openLibraryItem(selectedAnchor)

        let reloadedRouteStore = CameraRouteStore(contextStore: contextStore)

        #expect(reloadedRouteStore.destination == .camera)
        #expect(reloadedRouteStore.libraryRestoreAnchorID == nil)
        #expect(reloadedRouteStore.validLibraryRestoreAnchorID(availableItems: [selectedAnchor]) == "owned:asset-1")
    }

    @Test @MainActor func cameraRouteStoreClearsUnavailablePersistedAlbumAnchors() throws {
        let contextStore = try Self.makeRouteContextStore()
        let routeStore = CameraRouteStore(contextStore: contextStore)
        let deletedAnchor = Self.sampleAlbumAnchor(
            itemID: "owned:deleted",
            captureID: "capture-deleted",
            assetLocalIdentifier: "deleted"
        )

        routeStore.openLibraryItem(deletedAnchor)

        #expect(routeStore.validLibraryRestoreAnchorID(availableItems: [
            Self.sampleAlbumAnchor(itemID: "owned:asset-2", captureID: "capture-2", assetLocalIdentifier: "asset-2")
        ]) == nil)

        let reloadedRouteStore = CameraRouteStore(contextStore: contextStore)
        #expect(reloadedRouteStore.validLibraryRestoreAnchorID(availableItems: [deletedAnchor]) == nil)
    }

    @Test @MainActor func cameraRouteStoreMigratesPersistedPendingAnchorToOwnedPhotoAnchor() throws {
        let contextStore = try Self.makeRouteContextStore()
        let routeStore = CameraRouteStore(contextStore: contextStore)

        routeStore.openLibraryItem(
            Self.sampleAlbumAnchor(itemID: "pending:capture-1", captureID: "capture-1")
        )

        let reloadedRouteStore = CameraRouteStore(contextStore: contextStore)
        let ownedAnchor = Self.sampleAlbumAnchor(
            itemID: "owned:asset-1",
            captureID: "capture-1",
            assetLocalIdentifier: "asset-1"
        )

        #expect(reloadedRouteStore.validLibraryRestoreAnchorID(availableItems: [ownedAnchor]) == "owned:asset-1")
    }

    @Test @MainActor func cameraRouteContextPersistsTokensWithoutRawAlbumIdentifiers() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let contextStore = CameraRouteFileContextStore(directoryURL: directoryURL)
        let routeStore = CameraRouteStore(contextStore: contextStore)

        routeStore.openLibraryItem(
            Self.sampleAlbumAnchor(
                itemID: "owned:asset-secret",
                captureID: "capture-secret",
                assetLocalIdentifier: "asset-secret"
            )
        )

        let contextData = try Data(contentsOf: directoryURL.appendingPathComponent("CameraRouteContext.json"))
        let contextJSON = String(decoding: contextData, as: UTF8.self)

        #expect(!contextJSON.contains("owned:asset-secret"))
        #expect(!contextJSON.contains("capture-secret"))
        #expect(!contextJSON.contains("asset-secret"))
        #expect(contextJSON.contains("restoreAnchorTokens"))
    }

    @Test @MainActor func cameraRouteContextPersistsOnlyHexTokenValues() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let contextStore = CameraRouteFileContextStore(directoryURL: directoryURL)
        let routeStore = CameraRouteStore(contextStore: contextStore)

        routeStore.openLibraryItem(
            Self.sampleAlbumAnchor(
                itemID: "owned:asset-secret",
                captureID: "capture-secret",
                assetLocalIdentifier: "asset-secret"
            )
        )

        let contextData = try Data(contentsOf: directoryURL.appendingPathComponent("CameraRouteContext.json"))
        let context = try JSONDecoder().decode(CameraRouteContext.self, from: contextData)

        #expect(context.restoreAnchorTokens.count == 3)
        for token in context.restoreAnchorTokens {
            #expect(token.count == 64)
            #expect(token.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            })
        }
    }

    @Test func libraryThumbnailCacheKeyTracksSourceIdentityVersionAndSize() throws {
        let originalKey = LibraryThumbnailCacheKey.make(
            assetLocalIdentifier: "asset-1",
            pixelLength: 240,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 1_234)
        )
        let changedVersionKey = LibraryThumbnailCacheKey.make(
            assetLocalIdentifier: "asset-1",
            pixelLength: 240,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 9_999)
        )
        let changedSizeKey = LibraryThumbnailCacheKey.make(
            assetLocalIdentifier: "asset-1",
            pixelLength: 320,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 1_234)
        )

        #expect(changedVersionKey != originalKey)
        #expect(changedSizeKey != originalKey)
        for assetID in ["asset-1", "asset-2"] {
            let key = LibraryThumbnailCacheKey.make(
                assetLocalIdentifier: assetID,
                pixelLength: 240,
                pixelWidth: 4032,
                pixelHeight: 3024,
                versionDate: Date(timeIntervalSince1970: 1_234)
            )
            #expect((key == originalKey) == (assetID == "asset-1"))
        }
    }

    @Test func libraryPendingVideoThumbnailCacheKeyTracksVideoVersion() throws {
        let originalKey = LibraryThumbnailCacheKey.makePending(
            captureID: "video-capture",
            pixelLength: 240,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            thumbnailFilename: nil,
            videoFilename: TAPPendingCaptureBundlePaths.videoArtifactFilename,
            updatedAt: Date(timeIntervalSince1970: 1_001)
        )
        let signedKey = LibraryThumbnailCacheKey.makePending(
            captureID: "video-capture",
            pixelLength: 240,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            thumbnailFilename: nil,
            videoFilename: TAPPendingCaptureBundlePaths.videoArtifactFilename,
            updatedAt: Date(timeIntervalSince1970: 1_002)
        )

        #expect(signedKey != originalKey)
    }

    @Test func libraryItemsPreferOwnedExportsOverDuplicatePhotos() throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-1",
            capturedAt: Date(timeIntervalSince1970: 300)
        )
        let exportedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "exported-1",
            capturedAt: Date(timeIntervalSince1970: 100),
            status: .exported,
            assetLocalIdentifier: "asset-owned"
        )
        let ownedAsset = LibraryPhotoAsset(
            localIdentifier: "asset-owned",
            creationDate: Date(timeIntervalSince1970: 200),
            pixelWidth: 4_032,
            pixelHeight: 3_024
        )
        let photosOnlyAsset = LibraryPhotoAsset(
            localIdentifier: "asset-plain",
            creationDate: Date(timeIntervalSince1970: 50),
            pixelWidth: 4_032,
            pixelHeight: 3_024
        )

        let items = TAPLibraryItem.merged(
            pendingRecords: [pendingRecord, exportedRecord],
            exportedRecords: [exportedRecord],
            photoAssets: [ownedAsset, photosOnlyAsset],
            photoAssetsByLocalIdentifier: [ownedAsset.localIdentifier: ownedAsset]
        )

        #expect(items.map(\.id) == [
            "capture:pending-1",
            "capture:exported-1",
            "photos:asset-plain"
        ])
    }

    @Test func libraryItemsPublishLivePhotoFlagForPhotosOwnedAndPendingSources() throws {
        let livePending = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-live",
            capturedAt: Date(timeIntervalSince1970: 400),
            pairedVideoFilename: TAPPendingCaptureBundlePaths.pairedVideoFilename
        )
        let plainPending = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-plain",
            capturedAt: Date(timeIntervalSince1970: 300)
        )
        let exportedLiveRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "exported-live",
            capturedAt: Date(timeIntervalSince1970: 200),
            status: .exported,
            pairedVideoFilename: TAPPendingCaptureBundlePaths.pairedVideoFilename,
            assetLocalIdentifier: "asset-owned"
        )
        let ownedAsset = LibraryPhotoAsset(
            localIdentifier: "asset-owned",
            creationDate: Date(timeIntervalSince1970: 200),
            modificationDate: nil,
            pixelWidth: 0,
            pixelHeight: 0,
            isLivePhoto: false
        )
        let photosLiveAsset = LibraryPhotoAsset(
            localIdentifier: "asset-live",
            creationDate: Date(timeIntervalSince1970: 100),
            modificationDate: nil,
            pixelWidth: 0,
            pixelHeight: 0,
            isLivePhoto: true
        )

        let items = TAPLibraryItem.merged(
            pendingRecords: [livePending, plainPending],
            exportedRecords: [exportedLiveRecord],
            photoAssets: [photosLiveAsset],
            photoAssetsByLocalIdentifier: [ownedAsset.localIdentifier: ownedAsset]
        )
        let livePhotoFlags: [String: Bool] = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.isLivePhoto) }
        )

        #expect(livePhotoFlags["capture:pending-live"] == true)
        #expect(livePhotoFlags["capture:pending-plain"] == false)
        #expect(livePhotoFlags["capture:exported-live"] == true)
        #expect(livePhotoFlags["photos:asset-live"] == true)
    }

    @Test func libraryItemsSortByCapturedAtDescending() throws {
        let oldPending = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-old",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let exportedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "exported-mid",
            capturedAt: Date(timeIntervalSince1970: 20),
            status: .exported,
            assetLocalIdentifier: "asset-mid"
        )
        let ownedAsset = LibraryPhotoAsset(
            localIdentifier: "asset-mid",
            creationDate: Date(timeIntervalSince1970: 30)
        )
        let newestPhotosAsset = LibraryPhotoAsset(
            localIdentifier: "asset-newest",
            creationDate: Date(timeIntervalSince1970: 40)
        )

        let items = TAPLibraryItem.merged(
            pendingRecords: [oldPending],
            exportedRecords: [exportedRecord],
            photoAssets: [newestPhotosAsset],
            photoAssetsByLocalIdentifier: [ownedAsset.localIdentifier: ownedAsset]
        )

        #expect(items.map(\.id) == [
            "photos:asset-newest",
            "capture:exported-mid",
            "capture:pending-old"
        ])
    }

    @Test func libraryItemRouteAnchorsKeepPrivateIdentifiersInMemoryOnly() throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-pending",
            capturedAt: Date(timeIntervalSince1970: 300)
        )
        let exportedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-exported",
            capturedAt: Date(timeIntervalSince1970: 200),
            status: .exported,
            assetLocalIdentifier: "asset-owned"
        )
        let ownedAsset = LibraryPhotoAsset(localIdentifier: "asset-owned")
        let photosOnlyAsset = LibraryPhotoAsset(localIdentifier: "asset-plain")

        let items = TAPLibraryItem.merged(
            pendingRecords: [pendingRecord],
            exportedRecords: [exportedRecord],
            photoAssets: [photosOnlyAsset],
            photoAssetsByLocalIdentifier: [ownedAsset.localIdentifier: ownedAsset]
        )
        let anchors = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.routeAnchor) })

        #expect(anchors["capture:capture-pending"]?.captureID == "capture-pending")
        #expect(anchors["capture:capture-pending"]?.assetLocalIdentifier == nil)
        #expect(anchors["capture:capture-exported"]?.captureID == "capture-exported")
        #expect(anchors["capture:capture-exported"]?.assetLocalIdentifier == "asset-owned")
        #expect(anchors["photos:asset-plain"]?.captureID == nil)
        #expect(anchors["photos:asset-plain"]?.assetLocalIdentifier == "asset-plain")
    }

    @Test @MainActor func libraryCatalogReconcilerKeepsPendingItemsWhenPhotosFails() async throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-offline",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let provider = LibraryCatalogReconciler(
            recordsLoader: { [pendingRecord] },
            photoCatalogLoader: { _ in
                throw LibraryCatalogReconcilerTestError.photosUnavailable
            }
        )

        let snapshot = try await provider.loadSnapshot()

        #expect(snapshot.items.map(\.id) == ["capture:pending-offline"])
        #expect(snapshot.photoAssetsError != nil)

        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)
        await viewModel.loadForPresentation()
        #expect(viewModel.items.map(\.id) == ["capture:pending-offline"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor func tapLibraryPresentationReusesNonemptySnapshot() async throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "cached-pending",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        var loadCount = 0
        let provider = LibraryCatalogReconciler(
            recordsLoader: {
                loadCount += 1
                return [pendingRecord]
            },
            photoCatalogLoader: { _ in .empty }
        )
        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)

        await viewModel.loadForPresentation()
        await viewModel.loadForPresentation()

        #expect(loadCount == 1)
        #expect(viewModel.items.map(\.id) == ["capture:cached-pending"])
    }

    @Test @MainActor func tapLibraryPresentationRefreshesEmptySnapshot() async throws {
        var loadCount = 0
        let provider = LibraryCatalogReconciler(
            recordsLoader: {
                loadCount += 1
                return []
            },
            photoCatalogLoader: { _ in .empty }
        )
        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)

        await viewModel.loadForPresentation()
        await viewModel.loadForPresentation()

        #expect(loadCount == 2)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor func tapLibraryPresentationLoadRefreshesCachedEmptySnapshot() async throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "locked-import-pending",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        var loadCount = 0
        let provider = LibraryCatalogReconciler(
            recordsLoader: {
                defer { loadCount += 1 }
                return loadCount == 0 ? [] : [pendingRecord]
            },
            photoCatalogLoader: { _ in .empty }
        )
        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)

        #expect(viewModel.shouldShowLoading)

        await viewModel.loadForPresentation()

        #expect(loadCount == 1)
        #expect(viewModel.items.isEmpty)
        #expect(!viewModel.shouldShowLoading)

        await viewModel.loadForPresentation()

        #expect(loadCount == 2)
        #expect(viewModel.items.map(\.id) == ["capture:locked-import-pending"])
        #expect(!viewModel.shouldShowLoading)
    }

    @Test @MainActor func tapLibraryPresentationRetriesFailedSnapshot() async throws {
        var loadCount = 0
        let provider = LibraryCatalogReconciler(
            recordsLoader: {
                loadCount += 1
                throw LibraryCatalogReconcilerTestError.photosUnavailable
            },
            photoCatalogLoader: { _ in .empty }
        )
        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)

        await viewModel.loadForPresentation()
        await viewModel.loadForPresentation()

        #expect(loadCount == 2)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "Unable to load TAP Library. Check Photos access and try again.")
    }

    @Test @MainActor func tapLibraryShowsPhotosErrorOnlyWhenNoItemsSurvive() async throws {
        let provider = LibraryCatalogReconciler(
            recordsLoader: { [] },
            photoCatalogLoader: { _ in
                throw LibraryCatalogReconcilerTestError.photosUnavailable
            }
        )
        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)

        await viewModel.loadForPresentation()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "Unable to read the TAPCamDepth album. Check Photos access and try again.")
        #expect(viewModel.errorMessage?.contains("Photos unavailable for test") == false)
    }

    @Test @MainActor func tapLibraryTracksSharedStoreFailureAndRecovery() async {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "shared-store-recovery",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        var storeFails = true
        var photosFail = false
        var includesPendingItem = false
        let store = LibraryMediaStore(catalogReconciler: LibraryCatalogReconciler(
            recordsLoader: {
                if storeFails { throw LibraryCatalogReconcilerTestError.photosUnavailable }
                return includesPendingItem ? [pendingRecord] : []
            },
            photoCatalogLoader: { _ in
                if photosFail { throw LibraryCatalogReconcilerTestError.photosUnavailable }
                return .empty
            }
        ))
        let viewModel = TAPLibraryViewModel(libraryStore: store)
        await viewModel.loadForPresentation()
        #expect(viewModel.errorMessage == "Unable to load TAP Library. Check Photos access and try again.")
        #expect(!viewModel.shouldShowLoading)

        // Subsequent refreshes belong to the shared store, without another
        // picker load or presentation lifecycle event.
        storeFails = false
        photosFail = true
        await store.refresh()
        #expect(viewModel.errorMessage == "Unable to read the TAPCamDepth album. Check Photos access and try again.")

        includesPendingItem = true
        await store.refresh()
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.items.map(\.id) == ["capture:shared-store-recovery"])

        storeFails = true
        await store.refresh()
        #expect(viewModel.errorMessage == "Unable to load TAP Library. Check Photos access and try again.")

        storeFails = false
        photosFail = false
        includesPendingItem = false
        await store.refresh()
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.items.isEmpty)
        #expect(!viewModel.shouldShowLoading)
    }

    @Test @MainActor func tapLibraryUsesFixedErrorWhenStoreLoadFails() async throws {
        let sensitivePath = "/private/var/mobile/Containers/Data/capture-private-id"
        let provider = LibraryCatalogReconciler(
            recordsLoader: { throw LibraryCatalogReconcilerTestError.sensitiveStoreFailure(sensitivePath) },
            photoCatalogLoader: { _ in .empty }
        )
        let viewModel = TAPLibraryViewModel(catalogReconciler: provider)

        await viewModel.loadForPresentation()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "Unable to load TAP Library. Check Photos access and try again.")
        #expect(viewModel.errorMessage?.contains(sensitivePath) == false)
    }

    @Test func libraryOwnedThumbnailCacheKeyMatchesPosterRequest() throws {
        let captureID = "capture/private-owned"
        let assetID = "photos-library://asset/private-local-id"
        let exportedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: captureID,
            capturedAt: Date(timeIntervalSince1970: 100),
            status: .exported,
            assetLocalIdentifier: assetID
        )
        let ownedAsset = LibraryPhotoAsset(
            localIdentifier: assetID,
            creationDate: Date(timeIntervalSince1970: 100),
            pixelWidth: 4_032,
            pixelHeight: 3_024
        )

        let item = try #require(TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [exportedRecord],
            photoAssets: [],
            photoAssetsByLocalIdentifier: [assetID: ownedAsset]
        ).first)
        let cacheKey = item.thumbnailCacheKey(pixelLength: 240)

        let request = try #require(LibraryMediaPosterRequest(summary: item.summary, pixelLength: 240))
        #expect(cacheKey == request.cacheKey)
        #expect(cacheKey != item.thumbnailCacheKey(pixelLength: 320))
    }

    @Test func libraryPendingThumbnailCacheKeySurvivesSnapshotRebuild() throws {
        let captureID = "capture/private-pending"
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: captureID,
            capturedAt: Date(timeIntervalSince1970: 100),
            thumbnailFilename: TAPPendingCaptureBundlePaths.thumbnailFilename
        )

        let item = try #require(TAPLibraryItem.merged(
            pendingRecords: [pendingRecord],
            exportedRecords: [],
            photoAssets: []
        ).first)
        let cacheKey = item.thumbnailCacheKey(pixelLength: 240)

        let rebuiltItem = try #require(TAPLibraryItem.merged(
            pendingRecords: [pendingRecord], exportedRecords: [], photoAssets: []
        ).first)
        #expect(cacheKey == rebuiltItem.thumbnailCacheKey(pixelLength: 240))
        #expect(cacheKey != rebuiltItem.thumbnailCacheKey(pixelLength: 320))
    }

    @MainActor
    private static func makeRouteStore() throws -> CameraRouteStore {
        CameraRouteStore(contextStore: try makeRouteContextStore())
    }

    private static func makeRouteContextStore() throws -> CameraRouteFileContextStore {
        CameraRouteFileContextStore(directoryURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
    }

    private static func sampleAlbumAnchor(
        itemID: String,
        captureID: String? = nil,
        assetLocalIdentifier: String? = nil
    ) -> CameraRouteAlbumAnchor {
        CameraRouteAlbumAnchor(
            itemID: itemID,
            captureID: captureID,
            assetLocalIdentifier: assetLocalIdentifier
        )!
    }
}

private enum LibraryCatalogReconcilerTestError: LocalizedError {
    case photosUnavailable
    case sensitiveStoreFailure(String)

    var errorDescription: String? {
        switch self {
        case .photosUnavailable:
            return "Photos unavailable for test"
        case .sensitiveStoreFailure(let path):
            return "Raw store path \(path)"
        }
    }
}
