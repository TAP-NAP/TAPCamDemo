import PhotosUI
import Testing
import UIKit
@testable import TAPCamDemo

@Suite(.serialized)
@MainActor
struct TAPAnalysisRawZoomViewTests {
    @Test func landscapeZoomUsesMediaBoundsAndCentersTheShortAxis() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.dismantle() }
        fixture.show(image(width: 400, height: 300))
        let media = try #require(fixture.coordinator.viewForZooming(in: fixture.scrollView))

        #expect(abs(media.bounds.width - 372) < 0.01)
        #expect(abs(media.bounds.height - 279) < 0.01)
        #expect(!fixture.scrollView.panGestureRecognizer.isEnabled)

        fixture.scrollView.setZoomScale(2.5, animated: false)
        fixture.scrollView.layoutIfNeeded()

        #expect(abs(fixture.scrollView.contentSize.width - 930) < 1)
        #expect(abs(fixture.scrollView.contentSize.height - 697.5) < 1)
        #expect(abs(fixture.scrollView.contentInset.top - 73.25) < 1)
        #expect(fixture.scrollView.panGestureRecognizer.isEnabled)

        fixture.scrollView.setZoomScale(1, animated: false)
        #expect(!fixture.scrollView.panGestureRecognizer.isEnabled)
    }

    @Test func progressiveImageReplacementKeepsTheCurrentZoomAndOffset() {
        let fixture = Fixture()
        defer { fixture.coordinator.dismantle() }
        fixture.show(image(width: 80, height: 60))
        fixture.scrollView.setZoomScale(3, animated: false)
        fixture.scrollView.contentOffset = CGPoint(x: 175, y: -3.5)
        let offset = fixture.scrollView.contentOffset

        fixture.show(image(width: 800, height: 600))
        fixture.scrollView.layoutIfNeeded()

        #expect(abs(fixture.scrollView.zoomScale - 3) < 0.01)
        #expect(abs(fixture.scrollView.contentOffset.x - offset.x) < 0.01)
        #expect(abs(fixture.scrollView.contentOffset.y - offset.y) < 0.01)
    }

    @Test func changingTheSourceResetsZoomAndHonorsImageOrientation() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.dismantle() }
        let original = image(width: 400, height: 300)
        fixture.show(original)
        fixture.scrollView.setZoomScale(3, animated: false)
        let rotated = UIImage(
            cgImage: try #require(original.cgImage),
            scale: 1,
            orientation: .right
        )
        let replacement = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("replacement"))
        )

        fixture.show(rotated, slot: replacement)
        let media = try #require(fixture.coordinator.viewForZooming(in: fixture.scrollView))

        #expect(abs(fixture.scrollView.zoomScale - 1) < 0.01)
        #expect(abs(media.bounds.width - 372) < 0.01)
        #expect(abs(media.bounds.height - 496) < 0.01)
        #expect(abs(fixture.scrollView.contentOffset.y + 174) < 0.01)
    }

    @Test func nativeLivePhotoGestureBelongsToTheScrollViewAndStopsWhenRAWIsHiddenOrThePageLeaves() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.dismantle() }
        let photo = image(width: 400, height: 300)
        fixture.show(photo)
        let media = try #require(fixture.coordinator.viewForZooming(in: fixture.scrollView))
        let liveView = try #require(media.subviews.compactMap { $0 as? PHLivePhotoView }.first)
        let gesture = liveView.playbackGestureRecognizer

        #expect(gesture.view === fixture.scrollView)
        #expect(fixture.scrollView.gestureRecognizers?.contains(where: { $0 === gesture }) == true)
        #expect(liveView.delegate === fixture.coordinator)
        #expect(gesture.isEnabled)

        fixture.show(photo, isPaging: true)
        #expect(!gesture.isEnabled)
        #expect(!fixture.coordinator.livePhotoView(liveView, canBeginPlaybackWith: .full))

        fixture.show(photo)
        #expect(gesture.isEnabled)
        #expect(fixture.coordinator.livePhotoView(liveView, canBeginPlaybackWith: .full))

        fixture.show(photo, isInteractionEnabled: false)
        #expect(!fixture.scrollView.isUserInteractionEnabled)
        #expect(!gesture.isEnabled)
        #expect(!fixture.coordinator.livePhotoView(liveView, canBeginPlaybackWith: .full))

        fixture.show(photo)
        #expect(fixture.scrollView.isUserInteractionEnabled)
        #expect(gesture.isEnabled)

        fixture.show(photo, isCurrent: false)
        #expect(!gesture.isEnabled)
        #expect(!fixture.coordinator.livePhotoView(liveView, canBeginPlaybackWith: .full))
    }

    @Test func hiddenRAWWaitsForItsFirstVisitAndModeChangesKeepTheLivePhotoRequest() async throws {
        let probe = RawLivePhotoFetchProbe()
        let fixture = Fixture(mediaFetcher: WaitingRawLivePhotoFetcher(probe: probe))
        defer { fixture.coordinator.dismantle() }
        let photo = image(width: 400, height: 300)

        fixture.show(photo, isInteractionEnabled: false)
        try await Task.sleep(for: .milliseconds(40))
        #expect(probe.requestedAssetIDs.isEmpty)

        // Hide before the deferred request starts, then revisit RAW repeatedly
        // while Photos is still preparing the same resource.
        fixture.show(photo)
        fixture.show(photo, isInteractionEnabled: false)
        try await waitUntil { probe.requestedAssetIDs.count == 1 }
        for allowsInteraction in [true, false, true, false, true] {
            fixture.show(photo, isInteractionEnabled: allowsInteraction)
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(40))
        #expect(probe.requestedAssetIDs == ["zoom-fixture"])
        #expect(probe.cancelledAssetIDs.isEmpty)

        fixture.show(photo, isCurrent: false)
        try await waitUntil { probe.cancelledAssetIDs == ["zoom-fixture"] }
        fixture.show(photo, isInteractionEnabled: false)
        try await Task.sleep(for: .milliseconds(40))
        #expect(probe.requestedAssetIDs == ["zoom-fixture"])
    }

    @Test(arguments: [false, true])
    func replacingTheSlotReleasesHiddenLivePhotoAndWaitsForRAW(sameSource: Bool) async throws {
        let probe = RawLivePhotoFetchProbe()
        let fixture = Fixture(mediaFetcher: WaitingRawLivePhotoFetcher(probe: probe))
        defer { fixture.coordinator.dismantle() }
        let photo = image(width: 400, height: 300)
        fixture.show(photo)
        try await waitUntil { probe.requestedAssetIDs.count == 1 }
        fixture.show(photo, isInteractionEnabled: false)

        let replacementID = sameSource ? "zoom-fixture" : "replacement"
        let replacement = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset(replacementID))
        )
        fixture.show(photo, slot: replacement, isInteractionEnabled: false)
        try await waitUntil { probe.cancelledAssetIDs == ["zoom-fixture"] }
        #expect(probe.requestedAssetIDs == ["zoom-fixture"])

        fixture.show(photo, slot: replacement)
        try await waitUntil { probe.requestedAssetIDs.count == 2 }
        #expect(probe.requestedAssetIDs == ["zoom-fixture", replacementID])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Live Photo request did not reach the expected lifecycle state")
    }

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }

    @MainActor
    private struct Fixture {
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("zoom-fixture"))
        )
        let coordinator: AnalysisRawZoomScrollView.Coordinator
        let scrollView: UIScrollView

        init(mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()) {
            coordinator = AnalysisRawZoomScrollView.Coordinator(
                slot: slot,
                mediaFetcher: mediaFetcher
            )
            scrollView = coordinator.makeScrollView()
            scrollView.frame = CGRect(x: 0, y: 0, width: 372, height: 844)
        }

        // Synchronous layout tests dismantle before the deferred PhotoKit request;
        // asynchronous lifecycle tests inject their own resource fetcher.
        func show(
            _ image: UIImage,
            slot replacement: AnalysisPhotoSlot? = nil,
            isCurrent: Bool = true,
            isPaging: Bool = false,
            isInteractionEnabled: Bool = true
        ) {
            let currentSlot = replacement ?? slot
            coordinator.update(
                scrollView: scrollView,
                slot: currentSlot,
                source: currentSlot.source,
                image: image,
                isCurrent: isCurrent,
                isPagingInteracting: isPaging,
                isInteractionEnabled: isInteractionEnabled
            )
        }
    }
}

@MainActor
private final class RawLivePhotoFetchProbe {
    var requestedAssetIDs: [String] = []
    var cancelledAssetIDs: [String] = []
}

nonisolated private struct WaitingRawLivePhotoFetcher: LibraryMediaFetching {
    let probe: RawLivePhotoFetchProbe

    func mediaKind(for request: LibraryMediaAssetRequest) async throws -> LibraryMediaKind { .livePhoto }
    func posterPhase(for request: LibraryMediaPosterRequest, allowsNetworkAccess: Bool,
                     progress: @escaping @Sendable (Double?) -> Void) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> { .idle(nil) }
    func previewPhase(for request: LibraryMediaAssetRequest, pixelLength: Int, allowsNetworkAccess: Bool,
                      progress: @escaping @Sendable (Double?) -> Void) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> { .idle(nil) }
    func photoDisplayImage(for request: LibraryMediaAssetRequest, pixelLength: Int,
                           progress: @escaping @Sendable (Double?) -> Void) async throws -> UIImage { throw MediaFetchFailure.decode }
    func videoOriginalFile(for request: LibraryMediaAssetRequest,
                          progress: @escaping @Sendable (Double?) -> Void) async throws -> LibraryManagedTemporaryFile { throw MediaFetchFailure.decode }

    func livePhoto(for request: LibraryMediaAssetRequest, targetSize: CGSize,
                   progress: @escaping @Sendable (Double?) -> Void) async throws -> LibraryLivePhoto {
        await MainActor.run { probe.requestedAssetIDs.append(request.assetLocalIdentifier) }
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            await MainActor.run { probe.cancelledAssetIDs.append(request.assetLocalIdentifier) }
            throw error
        }
        throw MediaFetchFailure.download
    }
}
