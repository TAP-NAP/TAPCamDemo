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
    private typealias IdentifiedInputLoader = @Sendable (
        DepthAnalysisSource,
        MediaFetchRequestKey,
        @escaping OriginalProgressHandler
    ) async throws -> TAPDepthAnalysisInput

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
            self.identifiedInputLoader = { source, _, progressHandler in
                try await inputLoader(source, progressHandler)
            }
        } else {
            self.identifiedInputLoader = { source, requestKey, progressHandler in
                try await Self.defaultInput(
                    source: source,
                    requestKey: requestKey,
                    mediaFetcher: mediaFetcher,
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
        try await identifiedInputLoader(source, requestKey, progressHandler)
    }

    private static func defaultInput(
        source: DepthAnalysisSource,
        requestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> TAPDepthAnalysisInput {
        let data: Data
        switch source {
        case .photosAsset(let assetID):
            let request = LibraryMediaAssetRequest(
                key: requestKey,
                assetLocalIdentifier: assetID
            )
            data = try await mediaFetcher.photoOriginalData(
                for: request
            ) { progress in
                Task { @MainActor in
                    progressHandler(progress)
                }
            }
        case .pendingCapture(let captureID):
            do {
                data = try await TAPPendingCaptureStore.shared.bestAvailablePhotoData(captureID: captureID)
            } catch {
                NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
                throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
            }
        }

        try TAPDepthAnalysisInputValidation.validateHEICByteCount(data.count)
        return try TAPDepthMapReader.analysisInput(from: data)
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

nonisolated struct AnalysisPhotoSlotRetainedState {
    var planeSelection: DepthAnalysisPlaneSelectionState
}

@MainActor
final class AnalysisPhotoSlot: ObservableObject, Identifiable {
    let entry: DepthAnalysisCarouselEntry

    @Published private(set) var displayPhase: AnalysisPhotoDisplayPhase = .idle
    @Published private(set) var analysisPhase: AnalysisPhotoAnalysisPhase = .idle
    @Published private(set) var thumbnailImage: UIImage?
    @Published private(set) var displayPhoto: AnalysisDisplayPhoto?
    @Published private(set) var input: TAPDepthAnalysisInput?
    @Published private(set) var mediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorTitle = "Unable to analyze image"
    @Published private(set) var errorSystemImage = "exclamationmark.triangle"
    @Published var regionSelection = DepthAnalysisRegionSelectionState()
    @Published var planeSelection = DepthAnalysisPlaneSelectionState()

    private let planeRequestCoordinator: DepthAnalysisPlaneRegionRequestCoordinator
    private var thumbnailTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var displayTaskPixelLength: Int?
    private var inputTask: Task<Void, Never>?
    private var wantsPlaneGeometryPrewarm = false
    private var hasRequestedPlaneGeometryPrewarm = false
    private var fetchGeneration: UInt64 = 0
    private var activeRequestKey: MediaFetchRequestKey?
    private var originalMediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)
    private var livePhotoFetchGeneration: UInt64 = 0
    private var activeLivePhotoRequestKey: MediaFetchRequestKey?
    private var livePhotoMediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)
    private var cancelLivePhotoFetchAction: (() -> Void)?
    private var retryLivePhotoFetchAction: (() -> Void)?
    private var lastLoader: DepthAnalysisProgressivePhotoLoader?
    private var lastPixelLength = 960
    private var lastPriority: TaskPriority = .userInitiated
    private var lastRequestedAnalysis = false
    private var lastRequestedPlaneGeometryPrewarm = false

    var id: String { entry.id }
    var source: DepthAnalysisSource { entry.source }

    var phase: AnalysisSlotLoadPhase {
        if case .failed = analysisPhase {
            return .failed
        }
        if case .failed = displayPhase {
            return .failed
        }
        if case .ready = analysisPhase {
            return .analysisReady
        }
        if case .loading(let progress) = analysisPhase {
            return .originalLoading(progress: progress)
        }
        switch displayPhase {
        case .idle:
            return .idle
        case .thumbnailReady:
            return .thumbnailReady
        case .displayLoading:
            return .originalLoading(progress: nil)
        case .displayReady:
            return .thumbnailReady
        case .failed:
            return .failed
        }
    }

    var isOriginalLoading: Bool {
        analysisPhase.isLoading || displayPhase == .displayLoading
    }

    var loadProgress: Double? {
        if case .loading(let progress) = analysisPhase {
            return progress
        }
        return nil
    }

    var hasDisplayImage: Bool {
        displayPhoto != nil || input != nil || thumbnailImage != nil
    }

    init(
        entry: DepthAnalysisCarouselEntry,
        retainedState: AnalysisPhotoSlotRetainedState? = nil,
        planeRegionDetector: DepthAnalysisPlaneRegionDetector = DepthAnalysisPlaneRegionDetector()
    ) {
        self.entry = entry
        self.planeRequestCoordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: planeRegionDetector)
        if let retainedState {
            self.planeSelection = retainedState.planeSelection
            self.planeSelection.cancelDetection()
        }
    }

    deinit {
        thumbnailTask?.cancel()
        displayTask?.cancel()
        inputTask?.cancel()
        cancelLivePhotoFetchAction?()
    }

    func ensureLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority,
        prewarmPlaneGeometry: Bool = false
    ) {
        ensureDisplayPhoto(loader: loader, pixelLength: pixelLength, priority: priority)
        lastRequestedAnalysis = true
        lastRequestedPlaneGeometryPrewarm = prewarmPlaneGeometry
        ensureInputLoading(
            loader: loader,
            priority: priority,
            prewarmPlaneGeometry: prewarmPlaneGeometry
        )
    }

    func ensureThumbnail(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int
    ) {
        ensureThumbnailLoading(loader: loader, pixelLength: pixelLength)
    }

    func ensureDisplayPhoto(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority
    ) {
        lastLoader = loader
        lastPixelLength = pixelLength
        lastPriority = priority
        lastRequestedAnalysis = false
        lastRequestedPlaneGeometryPrewarm = false
        ensureThumbnail(loader: loader, pixelLength: pixelLength)
        ensureDisplayPhotoLoading(loader: loader, pixelLength: pixelLength, priority: priority)
    }

    func cancelCurrentMediaFetch() {
        cancelLivePhotoFetch(preserveCloudState: true, invokesCancellationAction: true)
        cancelOriginalTasks(preserveCloudState: true)
    }

    func retryLastMediaFetch() {
        let livePhotoRetryAction = retryLivePhotoFetchAction
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        cancelOriginalTasks(preserveCloudState: false)
        if let lastLoader {
            if lastRequestedAnalysis {
                ensureLoading(
                    loader: lastLoader,
                    pixelLength: lastPixelLength,
                    priority: lastPriority,
                    prewarmPlaneGeometry: lastRequestedPlaneGeometryPrewarm
                )
            } else {
                ensureDisplayPhoto(
                    loader: lastLoader,
                    pixelLength: lastPixelLength,
                    priority: lastPriority
                )
            }
        }
        livePhotoRetryAction?()
    }

    func prepareForAdjacentPreview() {
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        cancelOriginalTasks(preserveCloudState: true)
        // A previously-current item may hold the full decoded RGB/depth input.
        // Once it becomes adjacent, retain only its bounded display/thumbnail
        // preview so the three-slot carousel cannot accumulate full originals.
        input = nil
        analysisPhase = .idle
        planeRequestCoordinator.cancelRegionRequest()
        planeRequestCoordinator.resetForNewInput()
        hasRequestedPlaneGeometryPrewarm = false
    }

    func retainedStateForEviction() -> AnalysisPhotoSlotRetainedState {
        var retainedPlaneSelection = planeSelection
        retainedPlaneSelection.cancelDetection()
        return AnalysisPhotoSlotRetainedState(planeSelection: retainedPlaneSelection)
    }

    func prepareForEviction() {
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        thumbnailTask?.cancel()
        thumbnailTask = nil
        displayTask?.cancel()
        displayTask = nil
        displayTaskPixelLength = nil
        inputTask?.cancel()
        inputTask = nil
        planeRequestCoordinator.cancelRegionRequest()
        planeRequestCoordinator.resetForNewInput()
        thumbnailImage = nil
        displayPhoto = nil
        input = nil
        displayPhase = .idle
        analysisPhase = .idle
        activeRequestKey = nil
        fetchGeneration &+= 1
        originalMediaFetchPhase = .idle(false)
        livePhotoMediaFetchPhase = .idle(false)
        mediaFetchPhase = .idle(false)
        errorMessage = nil
        wantsPlaneGeometryPrewarm = false
        hasRequestedPlaneGeometryPrewarm = false
        regionSelection.clear()
        planeSelection.cancelDetection()
    }

    /// Registers the Live Photo request as a slot-owned fetch. The returned
    /// key is the only identity accepted by later progress/result callbacks.
    func beginLivePhotoFetch(
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) -> MediaFetchRequestKey {
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        livePhotoFetchGeneration &+= 1
        let requestKey = MediaFetchRequestKey(
            itemID: entry.mediaID,
            generation: livePhotoFetchGeneration,
            purpose: .livePhotoPlayback
        )
        activeLivePhotoRequestKey = requestKey
        cancelLivePhotoFetchAction = onCancel
        retryLivePhotoFetchAction = onRetry
        livePhotoMediaFetchPhase = hasDisplayImage ? .localPreview(true) : .idle(false)
        refreshMediaFetchPhase()
        return requestKey
    }

    func markLivePhotoFetchResolving(requestKey: MediaFetchRequestKey) {
        guard activeLivePhotoRequestKey == requestKey else {
            return
        }
        livePhotoMediaFetchPhase = .resolving(hasDisplayImage)
        refreshMediaFetchPhase()
    }

    func applyLivePhotoICloudProgress(
        _ progress: Double?,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeLivePhotoRequestKey == requestKey else {
            return
        }
        livePhotoMediaFetchPhase = .downloadingFromICloud(
            hasDisplayImage,
            progress: progress.map { min(max($0, 0), 1) }
        )
        refreshMediaFetchPhase()
    }

    func completeLivePhotoFetch(requestKey: MediaFetchRequestKey) {
        guard activeLivePhotoRequestKey == requestKey else {
            return
        }
        activeLivePhotoRequestKey = nil
        cancelLivePhotoFetchAction = nil
        retryLivePhotoFetchAction = nil
        livePhotoMediaFetchPhase = .ready(true)
        refreshMediaFetchPhase()
    }

    func failLivePhotoFetch(
        _ error: Error,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeLivePhotoRequestKey == requestKey else {
            return
        }
        guard !(error is CancellationError) else {
            cancelLivePhotoFetch(
                requestKey: requestKey,
                preserveCloudState: false
            )
            return
        }
        let failure = mediaFetchFailure(for: error)
        activeLivePhotoRequestKey = nil
        cancelLivePhotoFetchAction = nil
        livePhotoMediaFetchPhase = .failed(
            hasDisplayImage,
            reason: failure,
            retryable: failure.isRetryable
        )
        refreshMediaFetchPhase()
    }

    /// Called by the UIKit coordinator after it has cancelled its concrete
    /// PhotoKit/PHLivePhoto request. Stale coordinators cannot clear a newer
    /// request because the full request key must still match.
    func cancelLivePhotoFetch(
        requestKey: MediaFetchRequestKey,
        preserveCloudState: Bool
    ) {
        guard activeLivePhotoRequestKey == requestKey else {
            return
        }
        cancelLivePhotoFetch(
            preserveCloudState: preserveCloudState,
            invokesCancellationAction: false
        )
    }

    func clearSelection() {
        planeRequestCoordinator.cancelRegionRequest()
        regionSelection.clear()
        planeSelection.clear()
    }

    func dismissCompletedGridToast(_ toastID: UUID) {
        planeSelection.dismissCompletedGridToast(toastID)
    }

    func selectPlaneSeed(_ depthPoint: CGPoint, strictness: Double? = nil) {
        guard let input else {
            return
        }

        if let strictness {
            planeSelection.updateStrictness(strictness)
        }
        let generationID = planeSelection.selectSeed(depthPoint, depthMap: input.depthMap)
        updateSeedPlaneRegion(generationID: generationID)
    }

    func updatePlaneGrowthStrictness(_ strictness: Double) {
        planeSelection.updateStrictness(strictness)
        if planeSelection.hasSeed {
            updateSeedPlaneRegion(
                generationID: planeSelection.generationID,
                debounceNanoseconds: 120_000_000
            )
        }
    }

    private func ensureThumbnailLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int
    ) {
        guard thumbnailImage == nil, thumbnailTask == nil else {
            return
        }

        let source = entry.source
        thumbnailTask = Task(priority: .utility) { [weak self] in
            let image = await loader.thumbnail(source: source, pixelLength: pixelLength)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                self.thumbnailTask = nil
                guard let image else {
                    return
                }
                self.thumbnailImage = image
                self.refreshMediaFetchPhase()
                if self.displayPhoto == nil, case .idle = self.displayPhase {
                    self.displayPhase = .thumbnailReady
                }
            }
        }
    }

    private func ensureDisplayPhotoLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority
    ) {
        if displayPhoto != nil || displayTask != nil {
            if let displayPhoto,
               displayPhoto.requestedPixelLength >= Int(Double(pixelLength) * 0.9) {
                return
            }
            if let displayTaskPixelLength,
               displayTaskPixelLength >= Int(Double(pixelLength) * 0.9) {
                return
            }
            displayTask?.cancel()
            displayTask = nil
            displayTaskPixelLength = nil
        }

        let source = entry.source
        let requestKey = currentOrNewRequestKey()
        displayPhase = .displayLoading
        setOriginalMediaFetchPhase(.resolving(hasDisplayImage))
        errorMessage = nil
        displayTaskPixelLength = pixelLength
        displayTask = Task(priority: priority) { [weak self] in
            do {
                let loadedDisplayPhoto = try await loader.displayPhoto(
                    source: source,
                    pixelLength: pixelLength,
                    requestKey: requestKey
                ) { [weak self] progress in
                    self?.applyICloudProgress(progress, requestKey: requestKey)
                }
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeRequestKey == requestKey else {
                        return
                    }
                    self.displayTask = nil
                    self.displayTaskPixelLength = nil
                    self.displayPhoto = loadedDisplayPhoto
                    self.displayPhase = .displayReady
                    // A display-sized preview finishing must not hide the
                    // explicit iCloud state while the analysis original is
                    // still downloading.
                    if self.inputTask == nil {
                        self.setOriginalMediaFetchPhase(.ready(true))
                    } else {
                        self.markDisplayPreviewAvailableDuringOriginalFetch()
                    }
                    self.clearLoadErrorIfAnalysisIsHealthy()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard let self,
                              self.activeRequestKey == requestKey else {
                            return
                        }
                        self.displayTask = nil
                        self.displayTaskPixelLength = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeRequestKey == requestKey else {
                        return
                    }
                    self.displayTask = nil
                    self.displayTaskPixelLength = nil
                    self.applyDisplayLoadError(error)
                }
            }
        }
    }

    private func ensureInputLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        priority: TaskPriority,
        prewarmPlaneGeometry: Bool
    ) {
        if prewarmPlaneGeometry {
            wantsPlaneGeometryPrewarm = true
        }
        if let input {
            ensurePlaneGeometryPrewarmIfNeeded(for: input.depthMap)
        }
        guard input == nil, inputTask == nil else {
            return
        }

        let source = entry.source
        let requestKey = currentOrNewRequestKey()
        analysisPhase = .loading(progress: nil)
        if case .downloadingFromICloud = originalMediaFetchPhase {
            // Preserve the explicit iCloud state supplied by the display request.
        } else {
            setOriginalMediaFetchPhase(.resolving(hasDisplayImage))
        }
        errorMessage = nil
        inputTask = Task(priority: priority) { [weak self] in
            do {
                let loadedInput = try await loader.input(
                    source: source,
                    requestKey: requestKey
                ) { progress in
                    guard self?.activeRequestKey == requestKey else {
                        return
                    }
                    self?.analysisPhase = .loading(progress: progress)
                    self?.applyICloudProgress(progress, requestKey: requestKey)
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard let self,
                              self.activeRequestKey == requestKey else {
                            return
                        }
                        self.inputTask = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeRequestKey == requestKey else {
                        return
                    }
                    self.inputTask = nil
                    self.input = loadedInput
                    self.analysisPhase = .ready
                    self.setOriginalMediaFetchPhase(.ready(true))
                    self.clearLoadError()
                    self.regionSelection.clear()
                    self.planeSelection.cancelDetection()
                    self.planeRequestCoordinator.resetForNewInput()
                    self.hasRequestedPlaneGeometryPrewarm = false
                    self.ensurePlaneGeometryPrewarmIfNeeded(for: loadedInput.depthMap)
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard let self,
                              self.activeRequestKey == requestKey else {
                            return
                        }
                        self.inputTask = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeRequestKey == requestKey else {
                        return
                    }
                    self.inputTask = nil
                    self.applyLoadError(error)
                }
            }
        }
    }

    private func clearLoadError() {
        errorMessage = nil
        errorTitle = "Unable to analyze image"
        errorSystemImage = "exclamationmark.triangle"
    }

    private func clearLoadErrorIfAnalysisIsHealthy() {
        guard analysisPhase != .failed else {
            return
        }
        clearLoadError()
    }

    private func applyDisplayLoadError(_ error: Error) {
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        errorTitle = presentation.title
        errorSystemImage = presentation.systemImage
        errorMessage = presentation.message
        displayPhase = .failed
        applyMediaFetchFailure(error)
    }

    private func applyLoadError(_ error: Error) {
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        errorTitle = presentation.title
        errorSystemImage = presentation.systemImage
        errorMessage = presentation.message
        analysisPhase = .failed
        applyMediaFetchFailure(error)
        planeRequestCoordinator.resetForNewInput()
        planeSelection.cancelDetection()
    }

    private func currentOrNewRequestKey() -> MediaFetchRequestKey {
        if let activeRequestKey {
            return activeRequestKey
        }
        fetchGeneration &+= 1
        let requestKey = MediaFetchRequestKey(
            itemID: entry.mediaID,
            generation: fetchGeneration,
            purpose: .photoOriginal
        )
        activeRequestKey = requestKey
        return requestKey
    }

    private func applyICloudProgress(
        _ progress: Double?,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeRequestKey == requestKey else {
            return
        }
        setOriginalMediaFetchPhase(.downloadingFromICloud(
            hasDisplayImage,
            progress: progress.map { min(max($0, 0), 1) }
        ))
    }

    private func markDisplayPreviewAvailableDuringOriginalFetch() {
        originalMediaFetchPhase = phaseWithCurrentPreview(originalMediaFetchPhase)
        refreshMediaFetchPhase()
    }

    private func applyMediaFetchFailure(_ error: Error) {
        if error is CancellationError {
            return
        }
        let failure = mediaFetchFailure(for: error)
        setOriginalMediaFetchPhase(.failed(
            hasDisplayImage,
            reason: failure,
            retryable: failure.isRetryable
        ))
    }

    private func cancelOriginalTasks(preserveCloudState: Bool) {
        let wasCloudFetch: Bool
        switch originalMediaFetchPhase {
        case .cloudOnly, .downloadingFromICloud:
            wasCloudFetch = true
        default:
            wasCloudFetch = false
        }
        activeRequestKey = nil
        fetchGeneration &+= 1
        displayTask?.cancel()
        displayTask = nil
        displayTaskPixelLength = nil
        inputTask?.cancel()
        inputTask = nil
        if displayPhoto == nil {
            displayPhase = thumbnailImage == nil ? .idle : .thumbnailReady
        }
        if input == nil {
            analysisPhase = .idle
        }
        if preserveCloudState, wasCloudFetch {
            setOriginalMediaFetchPhase(.cloudOnly(hasDisplayImage))
        } else if hasDisplayImage {
            setOriginalMediaFetchPhase(.localPreview(true))
        } else {
            setOriginalMediaFetchPhase(.idle(false))
        }
    }

    private func cancelLivePhotoFetch(
        preserveCloudState: Bool,
        invokesCancellationAction: Bool
    ) {
        let wasCloudFetch: Bool
        switch livePhotoMediaFetchPhase {
        case .cloudOnly, .downloadingFromICloud:
            wasCloudFetch = true
        default:
            wasCloudFetch = false
        }
        let cancellationAction = cancelLivePhotoFetchAction
        activeLivePhotoRequestKey = nil
        livePhotoFetchGeneration &+= 1
        cancelLivePhotoFetchAction = nil
        if !preserveCloudState {
            retryLivePhotoFetchAction = nil
        }
        if preserveCloudState, wasCloudFetch {
            livePhotoMediaFetchPhase = .cloudOnly(hasDisplayImage)
        } else if hasDisplayImage {
            livePhotoMediaFetchPhase = .localPreview(true)
        } else {
            livePhotoMediaFetchPhase = .idle(false)
        }
        refreshMediaFetchPhase()
        if invokesCancellationAction {
            cancellationAction?()
        }
    }

    private func setOriginalMediaFetchPhase(_ phase: MediaFetchPhase<Bool, Bool>) {
        originalMediaFetchPhase = phase
        refreshMediaFetchPhase()
    }

    private func refreshMediaFetchPhase() {
        let originalPhase = phaseWithCurrentPreview(originalMediaFetchPhase)
        let livePhotoPhase = phaseWithCurrentPreview(livePhotoMediaFetchPhase)

        switch originalPhase {
        case .failed, .downloadingFromICloud, .cloudOnly:
            mediaFetchPhase = originalPhase
        case .resolving:
            if case .downloadingFromICloud = livePhotoPhase {
                mediaFetchPhase = livePhotoPhase
            } else {
                mediaFetchPhase = originalPhase
            }
        case .idle, .localPreview, .ready:
            switch livePhotoPhase {
            case .failed, .downloadingFromICloud, .cloudOnly, .resolving:
                mediaFetchPhase = livePhotoPhase
            case .idle, .localPreview, .ready:
                mediaFetchPhase = originalPhase
            }
        }
    }

    private func phaseWithCurrentPreview(
        _ phase: MediaFetchPhase<Bool, Bool>
    ) -> MediaFetchPhase<Bool, Bool> {
        switch phase {
        case .idle:
            return .idle(hasDisplayImage)
        case .resolving:
            return .resolving(hasDisplayImage)
        case .localPreview:
            return hasDisplayImage ? .localPreview(true) : .idle(false)
        case .cloudOnly:
            return .cloudOnly(hasDisplayImage)
        case .downloadingFromICloud(_, let progress):
            return .downloadingFromICloud(hasDisplayImage, progress: progress)
        case .ready(let value):
            return .ready(value)
        case .failed(_, let reason, let retryable):
            return .failed(
                hasDisplayImage,
                reason: reason,
                retryable: retryable
            )
        }
    }

    private func mediaFetchFailure(for error: Error) -> MediaFetchFailure {
        (error as? MediaFetchFailure) ?? .decode
    }

    private func ensurePlaneGeometryPrewarmIfNeeded(for depthMap: TAPMetricDepthMap) {
        guard wantsPlaneGeometryPrewarm, !hasRequestedPlaneGeometryPrewarm else {
            return
        }
        hasRequestedPlaneGeometryPrewarm = true
        planeRequestCoordinator.prewarmGeometry(for: depthMap)
    }

    private func updateSeedPlaneRegion(
        generationID: Int,
        debounceNanoseconds: UInt64 = 0
    ) {
        guard let input, let planeSeedPoint = planeSelection.seedPoint else {
            planeRequestCoordinator.cancelRegionRequest()
            planeSelection.clearDetection()
            return
        }

        planeRequestCoordinator.requestRegion(
            depthMap: input.depthMap,
            seed: planeSeedPoint,
            strictness: planeSelection.strictness,
            generationID: generationID,
            debounceNanoseconds: debounceNanoseconds,
            eventHandler: { [weak self] event in
                self?.applyPlaneRequestEvent(event)
            }
        )
    }

    private func applyPlaneRequestEvent(_ event: DepthAnalysisPlaneRegionRequestEvent) {
        switch event {
        case .started(let generationID):
            planeSelection.startDetection(generationID: generationID)
        case .partial(let progress, let generationID):
            planeSelection.applyPartialGrid(progress, generationID: generationID)
        case .succeeded(let detection, let generationID):
            planeSelection.finishDetection(detection, generationID: generationID)
        case .failed(let error, let generationID):
            planeSelection.finishFailure(error, generationID: generationID)
        case .cancelled(let generationID):
            planeSelection.cancelDetection(generationID: generationID)
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
