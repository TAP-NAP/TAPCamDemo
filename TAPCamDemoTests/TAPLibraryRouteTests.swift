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
        #expect(!routeStore.isDepthAlbumPresented)
        #expect(routeStore.depthAlbumRestoreAnchorID == nil)
    }

    @Test @MainActor func cameraRouteStoreReturnsToCameraWithoutDroppingAlbumAnchor() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.presentDepthAlbum()
        routeStore.openDepthAlbumItem(id: "owned:asset-1")
        routeStore.returnToCamera()

        #expect(routeStore.destination == .camera)
        #expect(!routeStore.isDepthAlbumPresented)
        #expect(routeStore.albumState.selectedItemID == "owned:asset-1")
        #expect(routeStore.depthAlbumRestoreAnchorID == "owned:asset-1")
    }

    @Test @MainActor func cameraRouteStoreRestoresCameraOnForeground() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.presentDepthAlbum()
        routeStore.restoreCameraOnForeground()

        #expect(routeStore.destination == .camera)
        #expect(!routeStore.isDepthAlbumPresented)
    }

    @Test @MainActor func cameraRouteStoreTracksVisibleAndSelectedAlbumAnchors() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.recordVisibleDepthAlbumItem(id: "photos:visible")
        #expect(routeStore.albumState.scrollAnchorItemID == "photos:visible")
        #expect(routeStore.depthAlbumRestoreAnchorID == "photos:visible")

        routeStore.openDepthAlbumItem(id: "pending:selected")
        #expect(routeStore.albumState.selectedItemID == "pending:selected")
        #expect(routeStore.albumState.scrollAnchorItemID == "pending:selected")
        #expect(routeStore.depthAlbumRestoreAnchorID == "pending:selected")
    }

    @Test @MainActor func cameraRouteStoreUsesLatestVisibleAlbumAnchorForRestore() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.openDepthAlbumItem(id: "owned:opened")
        routeStore.recordVisibleDepthAlbumItem(id: "photos:visible-after-open")

        #expect(routeStore.albumState.selectedItemID == "owned:opened")
        #expect(routeStore.albumState.scrollAnchorItemID == "photos:visible-after-open")
        #expect(routeStore.depthAlbumRestoreAnchorID == "photos:visible-after-open")
    }

    @Test @MainActor func cameraRouteStoreValidatesAlbumAnchorAgainstAvailableItems() throws {
        let routeStore = try Self.makeRouteStore()

        routeStore.openDepthAlbumItem(id: "owned:asset-1")

        #expect(routeStore.validDepthAlbumRestoreAnchorID(availableItemIDs: Set(["owned:asset-1"])) == "owned:asset-1")
        #expect(routeStore.validDepthAlbumRestoreAnchorID(availableItemIDs: Set(["owned:asset-2"])) == nil)
    }

    @Test @MainActor func cameraRouteStorePersistsAlbumAnchorsAcrossInstances() throws {
        let contextStore = try Self.makeRouteContextStore()
        let routeStore = CameraRouteStore(contextStore: contextStore)
        let selectedAnchor = Self.sampleAlbumAnchor(
            itemID: "owned:asset-1",
            captureID: "capture-1",
            assetLocalIdentifier: "asset-1"
        )

        routeStore.openDepthAlbumItem(selectedAnchor)

        let reloadedRouteStore = CameraRouteStore(contextStore: contextStore)

        #expect(reloadedRouteStore.destination == .camera)
        #expect(reloadedRouteStore.depthAlbumRestoreAnchorID == nil)
        #expect(reloadedRouteStore.validDepthAlbumRestoreAnchorID(availableItems: [selectedAnchor]) == "owned:asset-1")
    }

    @Test @MainActor func cameraRouteStoreClearsUnavailablePersistedAlbumAnchors() throws {
        let contextStore = try Self.makeRouteContextStore()
        let routeStore = CameraRouteStore(contextStore: contextStore)
        let deletedAnchor = Self.sampleAlbumAnchor(
            itemID: "owned:deleted",
            captureID: "capture-deleted",
            assetLocalIdentifier: "deleted"
        )

        routeStore.openDepthAlbumItem(deletedAnchor)

        #expect(routeStore.validDepthAlbumRestoreAnchorID(availableItems: [
            Self.sampleAlbumAnchor(itemID: "owned:asset-2", captureID: "capture-2", assetLocalIdentifier: "asset-2")
        ]) == nil)

        let reloadedRouteStore = CameraRouteStore(contextStore: contextStore)
        #expect(reloadedRouteStore.validDepthAlbumRestoreAnchorID(availableItems: [deletedAnchor]) == nil)
    }

    @Test @MainActor func cameraRouteStoreMigratesPersistedPendingAnchorToOwnedPhotoAnchor() throws {
        let contextStore = try Self.makeRouteContextStore()
        let routeStore = CameraRouteStore(contextStore: contextStore)

        routeStore.openDepthAlbumItem(
            Self.sampleAlbumAnchor(itemID: "pending:capture-1", captureID: "capture-1")
        )

        let reloadedRouteStore = CameraRouteStore(contextStore: contextStore)
        let ownedAnchor = Self.sampleAlbumAnchor(
            itemID: "owned:asset-1",
            captureID: "capture-1",
            assetLocalIdentifier: "asset-1"
        )

        #expect(reloadedRouteStore.validDepthAlbumRestoreAnchorID(availableItems: [ownedAnchor]) == "owned:asset-1")
    }

    @Test @MainActor func cameraRouteContextPersistsTokensWithoutRawAlbumIdentifiers() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let contextStore = CameraRouteFileContextStore(directoryURL: directoryURL)
        let routeStore = CameraRouteStore(contextStore: contextStore)

        routeStore.openDepthAlbumItem(
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

        routeStore.openDepthAlbumItem(
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

    @Test func depthAlbumThumbnailCacheKeyDoesNotExposePhotoIdentifier() throws {
        let photoIdentifier = "photos-library://asset/private-local-id"
        let cacheKey = DepthAlbumThumbnailCacheKey.make(
            assetLocalIdentifier: photoIdentifier,
            pixelLength: 240,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 1_234)
        )

        #expect(cacheKey.count == 64)
        #expect(cacheKey.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        })
        #expect(!cacheKey.contains(photoIdentifier))
        #expect(!cacheKey.contains("private-local-id"))
    }

    @Test func depthAlbumThumbnailCacheKeyChangesWhenSourceVersionChanges() throws {
        let originalKey = DepthAlbumThumbnailCacheKey.make(
            assetLocalIdentifier: "asset-1",
            pixelLength: 240,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 1_234)
        )
        let changedVersionKey = DepthAlbumThumbnailCacheKey.make(
            assetLocalIdentifier: "asset-1",
            pixelLength: 240,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 9_999)
        )
        let changedSizeKey = DepthAlbumThumbnailCacheKey.make(
            assetLocalIdentifier: "asset-1",
            pixelLength: 320,
            pixelWidth: 4032,
            pixelHeight: 3024,
            versionDate: Date(timeIntervalSince1970: 1_234)
        )

        #expect(changedVersionKey != originalKey)
        #expect(changedSizeKey != originalKey)
    }

    @Test func depthAlbumItemsPreferOwnedExportsOverDuplicatePhotos() throws {
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
        let ownedAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-owned",
            creationDate: Date(timeIntervalSince1970: 200),
            pixelWidth: 4_032,
            pixelHeight: 3_024
        )
        let photosOnlyAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-plain",
            creationDate: Date(timeIntervalSince1970: 50),
            pixelWidth: 4_032,
            pixelHeight: 3_024
        )

        let items = TAPLibraryItem.merged(
            pendingRecords: [pendingRecord, exportedRecord],
            exportedRecords: [exportedRecord],
            photoAssets: [ownedAsset, photosOnlyAsset],
            exportedAssetResolver: { $0 == ownedAsset.localIdentifier ? ownedAsset : nil }
        )

        #expect(items.map(\.id) == [
            "pending:pending-1",
            "owned:asset-owned",
            "photos:asset-plain"
        ])
    }

    @Test func depthAlbumItemsSortByCapturedAtDescending() throws {
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
        let ownedAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-mid",
            creationDate: Date(timeIntervalSince1970: 30)
        )
        let newestPhotosAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-newest",
            creationDate: Date(timeIntervalSince1970: 40)
        )

        let items = TAPLibraryItem.merged(
            pendingRecords: [oldPending],
            exportedRecords: [exportedRecord],
            photoAssets: [newestPhotosAsset],
            exportedAssetResolver: { $0 == ownedAsset.localIdentifier ? ownedAsset : nil }
        )

        #expect(items.map(\.id) == [
            "photos:asset-newest",
            "owned:asset-mid",
            "pending:pending-old"
        ])
    }

    @Test func depthAlbumItemRouteAnchorsKeepPrivateIdentifiersInMemoryOnly() throws {
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
        let ownedAsset = DepthAlbumPhotoAsset(localIdentifier: "asset-owned")
        let photosOnlyAsset = DepthAlbumPhotoAsset(localIdentifier: "asset-plain")

        let items = TAPLibraryItem.merged(
            pendingRecords: [pendingRecord],
            exportedRecords: [exportedRecord],
            photoAssets: [photosOnlyAsset],
            exportedAssetResolver: { $0 == ownedAsset.localIdentifier ? ownedAsset : nil }
        )
        let anchors = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.routeAnchor) })

        #expect(anchors["pending:capture-pending"]?.captureID == "capture-pending")
        #expect(anchors["pending:capture-pending"]?.assetLocalIdentifier == nil)
        #expect(anchors["owned:asset-owned"]?.captureID == "capture-exported")
        #expect(anchors["owned:asset-owned"]?.assetLocalIdentifier == "asset-owned")
        #expect(anchors["photos:asset-plain"]?.captureID == nil)
        #expect(anchors["photos:asset-plain"]?.assetLocalIdentifier == "asset-plain")
    }

    @Test @MainActor func depthAlbumItemProviderKeepsPendingItemsWhenPhotosFails() async throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-offline",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let provider = DepthAlbumItemProvider(
            pendingRecordsLoader: { [pendingRecord] },
            exportedRecordsLoader: { [] },
            photoAssetsLoader: { throw DepthAlbumItemProviderTestError.photosUnavailable },
            exportedAssetResolver: { _ in nil }
        )

        let snapshot = try await provider.loadSnapshot()

        #expect(snapshot.items.map(\.id) == ["pending:pending-offline"])
        #expect(snapshot.photoAssetsError != nil)

        let viewModel = DepthAlbumPickerViewModel(itemProvider: provider)
        await viewModel.load()
        #expect(viewModel.items.map(\.id) == ["pending:pending-offline"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor func depthAlbumPickerShowsPhotosErrorOnlyWhenNoItemsSurvive() async throws {
        let provider = DepthAlbumItemProvider(
            pendingRecordsLoader: { [] },
            exportedRecordsLoader: { [] },
            photoAssetsLoader: { throw DepthAlbumItemProviderTestError.photosUnavailable },
            exportedAssetResolver: { _ in nil }
        )
        let viewModel = DepthAlbumPickerViewModel(itemProvider: provider)

        await viewModel.load()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "Unable to read the TAPCamDepth album. Check Photos access and try again.")
        #expect(viewModel.errorMessage?.contains("Photos unavailable for test") == false)
    }

    @Test @MainActor func depthAlbumPickerUsesFixedErrorWhenStoreLoadFails() async throws {
        let sensitivePath = "/private/var/mobile/Containers/Data/capture-private-id"
        let provider = DepthAlbumItemProvider(
            pendingRecordsLoader: { throw DepthAlbumItemProviderTestError.sensitiveStoreFailure(sensitivePath) },
            exportedRecordsLoader: { [] },
            photoAssetsLoader: { [] },
            exportedAssetResolver: { _ in nil }
        )
        let viewModel = DepthAlbumPickerViewModel(itemProvider: provider)

        await viewModel.load()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "Unable to load TAP Library. Check Photos access and try again.")
        #expect(viewModel.errorMessage?.contains(sensitivePath) == false)
    }

    @Test func depthAlbumOwnedThumbnailCacheKeyDoesNotExposeCaptureOrPhotoIdentifier() throws {
        let captureID = "capture/private-owned"
        let assetID = "photos-library://asset/private-local-id"
        let exportedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: captureID,
            capturedAt: Date(timeIntervalSince1970: 100),
            status: .exported,
            assetLocalIdentifier: assetID
        )
        let ownedAsset = DepthAlbumPhotoAsset(
            localIdentifier: assetID,
            creationDate: Date(timeIntervalSince1970: 100),
            pixelWidth: 4_032,
            pixelHeight: 3_024
        )

        let item = try #require(TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [exportedRecord],
            photoAssets: [],
            exportedAssetResolver: { $0 == assetID ? ownedAsset : nil }
        ).first)
        let cacheKey = item.thumbnailCacheKey(pixelLength: 240)

        #expect(cacheKey.count == 64)
        #expect(cacheKey.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        })
        #expect(!cacheKey.contains(captureID))
        #expect(!cacheKey.contains(assetID))
        #expect(!cacheKey.contains("private-local-id"))
    }

    @Test func depthAlbumPendingThumbnailCacheKeyDoesNotExposeCaptureIdentifier() throws {
        let captureID = "capture/private-pending"
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: captureID,
            capturedAt: Date(timeIntervalSince1970: 100),
            thumbnailFilename: TAPPendingCaptureBundlePathPolicy.thumbnailFilename
        )

        let item = try #require(TAPLibraryItem.merged(
            pendingRecords: [pendingRecord],
            exportedRecords: [],
            photoAssets: [],
            exportedAssetResolver: { _ in nil }
        ).first)
        let cacheKey = item.thumbnailCacheKey(pixelLength: 240)

        #expect(cacheKey.count == 64)
        #expect(cacheKey.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        })
        #expect(!cacheKey.contains(captureID))
        #expect(!cacheKey.contains("private-pending"))
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

private enum DepthAlbumItemProviderTestError: LocalizedError {
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
