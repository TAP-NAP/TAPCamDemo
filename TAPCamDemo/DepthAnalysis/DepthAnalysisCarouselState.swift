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
import Photos
import UIKit

nonisolated struct DepthAnalysisCarouselEntry: Identifiable, Equatable {
    let id: String
    let source: DepthAnalysisSource
    let albumEntry: DepthAnalysisAlbumContext.Entry?

    init(source: DepthAnalysisSource) {
        self.id = Self.id(for: source)
        self.source = source
        self.albumEntry = nil
    }

    init(albumEntry: DepthAnalysisAlbumContext.Entry) {
        self.id = albumEntry.id
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
    typealias ThumbnailLoader = @Sendable (DepthAnalysisSource, Int) async -> UIImage?
    typealias DisplayLoader = @Sendable (DepthAnalysisSource, Int) async throws -> AnalysisDisplayPhoto

    private let thumbnailLoader: ThumbnailLoader
    private let displayLoader: DisplayLoader

    init(
        thumbnailLoader: @escaping ThumbnailLoader = { source, pixelLength in
            await Self.defaultThumbnail(source: source, pixelLength: pixelLength)
        },
        displayLoader: @escaping DisplayLoader = { source, pixelLength in
            try await Self.defaultDisplayPhoto(source: source, pixelLength: pixelLength)
        }
    ) {
        self.thumbnailLoader = thumbnailLoader
        self.displayLoader = displayLoader
    }

    func thumbnail(source: DepthAnalysisSource, pixelLength: Int) async -> UIImage? {
        await thumbnailLoader(source, pixelLength)
    }

    func displayPhoto(source: DepthAnalysisSource, pixelLength: Int) async throws -> AnalysisDisplayPhoto {
        try await displayLoader(source, pixelLength)
    }

    private static func defaultThumbnail(
        source: DepthAnalysisSource,
        pixelLength: Int
    ) async -> UIImage? {
        switch source {
        case .photosAsset(let assetID):
            guard let asset = await photosAsset(localIdentifier: assetID) else {
                return nil
            }
            let cacheKey = DepthAlbumThumbnailCacheKey.make(for: asset, pixelLength: pixelLength)
            guard let data = await DepthAlbumThumbnailLoader.shared.data(
                for: asset,
                cacheKey: cacheKey,
                pixelLength: pixelLength
            ) else {
                return nil
            }
            return UIImage(data: data)
        case .pendingCapture(let captureID):
            let data: Data?
            if let thumbnailData = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: captureID) {
                data = thumbnailData
            } else {
                data = try? await TAPPendingCaptureStore.shared.bestAvailablePhotoData(captureID: captureID)
            }
            guard let data else {
                return nil
            }
            return UIImage(data: data)
        }
    }

    private static func defaultDisplayPhoto(
        source: DepthAnalysisSource,
        pixelLength: Int
    ) async throws -> AnalysisDisplayPhoto {
        switch source {
        case .photosAsset(let assetID):
            guard let asset = await photosAsset(localIdentifier: assetID),
                  let image = await requestDisplayImage(for: asset, pixelLength: pixelLength) else {
                throw TAPDepthCaptureError.assetNotFound
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

    private static func requestDisplayImage(for asset: PHAsset, pixelLength: Int) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let targetLength = max(pixelLength, 1)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetLength, height: targetLength),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !didResume else {
                    return
                }
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool == true
                if isDegraded {
                    return
                }
                if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }
                guard let image else {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }
                didResume = true
                continuation.resume(returning: image)
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

    private static func photosAsset(localIdentifier: String) async -> PHAsset? {
        await Task.detached(priority: .utility) {
            PhotoLibraryWriter.asset(localIdentifier: localIdentifier)
        }.value
    }
}

nonisolated struct DepthAnalysisProgressivePhotoLoader {
    typealias OriginalProgressHandler = @Sendable @MainActor (Double?) -> Void
    typealias ThumbnailLoader = DepthAnalysisDisplayPhotoLoader.ThumbnailLoader
    typealias DisplayLoader = DepthAnalysisDisplayPhotoLoader.DisplayLoader
    typealias InputLoader = @Sendable (DepthAnalysisSource, @escaping OriginalProgressHandler) async throws -> TAPDepthAnalysisInput

    private let displayPhotoLoader: DepthAnalysisDisplayPhotoLoader
    private let inputLoader: InputLoader

    init(
        thumbnailLoader: @escaping ThumbnailLoader = { source, pixelLength in
            await DepthAnalysisDisplayPhotoLoader().thumbnail(source: source, pixelLength: pixelLength)
        },
        displayLoader: @escaping DisplayLoader = { source, pixelLength in
            try await DepthAnalysisDisplayPhotoLoader().displayPhoto(source: source, pixelLength: pixelLength)
        },
        inputLoader: @escaping InputLoader = { source, progressHandler in
            try await Self.defaultInput(source: source, progressHandler: progressHandler)
        }
    ) {
        self.displayPhotoLoader = DepthAnalysisDisplayPhotoLoader(
            thumbnailLoader: thumbnailLoader,
            displayLoader: displayLoader
        )
        self.inputLoader = inputLoader
    }

    func thumbnail(source: DepthAnalysisSource, pixelLength: Int) async -> UIImage? {
        await displayPhotoLoader.thumbnail(source: source, pixelLength: pixelLength)
    }

    func displayPhoto(source: DepthAnalysisSource, pixelLength: Int) async throws -> AnalysisDisplayPhoto {
        try await displayPhotoLoader.displayPhoto(source: source, pixelLength: pixelLength)
    }

    func input(
        source: DepthAnalysisSource,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> TAPDepthAnalysisInput {
        try await inputLoader(source, progressHandler)
    }

    private static func defaultInput(
        source: DepthAnalysisSource,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> TAPDepthAnalysisInput {
        let data: Data
        switch source {
        case .photosAsset(let assetID):
            data = try await originalPhotoData(
                localIdentifier: assetID,
                progressHandler: progressHandler
            )
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

    private static func originalPhotoData(
        localIdentifier: String,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let asset = PhotoLibraryWriter.asset(localIdentifier: localIdentifier) else {
                throw TAPDepthCaptureError.assetNotFound
            }
            return try await originalPhotoData(for: asset, progressHandler: progressHandler)
        }.value
    }

    private static func originalPhotoData(
        for asset: PHAsset,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> Data {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.error("analysis originalPhotoData missing photo resource assetID=\(asset.localIdentifier, privacy: .private)")
            #endif
            throw TAPDepthCaptureError.assetCreationFailed
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("analysis originalPhotoData request start assetID=\(asset.localIdentifier, privacy: .private)")
        #endif
        return try await withCheckedThrowingContinuation { continuation in
            var result = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { progress in
                Task { @MainActor in
                    progressHandler(progress.isFinite ? progress : nil)
                }
            }

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    result.append(chunk)
                },
                completionHandler: { error in
                    if let error {
                        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                        TAPDiagnostics.photoLibrary.error("analysis originalPhotoData request failed assetID=\(asset.localIdentifier, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                        #endif
                        continuation.resume(throwing: error)
                    } else {
                        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                        TAPDiagnostics.photoLibrary.info("analysis originalPhotoData request success assetID=\(asset.localIdentifier, privacy: .private) bytes=\(result.count, privacy: .public)")
                        #endif
                        continuation.resume(returning: result)
                    }
                }
            )
        }
    }

    private static func photosAsset(localIdentifier: String) async -> PHAsset? {
        await Task.detached(priority: .utility) {
            PhotoLibraryWriter.asset(localIdentifier: localIdentifier)
        }.value
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
    }

    func ensureLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority,
        prewarmPlaneGeometry: Bool = false
    ) {
        ensureDisplayPhoto(loader: loader, pixelLength: pixelLength, priority: priority)
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
        ensureThumbnail(loader: loader, pixelLength: pixelLength)
        ensureDisplayPhotoLoading(loader: loader, pixelLength: pixelLength, priority: priority)
    }

    func retainedStateForEviction() -> AnalysisPhotoSlotRetainedState {
        var retainedPlaneSelection = planeSelection
        retainedPlaneSelection.cancelDetection()
        return AnalysisPhotoSlotRetainedState(planeSelection: retainedPlaneSelection)
    }

    func prepareForEviction() {
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
        errorMessage = nil
        wantsPlaneGeometryPrewarm = false
        hasRequestedPlaneGeometryPrewarm = false
        regionSelection.clear()
        planeSelection.cancelDetection()
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
        displayPhase = .displayLoading
        errorMessage = nil
        displayTaskPixelLength = pixelLength
        displayTask = Task(priority: priority) { [weak self] in
            do {
                let loadedDisplayPhoto = try await loader.displayPhoto(source: source, pixelLength: pixelLength)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.displayTask = nil
                    self.displayTaskPixelLength = nil
                    self.displayPhoto = loadedDisplayPhoto
                    self.displayPhase = .displayReady
                    self.clearLoadErrorIfAnalysisIsHealthy()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self?.displayTask = nil
                        self?.displayTaskPixelLength = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self else {
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
        analysisPhase = .loading(progress: nil)
        errorMessage = nil
        inputTask = Task(priority: priority) { [weak self] in
            do {
                let loadedInput = try await loader.input(source: source) { progress in
                    self?.analysisPhase = .loading(progress: progress)
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self?.inputTask = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.inputTask = nil
                    self.input = loadedInput
                    self.analysisPhase = .ready
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
                        self?.inputTask = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self else {
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
    }

    private func applyLoadError(_ error: Error) {
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        errorTitle = presentation.title
        errorSystemImage = presentation.systemImage
        errorMessage = presentation.message
        analysisPhase = .failed
        planeRequestCoordinator.resetForNewInput()
        planeSelection.cancelDetection()
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

    let entries: [DepthAnalysisCarouselEntry]
    private let loader: DepthAnalysisProgressivePhotoLoader
    private var slots: [String: AnalysisPhotoSlot] = [:]
    private var retainedSlotStates: [String: AnalysisPhotoSlotRetainedState] = [:]

    init(
        source: DepthAnalysisSource,
        albumContext: DepthAnalysisAlbumContext? = nil,
        loader: DepthAnalysisProgressivePhotoLoader = DepthAnalysisProgressivePhotoLoader()
    ) {
        if let albumContext, !albumContext.entries.isEmpty {
            self.entries = albumContext.entries.map(DepthAnalysisCarouselEntry.init(albumEntry:))
            self.currentItemID = albumContext.currentItemID
        } else {
            let entry = DepthAnalysisCarouselEntry(source: source)
            self.entries = [entry]
            self.currentItemID = entry.id
        }
        self.loader = loader
    }

    var currentIndex: Int? {
        entries.firstIndex { $0.id == currentItemID }
    }

    var currentEntry: DepthAnalysisCarouselEntry? {
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
        loadCurrentAnalysis: Bool = false,
        prewarmCurrentPlaneGeometry: Bool = false
    ) -> DepthAnalysisCarouselEntry? {
        guard abs(offset) == 1,
              let entry = entry(offset: offset) else {
            return nil
        }
        currentItemID = entry.id
        ensureVisibleWindowLoaded(
            pixelLength: pixelLength,
            loadCurrentAnalysis: loadCurrentAnalysis,
            prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry
        )
        return entry
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
        loadCurrentAnalysis: Bool = false,
        prewarmCurrentPlaneGeometry: Bool = false
    ) {
        let window = windowEntries()
        let windowIDs = Set(window.map(\.entry.id))
        for item in window {
            let slot = slot(for: item.entry)
            if item.offset == 0 {
                slot.ensureDisplayPhoto(
                    loader: loader,
                    pixelLength: pixelLength,
                    priority: .userInitiated
                )
                if loadCurrentAnalysis {
                    slot.ensureLoading(
                        loader: loader,
                        pixelLength: pixelLength,
                        priority: .userInitiated,
                        prewarmPlaneGeometry: prewarmCurrentPlaneGeometry
                    )
                }
            } else {
                slot.ensureDisplayPhoto(
                    loader: loader,
                    pixelLength: pixelLength,
                    priority: .utility
                )
            }
        }
        pruneSlots(keeping: windowIDs)
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
