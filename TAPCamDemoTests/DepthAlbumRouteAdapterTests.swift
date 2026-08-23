//
//  DepthAlbumRouteAdapterTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct DepthAlbumRouteAdapterTests {
    @Test func preservesPhotoAndVideoItemIdentity() throws {
        let items = TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [],
            photoAssets: [
                DepthAlbumPhotoAsset(localIdentifier: "photo-route"),
                DepthAlbumPhotoAsset(localIdentifier: "video-route", isVideo: true)
            ]
        )
        let photoItem = try #require(items.first { !$0.isVideo })
        let videoItem = try #require(items.first { $0.isVideo })

        switch DepthAlbumRouteAdapter.destination(for: photoItem) {
        case .analysis(let route):
            #expect(route.itemID == photoItem.id)
            #expect(route.source == .photosAsset("photo-route"))
        case .video:
            Issue.record("Photo item was adapted to video playback")
        }

        switch DepthAlbumRouteAdapter.destination(for: videoItem) {
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
        let context = DepthAlbumDeletionContext(currentItemID: liveID, items: items)

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

        let deletingVideo = DepthAlbumDeletionContext(
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

        let unknownCursor = DepthAlbumDeletionContext(
            currentItemID: "missing-current",
            items: items
        )
        #expect(unknownCursor.entryAfterDeletingCurrent(
            excluding: ["missing-current"]
        ) == nil)

        let deletingPhotosVideo = DepthAlbumDeletionContext(
            currentItemID: photosVideoID,
            items: items
        )
        #expect(deletingPhotosVideo.entryAfterDeletingCurrent(
            excluding: ["photos:still-a", liveID, photosVideoID]
        )?.id == lastPhotoID)
    }

    @Test func specializedContextsStopAtMediaTypeBoundariesWithoutSkipping() {
        let items = Self.mixedMediaItems()

        let photoContext = DepthAnalysisAlbumContext(
            currentItemID: "photos:live-b",
            items: items
        )
        #expect(photoContext.entries.map(\.id) == ["photos:still-a", "photos:live-b"])
        #expect(photoContext.adjacentEntry(offset: -1)?.id == "photos:still-a")
        #expect(photoContext.adjacentEntry(offset: 1) == nil)

        let firstVideoContext = TAPVideoAlbumContext(
            currentItemID: "capture:video-c",
            items: items
        )
        #expect(firstVideoContext.entries.map(\.id) == ["capture:video-c", "photos:video-d"])
        #expect(firstVideoContext.adjacentEntry(offset: -1, excluding: []) == nil)
        #expect(firstVideoContext.adjacentEntry(offset: 1, excluding: [])?.id == "photos:video-d")

        let secondVideoContext = TAPVideoAlbumContext(
            currentItemID: "photos:video-d",
            items: items
        )
        #expect(secondVideoContext.adjacentEntry(offset: -1, excluding: [])?.id == "capture:video-c")
        #expect(secondVideoContext.adjacentEntry(offset: 1, excluding: []) == nil)

        let trailingPhotoContext = DepthAnalysisAlbumContext(
            currentItemID: "photos:still-e",
            items: items
        )
        #expect(trailingPhotoContext.entries.map(\.id) == ["photos:still-e"])
        #expect(trailingPhotoContext.adjacentEntry(offset: -1) == nil)
    }

    @Test func legacyExportedLivePhotoRetainsPairRequirementInShareSubject() throws {
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
                DepthAlbumPhotoAsset(
                    localIdentifier: "legacy-live-asset",
                    creationDate: capturedAt,
                    isLivePhoto: true
                )
            ]
        )
        let item = try #require(items.first)
        let context = DepthAnalysisAlbumContext(currentItemID: item.id, items: items)
        let entry = try #require(context.entries.first)

        #expect(entry.expectsPairedVideo)
        let subject = DepthAnalysisShareSubject(
            entry: DepthAnalysisCarouselEntry(albumEntry: entry)
        )
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
                DepthAlbumPhotoAsset(
                    localIdentifier: "still-e",
                    creationDate: Date(timeIntervalSince1970: 100)
                ),
                DepthAlbumPhotoAsset(
                    localIdentifier: "video-d",
                    creationDate: Date(timeIntervalSince1970: 200),
                    isVideo: true
                ),
                DepthAlbumPhotoAsset(
                    localIdentifier: "live-b",
                    creationDate: Date(timeIntervalSince1970: 400),
                    isLivePhoto: true
                ),
                DepthAlbumPhotoAsset(
                    localIdentifier: "still-a",
                    creationDate: Date(timeIntervalSince1970: 500)
                )
            ]
        )
    }
}
