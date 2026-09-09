//
//  TAPLibraryViewerPagingTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
import SwiftUI
import UIKit
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

    @Test @MainActor func nativePagerLaysOutPagesWhenItsViewportChanges() {
        let entries = ["photo", "video"].map { id in
            TAPLibraryViewerPagingEntry(
                id: id,
                destination: .analysis(.init(itemID: id, source: .photosAsset(id)))
            )
        }
        let pager = TAPLibraryNativePagingView(
            entries: entries,
            currentItemID: "video",
            pageBuilder: { _, _, size in
                AnyView(Color.black.frame(width: size.width, height: size.height))
            },
            onCurrentEntryChanged: { _ in }
        )
        let coordinator = pager.makeCoordinator()
        let scrollView = coordinator.makeScrollView()
        coordinator.update(parent: pager, scrollView: scrollView)

        // SwiftUI can supply the viewport after updateUIView, including when
        // a photo route is replaced by a video route in the same destination.
        for size in [CGSize(width: 400, height: 800), CGSize(width: 800, height: 400)] {
            scrollView.frame = CGRect(origin: .zero, size: size)
            scrollView.layoutIfNeeded()
            #expect(scrollView.contentSize == CGSize(width: size.width * 2, height: size.height))
            #expect(scrollView.contentOffset == CGPoint(x: size.width, y: 0))
            #expect(scrollView.subviews[1].frame == CGRect(
                x: size.width + 9, y: 0, width: size.width - 18, height: size.height
            ))
        }
        coordinator.cancelInteractionForTeardown()
    }

    @Test @MainActor func nativePagerCommitsOnlyOnceAfterDeceleration() {
        let entries = ["first", "current", "next"].map { id in
            TAPLibraryViewerPagingEntry(
                id: id,
                destination: .analysis(.init(itemID: id, source: .photosAsset(id)))
            )
        }
        var commits: [String] = []
        var interaction: [Bool] = []
        let pager = TAPLibraryNativePagingView(
            entries: entries,
            currentItemID: "current",
            pageBuilder: { _, _, _ in AnyView(Color.black) },
            onCurrentEntryChanged: { commits.append($0.id) },
            onPagingInteractionChanged: { interaction.append($0) }
        )
        let coordinator = pager.makeCoordinator()
        let scrollView = coordinator.makeScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        coordinator.update(parent: pager, scrollView: scrollView)
        coordinator.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset.x = 800
        coordinator.scrollViewDidEndDragging(scrollView, willDecelerate: true)
        #expect(commits.isEmpty)
        coordinator.scrollViewDidEndDecelerating(scrollView)
        coordinator.scrollViewDidEndDecelerating(scrollView)
        #expect(commits == ["next"])
        #expect(interaction == [true, false])
        coordinator.cancelInteractionForTeardown()
        coordinator.scrollViewDidEndDecelerating(scrollView)
        #expect(commits == ["next"])
    }

    @Test @MainActor func nativePagerRejectsATargetRemovedDuringTheDrag() {
        let entries = ["first", "current", "removed"].map { id in
            TAPLibraryViewerPagingEntry(
                id: id,
                destination: .analysis(.init(itemID: id, source: .photosAsset(id)))
            )
        }
        var commits: [String] = []
        func pager(_ entries: [TAPLibraryViewerPagingEntry]) -> TAPLibraryNativePagingView {
            TAPLibraryNativePagingView(
                entries: entries,
                currentItemID: "current",
                pageBuilder: { _, _, _ in AnyView(Color.black) },
                onCurrentEntryChanged: { commits.append($0.id) }
            )
        }
        let initial = pager(entries)
        let coordinator = initial.makeCoordinator()
        let scrollView = coordinator.makeScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        coordinator.update(parent: initial, scrollView: scrollView)
        coordinator.scrollViewWillBeginDragging(scrollView)
        coordinator.update(parent: pager(Array(entries.prefix(2))), scrollView: scrollView)
        scrollView.contentOffset.x = 800
        coordinator.scrollViewDidEndDragging(scrollView, willDecelerate: false)
        #expect(commits.isEmpty)
        coordinator.cancelInteractionForTeardown()
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
