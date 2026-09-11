//
//  TAPLibraryRouteAdapterTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPLibraryRouteAdapterTests {
    @Test func preservesPhotoAndVideoItemIdentity() throws {
        let items = TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [],
            photoAssets: [
                LibraryPhotoAsset(localIdentifier: "photo-route"),
                LibraryPhotoAsset(localIdentifier: "video-route", isVideo: true)
            ]
        )
        let photoItem = try #require(items.first { !$0.isVideo })
        let videoItem = try #require(items.first { $0.isVideo })

        switch TAPLibraryRouteAdapter.destination(for: photoItem) {
        case .analysis(let route):
            #expect(route.itemID == photoItem.id)
            #expect(route.source == .photosAsset("photo-route"))
        case .video:
            Issue.record("Photo item was adapted to video playback")
        }

        switch TAPLibraryRouteAdapter.destination(for: videoItem) {
        case .analysis:
            Issue.record("Video item was adapted to photo analysis")
        case .video(let route):
            #expect(route.itemID == videoItem.id)
            #expect(route.source == .photosAsset("video-route"))
        }
    }

    @Test func mixedMediaCatalogPreservesCanonicalPhotoLiveAndVideoOrder() {
        let items = Self.mixedMediaItems()

        #expect(items.map(\.id) == [
            "photos:still-a",
            "photos:live-b",
            "capture:video-c",
            "photos:video-d",
            "photos:still-e"
        ])
        #expect(items.map(\.summary.kind) == [
            .photo,
            .livePhoto,
            .tapVideo,
            .tapVideo,
            .photo
        ])
        #expect(items.map(\.capturedAt.timeIntervalSince1970) == [500, 400, 300, 200, 100])
    }

    @Test func mixedContextUsesImmediateNeighborsAndCanonicalDeletionFallback() throws {
        let items = Self.mixedMediaItems()
        let liveID = "photos:live-b"
        let pendingVideoID = "capture:video-c"
        let photosVideoID = "photos:video-d"
        let lastPhotoID = "photos:still-e"
        let context = LibraryDeletionContext(currentItemID: liveID, items: items)

        #expect(context.entries.map(\.id) == items.map(\.id))

        let previous = try #require(context.adjacentEntry(offset: -1))
        #expect(previous.id == "photos:still-a")
        guard case .analysis(let previousRoute) = previous.destination else {
            Issue.record("The photo before a Live Photo must keep the analysis route")
            return
        }
        #expect(previousRoute.source == .photosAsset("still-a"))

        let next = try #require(context.adjacentEntry(offset: 1))
        #expect(next.id == pendingVideoID)
        guard case .video(let nextRoute) = next.destination else {
            Issue.record("The video immediately after a Live Photo must keep the video route")
            return
        }
        #expect(nextRoute.source == .pendingCapture("video-c"))

        #expect(context.adjacentEntry(offset: -1, excluding: ["photos:still-a"]) == nil)
        #expect(context.adjacentEntry(offset: 2) == nil)

        let deletingVideo = LibraryDeletionContext(
            currentItemID: pendingVideoID,
            items: items
        )
        let nextAfterDelete = try #require(deletingVideo.entryAfterDeletingCurrent(
            excluding: [pendingVideoID]
        ))
        #expect(nextAfterDelete.id == photosVideoID)

        let previousAfterDeletingTail = try #require(deletingVideo.entryAfterDeletingCurrent(
            excluding: [pendingVideoID, photosVideoID, lastPhotoID]
        ))
        #expect(previousAfterDeletingTail.id == liveID)
        #expect(deletingVideo.entryAfterDeletingCurrent(
            excluding: Set(items.map(\.id))
        ) == nil)

        let unknownCursor = LibraryDeletionContext(
            currentItemID: "missing-current",
            items: items
        )
        #expect(unknownCursor.entryAfterDeletingCurrent(
            excluding: ["missing-current"]
        ) == nil)

        let deletingPhotosVideo = LibraryDeletionContext(
            currentItemID: photosVideoID,
            items: items
        )
        #expect(deletingPhotosVideo.entryAfterDeletingCurrent(
            excluding: ["photos:still-a", liveID, photosVideoID]
        )?.id == lastPhotoID)
    }

    @Test @MainActor func mixedViewerCrossesEveryMediaTypeBoundaryWithoutSkipping() {
        let items = Self.mixedMediaItems()
        let context = LibraryDeletionContext(currentItemID: items[0].id, items: items)
        let entries = context.entries.map(TAPLibraryViewerPagingEntry.init)
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in throw CancellationError() },
            inputLoader: { _, _ in throw CancellationError() })
        let store = TAPLibraryViewerStore(entries: entries, currentItemID: context.currentItemID, loader: loader)
        for (index, entry) in entries.enumerated() {
            store.select(entry, pixelLength: 80, prewarmCurrentPlaneGeometry: false)
            #expect(store.currentItemID == items[index].id)
            #expect(store.currentPagingEntry?.destination == TAPLibraryRouteAdapter.destination(for: items[index]))
            let expectedIDs = items[max(0, index - 1)...min(items.count - 1, index + 1)].map(\.id)
            #expect(store.windowPagingEntries.map(\.id) == expectedIDs)
        }
        store.cancelViewerRequests()
    }

    @Test @MainActor func legacyExportedLivePhotoRetainsPairRequirementInShareSubject() throws {
        let capturedAt = Date(timeIntervalSince1970: 600)
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-live",
            capturedAt: capturedAt,
            status: .exported,
            signedPhotoFilename: nil,
            pairedVideoFilename: nil,
            assetLocalIdentifier: "legacy-live-asset"
        )
        let items = TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [record],
            photoAssets: [
                LibraryPhotoAsset(
                    localIdentifier: "legacy-live-asset",
                    creationDate: capturedAt,
                    isLivePhoto: true
                )
            ]
        )
        let item = try #require(items.first)
        let context = LibraryDeletionContext(currentItemID: item.id, items: items)
        let store = TAPLibraryViewerStore(entries: context.entries.map(TAPLibraryViewerPagingEntry.init),
            currentItemID: item.id)
        let entry = try #require(store.currentEntry)

        #expect(entry.expectsPairedVideo)
        let subject = DepthAnalysisShareSubject(entry: entry)
        #expect(subject.expectsPairedVideo)

        let request = TAPNAPShareResourceRequest(
            record: record,
            expectsPairedVideo: subject.expectsPairedVideo
        )
        #expect(request.expectsPairedVideo)
        #expect(request.prefersPhotoLibraryResources)
    }

    private static func mixedMediaItems() -> [TAPLibraryItem] {
        let pendingVideo = TAPCamDemoTestFixtures.samplePendingVideoRecord(
            captureID: "video-c",
            capturedAt: Date(timeIntervalSince1970: 300)
        )
        return TAPLibraryItem.merged(
            pendingRecords: [pendingVideo],
            exportedRecords: [],
            photoAssets: [
                LibraryPhotoAsset(
                    localIdentifier: "still-e",
                    creationDate: Date(timeIntervalSince1970: 100)
                ),
                LibraryPhotoAsset(
                    localIdentifier: "video-d",
                    creationDate: Date(timeIntervalSince1970: 200),
                    isVideo: true
                ),
                LibraryPhotoAsset(
                    localIdentifier: "live-b",
                    creationDate: Date(timeIntervalSince1970: 400),
                    isLivePhoto: true
                ),
                LibraryPhotoAsset(
                    localIdentifier: "still-a",
                    creationDate: Date(timeIntervalSince1970: 500)
                )
            ]
        )
    }
}
