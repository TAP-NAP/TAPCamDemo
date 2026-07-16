//
//  DepthAlbumRouteAdapterTests.swift
//  TAPCamDemoTests
//

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
}
