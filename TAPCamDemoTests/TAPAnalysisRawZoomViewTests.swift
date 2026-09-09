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

    @Test func nativeLivePhotoGestureBelongsToTheScrollViewAndStopsAtPageBoundaries() throws {
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

        fixture.show(photo, isCurrent: false)
        #expect(!gesture.isEnabled)
        #expect(!fixture.coordinator.livePhotoView(liveView, canBeginPlaybackWith: .full))
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

        init() {
            coordinator = AnalysisRawZoomScrollView.Coordinator(
                slot: slot,
                mediaFetcher: PhotoKitLibraryMediaFetcher()
            )
            scrollView = coordinator.makeScrollView()
            scrollView.frame = CGRect(x: 0, y: 0, width: 372, height: 844)
        }

        // Tests stay synchronous and dismantle before yielding, so the deferred
        // Live Photo request never reaches PhotoKit or the user's photo library.
        func show(
            _ image: UIImage,
            slot replacement: AnalysisPhotoSlot? = nil,
            isCurrent: Bool = true,
            isPaging: Bool = false
        ) {
            let currentSlot = replacement ?? slot
            coordinator.update(
                scrollView: scrollView,
                slot: currentSlot,
                source: currentSlot.source,
                image: image,
                isCurrent: isCurrent,
                isPagingInteracting: isPaging
            )
        }
    }
}
