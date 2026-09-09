//
//  TAPDepthAnalysisPresentationTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import CoreLocation
import Photos
import Testing
import UIKit
@testable import TAPCamDemo

@Suite(.serialized)
struct TAPDepthAnalysisPresentationTests {
    @Test func videoViewerModesKeepPhotoOrderAndFailClosedTwoDAvailability() throws {
        let registeredDescriptor = TAPVideoDepthRegistrationDescriptor(
            schemaID: "test.registered-rgb-presentation",
            rgbPresentationWidth: 1,
            rgbPresentationHeight: 1,
            mapping: .preRegisteredRGBPresentation
        )
        let availableItems = TAPVideoViewerModePolicy.items(
            availability: .available(registeredDescriptor),
            selectedTool: .raw,
            isTwoDPlaybackReady: false
        )

        #expect(availableItems.map(\.id) == ["raw", "twoD", "threeD"])
        #expect(availableItems.map(\.accessibilityIdentifier) == [
            "tap.viewer.mode.raw",
            "tap.viewer.mode.2d",
            "tap.viewer.mode.3d"
        ])
        #expect(availableItems.map(\.accessibilityLabel) == [
            "Raw video",
            "2D analysis",
            "3D projection"
        ])
        #expect(availableItems.map(\.isEnabled) == [true, true, true])
        #expect(availableItems.map(\.accessibilityValue) == [
            "Selected",
            "Available",
            "Coming soon"
        ])

        let readyTwoDItems = TAPVideoViewerModePolicy.items(
            availability: .available(registeredDescriptor),
            selectedTool: .twoD,
            isTwoDPlaybackReady: true
        )
        #expect(readyTwoDItems[1].accessibilityValue == "Selected, Ready")

        let unavailableItems = TAPVideoViewerModePolicy.items(
            availability: .unavailable,
            selectedTool: .raw,
            isTwoDPlaybackReady: false
        )
        #expect(unavailableItems.map(\.isEnabled) == [true, false, true])
        #expect(unavailableItems[1].accessibilityValue == "Registered depth unavailable")

        let incompleteDescriptor = TAPVideoDepthRegistrationDescriptor(
            schemaID: "test.incomplete",
            rgbPresentationWidth: 0,
            rgbPresentationHeight: 0,
            mapping: .preRegisteredRGBPresentation
        )
        let incompleteItems = TAPVideoViewerModePolicy.items(
            availability: .available(incompleteDescriptor),
            selectedTool: .raw,
            isTwoDPlaybackReady: false
        )
        #expect(incompleteItems.map(\.isEnabled) == [true, false, true])
    }

    @Test func videoTransportTreatsBufferingAsActivePlaybackIntent() {
        #expect(!TAPVideoPlaybackTransportPolicy.hasActivePlaybackIntent(status: .paused))
        #expect(TAPVideoPlaybackTransportPolicy.hasActivePlaybackIntent(status: .playing))
        #expect(
            TAPVideoPlaybackTransportPolicy.hasActivePlaybackIntent(
                status: .waitingToPlayAtSpecifiedRate
            )
        )
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func analysisPlaneConfidenceBadgeIsDebugOnly() throws {
        let interactiveSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInteractiveImage.swift"
        )
        let badgeSection = try #require(TAPCamDemoTestSourceInspection.substring(
            in: interactiveSource,
            from: "#if DEBUG\n                    let rect = viewRect(for: planeRegion.imageBounds",
            to: "#endif\n                } else if let planeSeedPoint"
        ))

        #expect(badgeSection.contains("PlaneRegionBadge"))
    }

    @Test func videoAlbumContextKeepsSwipeAndDeleteOrdering() throws {
        let entries = try ["a", "b", "c"].map { id in
            TAPVideoAlbumContext.Entry(
                id: id,
                source: .photosAsset(id),
                routeAnchor: try #require(CameraRouteAlbumAnchor(itemID: id))
            )
        }
        let context = TAPVideoAlbumContext(currentItemID: "b", entries: entries)

        #expect(context.adjacentEntry(offset: -1, excluding: [])?.id == "a")
        #expect(context.adjacentEntry(offset: 1, excluding: [])?.id == "c")
        #expect(context.adjacentEntry(offset: 2, excluding: []) == nil)
        #expect(
            context.entryAfterDeletingCurrent(excluding: ["b"])?.id == "c"
        )
        #expect(
            context.entryAfterDeletingCurrent(excluding: ["b", "c"])?.id == "a"
        )
        #expect(TAPVideoPlaybackSource.pendingCapture("p")
            .requiresUnsavedDeleteConfirmation)
        #expect(!TAPVideoPlaybackSource.photosAsset("p")
            .requiresUnsavedDeleteConfirmation)
    }

    @Test func analysisAlbumContextMovesThroughAdjacentEntries() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third]
        )

        #expect(context.adjacentEntry(offset: -1) == first)
        #expect(context.adjacentEntry(offset: 1) == third)
        #expect(context.adjacentEntry(offset: 2) == nil)
        #expect(context.selecting(third).currentItemID == third.id)
    }

    @Test @MainActor func analysisCarouselStoreKeepsStableThreeSlotWindow() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: .noop
        )

        #expect(store.currentIndex == 1)
        #expect(store.windowEntries().map(\.entry.id) == ["first", "second", "third"])
        let cachedSecondSlot = store.slot(for: store.windowEntries()[1].entry)

        let movedEntry = try #require(store.move(offset: 1))

        #expect(movedEntry.id == "third")
        #expect(store.currentIndex == 2)
        #expect(store.windowEntries().map(\.entry.id) == ["second", "third"])
        #expect(store.slot(for: DepthAnalysisCarouselEntry(albumEntry: second)) === cachedSecondSlot)
    }

    @Test @MainActor func analysisCarouselStoreMoveKeepsAlbumRouteContext() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .photosAsset("asset-second"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: first.id,
            entries: [first, second]
        )
        let store = DepthAnalysisCarouselStore(
            source: first.source,
            albumContext: context,
            loader: .noop
        )

        let movedEntry = try #require(store.move(offset: 1))

        #expect(movedEntry.albumEntry?.id == second.id)
        #expect(movedEntry.albumEntry?.routeAnchor == second.routeAnchor)
        #expect(store.currentItemID == second.id)
    }

    @Test @MainActor func analysisCarouselStoreSelectsNextEntryAfterDeletingCurrent() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: .noop
        )

        let nextEntry = try #require(store.advanceAfterDeletingCurrent())

        #expect(nextEntry.id == third.id)
        #expect(store.currentEntry?.id == third.id)
        #expect(store.windowEntries().map(\.entry.id) == ["first", "third"])
        #expect(store.entry(offset: -1)?.id == first.id)
        #expect(store.entry(offset: 1) == nil)
    }

    @Test @MainActor func analysisCarouselStoreSelectsPreviousEntryAfterDeletingLast() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .photosAsset("asset-second"))
        let third = try analysisAlbumEntry(id: "third", source: .pendingCapture("capture-third"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: third.id,
            entries: [first, second, third]
        )
        let store = DepthAnalysisCarouselStore(
            source: third.source,
            albumContext: context,
            loader: .noop
        )

        let previousEntry = try #require(store.advanceAfterDeletingCurrent())

        #expect(previousEntry.id == second.id)
        #expect(store.currentEntry?.id == second.id)
        #expect(store.windowEntries().map(\.entry.id) == ["first", "second"])
        #expect(store.entry(offset: -1)?.id == first.id)
        #expect(store.entry(offset: 1) == nil)
    }

    @Test @MainActor func analysisCarouselStoreReturnsNilAfterDeletingOnlyEntry() throws {
        let only = try analysisAlbumEntry(id: "only", source: .pendingCapture("capture-only"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: only.id,
            entries: [only]
        )
        let store = DepthAnalysisCarouselStore(
            source: only.source,
            albumContext: context,
            loader: .noop
        )

        let nextEntry = store.advanceAfterDeletingCurrent()

        #expect(nextEntry == nil)
        #expect(store.currentEntry == nil)
        #expect(store.windowEntries().isEmpty)
    }

    @Test @MainActor func analysisCarouselStoreEvictsSlotsOutsideVisibleWindow() throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .pendingCapture("capture-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let fourth = try analysisAlbumEntry(id: "fourth", source: .photosAsset("asset-fourth"))
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third, fourth]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: .noop
        )
        let firstEntry = DepthAnalysisCarouselEntry(albumEntry: first)
        let cachedFirstSlot = store.slot(for: firstEntry)
        cachedFirstSlot.updatePlaneGrowthStrictness(0.9)

        let movedEntry = try #require(store.move(offset: 1))

        #expect(movedEntry.id == third.id)
        #expect(store.windowEntries().map(\.entry.id) == ["second", "third", "fourth"])
        #expect(store.retainedSlotCount == 3)

        let restoredFirstSlot = store.slot(for: firstEntry)
        #expect(restoredFirstSlot !== cachedFirstSlot)
        #expect(abs(restoredFirstSlot.planeSelection.strictness - 0.9) < 0.0001)
    }

    @Test @MainActor func analysisCarouselStoreLoadsCurrentOriginalAndAdjacentThumbnails() async throws {
        let first = try analysisAlbumEntry(id: "first", source: .photosAsset("asset-first"))
        let second = try analysisAlbumEntry(id: "second", source: .photosAsset("asset-second"))
        let third = try analysisAlbumEntry(id: "third", source: .photosAsset("asset-third"))
        let fourth = try analysisAlbumEntry(id: "fourth", source: .photosAsset("asset-fourth"))
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let thumbnail = try singlePixelUIImage()
        let events = AnalysisLoaderEventRecorder()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { source, _ in
                await events.recordThumbnail(source)
                return thumbnail
            },
            displayLoader: { source, _ in
                await events.recordDisplay(source)
                return AnalysisDisplayPhoto(image: thumbnail)
            },
            inputLoader: { source, _ in
                await events.recordInput(source)
                return input
            }
        )
        let context = DepthAnalysisAlbumContext(
            currentItemID: second.id,
            entries: [first, second, third, fourth]
        )
        let store = DepthAnalysisCarouselStore(
            source: second.source,
            albumContext: context,
            loader: loader
        )

        store.ensureVisibleWindowLoaded(pixelLength: 80)
        try await waitForLoaderEvents(events, thumbnailCount: 3, displayCount: 1, inputCount: 1)

        var snapshot = await events.snapshot()
        #expect(Set(snapshot.thumbnails) == ["photos:asset-first", "photos:asset-second", "photos:asset-third"])
        #expect(snapshot.displays == ["photos:asset-second"])
        #expect(snapshot.inputs == ["photos:asset-second"])

        let movedEntry = try #require(store.move(offset: 1))
        #expect(movedEntry.id == third.id)
        try await waitForLoaderEvents(events, thumbnailCount: 4, displayCount: 2, inputCount: 2)

        snapshot = await events.snapshot()
        #expect(Set(snapshot.thumbnails) == [
            "photos:asset-first",
            "photos:asset-second",
            "photos:asset-third",
            "photos:asset-fourth"
        ])
        #expect(snapshot.displays == ["photos:asset-second", "photos:asset-third"])
        #expect(snapshot.inputs == ["photos:asset-second", "photos:asset-third"])
        let previousSlot = store.slot(for: DepthAnalysisCarouselEntry(albumEntry: second))
        let currentSlot = store.slot(for: DepthAnalysisCarouselEntry(albumEntry: third))
        try await waitForCondition { currentSlot.input != nil }
        #expect(previousSlot.input == nil)
        #expect(currentSlot.input != nil)
    }

    @Test @MainActor func originalPhotoLoaderRunsOffMainActorAcrossProgressCallback() async throws {
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let loader = originalLoaderCheckingExecutionBoundary(input: input)

        let original = try await loader.loadedOriginal(
            source: .photosAsset("original-execution-boundary"),
            requestKey: MediaFetchRequestKey(
                itemID: .photosAsset("original-execution-boundary"),
                generation: 0,
                purpose: .photoOriginal
            ),
            expectsPairedVideo: false,
            progressHandler: { progress in
                #expect(Thread.isMainThread)
                #expect(progress == 0.5)
            }
        )

        #expect(try original.analysisInput().depthMap.width == 2)
    }

    @Test @MainActor func displayPhotoLoaderRunsOffMainActor() async throws {
        let image = try singlePixelUIImage()
        let loader = displayLoaderCheckingExecutionBoundary(image: image)

        let displayPhoto = try await loader.displayPhoto(
            source: .photosAsset("display-execution-boundary"),
            pixelLength: 80,
            requestKey: MediaFetchRequestKey(
                itemID: .photosAsset("display-execution-boundary"),
                generation: 0,
                purpose: .photoDisplay
            ),
            progressHandler: { _ in }
        )

        #expect(displayPhoto.image.size == image.size)
    }

    @Test @MainActor func analysisPhotoSlotPublishesThumbnailProgressAndDecodedInput() async throws {
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let thumbnail = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in thumbnail },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: thumbnail) },
            inputLoader: { _, progress in
                await progress(0.35)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(entry: DepthAnalysisCarouselEntry(source: .photosAsset("asset-a")))

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition {
            slot.thumbnailImage != nil && slot.input != nil
        }

        #expect(slot.phase == .analysisReady)
        #expect(slot.thumbnailImage != nil)
        #expect(slot.displayPhoto?.image.size == thumbnail.size)
        #expect(slot.input?.depthMap.width == 2)
        #expect(slot.loadProgress == nil)
    }

    @Test @MainActor func currentPhotoKeepsDisplayPreviewDuringICloudOriginalDownload() async throws {
        let image = try singlePixelUIImage()
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, progress in
                await progress(0.42)
                try await Task.sleep(nanoseconds: 300_000_000)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("icloud-original"))
        )

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition {
            guard slot.displayPhoto != nil,
                  case .downloadingFromICloud(let hasPreview, let progress) = slot.mediaFetchPhase else {
                return false
            }
            return hasPreview == true && progress == 0.42
        }

        #expect(slot.displayPhoto?.image.size == image.size)
        #expect(slot.input == nil)
        try await waitForCondition { slot.input != nil }
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func completedAnalysisIdentityFollowsRetainedInputAndReload() async throws {
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        ))
        let slot = AnalysisPhotoSlot(entry: DepthAnalysisCarouselEntry(source: .photosAsset("input-identity")))
        let loader = DepthAnalysisProgressivePhotoLoader(inputLoader: { _, _ in input })
        #expect(slot.analysisState.completedInputRequestKey == nil)
        slot.ensureInputLoading(loader: loader, priority: .userInitiated, prewarmPlaneGeometry: false)
        let firstRequest = try #require(slot.analysisState.activeOriginalRequestKey)
        await (try #require(slot.analysisState.inputTask)).value
        #expect(slot.input != nil)
        #expect(slot.analysisState.completedInputRequestKey == firstRequest)
        #expect(slot.analysisState.activeOriginalRequestKey == nil)

        slot.cancelCurrentMediaFetch()
        #expect(slot.input != nil)
        #expect(slot.analysisState.completedInputRequestKey == firstRequest)
        slot.prepareForAdjacentPreview()
        #expect(slot.input == nil)
        #expect(slot.analysisState.completedInputRequestKey == nil)

        let calibration = try #require(input.depthMap.calibration)
        let changedCalibration = TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: calibration.intrinsicMatrixReferenceWidth,
            intrinsicMatrixReferenceHeight: calibration.intrinsicMatrixReferenceHeight,
            pixelSizeMillimeters: calibration.pixelSizeMillimeters,
            lensDistortionLookupTablePresent: calibration.lensDistortionLookupTablePresent,
            inverseLensDistortionLookupTablePresent: calibration.inverseLensDistortionLookupTablePresent,
            lensDistortionCenterX: calibration.lensDistortionCenterX,
            lensDistortionCenterY: calibration.lensDistortionCenterY,
            intrinsicMatrix: [200, 0, 0, 0, 100, 0, 4, 4, 1],
            extrinsicMatrix: calibration.extrinsicMatrix
        )
        let replacement = TAPDepthAnalysisInput(
            manifest: input.manifest,
            image: input.image,
            imageOrientation: input.imageOrientation,
            depthMap: TAPMetricDepthMap(
                width: input.depthMap.width,
                height: input.depthMap.height,
                samples: input.depthMap.samples,
                calibration: changedCalibration
            ),
            depthAccuracy: input.depthAccuracy,
            depthQuality: input.depthQuality,
            heatmap: input.heatmap
        )
        slot.ensureInputLoading(
            loader: DepthAnalysisProgressivePhotoLoader(inputLoader: { _, _ in replacement }),
            priority: .userInitiated,
            prewarmPlaneGeometry: false
        )
        let secondRequest = try #require(slot.analysisState.activeOriginalRequestKey)
        await (try #require(slot.analysisState.inputTask)).value
        #expect(secondRequest != firstRequest)
        #expect(slot.analysisState.completedInputRequestKey == secondRequest)
        #expect(slot.input?.depthMap.calibration == changedCalibration)
        #expect(slot.input?.depthMap.samples == input.depthMap.samples)
        slot.prepareForEviction()
        #expect(slot.input == nil)
        #expect(slot.analysisState.completedInputRequestKey == nil)
    }

    @Test @MainActor func originalICloudProgressNeverRegressesOrReturnsToIndeterminate() async throws {
        let image = try singlePixelUIImage()
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, progress in
                await progress(0.64)
                await progress(nil)
                await progress(0.21)
                try await Task.sleep(nanoseconds: 300_000_000)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("icloud-monotonic-progress"))
        )

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition {
            slot.mediaFetchPhase == .downloadingFromICloud(true, progress: 0.64)
        }

        #expect(slot.loadProgress == 0.64)
        try await waitForCondition { slot.input != nil }
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func lateOriginalProgressCannotDemotePublishedResourceReadiness() throws {
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = directory.appendingPathComponent("original.heic")
        try Data("complete-original".utf8).write(to: photoURL)
        let lease = try TAPPhotoOriginalResourceLease(
            mediaID: .photosAsset("late-progress"),
            origin: .photosAsset(assetID: "late-progress"),
            photoURL: photoURL,
            pairedVideoURL: nil,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: .heic,
            expectsPairedVideo: false,
            ownedTemporaryDirectoryURL: directory
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("late-progress"))
        )
        let requestKey = slot.newOriginalRequestKey()
        slot.originalResourceOwner.install(lease)
        slot.setOriginalMediaFetchPhase(.ready(true))

        // A queued PhotoKit callback may arrive after the resource-ready
        // callback but before depth analysis returns. It must be ignored.
        slot.applyOriginalICloudProgress(0.99, requestKey: requestKey)

        #expect(slot.mediaFetchPhase == .ready(true))
        #expect(slot.originalResourceOwner.isReady)
    }

    @Test @MainActor func livePhotoProgressAggregatesWithReadyOriginalAndCanonicalIdentity() async throws {
        let image = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in throw CancellationError() }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("live-photo-progress"))
        )

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition { slot.mediaFetchPhase == .ready(true) }

        let requestKey = slot.beginLivePhotoFetch(onCancel: {}, onRetry: {})
        #expect(requestKey.itemID == .photosAsset("live-photo-progress"))
        #expect(requestKey.purpose == .livePhotoPlayback)

        slot.markLivePhotoFetchResolving(requestKey: requestKey)
        #expect(slot.mediaFetchPhase == .resolving(true))
        slot.applyLivePhotoICloudProgress(0.42, requestKey: requestKey)
        #expect(slot.mediaFetchPhase == .downloadingFromICloud(true, progress: 0.42))

        slot.completeLivePhotoFetch(requestKey: requestKey)
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func staleLivePhotoCallbacksCannotOverrideReplacementRequestOrPreview() async throws {
        let image = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in throw CancellationError() }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("live-photo-race"))
        )
        var cancellationCount = 0

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition { slot.mediaFetchPhase == .ready(true) }

        let staleKey = slot.beginLivePhotoFetch(
            onCancel: { cancellationCount += 1 },
            onRetry: {}
        )
        slot.applyLivePhotoICloudProgress(0.1, requestKey: staleKey)
        let replacementKey = slot.beginLivePhotoFetch(onCancel: {}, onRetry: {})
        #expect(cancellationCount == 1)
        #expect(slot.mediaFetchPhase == .ready(true))

        slot.applyLivePhotoICloudProgress(0.99, requestKey: staleKey)
        slot.failLivePhotoFetch(MediaFetchFailure.download, requestKey: staleKey)
        #expect(slot.mediaFetchPhase == .ready(true))

        slot.applyLivePhotoICloudProgress(0.25, requestKey: replacementKey)
        #expect(slot.mediaFetchPhase == .downloadingFromICloud(true, progress: 0.25))
        slot.completeLivePhotoFetch(requestKey: replacementKey)

        slot.applyLivePhotoICloudProgress(0.75, requestKey: staleKey)
        #expect(slot.mediaFetchPhase == .ready(true))
    }

    @Test @MainActor func cancelAndRetryControlOriginalAndLivePhotoRequestsTogether() async throws {
        let image = try singlePixelUIImage()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in image },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in throw CancellationError() }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("live-photo-cancel"))
        )
        var cancellationCount = 0
        var retryCount = 0

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCondition { slot.mediaFetchPhase == .ready(true) }
        let requestKey = slot.beginLivePhotoFetch(
            onCancel: { cancellationCount += 1 },
            onRetry: { retryCount += 1 }
        )
        slot.applyLivePhotoICloudProgress(0.3, requestKey: requestKey)

        slot.cancelCurrentMediaFetch()
        #expect(cancellationCount == 1)
        #expect(slot.mediaFetchPhase == .cloudOnly(true))

        slot.retryLastMediaFetch()
        #expect(retryCount == 1)
        #expect(slot.mediaFetchPhase == .resolving(true))
    }

    @Test @MainActor func cancelledDisplayTaskCannotClearReplacementTaskHandle() async throws {
        let image = try singlePixelUIImage()
        let calls = CancellationRaceLoaderCallRecorder()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in
                let call = await calls.beginCall()
                if call == 1 {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        await nonCancellableDelay(nanoseconds: 80_000_000)
                        throw CancellationError()
                    }
                }
                try await Task.sleep(nanoseconds: 400_000_000)
                return AnalysisDisplayPhoto(image: image)
            },
            inputLoader: { _, _ in
                throw CancellationError()
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("display-race"))
        )

        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCancellationRaceCalls(calls, count: 1)
        slot.cancelCurrentMediaFetch()
        slot.retryLastMediaFetch()
        try await waitForCancellationRaceCalls(calls, count: 2)

        try await Task.sleep(nanoseconds: 120_000_000)
        slot.ensureDisplayPhoto(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await Task.sleep(nanoseconds: 40_000_000)

        let callCount = await calls.callCount()
        #expect(callCount == 2)
        slot.prepareForEviction()
    }

    @Test @MainActor func cancelledInputTaskCannotClearReplacementTaskHandle() async throws {
        let image = try singlePixelUIImage()
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )
        let input = try TAPCamDemoTestFixtures.analysisInput(depthMap: depthMap)
        let calls = CancellationRaceLoaderCallRecorder()
        let loader = DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in AnalysisDisplayPhoto(image: image) },
            inputLoader: { _, _ in
                let call = await calls.beginCall()
                if call == 1 {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        await nonCancellableDelay(nanoseconds: 80_000_000)
                        throw CancellationError()
                    }
                }
                try await Task.sleep(nanoseconds: 400_000_000)
                return input
            }
        )
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .photosAsset("input-race"))
        )

        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await waitForCancellationRaceCalls(calls, count: 1)
        try await waitForCondition { slot.displayPhoto != nil }
        slot.cancelCurrentMediaFetch()
        slot.retryLastMediaFetch()
        try await waitForCancellationRaceCalls(calls, count: 2)

        try await Task.sleep(nanoseconds: 120_000_000)
        slot.ensureLoading(loader: loader, pixelLength: 80, priority: .userInitiated)
        try await Task.sleep(nanoseconds: 40_000_000)

        let callCount = await calls.callCount()
        #expect(callCount == 2)
        slot.prepareForEviction()
    }

    @Test func planeGrowthStrictnessUsesTheReleaseDefaultAndClampsDebugOverrides() {
        #expect(DepthAnalyzerPreferences.resolvedPlaneGrowthStrictness(
            storedValue: DepthAnalysisPlaneSelectionState.minimumStrictness,
            allowsDebugOverride: true
        ) == DepthAnalysisPlaneSelectionState.minimumStrictness)
        #expect(DepthAnalyzerPreferences.resolvedPlaneGrowthStrictness(
            storedValue: DepthAnalysisPlaneSelectionState.minimumStrictness - 0.2,
            allowsDebugOverride: true
        ) == DepthAnalysisPlaneSelectionState.minimumStrictness)
        #expect(DepthAnalyzerPreferences.resolvedPlaneGrowthStrictness(
            storedValue: DepthAnalysisPlaneSelectionState.maximumStrictness + 0.2,
            allowsDebugOverride: true
        ) == DepthAnalysisPlaneSelectionState.maximumStrictness)
        #expect(DepthAnalyzerPreferences.resolvedPlaneGrowthStrictness(
            storedValue: DepthAnalysisPlaneSelectionState.maximumStrictness,
            allowsDebugOverride: false
        ) == DepthAnalysisPlaneSelectionState.defaultStrictness)
        #expect(DepthAnalyzerPreferences.resolvedPlaneGrowthStrictness(
            storedValue: .nan,
            allowsDebugOverride: true
        ) == DepthAnalysisPlaneSelectionState.defaultStrictness)
    }

}

private func analysisAlbumEntry(
    id: String,
    source: DepthAnalysisSource
) throws -> DepthAnalysisAlbumContext.Entry {
    let anchor = try #require(CameraRouteAlbumAnchor(itemID: id))
    let mediaID: LibraryMediaID
    switch source {
    case .photosAsset(let assetID):
        mediaID = .photosAsset(assetID)
    case .pendingCapture(let captureID):
        mediaID = .tapCapture(captureID)
    }
    return DepthAnalysisAlbumContext.Entry(
        id: id,
        mediaID: mediaID,
        source: source,
        routeAnchor: anchor
    )
}

private func singlePixelUIImage() throws -> UIImage {
    let image = try TAPDepthRGBAImageRenderer.image(
        pixels: [UInt8(255), 0, 0, 255],
        width: 1,
        height: 1
    )
    return UIImage(cgImage: image)
}

private nonisolated func originalLoaderCheckingExecutionBoundary(
    input: TAPDepthAnalysisInput
) -> DepthAnalysisProgressivePhotoLoader {
    DepthAnalysisProgressivePhotoLoader(inputLoader: { _, progress in
        #expect(!isRunningOnMainThread())
        await progress(0.5)
        #expect(!isRunningOnMainThread())
        return input
    })
}

private nonisolated func displayLoaderCheckingExecutionBoundary(
    image: UIImage
) -> DepthAnalysisDisplayPhotoLoader {
    DepthAnalysisDisplayPhotoLoader(displayLoader: { _, _ in
        #expect(!isRunningOnMainThread())
        return AnalysisDisplayPhoto(image: image)
    })
}

private nonisolated func isRunningOnMainThread() -> Bool {
    Thread.isMainThread
}

@MainActor
private func waitForCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @MainActor @escaping () -> Bool
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let maximumAttempts = max(1, Int(timeoutNanoseconds / pollIntervalNanoseconds))
    for _ in 0..<maximumAttempts {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    if condition() {
        return
    }
    Issue.record("Timed out waiting for condition.")
}

private func waitForLoaderEvents(
    _ events: AnalysisLoaderEventRecorder,
    thumbnailCount: Int,
    displayCount: Int,
    inputCount: Int,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let maximumAttempts = max(1, Int(timeoutNanoseconds / pollIntervalNanoseconds))
    for _ in 0..<maximumAttempts {
        let snapshot = await events.snapshot()
        if snapshot.thumbnails.count >= thumbnailCount,
           snapshot.displays.count >= displayCount,
           snapshot.inputs.count >= inputCount {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    let finalSnapshot = await events.snapshot()
    if finalSnapshot.thumbnails.count >= thumbnailCount,
       finalSnapshot.displays.count >= displayCount,
       finalSnapshot.inputs.count >= inputCount {
        return
    }
    Issue.record("Timed out waiting for loader events.")
}

private func waitForCancellationRaceCalls(
    _ recorder: CancellationRaceLoaderCallRecorder,
    count: Int,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let maximumAttempts = max(1, Int(timeoutNanoseconds / pollIntervalNanoseconds))
    for _ in 0..<maximumAttempts {
        if await recorder.callCount() >= count {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    if await recorder.callCount() >= count {
        return
    }
    Issue.record("Timed out waiting for cancellation-race loader calls.")
}

private func nonCancellableDelay(nanoseconds: UInt64) async {
    await Task.detached(priority: .utility) {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }.value
}

private actor CancellationRaceLoaderCallRecorder {
    private var count = 0

    func beginCall() -> Int {
        count += 1
        return count
    }

    func callCount() -> Int {
        count
    }
}

private actor AnalysisLoaderEventRecorder {
    private(set) var thumbnails: [String] = []
    private(set) var displays: [String] = []
    private(set) var inputs: [String] = []

    func recordThumbnail(_ source: DepthAnalysisSource) {
        thumbnails.append(Self.id(for: source))
    }

    func recordDisplay(_ source: DepthAnalysisSource) {
        displays.append(Self.id(for: source))
    }

    func recordInput(_ source: DepthAnalysisSource) {
        inputs.append(Self.id(for: source))
    }

    func snapshot() -> (thumbnails: [String], displays: [String], inputs: [String]) {
        (thumbnails, displays, inputs)
    }

    private static func id(for source: DepthAnalysisSource) -> String {
        switch source {
        case .photosAsset(let assetID):
            "photos:\(assetID)"
        case .pendingCapture(let captureID):
            "pending:\(captureID)"
        }
    }
}

private extension DepthAnalysisProgressivePhotoLoader {
    static var noop: DepthAnalysisProgressivePhotoLoader {
        DepthAnalysisProgressivePhotoLoader(
            thumbnailLoader: { _, _ in nil },
            displayLoader: { _, _ in
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            },
            inputLoader: { _, _ in
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            }
        )
    }
}
