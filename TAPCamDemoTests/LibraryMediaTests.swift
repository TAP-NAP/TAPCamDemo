//
//  LibraryMediaTests.swift
//  TAPCamDemoTests
//

import Foundation
import Observation
@preconcurrency import Photos
import Testing
import UIKit
@testable import TAPCamDemo

struct LibraryMediaTests {
    @Test func recentLibraryPlaceholderRemainsVisibleUntilPosterIsReady() {
        let itemID = LibraryMediaID.tapCapture("placeholder")
        let readyPoster = MediaPoster(
            cacheKey: "ready",
            image: UIImage()
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
            recordsLoader: { [exported] },
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
            relativePath: "TAPCamDemo/MediaLibrary/DepthAlbumItemProvider.swift"
        )

        #expect(!providerSource.contains("import Photos"))
        #expect(!providerSource.contains("PhotoLibraryWriter.depthAlbumAssets"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func providerKeepsScalableLibraryMergeBehindExplicitIsolationBoundary() throws {
        let providerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/MediaLibrary/DepthAlbumItemProvider.swift"
        )

        #expect(providerSource.contains("let reconciled = await Task.detached(priority: .userInitiated)"))
        #expect(providerSource.contains("TAPLibraryItem.merged("))
        #expect(providerSource.contains("items.map(\\.summary)"))
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

    @Test func posterRequestCacheKeyTracksPixelLength() throws {
        let assetID = "photos-library://private/asset"
        let summary = Self.summary(
            id: .photosAsset(assetID),
            source: .photosOnly(assetID: assetID)
        )
        let request = try #require(LibraryMediaPosterRequest(summary: summary, pixelLength: 256))

        let resizedRequest = try #require(LibraryMediaPosterRequest(summary: summary, pixelLength: 128))
        #expect(request.cacheKey != resizedRequest.cacheKey)
    }

    @Test func photosDeletionUserCancellationStopsAsCancellation() {
        let error = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.userCancelled.rawValue)

        #expect(PhotoLibraryWriter.normalizedDeletionError(error) is CancellationError)
    }

    @Test func photosDeletionPreservesPermissionAndRealFailures() {
        let errors = [
            PHPhotosError.accessUserDenied,
            PHPhotosError.accessRestricted,
            PHPhotosError.operationInterrupted,
            PHPhotosError.internalError
        ].map { NSError(domain: PHPhotosErrorDomain, code: $0.rawValue) } + [
            NSError(domain: NSCocoaErrorDomain, code: PHPhotosError.userCancelled.rawValue)
        ]

        for error in errors {
            let normalized = PhotoLibraryWriter.normalizedDeletionError(error)
            #expect(!(normalized is CancellationError))
            #expect(normalized as NSError === error)
        }
    }

    @Test func photoKitBridgeCancelsWhenCancellationPrecedesRequestID() async {
        let recorder = PhotoKitCancellationRecorder()
        let bridge = DepthAlbumPhotoKitImageRequestBridge(
            cacheKey: "bridge",
            cancelRequest: { recorder.record($0) }
        )
        bridge.cancel()

        do {
            let _: MediaFetchPhase<MediaPoster, MediaPoster> = try await withCheckedThrowingContinuation { continuation in
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
            cacheKey: "bridge",
            cancelRequest: { recorder.record($0) }
        )

        do {
            let _: MediaFetchPhase<MediaPoster, MediaPoster> = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<MediaFetchPhase<MediaPoster, MediaPoster>, any Error>) in
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
            cacheKey: "bridge",
            cancelRequest: { recorder.record($0) }
        )

        let result: MediaFetchPhase<MediaPoster, MediaPoster> = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<MediaFetchPhase<MediaPoster, MediaPoster>, any Error>) in
            bridge.install(continuation: continuation)
            bridge.receive(image: nil, info: [PHImageResultIsInCloudKey: true])
            bridge.receive(image: nil, info: [
                PHImageErrorKey: MediaFetchFailure.download
            ])
            bridge.install(requestID: 44)
            bridge.cancel()
        }

        guard case .cloudOnly(nil) = result else {
            Issue.record("Expected cloud-only result without a local preview")
            return
        }
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

    @Test(arguments: [false, true])
    func resourceFileFailureCancelsAndFinishesExactlyOnce(failsDuringFinalization: Bool) async throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        let sink = try PhotoKitResourceFileSink(
            fileURL: fileURL,
            writeChunk: { fileHandle, chunk in
                if !failsDuringFinalization {
                    throw PhotoKitSinkWriteFailure()
                }
                try fileHandle.write(contentsOf: chunk)
            },
            finishFile: { _ in throw PhotoKitSinkWriteFailure() }
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
                completion(nil)
                completion(PhotoKitSinkWriteFailure())
                completion(nil)
                return 54
            }
            Issue.record("Expected file failure")
        } catch {
            #expect(error as? MediaFetchFailure == .download)
        }
        bridge.cancel()

        #expect(cancellations.requestIDs == [54])
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test(arguments: [false, true])
    func resourceFileRequestPreservesOriginalFailure(failsWhileWriting: Bool) async throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        try Data().write(to: fileURL, options: .atomic)
        let expectedError = NSError(
            domain: failsWhileWriting ? NSCocoaErrorDomain : PHPhotosErrorDomain,
            code: failsWhileWriting
                ? CocoaError.Code.fileWriteOutOfSpace.rawValue
                : PHPhotosError.networkAccessRequired.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Original resource failure"]
        )
        let sink = try PhotoKitResourceFileSink(
            fileURL: fileURL,
            writeChunk: { fileHandle, chunk in
                if failsWhileWriting {
                    throw expectedError
                }
                try fileHandle.write(contentsOf: chunk)
            }
        )
        let cancellations = PhotoKitCancellationRecorder()
        let bridge = PhotoKitResourceRequestBridge(
            sink: sink,
            allowsNetworkAccess: true,
            progress: { _ in },
            mapError: { $0 },
            cancelRequest: { cancellations.record($0) }
        )

        do {
            try await bridge.startRequest { receive, completion in
                receive(Data([1]))
                completion(failsWhileWriting ? nil : expectedError)
                return 57
            }
            Issue.record("Expected the original resource error")
        } catch {
            #expect((error as NSError) === expectedError)
        }

        #expect(cancellations.requestIDs == [57])
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func resourceFileCancellationBeforeStartDeletesFileWithoutRegistering() async throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        try Data().write(to: fileURL, options: .atomic)
        let cancellations = PhotoKitCancellationRecorder()
        let bridge = PhotoKitResourceRequestBridge(
            sink: try PhotoKitResourceFileSink(fileURL: fileURL),
            allowsNetworkAccess: true,
            progress: { _ in },
            mapError: { $0 },
            cancelRequest: { cancellations.record($0) }
        )

        bridge.cancel()
        do {
            try await bridge.startRequest { _, completion in
                Issue.record("Cancelled request must not register with Photos")
                completion(nil)
                return 58
            }
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // A cancelled file request must not start a Photos download.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(cancellations.requestIDs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func resourceFileFinalizesWrittenBytesBeforeCompletionAndRejectsLateChunks() async throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        try Data().write(to: fileURL, options: .atomic)
        let chunks = [Data([1, 2]), Data([3, 4, 5])]
        let expected = Data([1, 2, 3, 4, 5])
        let finalizations = PhotoKitTerminalRecorder()
        let bridge = PhotoKitResourceRequestBridge(
            sink: try PhotoKitResourceFileSink(
                fileURL: fileURL,
                finishFile: { fileHandle in
                    #expect(try Data(contentsOf: fileURL) == expected)
                    try fileHandle.synchronize()
                    try fileHandle.close()
                    finalizations.record()
                }
            ),
            allowsNetworkAccess: true,
            progress: { value in
                #expect(value == 1)
                #expect(finalizations.count == 1)
            },
            mapError: { $0 },
            cancelRequest: { _ in }
        )

        try await bridge.startRequest { receive, completion in
            for chunk in chunks {
                receive(chunk)
            }
            completion(nil)
            receive(Data([6]))
            return 59
        }

        #expect(finalizations.count == 1)
        #expect(try Data(contentsOf: fileURL) == expected)
    }

    @Test func resourceFileFinalizationFailurePreservesErrorClosesAndDeletesFile() async throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("resource.bin")
        try Data().write(to: fileURL, options: .atomic)
        let writes = PhotoKitTerminalRecorder()
        let finalizations = PhotoKitTerminalRecorder()
        let successes = PhotoKitTerminalRecorder()
        let cancellations = PhotoKitCancellationRecorder()
        let bridge = PhotoKitResourceRequestBridge(
            sink: try PhotoKitResourceFileSink(
                fileURL: fileURL,
                writeChunk: { fileHandle, chunk in
                    writes.record()
                    try fileHandle.write(contentsOf: chunk)
                },
                finishFile: { fileHandle in
                    finalizations.record()
                    // Retain the native handle in the error so the test can
                    // verify that failure cleanup closed it before resuming.
                    throw NSError(
                        domain: NSCocoaErrorDomain,
                        code: CocoaError.Code.fileWriteOutOfSpace.rawValue,
                        userInfo: ["fileHandle": fileHandle]
                    )
                }
            ),
            allowsNetworkAccess: true,
            progress: { _ in successes.record() },
            mapError: { $0 },
            cancelRequest: { cancellations.record($0) }
        )

        do {
            try await bridge.startRequest { receive, completion in
                receive(Data([1]))
                completion(nil)
                receive(Data([2]))
                completion(nil)
                completion(PhotoKitSinkWriteFailure())
                return 60
            }
            Issue.record("Expected the original finalization error")
        } catch {
            let fileError = error as NSError
            #expect(fileError.domain == NSCocoaErrorDomain)
            #expect(fileError.code == CocoaError.Code.fileWriteOutOfSpace.rawValue)
            let fileHandle = try #require(fileError.userInfo["fileHandle"] as? FileHandle)
            do {
                try fileHandle.write(contentsOf: Data([3]))
                Issue.record("Failure cleanup must close the file handle before resuming")
            } catch {
                // The failed sink has already closed this handle.
            }
        }
        bridge.cancel()
        bridge.cancel()

        #expect(writes.count == 1)
        #expect(finalizations.count == 1)
        #expect(successes.count == 0)
        #expect(cancellations.requestIDs == [60])
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
            allowsNetworkAccess: false
        ) {
            Issue.record("Degraded callback must not finish: \(result)")
        }

        let cloudProbe = PhotoKitDisplayImageResultAdapter.result(
            image: nil,
            info: [PHImageResultIsInCloudKey: true],
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
            allowsNetworkAccess: true
        )
        guard case .failure(let networkError)? = networkResult else {
            Issue.record("Expected decode failure for an empty network callback")
            return
        }
        #expect(networkError as? MediaFetchFailure == .decode)
    }

    @Test @MainActor func displayImageAdapterPreservesNativeImageAndOrientation() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let pixels = UIGraphicsImageRenderer(
            size: CGSize(width: 8, height: 4),
            format: format
        ).image { _ in }
        let image = UIImage(
            cgImage: try #require(pixels.cgImage),
            scale: 2,
            orientation: .rightMirrored
        )

        let result = PhotoKitDisplayImageResultAdapter.result(
            image: image,
            info: nil,
            allowsNetworkAccess: true
        )
        guard case .success(let displayImage)? = result else {
            Issue.record("Expected a final native display image")
            return
        }
        #expect(displayImage === image)
        #expect(displayImage.imageOrientation == .rightMirrored)
        #expect(displayImage.scale == 2)
        #expect(displayImage.cgImage?.width == 8)
        #expect(displayImage.cgImage?.height == 4)
    }

    @Test func displayImageAdapterPreservesCancellationAndResourceErrors() {
        let cancelled = PhotoKitDisplayImageResultAdapter.result(
            image: nil,
            info: [PHImageCancelledKey: true],
            allowsNetworkAccess: true
        )
        guard case .failure(let cancellationError)? = cancelled else {
            Issue.record("Expected display image cancellation")
            return
        }
        #expect(cancellationError is CancellationError)

        let failed = PhotoKitDisplayImageResultAdapter.result(
            image: nil,
            info: [PHImageErrorKey: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )],
            allowsNetworkAccess: true
        )
        guard case .failure(let resourceError)? = failed else {
            Issue.record("Expected display image resource failure")
            return
        }
        #expect(resourceError as? MediaFetchFailure == .offline)
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
            recordsLoader: { await loader.load() },
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

    @Test @MainActor func storePublishesFirstEmptySnapshotOnlyOnce() async {
        let provider = DepthAlbumItemProvider(
            recordsLoader: { [] },
            photoCatalogLoader: { _ in .empty }
        )
        let store = LibraryMediaStore(itemProvider: provider, observesChanges: false)

        _ = await store.refresh()
        let firstRevision = store.snapshot.revision
        #expect(firstRevision > 0)
        #expect(store.snapshot.items.isEmpty)
        #expect(store.hasUsableSnapshot)

        let publicationRecorder = LibraryMediaObservationRecorder()
        withObservationTracking {
            _ = store.items
            _ = store.snapshot.revision
        } onChange: {
            publicationRecorder.record()
        }

        _ = await store.refresh()

        #expect(store.snapshot.revision == firstRevision)
        #expect(publicationRecorder.count == 0)
    }

    @Test @MainActor func storeChangeObservationIsInertAndIdempotentUntilActivated() async throws {
        let notificationCenter = NotificationCenter()
        var loadCount = 0
        let provider = DepthAlbumItemProvider(
            recordsLoader: {
                loadCount += 1
                return []
            },
            photoCatalogLoader: { _ in .empty }
        )
        var registrations = 0
        var unregistrations = 0
        let store = LibraryMediaStore(
            itemProvider: provider,
            notificationCenter: notificationCenter,
            registerPhotoLibraryChangeObserver: { _ in registrations += 1 },
            unregisterPhotoLibraryChangeObserver: { _ in unregistrations += 1 }
        )

        #expect(!store.isObservingChanges)
        #expect(registrations == 0)
        notificationCenter.post(name: .tapLibraryDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(loadCount == 0)

        #expect(store.startObservingChangesIfNeeded())
        #expect(!store.startObservingChangesIfNeeded())
        #expect(store.isObservingChanges)
        #expect(registrations == 1)
        notificationCenter.post(name: .tapLibraryDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(loadCount == 1)

        notificationCenter.post(name: .tapLibraryDidChange, object: nil)
        #expect(store.stopObservingChangesIfNeeded())
        #expect(!store.stopObservingChangesIfNeeded())
        #expect(!store.isObservingChanges)
        #expect(unregistrations == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(loadCount == 1)

        notificationCenter.post(name: .tapLibraryDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(loadCount == 1)
    }

    @Test @MainActor func storeDoesNotRepublishEquivalentNineHundredItemSnapshot() async {
        let records = (0..<900).map { index in
            TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: "capture-\(index)",
                capturedAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let provider = DepthAlbumItemProvider(
            recordsLoader: { records },
            photoCatalogLoader: { _ in .empty }
        )
        let store = LibraryMediaStore(itemProvider: provider, observesChanges: false)

        _ = await store.refresh()
        let firstRevision = store.snapshot.revision
        #expect(store.items.count == 900)

        let publicationRecorder = LibraryMediaObservationRecorder()
        withObservationTracking {
            _ = store.items
            _ = store.snapshot.revision
        } onChange: {
            publicationRecorder.record()
        }

        _ = await store.refresh()

        #expect(store.items.count == 900)
        #expect(store.snapshot.revision == firstRevision)
        #expect(publicationRecorder.count == 0)
    }

    @Test @MainActor func storePublishesOnlySemanticSnapshotChanges() async {
        let firstRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "first",
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        let secondRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "second",
            capturedAt: Date(timeIntervalSince1970: 2)
        )
        let loader = SequencedPendingLoader(first: [firstRecord], second: [secondRecord])
        let provider = DepthAlbumItemProvider(
            recordsLoader: { await loader.load() },
            photoCatalogLoader: { _ in .empty }
        )
        let store = LibraryMediaStore(itemProvider: provider, observesChanges: false)

        _ = await store.refresh()
        let firstRevision = store.snapshot.revision
        _ = await store.refresh()
        let changedRevision = store.snapshot.revision

        #expect(changedRevision == firstRevision + 1)
        #expect(store.items.map(\.id) == ["capture:second"])

        _ = await store.refresh()

        #expect(store.snapshot.revision == changedRevision)
    }

    @Test @MainActor func storeTreatsEquivalentPhotosErrorsAsOneSnapshot() async {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "partial",
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        let provider = DepthAlbumItemProvider(
            recordsLoader: { [record] },
            photoCatalogLoader: { _ in
                throw NSError(domain: PHPhotosErrorDomain, code: 3)
            }
        )
        let store = LibraryMediaStore(itemProvider: provider, observesChanges: false)

        _ = await store.refresh()
        let firstRevision = store.snapshot.revision
        _ = await store.refresh()

        #expect(store.snapshot.revision == firstRevision)
        #expect(store.items.map(\.id) == ["capture:partial"])
        #expect(store.photoAssetsError != nil)
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

    @Test @MainActor func thumbnailDecoderRunsOffMainActorAndCoalescesSameKey() async throws {
        let cache = DepthAlbumThumbnailMemoryCache.shared
        cache.removeAll()
        defer { cache.removeAll() }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let sourceImage = renderer.image { context in
            UIColor.red.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let jpegData = try #require(sourceImage.jpegData(compressionQuality: 0.8))
        let recorder = ThumbnailDecodeRecorder()
        let decoder = DepthAlbumThumbnailDecoder { data in
            recorder.recordDecode(isMainThread: Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.04)
            return UIImage(data: data)
        }

        let cancelledWaiter = Task {
            await decoder.decodedThumbnail(data: jpegData, cacheKey: "coalesced")
        }
        let liveWaiter = Task {
            await decoder.decodedThumbnail(data: jpegData, cacheKey: "coalesced")
        }
        try await Task.sleep(for: .milliseconds(5))
        cancelledWaiter.cancel()
        let cancelledResult = await cancelledWaiter.value
        let liveResult = try #require(await liveWaiter.value)

        #expect(cancelledResult == nil)
        #expect(recorder.decodeCount == 1)
        #expect(!recorder.didRunOnMainThread)
        #expect(cache.poster(for: "coalesced")?.image === liveResult.image)
    }

    @Test @MainActor func visiblePosterSurvivesCacheEvictionAndReleasesWhenHidden() {
        let cache = DepthAlbumThumbnailMemoryCache.shared
        cache.removeAll()
        defer { cache.removeAll() }
        var visiblePhase: MediaFetchPhase<MediaPoster, MediaPoster> = .idle(nil)
        weak var presentedImage: UIImage?
        autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3), format: format)
            let image = renderer.image { context in
                UIColor.blue.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
            }
            let poster = MediaPoster(cacheKey: "visible", image: image)
            presentedImage = image
            cache.insert(poster)
            visiblePhase = .ready(poster)
            #expect(cache.poster(for: "visible")?.image === image)
        }
        cache.removeAll()

        autoreleasepool {
            #expect(cache.poster(for: "visible") == nil)
            #expect(visiblePhase.previewOrReadyValue?.image === presentedImage)
            #expect(presentedImage?.cgImage?.width == 2)
            #expect(presentedImage?.cgImage?.height == 3)
        }
        autoreleasepool {
            visiblePhase = .idle(nil)
        }
        #expect(presentedImage == nil)
    }

    @Test @MainActor func photoKitPosterKeepsNativeImageAndDegradedCloudPreview() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2))
        let image = renderer.image { context in
            UIColor.green.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        let bridge = DepthAlbumPhotoKitImageRequestBridge(cacheKey: "native") { _ in }
        let phase = try await withCheckedThrowingContinuation { continuation in
            bridge.install(continuation: continuation)
            bridge.receive(image: image, info: [PHImageResultIsDegradedKey: true])
            bridge.receive(image: nil, info: [PHImageResultIsInCloudKey: true])
        }
        guard case .cloudOnly(let poster) = phase else {
            Issue.record("Expected the native degraded preview to survive a cloud-only original")
            return
        }
        #expect(poster?.image === image)
        #expect(poster?.cacheKey == "native")
    }

    @Test @MainActor func fastFormatPosterCompletesWithItsOnlyDegradedCallback() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.red.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        let bridge = DepthAlbumPhotoKitImageRequestBridge(
            cacheKey: "fast", acceptsDegradedResult: true, cancelRequest: { _ in }
        )
        let phase = try await withCheckedThrowingContinuation { continuation in
            bridge.install(continuation: continuation)
            bridge.receive(image: image, info: [PHImageResultIsDegradedKey: true])
        }
        guard case .localPreview(let poster) = phase else {
            Issue.record("fastFormat has no second callback to wait for")
            return
        }
        #expect(poster.image === image)
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

private nonisolated final class LibraryMediaObservationRecorder: @unchecked Sendable {
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

private nonisolated final class ThumbnailDecodeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var ranOnMainThread = false

    var decodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var didRunOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ranOnMainThread
    }

    func recordDecode(isMainThread: Bool) {
        lock.lock()
        count += 1
        ranOnMainThread = ranOnMainThread || isMainThread
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
