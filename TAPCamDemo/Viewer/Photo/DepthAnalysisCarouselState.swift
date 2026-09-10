//
//  DepthAnalysisCarouselState.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/7/5.
//

import Combine
import CoreGraphics
import Foundation
import ImageIO
import os
import UIKit

nonisolated struct DepthAnalysisCarouselEntry: Identifiable, Equatable {
    let id: String
    let mediaID: LibraryMediaID
    let source: DepthAnalysisSource
    let albumEntry: DepthAnalysisAlbumContext.Entry?
    var expectsPairedVideo: Bool { albumEntry?.expectsPairedVideo ?? false }
    var mediaVersion: LibraryMediaVersion? { albumEntry?.mediaVersion }

    init(source: DepthAnalysisSource) {
        self.id = Self.id(for: source)
        self.mediaID = source.libraryMediaID
        self.source = source
        self.albumEntry = nil
    }

    init(albumEntry: DepthAnalysisAlbumContext.Entry) {
        self.id = albumEntry.id
        self.mediaID = albumEntry.mediaID
        self.source = albumEntry.source
        self.albumEntry = albumEntry
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

nonisolated extension DepthAnalysisSource {
    var libraryMediaID: LibraryMediaID {
        switch self {
        case .photosAsset(let assetID):
            .photosAsset(assetID)
        case .pendingCapture(let captureID):
            .tapCapture(captureID)
        }
    }

    var assetLocalIdentifier: String? {
        guard case .photosAsset(let assetID) = self else {
            return nil
        }
        return assetID
    }
}

nonisolated struct AnalysisDisplayPhoto {
    let image: UIImage
    let orientation: CGImagePropertyOrientation
    let pixelSize: CGSize
    let requestedPixelLength: Int

    init(image: UIImage, requestedPixelLength: Int = 0) {
        self.image = image
        self.orientation = image.imageOrientation.cgImagePropertyOrientation
        self.requestedPixelLength = requestedPixelLength
        if let cgImage = image.cgImage {
            self.pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            self.pixelSize = image.size
        }
    }
}

nonisolated enum AnalysisPhotoDisplayPhase: Equatable {
    case idle
    case thumbnailReady
    case displayLoading
    case displayReady
    case failed
}

nonisolated enum AnalysisPhotoAnalysisPhase: Equatable {
    case idle
    case loading(progress: Double?)
    case ready
    case failed

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

nonisolated enum AnalysisSlotLoadPhase: Equatable {
    case idle
    case thumbnailReady
    case originalLoading(progress: Double?)
    case analysisReady
    case failed

    var isOriginalLoading: Bool {
        if case .originalLoading = self {
            return true
        }
        return false
    }
}

nonisolated struct DepthAnalysisDisplayPhotoLoader {
    typealias ProgressHandler = @Sendable @MainActor (Double?) -> Void
    typealias ThumbnailLoader = @Sendable (DepthAnalysisSource, Int) async -> UIImage?
    typealias DisplayLoader = @Sendable (DepthAnalysisSource, Int) async throws -> AnalysisDisplayPhoto
    private typealias IdentifiedDisplayLoader = @Sendable (
        DepthAnalysisSource,
        Int,
        MediaFetchRequestKey,
        @escaping ProgressHandler
    ) async throws -> AnalysisDisplayPhoto

    private let thumbnailLoader: ThumbnailLoader
    private let identifiedDisplayLoader: IdentifiedDisplayLoader

    init(
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        thumbnailLoader: ThumbnailLoader? = nil,
        displayLoader: DisplayLoader? = nil
    ) {
        self.thumbnailLoader = thumbnailLoader ?? { source, pixelLength in
            await Self.defaultThumbnail(
                source: source,
                pixelLength: pixelLength,
                mediaFetcher: mediaFetcher
            )
        }
        if let displayLoader {
            self.identifiedDisplayLoader = { source, pixelLength, _, _ in
                try await displayLoader(source, pixelLength)
            }
        } else {
            self.identifiedDisplayLoader = { source, pixelLength, requestKey, progress in
                try await Self.defaultDisplayPhoto(
                    source: source,
                    pixelLength: pixelLength,
                    requestKey: requestKey,
                    mediaFetcher: mediaFetcher,
                    progressHandler: progress
                )
            }
        }
    }

    func thumbnail(source: DepthAnalysisSource, pixelLength: Int) async -> UIImage? {
        await thumbnailLoader(source, pixelLength)
    }

    @concurrent
    func displayPhoto(
        source: DepthAnalysisSource,
        pixelLength: Int,
        requestKey: MediaFetchRequestKey,
        progressHandler: @escaping ProgressHandler
    ) async throws -> AnalysisDisplayPhoto {
        try await identifiedDisplayLoader(
            source,
            pixelLength,
            requestKey,
            progressHandler
        )
    }

    private static func defaultThumbnail(
        source: DepthAnalysisSource,
        pixelLength: Int,
        mediaFetcher: any LibraryMediaFetching
    ) async -> UIImage? {
        switch source {
        case .photosAsset(let assetID):
            let key = MediaFetchRequestKey(
                itemID: .photosAsset(assetID),
                generation: 0,
                purpose: .gridPoster
            )
            let request = LibraryMediaAssetRequest(
                key: key,
                assetLocalIdentifier: assetID
            )
            guard let phase = try? await mediaFetcher.previewPhase(
                for: request,
                pixelLength: pixelLength,
                allowsNetworkAccess: false,
                progress: { _ in }
            ),
            let poster = phase.previewOrReadyValue else {
                return nil
            }
            return poster.image
        case .pendingCapture(let captureID):
            // Adjacent carousel items are preview-only. Never decode a 48 MP
            // pending original merely because its derivative is missing.
            guard let data = try? await TAPPendingCaptureStore.shared.thumbnailData(
                captureID: captureID
            ) else {
                return nil
            }
            return await DepthAlbumThumbnailDecoder.image(data: data)
        }
    }

    private static func defaultDisplayPhoto(
        source: DepthAnalysisSource,
        pixelLength: Int,
        requestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching,
        progressHandler: @escaping ProgressHandler
    ) async throws -> AnalysisDisplayPhoto {
        switch source {
        case .photosAsset(let assetID):
            let request = LibraryMediaAssetRequest(
                key: requestKey,
                assetLocalIdentifier: assetID
            )
            let image = try await mediaFetcher.photoDisplayImage(
                for: request,
                pixelLength: pixelLength
            ) { progress in
                Task { @MainActor in
                    progressHandler(progress)
                }
            }
            return AnalysisDisplayPhoto(image: image, requestedPixelLength: pixelLength)
        case .pendingCapture(let captureID):
            do {
                let data = try await TAPPendingCaptureStore.shared.bestAvailablePhotoData(captureID: captureID)
                guard let image = downsampledImage(data: data, pixelLength: pixelLength) ?? UIImage(data: data) else {
                    throw TAPDepthCaptureError.assetCreationFailed
                }
                return AnalysisDisplayPhoto(image: image, requestedPixelLength: pixelLength)
            } catch {
                TAPLibraryChangeNotifier.post()
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            }
        }
    }

    private static func downsampledImage(data: Data, pixelLength: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelLength, 1)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

}

nonisolated struct DepthAnalysisProgressivePhotoLoader {
    typealias OriginalProgressHandler = @Sendable @MainActor (Double?) -> Void
    typealias ThumbnailLoader = DepthAnalysisDisplayPhotoLoader.ThumbnailLoader
    typealias DisplayLoader = DepthAnalysisDisplayPhotoLoader.DisplayLoader
    typealias InputLoader = @Sendable (DepthAnalysisSource, @escaping OriginalProgressHandler) async throws -> TAPDepthAnalysisInput
    struct LoadedOriginal {
        let analysisResult: Result<TAPDepthAnalysisInput, any Error>
        let resourceLease: TAPPhotoOriginalResourceLease?

        func analysisInput() throws -> TAPDepthAnalysisInput {
            try analysisResult.get()
        }
    }
    private typealias IdentifiedInputLoader = @Sendable (
        DepthAnalysisSource,
        MediaFetchRequestKey,
        Bool,
        @escaping @Sendable @MainActor (TAPPhotoOriginalResourceLease) -> Void,
        @escaping OriginalProgressHandler
    ) async throws -> LoadedOriginal

    private let displayPhotoLoader: DepthAnalysisDisplayPhotoLoader
    private let identifiedInputLoader: IdentifiedInputLoader

    init(
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        thumbnailLoader: ThumbnailLoader? = nil,
        displayLoader: DisplayLoader? = nil,
        inputLoader: InputLoader? = nil
    ) {
        self.displayPhotoLoader = DepthAnalysisDisplayPhotoLoader(
            mediaFetcher: mediaFetcher,
            thumbnailLoader: thumbnailLoader,
            displayLoader: displayLoader
        )
        if let inputLoader {
            self.identifiedInputLoader = { source, _, _, _, progressHandler in
                LoadedOriginal(
                    analysisResult: .success(
                        try await inputLoader(source, progressHandler)
                    ),
                    resourceLease: nil
                )
            }
        } else {
            self.identifiedInputLoader = { source, requestKey, expectsPairedVideo, resourceReadyHandler, progressHandler in
                try await Self.defaultInput(
                    source: source,
                    mediaID: requestKey.itemID,
                    expectsPairedVideo: expectsPairedVideo,
                    resourceReadyHandler: resourceReadyHandler,
                    progressHandler: progressHandler
                )
            }
        }
    }

    func thumbnail(source: DepthAnalysisSource, pixelLength: Int) async -> UIImage? {
        await displayPhotoLoader.thumbnail(source: source, pixelLength: pixelLength)
    }

    func displayPhoto(
        source: DepthAnalysisSource,
        pixelLength: Int,
        requestKey: MediaFetchRequestKey,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> AnalysisDisplayPhoto {
        try await displayPhotoLoader.displayPhoto(
            source: source,
            pixelLength: pixelLength,
            requestKey: requestKey,
            progressHandler: progressHandler
        )
    }

    @concurrent
    func loadedOriginal(
        source: DepthAnalysisSource,
        requestKey: MediaFetchRequestKey,
        expectsPairedVideo: Bool,
        retainedResourceLease: TAPPhotoOriginalResourceLease? = nil,
        resourceReadyHandler: @escaping @Sendable @MainActor (
            TAPPhotoOriginalResourceLease
        ) -> Void = { _ in },
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> LoadedOriginal {
        if let retainedResourceLease {
            return Self.analyzeOriginal(retainedResourceLease)
        }
        return try await identifiedInputLoader(
            source,
            requestKey,
            expectsPairedVideo,
            resourceReadyHandler,
            progressHandler
        )
    }

    private static func defaultInput(
        source: DepthAnalysisSource,
        mediaID: LibraryMediaID,
        expectsPairedVideo: Bool,
        resourceReadyHandler: @escaping @Sendable @MainActor (
            TAPPhotoOriginalResourceLease
        ) -> Void,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> LoadedOriginal {
        let resourceLease = try await TAPPhotoOriginalResourceLoader().load(
            TAPPhotoOriginalResourceRequest(
                mediaID: mediaID,
                source: source,
                expectsPairedVideo: expectsPairedVideo
            )
        ) { progress in
            Task { @MainActor in
                progressHandler(progress)
            }
        }
        await resourceReadyHandler(resourceLease.retaining())
        return analyzeOriginal(resourceLease)
    }

    private static func analyzeOriginal(_ resourceLease: TAPPhotoOriginalResourceLease) -> LoadedOriginal {
        let analysisResult = Result<TAPDepthAnalysisInput, any Error> {
            let data = try Data(
                contentsOf: resourceLease.photoURL,
                options: [.mappedIfSafe]
            )
            try TAPDepthAnalysisInputValidation.validateHEICByteCount(data.count)
            return try TAPDepthMapReader.analysisInput(from: data)
        }
        return LoadedOriginal(
            analysisResult: analysisResult,
            resourceLease: resourceLease
        )
    }

}

extension UIImage.Orientation {
    nonisolated var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        @unknown default:
            .up
        }
    }
}


/// Owns the committed mixed-media cursor and its bounded resource window.
/// User presentation choices live here once for the whole detail visit.
@MainActor
final class TAPLibraryViewerStore: ObservableObject {
    @Published private(set) var currentItemID: String
    @Published private(set) var pagingEntries: [TAPLibraryViewerPagingEntry]
    @Published var selectedTool = AnalysisViewerTool.raw
    @Published private(set) var contentGeneration: UInt64 = 0

    private let loader: DepthAnalysisProgressivePhotoLoader
    private let mediaFetcher: any LibraryMediaFetching
    private let registrationAdapter: any TAPVideoDepthRegistrationAdapting
    private var slots: [String: AnalysisPhotoSlot] = [:]
    private var slotObservations: [String: AnyCancellable] = [:]
    private var videoSessions: [String: TAPVideoPlaybackSession] = [:]
    private var retainedSlotStates: [String: AnalysisPhotoSlotRetainedState] = [:]

    init(
        entries: [TAPLibraryViewerPagingEntry],
        currentItemID: String,
        loader: DepthAnalysisProgressivePhotoLoader? = nil,
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        registrationAdapter: any TAPVideoDepthRegistrationAdapting = TAPVideoManifestDepthRegistrationAdapter()
    ) {
        pagingEntries = entries
        self.currentItemID = currentItemID
        self.mediaFetcher = mediaFetcher
        self.registrationAdapter = registrationAdapter
        self.loader = loader ?? DepthAnalysisProgressivePhotoLoader(mediaFetcher: mediaFetcher)
    }

    var currentIndex: Int? { pagingEntries.firstIndex { $0.id == currentItemID } }
    var currentPagingEntry: TAPLibraryViewerPagingEntry? {
        pagingEntries.first { $0.id == currentItemID }
    }
    var currentEntry: DepthAnalysisCarouselEntry? { currentPagingEntry.flatMap(photoEntry) }
    var currentSlot: AnalysisPhotoSlot? { currentEntry.map(slot(for:)) }
    var currentVideoSession: TAPVideoPlaybackSession? {
        guard let currentPagingEntry, case .video = currentPagingEntry.destination else { return nil }
        return videoSession(for: currentPagingEntry)
    }
    var retainedSlotCount: Int { slots.count }

    var windowPagingEntries: [TAPLibraryViewerPagingEntry] {
        guard let currentIndex else { return [] }
        return Array(pagingEntries[max(0, currentIndex - 1)...min(pagingEntries.count - 1, currentIndex + 1)])
    }

    func photoEntry(_ entry: TAPLibraryViewerPagingEntry) -> DepthAnalysisCarouselEntry? {
        guard case .analysis(let route) = entry.destination,
              let anchor = entry.routeAnchor ?? CameraRouteAlbumAnchor(itemID: entry.id) else { return nil }
        return DepthAnalysisCarouselEntry(albumEntry: DepthAnalysisAlbumContext.Entry(
            id: entry.id, mediaID: entry.mediaID, source: route.source, routeAnchor: anchor,
            expectsPairedVideo: entry.expectsPairedVideo, mediaVersion: entry.mediaVersion
        ))
    }

    func select(_ target: TAPLibraryViewerPagingEntry, pixelLength: Int, prewarmCurrentPlaneGeometry: Bool) {
        guard target.id != currentItemID, pagingEntries.contains(where: { $0.id == target.id }) else { return }
        currentVideoSession?.suspendForAdjacent()
        currentItemID = target.id
        contentGeneration &+= 1
        ensureVisibleWindowLoaded(pixelLength: pixelLength, prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry)
    }

    @discardableResult
    func removeCurrent(pixelLength: Int = 960) -> TAPLibraryViewerPagingEntry? {
        guard let deletedIndex = currentIndex else { return nil }
        let deletedID = currentItemID
        discardResources(id: deletedID)
        pagingEntries.remove(at: deletedIndex)
        currentItemID = pagingEntries.isEmpty ? "" : pagingEntries[min(deletedIndex, pagingEntries.count - 1)].id
        contentGeneration &+= 1
        ensureVisibleWindowLoaded(pixelLength: pixelLength, prewarmCurrentPlaneGeometry: selectedTool == .threeD)
        return currentPagingEntry
    }

    func reconcile(entries: [TAPLibraryViewerPagingEntry], selectedItemID: String, pixelLength: Int) {
        guard entries != pagingEntries || selectedItemID != currentItemID else { return }
        let previousIndex = currentIndex ?? 0
        for old in pagingEntries {
            let fresh = entries.first { $0.id == old.id }
            if fresh?.destination != old.destination || fresh?.expectsPairedVideo != old.expectsPairedVideo
                || fresh?.mediaVersion?.contentRevision != old.mediaVersion?.contentRevision {
                discardResources(id: old.id)
            } else if let fresh, fresh.mediaVersion?.posterRevision != old.mediaVersion?.posterRevision {
                if let slot = slots[old.id], let refreshedPhoto = photoEntry(fresh) {
                    slot.entry = refreshedPhoto
                    slot.displayFetchState.thumbnailTask?.cancel()
                    slot.displayFetchState.thumbnailTask = nil
                    slot.ensureThumbnailLoading(loader: loader, pixelLength: pixelLength, refresh: true)
                }
                videoSessions[old.id]?.refreshLoadingPreview(
                    cachedImage: TAPLibraryPagingPreviewCache.shared.image(for: fresh.id, version: fresh.mediaVersion))
            }
        }
        pagingEntries = entries
        if entries.contains(where: { $0.id == selectedItemID }) {
            if currentItemID != selectedItemID { currentVideoSession?.suspendForAdjacent() }
            currentItemID = selectedItemID
        } else if !entries.contains(where: { $0.id == currentItemID }) {
            currentItemID = entries.isEmpty ? "" : entries[min(previousIndex, entries.count - 1)].id
        }
        contentGeneration &+= 1
        ensureVisibleWindowLoaded(pixelLength: pixelLength, prewarmCurrentPlaneGeometry: selectedTool == .threeD)
    }

    func slot(for requestedEntry: DepthAnalysisCarouselEntry) -> AnalysisPhotoSlot {
        let entry = pagingEntries.first(where: { $0.id == requestedEntry.id }).flatMap(photoEntry) ?? requestedEntry
        if let slot = slots[entry.id] { return slot }
        let slot = AnalysisPhotoSlot(entry: entry, retainedState: retainedSlotStates.removeValue(forKey: entry.id))
        if let preview = TAPLibraryPagingPreviewCache.shared.image(for: entry.id, version: entry.mediaVersion) {
            slot.seedThumbnailIfEmpty(preview)
        }
        slot.displayFetchState.lastLoader = loader
        slots[entry.id] = slot
        slotObservations[entry.id] = slot.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        return slot
    }

    func videoSession(for entry: TAPLibraryViewerPagingEntry) -> TAPVideoPlaybackSession? {
        guard case .video(let route) = entry.destination else { return nil }
        if let session = videoSessions[entry.id] { return session }
        let session = TAPVideoPlaybackSession(
            source: route.source, registrationAdapter: registrationAdapter, mediaFetcher: mediaFetcher,
            initialLoadingPreviewImage: TAPLibraryPagingPreviewCache.shared.image(for: entry.id, version: entry.mediaVersion)
        )
        videoSessions[entry.id] = session
        return session
    }

    func ensureVisibleWindowLoaded(pixelLength: Int = 960, prewarmCurrentPlaneGeometry: Bool = false) {
        let window = windowPagingEntries
        for pagingEntry in window {
            if let entry = photoEntry(pagingEntry) {
                let slot = slot(for: entry)
                if entry.id == currentItemID {
                    slot.ensureLoading(loader: loader, pixelLength: pixelLength, priority: .userInitiated,
                                       prewarmPlaneGeometry: prewarmCurrentPlaneGeometry)
                } else {
                    slot.prepareForAdjacentPreview()
                    slot.ensureThumbnail(loader: loader, pixelLength: pixelLength)
                }
            } else if pagingEntry.id == currentItemID {
                videoSession(for: pagingEntry)?.prepareForCurrentSelection()
            }
        }
        let kept = Set(window.map(\.id))
        for id in Set(slots.keys).union(videoSessions.keys) where !kept.contains(id) {
            if let slot = slots[id] { retainedSlotStates[id] = slot.retainedStateForEviction() }
            discardResources(id: id, preserveSelection: true)
        }
    }

    func cancelViewerRequests() {
        slots.values.forEach { $0.prepareForEviction() }
        videoSessions.values.forEach { $0.stopPlayback() }
    }

    func handleMemoryWarning() {
        for id in Set(slots.keys).union(videoSessions.keys) where id != currentItemID {
            discardResources(id: id)
        }
        currentVideoSession?.handleMemoryWarning()
    }

    private func discardResources(id: String, preserveSelection: Bool = false) {
        if !preserveSelection { retainedSlotStates.removeValue(forKey: id) }
        slotObservations.removeValue(forKey: id)
        slots.removeValue(forKey: id)?.prepareForEviction()
        videoSessions.removeValue(forKey: id)?.stopPlayback()
    }
}
