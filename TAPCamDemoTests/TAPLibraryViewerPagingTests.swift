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

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func photoAndVideoUseTheSameNativeInteractivePager() throws {
        let pagerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPLibraryNativePagingView.swift"
        )
        let photoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let videoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackScreen.swift"
        )
        let sessionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackSession.swift"
        )

        #expect(pagerSource.contains("scrollView.isPagingEnabled = true"))
        #expect(pagerSource.contains("scrollView.bounces = true"))
        #expect(pagerSource.contains("scrollView.alwaysBounceHorizontal = true"))
        #expect(pagerSource.contains("DepthAnalysisViewerInteractionPolicy.nativePageSpacing"))
        #expect(pagerSource.contains("hosts = (0..<3).map"))
        #expect(pagerSource.contains("interactionEntries = parent?.entries"))
        #expect(pagerSource.contains("interactionContentRevision = parent?.pageContentRevision"))
        #expect(pagerSource.contains("let settledEntries = interactionEntries"))
        #expect(pagerSource.contains("parent.onCurrentEntryChanged(freshTarget)"))
        #expect(pagerSource.contains("committedTargetID == nil"))
        #expect(pagerSource.contains("finishInteractionIfNeeded(scrollView: scrollView)"))
        #expect(pagerSource.contains("hostConfigurations[index] != configuration"))
        #expect(pagerSource.contains("contentRevision: contentRevision"))
        #expect(pagerSource.contains("override func gestureRecognizerShouldBegin"))
        #expect(pagerSource.contains("shouldBeginPaging(visibleLocation, bounds.size)"))
        #expect(photoSource.contains("TAPLibraryNativePagingView("))
        #expect(photoSource.contains("localCarouselEntry(matching:"))
        #expect(photoSource.contains("== pagingEntry.expectsPairedVideo"))
        #expect(photoSource.contains("shouldBeginPaging: shouldBeginPaging"))
        #expect(photoSource.contains("return !toolContainerRect.contains(location)"))
        #expect(videoSource.contains("TAPLibraryNativePagingView("))
        #expect(!videoSource.contains("DragGesture("))
        #expect(!videoSource.contains("swipeGesture"))
        #expect(videoSource.contains("session.beginInteractivePaging()"))
        #expect(videoSource.contains("session.endInteractivePaging()"))
        #expect(sessionSource.contains("shouldResumeAfterInteractivePaging = false"))
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func adjacentVideoPagesStayPosterOnly() throws {
        let pagerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPLibraryNativePagingView.swift"
        )
        let videoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackScreen.swift"
        )

        #expect(pagerSource.contains("TAPVideoPlaybackResourceLoader.adjacentPreviewData"))
        #expect(pagerSource.contains("TAPLibraryPagingPreviewCache.shared"))
        #expect(pagerSource.contains("image = TAPLibraryPagingPreviewCache.shared.image"))
        #expect(!pagerSource.contains("TAPVideoPlaybackSession("))
        #expect(videoSource.contains("if isCurrent"))
        #expect(videoSource.contains("TAPLibraryAdjacentMediaPreview("))
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

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func videoFirstFrameHandoffDoesNotReplaceTheViewerRoot() throws {
        let videoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackScreen.swift"
        )
        let surfaceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlayerSurface.swift"
        )

        #expect(videoSource.contains("@State private var readyPlayerID: ObjectIdentifier?"))
        #expect(videoSource.contains("acceptPlayerFrameReadiness("))
        #expect(videoSource.contains("playerID: playerID"))
        #expect(videoSource.contains("guard isReady else"))
        #expect(videoSource.contains("guard playerID == playerIdentity"))
        #expect(videoSource.contains("return readyPlayerID == playerIdentity"))
        #expect(videoSource.contains(".opacity(showsLoadingPreview ? 1 : 0)"))
        #expect(videoSource.contains("state: isPlayerFrameReady ? .hidden : .preparing"))
        #expect(videoSource.contains("TAPVideoPlaybackSessionChrome("))
        #expect(!videoSource.contains("case .ready:\n            playbackSurface"))
        #expect(surfaceSource.contains("\\.isReadyForDisplay"))
        #expect(surfaceSource.contains("let isReadyForDisplay = playerLayer.isReadyForDisplay"))
        #expect(surfaceSource.contains("let playerID = playerLayer.player.map(ObjectIdentifier.init)"))
        #expect(surfaceSource.contains("== playerID else"))
        #expect(surfaceSource.contains("onReadyForDisplay(playerID, isReadyForDisplay)"))
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func sameVideoSourceMigrationKeepsTheViewerIdentityStable() throws {
        let pickerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )
        let playbackSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPVideoDepthPlaybackView.swift"
        )
        let resourceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackResourceLoader.swift"
        )

        #expect(!pickerSource.contains(".id(route"))
        #expect(playbackSource.contains(".onChange(of: source)"))
        #expect(playbackSource.contains("replacePlaybackSessionIfNeeded("))
        #expect(playbackSource.contains("guard sessionSource != updatedSource"))
        #expect(playbackSource.contains("session.stopPlayback()"))
        #expect(playbackSource.contains("session = replacement"))
        #expect(playbackSource.contains("sessionSource = updatedSource"))
        #expect(playbackSource.contains("session: ObjectIdentifier(session)"))
        #expect(playbackSource.contains("let targetPreview = TAPLibraryPagingPreviewCache.shared.image"))
        #expect(playbackSource.contains("isSameMedia ? session.loadingPreviewImage : nil"))
        #expect(playbackSource.contains("sessionGeneration &+= 1"))
        #expect(playbackSource.contains("preparePlaybackForPagingTarget(target)"))
        #expect(playbackSource.contains("guard !Task.isCancelled"))
        let ownedBranch = try #require(resourceSource.range(
            of: "case .ownedCapture(let captureID, let assetID):"
        ))
        let photosBranch = try #require(resourceSource.range(
            of: "case .photosAsset(let assetID):"
        ))
        let ownedBody = resourceSource[ownedBranch.lowerBound..<photosBranch.lowerBound]
        #expect(ownedBody.contains("return try await photoResource("))
        #expect(!ownedBody.contains("bestAvailableVideoURL"))
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func viewerIdentityTracksMixedHandoffsAndPendingToOwnedSourceChanges() throws {
        let pickerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )

        #expect(pickerSource.contains(".id(analysisViewerGeneration)"))
        #expect(!pickerSource.contains(".id(route"))
        #expect(pickerSource.contains(
            "reconcilePresentedDestination(previousRevisions: previousRevisions)"
        ))
        #expect(pickerSource.contains("updatedRevision != presentedItemRevision"))
        #expect(pickerSource.contains("isLivePhoto = item.isLivePhoto"))
        #expect(pickerSource.contains("moveAfterExternalRemoval("))
        #expect(pickerSource.contains("isViewerPresented = false"))
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func livePhotoUsesTheSharedPhotoPagerAndRetainsItsNativePlaybackPair() throws {
        let photoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let contextSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisAlbumContext.swift"
        )
        let shareSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisSharePresentation.swift"
        )
        let videoChromeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoViewerChrome.swift"
        )

        #expect(photoSource.contains("TAPLibraryNativePagingView("))
        #expect(photoSource.contains("PHLivePhotoView()"))
        #expect(photoSource.contains("startPlayback(with: .full)"))
        #expect(photoSource.contains("guard isCurrent,"))
        #expect(photoSource.contains("onPagingInteractionChanged: { isInteracting in"))
        #expect(photoSource.contains("if isPagingInteracting"))
        #expect(photoSource.contains("UIApplication.willEnterForegroundNotification"))
        #expect(photoSource.contains("carouselStore.currentSlot?.retryLastMediaFetch()"))
        #expect(contextSource.contains("expectsPairedVideo: item.isLivePhoto"))
        #expect(shareSource.contains(
            "expectsPairedVideo = entry.albumEntry?.expectsPairedVideo ?? false"
        ))
        #expect(videoChromeSource.contains("accessibilityValue = \"Coming soon\""))
        #expect(videoChromeSource.contains("TAPVideoPlaybackTransportAccessory"))
    }

    @Test(.enabled(
        if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable,
        "Source tree is unavailable on this runtime."
    ))
    func nestedMediaGesturesKeepExplicitOwnershipAgainstThePager() throws {
        let photoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift"
        )
        let pointCloudSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AnalysisTools/DepthPointCloudPreview.swift"
        )
        let videoSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackScreen.swift"
        )

        // RAW owns horizontal pan only after zooming beyond fit size.
        #expect(photoSource.contains(
            "scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale >"
        ))
        // Live Photo press remains compatible with the containing scroll view.
        #expect(photoSource.contains("gesture.cancelsTouchesInView = false"))
        #expect(photoSource.contains(
            "gestureRecognizer is UILongPressGestureRecognizer"
        ))
        // SceneKit projection gestures explicitly defeat ancestor pagers.
        #expect(pointCloudSource.contains(
            "requireAncestorScrollViewsToFailProjectionGestures()"
        ))
        #expect(pointCloudSource.contains(
            "scrollView.panGestureRecognizer.require(toFail: gesture)"
        ))
        // Video transport/chrome is a fixed sibling above the paged content.
        #expect(videoSource.contains("TAPVideoViewerChrome("))
        #expect(videoSource.contains(".zIndex(5)"))
        let pagerIndex = try #require(videoSource.range(
            of: "TAPLibraryNativePagingView("
        )?.lowerBound)
        let chromeIndex = try #require(videoSource.range(
            of: "TAPVideoViewerChrome("
        )?.lowerBound)
        #expect(pagerIndex < chromeIndex)
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
