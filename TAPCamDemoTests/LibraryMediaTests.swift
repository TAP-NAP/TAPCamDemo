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
        let fetcherSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/MediaLibrary/LibraryMediaFetching.swift"
        )
        let appSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift"
        )

        #expect(!providerSource.contains("import Photos"))
        #expect(!providerSource.contains("PhotoLibraryWriter.depthAlbumAssets"))
        #expect(!providerSource.contains("exportedAssetResolver"))
        #expect(fetcherSource.contains("DepthAlbumPhotoCataloging"))
        #expect(fetcherSource.contains("withLocalIdentifiers: exportedAssetLocalIdentifiers.sorted()"))
        #expect(appSource.contains("LibraryMediaStore(photoCatalog: photoKitClient)"))
        #expect(!fetcherSource.contains("LibraryAVAsset"))
        #expect(!fetcherSource.contains("PhotoKitAVAssetRequestBridge"))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func gridAndCameraUseRevisionAndPreviewPreservationContracts() throws {
        let gridSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift"
        )

        #expect(gridSource.contains(
            "item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)"
        ))
        #expect(cameraSource.contains(".preservingFailurePreview(preview)"))
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

    @Test @MainActor func videoPosterPreservesAspectRatioWith512PixelLongEdge() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_600, height: 900),
            format: format
        ).image { context in
            UIColor.red.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
        }

        let data = try #require(DepthAlbumThumbnailJPEGRenderer.videoPosterData(
            from: image,
            maximumPixelLength: 512
        ))
        let poster = try #require(UIImage(data: data)?.cgImage)

        #expect(poster.width == 512)
        #expect(poster.height == 288)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func simplifiedChineseICloudCopyIsPresent() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/Localizable.xcstrings"
        )

        #expect(source.contains("正在从 iCloud 中加载…"))
        #expect(source.contains("已存储在 iCloud"))
        #expect(source.contains("前往设置"))
        #expect(source.contains("当前处于离线状态"))
        #expect(source.contains("项目已不可用"))
        #expect(source.contains("无法下载"))
        #expect(source.contains("无法打开项目"))
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
