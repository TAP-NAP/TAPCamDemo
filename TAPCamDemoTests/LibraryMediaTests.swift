//
//  LibraryMediaTests.swift
//  TAPCamDemoTests
//

import Foundation
@preconcurrency import Photos
import Testing
import UIKit
@testable import TAPCamDemo

struct LibraryMediaTests {
    @Test func recentLibraryPlaceholderRemainsVisibleUntilPosterIsReady() {
        let itemID = LibraryMediaID.tapCapture("placeholder")
        let readyPoster = MediaPoster(
            cacheKey: "ready",
            jpegData: Data([0])
        )

        #expect(RecentLibraryPresentation.unresolved.showsPlaceholderSymbol)
        #expect(RecentLibraryPresentation.empty.showsPlaceholderSymbol)
        #expect(
            RecentLibraryPresentation.resolving(
                itemID: itemID,
                kind: .photo
            ).showsPlaceholderSymbol
        )
        #expect(
            RecentLibraryPresentation.loading(
                itemID: itemID,
                kind: .photo,
                preview: nil,
                progress: nil
            ).showsPlaceholderSymbol
        )
        #expect(
            !RecentLibraryPresentation.loading(
                itemID: itemID,
                kind: .photo,
                preview: readyPoster,
                progress: 0.5
            ).showsPlaceholderSymbol
        )
        #expect(
            RecentLibraryPresentation.failed(
                itemID: itemID,
                kind: .photo,
                preview: nil,
                retryable: true
            ).showsPlaceholderSymbol
        )
        #expect(
            !RecentLibraryPresentation.failed(
                itemID: itemID,
                kind: .photo,
                preview: readyPoster,
                retryable: true
            ).showsPlaceholderSymbol
        )
        #expect(
            !RecentLibraryPresentation.ready(
                itemID: itemID,
                kind: .photo,
                poster: readyPoster
            ).showsPlaceholderSymbol
        )
    }

    @Test func originalVideoResourceAlwaysWinsOverAdjustedFullSizeVideo() {
        #expect(LibraryVideoResourceSelectionPolicy.preferredType(
            in: [.fullSizeVideo, .video]
        ) == .video)
        #expect(LibraryVideoResourceSelectionPolicy.preferredType(
            in: [.video, .fullSizeVideo]
        ) == .video)
        #expect(LibraryVideoResourceSelectionPolicy.preferredType(
            in: [.fullSizeVideo]
        ) == .fullSizeVideo)
        #expect(LibraryVideoResourceSelectionPolicy.preferredType(
            in: [.photo]
        ) == nil)
    }

    @Test func canonicalIdentitySurvivesPendingToOwnedExport() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let pending = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-stable",
            capturedAt: capturedAt
        )
        let exported = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-stable",
            capturedAt: capturedAt,
            status: .exported,
            assetLocalIdentifier: "asset-owned"
        )
        let asset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-owned",
            creationDate: Date(timeIntervalSince1970: 9_999)
        )

        let pendingItem = try #require(TAPLibraryItem.merged(
            pendingRecords: [pending],
            exportedRecords: [],
            photoAssets: []
        ).first)
        let ownedItem = try #require(TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [exported],
            photoAssets: [asset],
            photoAssetsByLocalIdentifier: [asset.localIdentifier: asset]
        ).first)

        #expect(pendingItem.mediaID == .tapCapture("capture-stable"))
        #expect(ownedItem.mediaID == pendingItem.mediaID)
        #expect(ownedItem.id == pendingItem.id)
        #expect(ownedItem.capturedAt == capturedAt)
        #expect(ownedItem.summary.source == .ownedPhotosAsset(
            captureID: "capture-stable",
            assetID: "asset-owned"
        ))
    }

    @Test @MainActor func providerBatchResolvesExportedAssetsFromOneCatalogSnapshot() async throws {
        let exported = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-catalog",
            capturedAt: Date(timeIntervalSince1970: 200),
            status: .exported,
            assetLocalIdentifier: "asset-owned"
        )
        let ownedAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-owned",
            creationDate: Date(timeIntervalSince1970: 200),
            isLivePhoto: true
        )
        let photosOnlyAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-photos-only",
            creationDate: Date(timeIntervalSince1970: 100)
        )
        var catalogCallCount = 0
        var requestedExportedAssetIDs = Set<String>()
        let provider = DepthAlbumItemProvider(
            pendingRecordsLoader: { [] },
            exportedRecordsLoader: { [exported] },
            photoCatalogLoader: { exportedAssetIDs in
                catalogCallCount += 1
                requestedExportedAssetIDs = exportedAssetIDs
                return DepthAlbumPhotoCatalogSnapshot(
                    albumAssets: [photosOnlyAsset],
                    resolvedAssets: [ownedAsset]
                )
            }
        )

        let snapshot = try await provider.loadSnapshot()

        #expect(catalogCallCount == 1)
        #expect(requestedExportedAssetIDs == ["asset-owned"])
        #expect(snapshot.items.map(\.id) == [
            "capture:capture-catalog",
            "photos:asset-photos-only"
        ])
        #expect(snapshot.items.first?.isLivePhoto == true)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func photoKitCatalogKeepsFrameworkObjectsBehindInjectedActorBoundary() throws {
        let providerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumItemProvider.swift"
        )

        #expect(!providerSource.contains("import Photos"))
        #expect(!providerSource.contains("PhotoLibraryWriter.depthAlbumAssets"))
    }

    @Test func exportedScalarRecordSurvivesTemporaryPhotosResolutionFailure() throws {
        let capturedAt = Date(timeIntervalSince1970: 321)
        let exported = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-exported",
            capturedAt: capturedAt,
            status: .exported,
            assetLocalIdentifier: "asset-temporarily-unresolved"
        )

        let item = try #require(TAPLibraryItem.merged(
            pendingRecords: [],
            exportedRecords: [exported],
            photoAssets: []
        ).first)

        #expect(item.mediaID == .tapCapture("capture-exported"))
        #expect(item.capturedAt == capturedAt)
        #expect(item.summary.source == .ownedPhotosAsset(
            captureID: "capture-exported",
            assetID: "asset-temporarily-unresolved"
        ))
    }

    @Test func appOwnedAssetIDIsDeduplicatedWhileRecordRemainsTerminallyFailed() throws {
        let capturedAt = Date(timeIntervalSince1970: 432)
        let failedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-readback-failed",
            capturedAt: capturedAt,
            status: .failedTerminal,
            assetLocalIdentifier: "asset-already-committed"
        )
        let committedAsset = DepthAlbumPhotoAsset(
            localIdentifier: "asset-already-committed",
            creationDate: capturedAt,
            isVideo: true
        )

        let items = TAPLibraryItem.merged(
            pendingRecords: [failedRecord],
            exportedRecords: [],
            photoAssets: [committedAsset]
        )

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.mediaID == .tapCapture("capture-readback-failed"))
        #expect(item.summary.source == .pending(captureID: "capture-readback-failed"))
    }

    @Test func fetchPolicyAllowsOnlyCanonicalPhotosOnlyCover() {
        let photos = Self.summary(id: .photosAsset("asset"), source: .photosOnly(assetID: "asset"))
        let pending = Self.summary(id: .tapCapture("capture"), source: .pending(captureID: "capture"))

        #expect(LibraryMediaFetchPolicy.allowsNetworkAccess(
            purpose: .recentCover,
            item: photos,
            currentItemID: photos.id
        ))
        #expect(!LibraryMediaFetchPolicy.allowsNetworkAccess(
            purpose: .recentCover,
            item: photos,
            currentItemID: .photosAsset("newer")
        ))
        #expect(!LibraryMediaFetchPolicy.allowsNetworkAccess(
            purpose: .recentCover,
            item: pending,
            currentItemID: pending.id
        ))
        #expect(!LibraryMediaFetchPolicy.allowsNetworkAccess(
            purpose: .gridPoster,
            item: photos,
            currentItemID: photos.id
        ))
        #expect(LibraryMediaFetchPolicy.allowsNetworkAccess(
            purpose: .photoDisplay,
            item: photos,
            currentItemID: photos.id
        ))
        #expect(!LibraryMediaFetchPolicy.allowsNetworkAccess(
            purpose: .photoDisplay,
            item: photos,
            currentItemID: .photosAsset("newer")
        ))
    }

    @Test func unifiedFetchStatePreservesPreviewAndProgress() {
        let preview = Data([1, 2, 3])
        let phase = MediaFetchPhase<Data, Data>.downloadingFromICloud(
            preview,
            progress: 0.42
        )

        #expect(phase == .downloadingFromICloud(preview, progress: 0.42))
        #expect(MediaFetchFailure.offline.isRetryable)
        #expect(!MediaFetchFailure.permission.isRetryable)
    }

    @Test func failedNetworkUpgradePreservesExistingPreview() {
        let localPreview = Data([4, 2])
        let failed = MediaFetchPhase<Data, Data>.failed(
            nil,
            reason: .offline,
            retryable: true
        )

        #expect(
            failed.preservingFailurePreview(localPreview)
                == .failed(localPreview, reason: .offline, retryable: true)
        )
    }

    @Test func posterCacheIdentityChangesWithoutChangingCanonicalMediaID() throws {
        let capturedAt = Date(timeIntervalSince1970: 543)
        let originalRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "capture-poster-revision",
            capturedAt: capturedAt
        )
        var revisedRecord = originalRecord
        revisedRecord.thumbnailFilename = TAPPendingCaptureBundlePathPolicy.thumbnailFilename
        revisedRecord.posterRevision = 1
        revisedRecord.updatedAt = capturedAt.addingTimeInterval(1)

        let originalItem = try #require(TAPLibraryItem.merged(
            pendingRecords: [originalRecord],
            exportedRecords: [],
            photoAssets: []
        ).first)
        let revisedItem = try #require(TAPLibraryItem.merged(
            pendingRecords: [revisedRecord],
            exportedRecords: [],
            photoAssets: []
        ).first)

        #expect(originalItem.mediaID == revisedItem.mediaID)
        #expect(
            originalItem.thumbnailCacheKey(pixelLength: 240)
                != revisedItem.thumbnailCacheKey(pixelLength: 240)
        )
    }

    @Test func fetchOverlayKeepsICloudAndFailureStatesDistinct() {
        #expect(
            LibraryMediaFetchOverlayState(
                MediaFetchPhase<Bool, Bool>.downloadingFromICloud(true, progress: 0.42)
            ) == .downloading(progress: 0.42)
        )
        #expect(
            LibraryMediaFetchOverlayState(
                MediaFetchPhase<Bool, Bool>.failed(
                    true,
                    reason: .permission,
                    retryable: false
                )
            ) == .failed(reason: .permission, retryable: false)
        )
        #expect(LibraryMediaCopy.loadingFromICloud(progress: 0.42).hasSuffix("42%"))
    }

    @Test func posterRequestCacheKeyDoesNotExposePhotoIdentifier() throws {
        let assetID = "photos-library://private/asset"
        let summary = Self.summary(
            id: .photosAsset(assetID),
            source: .photosOnly(assetID: assetID)
        )
        let request = try #require(LibraryMediaPosterRequest(summary: summary, pixelLength: 256))

        #expect(request.cacheKey.count == 64)
        #expect(!request.cacheKey.contains(assetID))
        #expect(!request.cacheKey.contains("private"))
    }

    @Test func photoKitBridgeCancelsWhenCancellationPrecedesRequestID() async {
        let recorder = PhotoKitCancellationRecorder()
        let bridge = DepthAlbumPhotoKitImageRequestBridge(
            pixelLength: 64,
            cancelRequest: { recorder.record($0) }
        )
        bridge.cancel()

        do {
            let _: DepthAlbumPhotoKitPosterResult = try await withCheckedThrowingContinuation { continuation in
                bridge.install(continuation: continuation)
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Cancellation is the expected, non-user-facing completion path.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        bridge.install(requestID: 42)
        bridge.cancel()
        bridge.receive(image: nil, info: nil)
        #expect(recorder.requestIDs == [42])
    }

    @Test func photoKitBridgeCancelsInstalledRequestExactlyOnce() async {
        let recorder = PhotoKitCancellationRecorder()
        let bridge = DepthAlbumPhotoKitImageRequestBridge(
            pixelLength: 64,
            cancelRequest: { recorder.record($0) }
        )

        do {
            let _: DepthAlbumPhotoKitPosterResult = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<DepthAlbumPhotoKitPosterResult, any Error>) in
                bridge.install(continuation: continuation)
                bridge.install(requestID: 43)
                bridge.cancel()
                bridge.cancel()
                bridge.receive(image: nil, info: [
                    PHImageErrorKey: MediaFetchFailure.download
                ])
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // The installed request and continuation are cancelled once.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(recorder.requestIDs == [43])
    }

    @Test func photoKitBridgeFinishesOnceBeforeLateRequestIDInstallation() async throws {
        let recorder = PhotoKitCancellationRecorder()
        let bridge = DepthAlbumPhotoKitImageRequestBridge(
            pixelLength: 64,
            cancelRequest: { recorder.record($0) }
        )

        let result: DepthAlbumPhotoKitPosterResult = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<DepthAlbumPhotoKitPosterResult, any Error>) in
            bridge.install(continuation: continuation)
            bridge.receive(image: nil, info: [PHImageResultIsInCloudKey: true])
            bridge.receive(image: nil, info: [
                PHImageErrorKey: MediaFetchFailure.download
            ])
            bridge.install(requestID: 44)
            bridge.cancel()
        }

        #expect(result.finalData == nil)
        #expect(result.isCloudOnly)
        #expect(recorder.requestIDs == [44])
    }

    @Test func requestLifecycleCancelsLateInstallAfterCancellationExactlyOnce() async {
        let cancellations = PhotoKitCancellationRecorder()
        let terminals = PhotoKitTerminalRecorder()
        let lifecycle = PhotoKitRequestLifecycle<PHImageRequestID, Int>(
            cancelRequest: { cancellations.record($0) },
            onFinish: { _ in terminals.record() }
        )

        lifecycle.cancel()
        do {
            let _: Int = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int, any Error>) in
                #expect(!lifecycle.install(continuation: continuation))
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Cancellation is the expected terminal result.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        lifecycle.install(requestID: 51)
        lifecycle.finish(.failure(MediaFetchFailure.download))
        lifecycle.cancel()

        #expect(cancellations.requestIDs == [51])
        #expect(terminals.count == 1)
    }

    @Test func requestLifecycleCancellationAfterInstallBeatsLaterError() async {
        let cancellations = PhotoKitCancellationRecorder()
        let terminals = PhotoKitTerminalRecorder()
        let lifecycle = PhotoKitRequestLifecycle<PHImageRequestID, Int>(
            cancelRequest: { cancellations.record($0) },
            onFinish: { _ in terminals.record() }
        )

        do {
            let _: Int = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int, any Error>) in
                #expect(lifecycle.install(continuation: continuation))
                lifecycle.install(requestID: 52)
                lifecycle.cancel()
                lifecycle.finish(.failure(MediaFetchFailure.download))
                lifecycle.cancel()
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Cancellation must remain the exactly-once terminal result.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(cancellations.requestIDs == [52])
        #expect(terminals.count == 1)
    }

    @Test func requestLifecycleFinishesOnceAndCancelsIDInstalledAfterFinish() async throws {
        let cancellations = PhotoKitCancellationRecorder()
        let terminals = PhotoKitTerminalRecorder()
        let lifecycle = PhotoKitRequestLifecycle<PHImageRequestID, Int>(
            cancelRequest: { cancellations.record($0) },
            onFinish: { _ in terminals.record() }
        )

        let value: Int = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int, any Error>) in
            #expect(lifecycle.install(continuation: continuation))
            lifecycle.finish(.success(7))
            lifecycle.finish(.success(8))
            lifecycle.install(requestID: 53)
        }

        #expect(value == 7)
        #expect(cancellations.requestIDs == [53])
        #expect(terminals.count == 1)
    }

    @Test func requestLifecycleSerializesConcurrentTerminalAndInstallRaces() async {
        for offset in 0..<32 {
            let requestID = PHImageRequestID(100 + offset)
            let cancellations = PhotoKitCancellationRecorder()
            let terminals = PhotoKitTerminalRecorder()
            let lifecycle = PhotoKitRequestLifecycle<PHImageRequestID, Int>(
                cancelRequest: { cancellations.record($0) },
                onFinish: { _ in terminals.record() }
            )
            let waiter = Task {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Int, any Error>) in
                    _ = lifecycle.install(continuation: continuation)
                }
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    lifecycle.install(requestID: requestID)
                }
                group.addTask {
                    lifecycle.cancel()
                }
                group.addTask {
                    lifecycle.finish(.success(7))
                }
            }

            switch await waiter.result {
            case .success(let value):
                #expect(value == 7)
            case .failure(let error):
                #expect(error is CancellationError)
            }
            #expect(terminals.count == 1)
            #expect(cancellations.requestIDs.count <= 1)
            #expect(cancellations.requestIDs.allSatisfy { $0 == requestID })
        }
    }

    @Test func resourceDataAndFileSinksShareTheRequestBridge() async throws {
        let chunks = [Data([1, 2]), Data([3, 4, 5])]
        let dataBridge = PhotoKitResourceRequestBridge(
            sink: PhotoKitResourceDataSink(),
            allowsNetworkAccess: false,
            progress: { _ in },
            cancelRequest: { _ in }
        )
        let data = try await dataBridge.startRequest { receive, completion in
            for chunk in chunks {
                receive(chunk)
            }
            completion(nil)
            return 55
        }

        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        let fileBridge = PhotoKitResourceRequestBridge(
            sink: try PhotoKitResourceFileSink(fileURL: fileURL),
            allowsNetworkAccess: false,
            progress: { _ in },
            cancelRequest: { _ in }
        )
        let _: Void = try await fileBridge.startRequest { receive, completion in
            for chunk in chunks {
                receive(chunk)
            }
            completion(nil)
            return 56
        }

        let expected = Data([1, 2, 3, 4, 5])
        #expect(data == expected)
        #expect(try Data(contentsOf: fileURL) == expected)
    }

    @Test func resourceFileWriteFailureCancelsAndFinishesExactlyOnce() async throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        let sink = try PhotoKitResourceFileSink(
            fileURL: fileURL,
            writeChunk: { _, _ in throw PhotoKitSinkWriteFailure() }
        )
        let cancellations = PhotoKitCancellationRecorder()
        let bridge = PhotoKitResourceRequestBridge(
            sink: sink,
            allowsNetworkAccess: false,
            progress: { _ in },
            cancelRequest: { cancellations.record($0) },
        )

        do {
            let _: Void = try await bridge.startRequest { receive, completion in
                receive(Data([1]))
                completion(PhotoKitSinkWriteFailure())
                completion(nil)
                return 54
            }
            Issue.record("Expected write failure")
        } catch {
            #expect(error as? MediaFetchFailure == .download)
        }
        bridge.cancel()

        #expect(cancellations.requestIDs == [54])
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func resourceLocalProbePreservesNetworkAccessRequired() {
        let error = NSError(
            domain: PHPhotosErrorDomain,
            code: PHPhotosError.networkAccessRequired.rawValue
        )

        #expect(
            PhotoKitMediaFetchFailure.resourceError(error)
                is PhotoKitNetworkAccessRequired
        )
    }

    @Test @MainActor func displayImageAdapterKeepsDegradedAndCloudProbeResultsExplicit() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 8, height: 4),
            format: format
        ).image { _ in }

        if let result = PhotoKitDisplayImageResultAdapter.result(
            image: image,
            info: [PHImageResultIsDegradedKey: true],
            pixelLength: 8,
            allowsNetworkAccess: false
        ) {
            Issue.record("Degraded callback must not finish: \(result)")
        }

        let cloudProbe = PhotoKitDisplayImageResultAdapter.result(
            image: nil,
            info: [PHImageResultIsInCloudKey: true],
            pixelLength: 8,
            allowsNetworkAccess: false
        )
        guard case .failure(let cloudError)? = cloudProbe else {
            Issue.record("Expected local-only iCloud probe failure")
            return
        }
        #expect(cloudError is PhotoKitNetworkAccessRequired)

        let networkResult = PhotoKitDisplayImageResultAdapter.result(
            image: nil,
            info: [PHImageResultIsInCloudKey: true],
            pixelLength: 8,
            allowsNetworkAccess: true
        )
        guard case .failure(let networkError)? = networkResult else {
            Issue.record("Expected decode failure for an empty network callback")
            return
        }
        #expect(networkError as? MediaFetchFailure == .decode)
    }

    @Test func livePhotoAdapterKeepsItsOwnCallbackInterpretation() {
        let degraded = PhotoKitLivePhotoResultAdapter.result(
            livePhoto: nil,
            info: [PHImageResultIsDegradedKey: true]
        )
        if let degraded {
            Issue.record("Degraded Live Photo callback must not finish: \(degraded)")
        }

        let cancelled = PhotoKitLivePhotoResultAdapter.result(
            livePhoto: nil,
            info: [PHImageCancelledKey: true]
        )
        guard case .failure(let cancellationError)? = cancelled else {
            Issue.record("Expected Live Photo cancellation")
            return
        }
        #expect(cancellationError is CancellationError)

        let offline = PhotoKitLivePhotoResultAdapter.result(
            livePhoto: nil,
            info: [
                PHImageErrorKey: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNotConnectedToInternet
                )
            ]
        )
        guard case .failure(let offlineError)? = offline else {
            Issue.record("Expected mapped Live Photo error")
            return
        }
        #expect(offlineError as? MediaFetchFailure == .offline)

        let emptyFinal = PhotoKitLivePhotoResultAdapter.result(
            livePhoto: nil,
            info: nil
        )
        guard case .failure(let decodeError)? = emptyFinal else {
            Issue.record("Expected final Live Photo decode failure")
            return
        }
        #expect(decodeError as? MediaFetchFailure == .decode)
    }

    @Test @MainActor func storeRejectsOutOfOrderRefreshCompletion() async throws {
        let old = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "old",
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        let newest = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "new",
            capturedAt: Date(timeIntervalSince1970: 2)
        )
        let loader = SequencedPendingLoader(first: [old], second: [newest])
        let provider = DepthAlbumItemProvider(
            pendingRecordsLoader: { await loader.load() },
            exportedRecordsLoader: { [] },
            photoCatalogLoader: { _ in .empty }
        )
        let store = LibraryMediaStore(itemProvider: provider, observesChanges: false)

        let first = Task { @MainActor in await store.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task { @MainActor in await store.refresh() }
        _ = await second.value
        _ = await first.value

        #expect(store.snapshot.latest?.id == .tapCapture("new"))
        #expect(store.items.map(\.id) == ["capture:new"])
        #expect(store.latestItem?.mediaID == store.snapshot.items.first?.id)
    }

    @Test func diskCacheEnforcesByteBudgetAndTTL() async throws {
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
            .appendingPathComponent("LibraryPosterCache", isDirectory: true)
        let clock = LibraryMediaTestClock(Date(timeIntervalSince1970: 1_000))
        let cache = DepthAlbumThumbnailDiskCache(
            directoryURL: directory,
            configuration: DepthAlbumThumbnailDiskCacheConfiguration(
                maximumByteCount: 12,
                maximumFileAge: 5
            ),
            now: { clock.now() }
        )

        await cache.store(Data(repeating: 1, count: 8), for: "one")
        clock.advance(by: 1)
        await cache.store(Data(repeating: 2, count: 8), for: "two")
        let firstData = await cache.data(for: "one")
        let secondData = await cache.data(for: "two")
        let byteCount = await cache.currentByteCount()
        #expect(firstData == nil)
        #expect(secondData != nil)
        #expect(byteCount <= 12)

        clock.advance(by: 10)
        await cache.store(Data([3]), for: "three")
        let expiredData = await cache.data(for: "two")
        let currentData = await cache.data(for: "three")
        #expect(expiredData == nil)
        #expect(currentData == Data([3]))
    }

    @Test func videoPosterBackfillContinuesAfterOneCandidateFails() async throws {
        let source = LibraryVideoBackfillSourceFake(candidates: [
            LibraryVideoPosterBackfillCandidate(
                captureID: "bad",
                videoURL: URL(fileURLWithPath: "/tmp/bad.mp4"),
                cacheKey: "bad"
            ),
            LibraryVideoPosterBackfillCandidate(
                captureID: "good",
                videoURL: URL(fileURLWithPath: "/tmp/good.mp4"),
                cacheKey: "good"
            )
        ])
        let persistence = LibraryVideoPosterPersistenceFake()
        let service = LibraryVideoPosterBackfillService(
            source: source,
            persistence: persistence,
            generator: LibraryVideoPosterGeneratorFake()
        )

        try await service.run()

        let captureIDs = await persistence.captureIDs
        #expect(captureIDs == ["good"])
    }

    @Test @MainActor func mediaPosterPreservesLandscapeAndPortraitAspectRatios() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let landscapeImage = UIGraphicsImageRenderer(
            size: CGSize(width: 1_600, height: 900),
            format: format
        ).image { context in
            UIColor.red.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
        }
        let portraitImage = UIGraphicsImageRenderer(
            size: CGSize(width: 900, height: 1_600),
            format: format
        ).image { context in
            UIColor.blue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: 1_600))
        }

        let landscapeData = try #require(DepthAlbumThumbnailJPEGRenderer.aspectPreservingData(
            from: landscapeImage,
            maximumPixelLength: 512
        ))
        let portraitData = try #require(DepthAlbumThumbnailJPEGRenderer.aspectPreservingData(
            from: portraitImage,
            maximumPixelLength: 512
        ))
        let landscapePoster = try #require(UIImage(data: landscapeData)?.cgImage)
        let portraitPoster = try #require(UIImage(data: portraitData)?.cgImage)

        #expect(landscapePoster.width == 512)
        #expect(landscapePoster.height == 288)
        #expect(portraitPoster.width == 288)
        #expect(portraitPoster.height == 512)
    }

    @Test @MainActor func mediaPosterNormalizesRotatedOrientationWithoutSquaring() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let baseImage = UIGraphicsImageRenderer(
            size: CGSize(width: 1_600, height: 900),
            format: format
        ).image { context in
            UIColor.green.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
        }
        let cgImage = try #require(baseImage.cgImage)
        let rotatedImage = UIImage(cgImage: cgImage, scale: 1, orientation: .left)
        let data = try #require(DepthAlbumThumbnailJPEGRenderer.aspectPreservingData(
            from: rotatedImage,
            maximumPixelLength: 512
        ))
        let poster = try #require(UIImage(data: data)?.cgImage)

        #expect(poster.width == 288)
        #expect(poster.height == 512)
    }

    private static func summary(
        id: LibraryMediaID,
        source: LibraryMediaSource
    ) -> LibraryMediaSummary {
        LibraryMediaSummary(
            id: id,
            capturedAt: .distantPast,
            kind: .photo,
            source: source,
            version: LibraryMediaVersion(contentRevision: "content", posterRevision: "poster")
        )
    }
}

private actor SequencedPendingLoader {
    private let first: [TAPPendingCaptureRecord]
    private let second: [TAPPendingCaptureRecord]
    private var callCount = 0

    init(first: [TAPPendingCaptureRecord], second: [TAPPendingCaptureRecord]) {
        self.first = first
        self.second = second
    }

    func load() async -> [TAPPendingCaptureRecord] {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(120))
            return first
        }
        return second
    }
}

private nonisolated final class LibraryMediaTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private nonisolated final class PhotoKitCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int32] = []

    var requestIDs: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func record(_ requestID: Int32) {
        lock.lock()
        values.append(requestID)
        lock.unlock()
    }
}

private nonisolated final class PhotoKitTerminalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private nonisolated struct PhotoKitSinkWriteFailure: Error {}

private nonisolated struct LibraryVideoBackfillSourceFake: LibraryVideoPosterBackfillSource {
    let candidates: [LibraryVideoPosterBackfillCandidate]

    func videosMissingPosters() async throws -> [LibraryVideoPosterBackfillCandidate] {
        candidates
    }
}

private actor LibraryVideoPosterPersistenceFake: LibraryVideoPosterPersisting {
    private(set) var captureIDs: [String] = []

    func persistPosterData(_ data: Data, captureID: String) async throws {
        captureIDs.append(captureID)
    }
}

private nonisolated struct LibraryVideoPosterGeneratorFake: LibraryVideoPosterGenerating {
    func posterData(for videoURL: URL, cacheKey: String, pixelLength: Int) async throws -> Data {
        if cacheKey == "bad" {
            throw MediaFetchFailure.decode
        }
        return Data(cacheKey.utf8)
    }
}
