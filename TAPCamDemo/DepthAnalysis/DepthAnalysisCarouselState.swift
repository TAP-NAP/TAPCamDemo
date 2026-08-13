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

nonisolated private extension DepthAnalysisSource {
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
            let data = phase.previewOrReadyValue else {
                return nil
            }
            return UIImage(data: data)
        case .pendingCapture(let captureID):
            // Adjacent carousel items are preview-only. Never decode a 48 MP
            // pending original merely because its derivative is missing.
            guard let data = try? await TAPPendingCaptureStore.shared.thumbnailData(
                captureID: captureID
            ) else {
                return nil
            }
            return UIImage(data: data)
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
            let data = try await mediaFetcher.photoDisplayData(
                for: request,
                pixelLength: pixelLength
            ) { progress in
                Task { @MainActor in
                    progressHandler(progress)
                }
            }
            guard let image = downsampledImage(data: data, pixelLength: pixelLength)
                    ?? UIImage(data: data) else {
                throw MediaFetchFailure.decode
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
                NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
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

    func input(
        source: DepthAnalysisSource,
        requestKey: MediaFetchRequestKey,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> TAPDepthAnalysisInput {
        try await loadedOriginal(
            source: source,
            requestKey: requestKey,
            expectsPairedVideo: false,
            progressHandler: progressHandler
        ).analysisInput()
    }

    func loadedOriginal(
        source: DepthAnalysisSource,
        requestKey: MediaFetchRequestKey,
        expectsPairedVideo: Bool,
        resourceReadyHandler: @escaping @Sendable @MainActor (
            TAPPhotoOriginalResourceLease
        ) -> Void = { _ in },
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> LoadedOriginal {
        try await identifiedInputLoader(
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


@MainActor
final class DepthAnalysisCarouselStore: ObservableObject {
    @Published private(set) var currentItemID: String
    @Published private var removedEntryIDs: Set<String> = []

    let entries: [DepthAnalysisCarouselEntry]
    private let loader: DepthAnalysisProgressivePhotoLoader
    private var slots: [String: AnalysisPhotoSlot] = [:]
    private var retainedSlotStates: [String: AnalysisPhotoSlotRetainedState] = [:]

    init(
        source: DepthAnalysisSource,
        albumContext: DepthAnalysisAlbumContext? = nil,
        loader: DepthAnalysisProgressivePhotoLoader? = nil,
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()
    ) {
        if let albumContext, !albumContext.entries.isEmpty {
            self.entries = albumContext.entries.map(DepthAnalysisCarouselEntry.init(albumEntry:))
            self.currentItemID = albumContext.currentItemID
        } else {
            let entry = DepthAnalysisCarouselEntry(source: source)
            self.entries = [entry]
            self.currentItemID = entry.id
        }
        self.loader = loader ?? DepthAnalysisProgressivePhotoLoader(
            mediaFetcher: mediaFetcher
        )
    }

    private var activeEntries: [DepthAnalysisCarouselEntry] {
        entries.filter { !removedEntryIDs.contains($0.id) }
    }

    var currentIndex: Int? {
        activeEntries.firstIndex { $0.id == currentItemID }
    }

    var currentEntry: DepthAnalysisCarouselEntry? {
        let entries = activeEntries
        guard let currentIndex else {
            return entries.first
        }
        return entries[currentIndex]
    }

    var currentSlot: AnalysisPhotoSlot? {
        guard let currentEntry else {
            return nil
        }
        return slot(for: currentEntry)
    }

    var retainedSlotCount: Int {
        slots.count
    }

    func entry(offset: Int) -> DepthAnalysisCarouselEntry? {
        let entries = activeEntries
        guard let currentIndex else {
            return nil
        }
        let targetIndex = currentIndex + offset
        guard entries.indices.contains(targetIndex) else {
            return nil
        }
        return entries[targetIndex]
    }

    func windowEntries() -> [(offset: Int, entry: DepthAnalysisCarouselEntry)] {
        [-1, 0, 1].compactMap { offset in
            guard let entry = entry(offset: offset) else {
                return nil
            }
            return (offset, entry)
        }
    }

    func canMove(offset: Int) -> Bool {
        entry(offset: offset) != nil
    }

    @discardableResult
    func move(
        offset: Int,
        pixelLength: Int = 960,
        prewarmCurrentPlaneGeometry: Bool = false
    ) -> DepthAnalysisCarouselEntry? {
        guard abs(offset) == 1,
              let entry = entry(offset: offset) else {
            return nil
        }
        currentItemID = entry.id
        ensureVisibleWindowLoaded(
            pixelLength: pixelLength,
            prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry
        )
        return entry
    }

    @discardableResult
    func advanceAfterDeletingCurrent(
        pixelLength: Int = 960,
        prewarmCurrentPlaneGeometry: Bool = false
    ) -> DepthAnalysisCarouselEntry? {
        let entries = activeEntries
        let deletedIndex = entries.firstIndex { $0.id == currentItemID } ?? 0
        guard entries.indices.contains(deletedIndex) else {
            return nil
        }

        let deletedEntry = entries[deletedIndex]
        removedEntryIDs.insert(deletedEntry.id)
        discardSlot(id: deletedEntry.id)

        let remainingEntries = entries.filter { $0.id != deletedEntry.id }
        guard !remainingEntries.isEmpty else {
            currentItemID = ""
            pruneSlots(keeping: [])
            return nil
        }

        let nextIndex = min(deletedIndex, remainingEntries.count - 1)
        let nextEntry = remainingEntries[nextIndex]
        currentItemID = nextEntry.id
        ensureVisibleWindowLoaded(
            pixelLength: pixelLength,
            prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry
        )
        return nextEntry
    }

    func slot(for entry: DepthAnalysisCarouselEntry) -> AnalysisPhotoSlot {
        if let existing = slots[entry.id] {
            return existing
        }
        let retainedState = retainedSlotStates.removeValue(forKey: entry.id)
        let slot = AnalysisPhotoSlot(entry: entry, retainedState: retainedState)
        if let preview = TAPLibraryPagingPreviewCache.shared.image(for: entry.id) {
            slot.seedThumbnailIfEmpty(preview)
        }
        slots[entry.id] = slot
        return slot
    }

    func ensureVisibleWindowLoaded(
        pixelLength: Int = 960,
        prewarmCurrentPlaneGeometry: Bool = false
    ) {
        let window = windowEntries()
        let windowIDs = Set(window.map(\.entry.id))
        for item in window {
            let slot = slot(for: item.entry)
            if item.offset == 0 {
                // The current viewer item always resolves its original,
                // independent of RAW/2D/3D presentation. `ensureLoading`
                // starts the bounded display rendition first, then keeps that
                // preview visible while the original resource is fetched.
                slot.ensureLoading(
                    loader: loader,
                    pixelLength: pixelLength,
                    priority: .userInitiated,
                    prewarmPlaneGeometry: prewarmCurrentPlaneGeometry
                )
            } else {
                slot.prepareForAdjacentPreview()
                slot.ensureThumbnail(loader: loader, pixelLength: pixelLength)
            }
        }
        pruneSlots(keeping: windowIDs)
    }

    func cancelViewerRequests() {
        for slot in slots.values {
            slot.cancelCurrentMediaFetch()
        }
    }

    private func discardSlot(id: String) {
        retainedSlotStates.removeValue(forKey: id)
        guard let slot = slots.removeValue(forKey: id) else {
            return
        }
        slot.prepareForEviction()
    }

    private func pruneSlots(keeping retainedIDs: Set<String>) {
        let evictedIDs = slots.keys.filter { !retainedIDs.contains($0) }
        for id in evictedIDs {
            guard let slot = slots.removeValue(forKey: id) else {
                continue
            }
            retainedSlotStates[id] = slot.retainedStateForEviction()
            slot.prepareForEviction()
        }
    }
}
