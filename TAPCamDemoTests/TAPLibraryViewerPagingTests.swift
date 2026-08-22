//
//  TAPLibraryViewerPagingTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPLibraryViewerPagingTests {
    @Test func settlementStaysOnTheCurrentPageWhenOffsetHasNotCrossedHalfway() {
        let pageWidth: CGFloat = 400

        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 1,
            pageCount: 3,
            contentOffsetX: pageWidth,
            pageWidth: pageWidth
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 1,
            pageCount: 3,
            contentOffsetX: pageWidth * 1.49,
            pageWidth: pageWidth
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 1,
            pageCount: 3,
            contentOffsetX: pageWidth * 0.51,
            pageWidth: pageWidth
        ) == .stay)
    }

    @Test func settlementMovesExactlyOnePageAfterCrossingHalfway() {
        let pageWidth: CGFloat = 400

        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 1,
            pageCount: 4,
            contentOffsetX: pageWidth * 1.51,
            pageWidth: pageWidth
        ) == .move(1))
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 1,
            pageCount: 4,
            contentOffsetX: pageWidth * 0.49,
            pageWidth: pageWidth
        ) == .move(-1))

        // Even a malformed or interrupted scroll offset must not make the
        // canonical library cursor skip over an intermediate item.
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 1,
            pageCount: 4,
            contentOffsetX: pageWidth * 3,
            pageWidth: pageWidth
        ) == .move(1))
    }

    @Test func settlementKeepsFirstLastAndOnlyPagesInsideTheirBounds() {
        let pageWidth: CGFloat = 400

        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 0,
            pageCount: 3,
            contentOffsetX: -140,
            pageWidth: pageWidth
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 2,
            pageCount: 3,
            contentOffsetX: (pageWidth * 2) + 140,
            pageWidth: pageWidth
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 0,
            pageCount: 1,
            contentOffsetX: 160,
            pageWidth: pageWidth
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 0,
            pageCount: 1,
            contentOffsetX: -160,
            pageWidth: pageWidth
        ) == .stay)
    }

    @Test func settlementRejectsInvalidGeometryAndCursorState() {
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 0,
            pageCount: 0,
            contentOffsetX: 0,
            pageWidth: 400
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: -1,
            pageCount: 3,
            contentOffsetX: 0,
            pageWidth: 400
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 3,
            pageCount: 3,
            contentOffsetX: 0,
            pageWidth: 400
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 0,
            pageCount: 1,
            contentOffsetX: 0,
            pageWidth: 0
        ) == .stay)
        #expect(TAPLibraryViewerPagingPolicy.settlement(
            currentIndex: 0,
            pageCount: 1,
            contentOffsetX: .nan,
            pageWidth: 400
        ) == .stay)
    }

    @Test func pageGeometryConvertsViewportTouchesIntoTheInsetHost() {
        let viewportSize = CGSize(width: 390, height: 844)
        let pageSize = TAPLibraryViewerPagingPolicy.pageContentSize(
            viewportSize: viewportSize,
            pageSpacing: 18
        )

        #expect(pageSize == CGSize(width: 372, height: 844))
        #expect(TAPLibraryViewerPagingPolicy.pageLocation(
            viewportLocation: CGPoint(x: 9, y: 200),
            viewportSize: viewportSize,
            pageSpacing: 18
        ) == CGPoint(x: 0, y: 200))
        #expect(TAPLibraryViewerPagingPolicy.pageLocation(
            viewportLocation: CGPoint(x: 381, y: 200),
            viewportSize: viewportSize,
            pageSpacing: 18
        ) == CGPoint(x: 372, y: 200))
    }

    @Test @MainActor
    func videoPlaybackIntentSurvivesAPausedSeekWhilePagingBouncesBack() {
        let intent = TAPVideoPlaybackIntentState()
        intent.setUserIntent(true)

        #expect(intent.beginPagingSuspension(currentStatus: .paused))
        intent.updateFromPlayerStatus(.paused)
        #expect(intent.intendsPlayback)

        intent.endPagingSuspension()
        intent.updateFromPlayerStatus(.paused)
        #expect(!intent.intendsPlayback)
    }

    @Test func pagingEntriesKeepCanonicalMixedMediaNeighbors() throws {
        let items = Self.mixedMediaItems()
        let context = DepthAlbumDeletionContext(
            currentItemID: "capture:video-c",
            items: items
        )

        let window = context.pagingEntries(
            from: "capture:video-c",
            excluding: []
        )

        #expect(window.map(\.id) == [
            "photos:live-b",
            "capture:video-c",
            "photos:video-d"
        ])
        try #require(window.count == 3)

        guard case .analysis(let previousRoute) = window[0].destination else {
            Issue.record("The previous Live Photo must retain its analysis route")
            return
        }
        #expect(previousRoute.source == .photosAsset("live-b"))
        #expect(window[0].expectsPairedVideo)

        guard case .video(let currentRoute) = window[1].destination else {
            Issue.record("The current pending video must retain its video route")
            return
        }
        #expect(currentRoute.source == .pendingCapture("video-c"))

        guard case .video(let nextRoute) = window[2].destination else {
            Issue.record("The next Photos video must retain its video route")
            return
        }
        #expect(nextRoute.source == .photosAsset("video-d"))
    }

    @Test func pagingEntriesReturnTwoPagesAtTheCanonicalEnds() {
        let items = Self.mixedMediaItems()
        let context = DepthAlbumDeletionContext(
            currentItemID: "photos:still-a",
            items: items
        )

        #expect(context.pagingEntries(
            from: "photos:still-a",
            excluding: []
        ).map(\.id) == [
            "photos:still-a",
            "photos:live-b"
        ])
        #expect(context.pagingEntries(
            from: "photos:still-e",
            excluding: []
        ).map(\.id) == [
            "photos:video-d",
            "photos:still-e"
        ])
    }

    @Test func pagingEntriesExcludeRemovedItemsWithoutReorderingTheRemainder() {
        let items = Self.mixedMediaItems()
        let context = DepthAlbumDeletionContext(
            currentItemID: "capture:video-c",
            items: items
        )

        let window = context.pagingEntries(
            from: "capture:video-c",
            excluding: ["photos:live-b", "photos:video-d"]
        )

        #expect(window.map(\.id) == [
            "photos:still-a",
            "capture:video-c",
            "photos:still-e"
        ])
        #expect(window.count == 3)
    }

    @Test func pagingEntriesRejectUnknownOrRemovedCurrentItem() {
        let items = Self.mixedMediaItems()
        let context = DepthAlbumDeletionContext(
            currentItemID: "capture:video-c",
            items: items
        )

        #expect(context.pagingEntries(
            from: "missing-item",
            excluding: []
        ).isEmpty)
        #expect(context.pagingEntries(
            from: "capture:video-c",
            excluding: ["capture:video-c"]
        ).isEmpty)
    }

    @Test func videoPosterRemainsUntilThePlayerLayerHasAFrame() {
        #expect(TAPVideoFirstFramePresentationPolicy.showsLoadingPreview(
            state: .idle,
            isPlayerFrameReady: false
        ))
        #expect(TAPVideoFirstFramePresentationPolicy.showsLoadingPreview(
            state: .loading,
            isPlayerFrameReady: false
        ))
        #expect(TAPVideoFirstFramePresentationPolicy.showsLoadingPreview(
            state: .ready,
            isPlayerFrameReady: false
        ))
        #expect(!TAPVideoFirstFramePresentationPolicy.showsLoadingPreview(
            state: .ready,
            isPlayerFrameReady: true
        ))
        #expect(TAPVideoFirstFramePresentationPolicy.showsLoadingPreview(
            state: .failed("fixture"),
            isPlayerFrameReady: false
        ))
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
