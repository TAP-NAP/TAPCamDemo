//
//  DepthAnalysisCarouselState.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/7/5.
//

import Combine
import CoreGraphics
import Foundation
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

nonisolated struct DepthAnalysisProgressivePhotoLoader {
    typealias OriginalProgressHandler = @Sendable @MainActor (Double?) -> Void
    typealias ThumbnailLoader = @Sendable (DepthAnalysisSource, Int) async -> UIImage?
    typealias InputLoader = @Sendable (DepthAnalysisSource, @escaping OriginalProgressHandler) async throws -> TAPDepthAnalysisInput

    private let thumbnailLoader: ThumbnailLoader
    private let inputLoader: InputLoader

    init(
        thumbnailLoader: @escaping ThumbnailLoader = { source, pixelLength in
            await Self.defaultThumbnail(source: source, pixelLength: pixelLength)
        },
        inputLoader: @escaping InputLoader = { source, progressHandler in
            try await Self.defaultInput(source: source, progressHandler: progressHandler)
        }
    ) {
        self.thumbnailLoader = thumbnailLoader
        self.inputLoader = inputLoader
    }

    func thumbnail(source: DepthAnalysisSource, pixelLength: Int) async -> UIImage? {
        await thumbnailLoader(source, pixelLength)
    }

    func input(
        source: DepthAnalysisSource,
        progressHandler: @escaping OriginalProgressHandler
    ) async throws -> TAPDepthAnalysisInput {
        try await inputLoader(source, progressHandler)
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
            guard let data = try? await TAPPendingCaptureStore.shared.bestAvailablePhotoData(captureID: captureID) else {
                return nil
            }
            return UIImage(data: data)
        }
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

@MainActor
final class AnalysisPhotoSlot: ObservableObject, Identifiable {
    let entry: DepthAnalysisCarouselEntry

    @Published private(set) var phase: AnalysisSlotLoadPhase = .idle
    @Published private(set) var thumbnailImage: UIImage?
    @Published private(set) var input: TAPDepthAnalysisInput?
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorTitle = "Unable to analyze image"
    @Published private(set) var errorSystemImage = "exclamationmark.triangle"
    @Published var regionSelection = DepthAnalysisRegionSelectionState()
    @Published var planeSelection = DepthAnalysisPlaneSelectionState()

    private let planeRequestCoordinator: DepthAnalysisPlaneRegionRequestCoordinator
    private var thumbnailTask: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?

    var id: String { entry.id }
    var source: DepthAnalysisSource { entry.source }

    var isOriginalLoading: Bool {
        phase.isOriginalLoading
    }

    var loadProgress: Double? {
        if case .originalLoading(let progress) = phase {
            return progress
        }
        return nil
    }

    var hasDisplayImage: Bool {
        input != nil || thumbnailImage != nil
    }

    init(
        entry: DepthAnalysisCarouselEntry,
        planeRegionDetector: DepthAnalysisPlaneRegionDetector = DepthAnalysisPlaneRegionDetector()
    ) {
        self.entry = entry
        self.planeRequestCoordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: planeRegionDetector)
    }

    deinit {
        thumbnailTask?.cancel()
        inputTask?.cancel()
    }

    func ensureLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority
    ) {
        ensureThumbnailLoading(loader: loader, pixelLength: pixelLength)
        ensureInputLoading(loader: loader, priority: priority)
    }

    func clearSelection() {
        planeRequestCoordinator.cancelRegionRequest()
        regionSelection.clear()
        planeSelection.clear()
    }

    func selectPlaneSeed(_ depthPoint: CGPoint) {
        guard let input else {
            return
        }

        planeSelection.selectSeed(depthPoint, depthMap: input.depthMap)
        updateSeedPlaneRegion()
    }

    func updatePlaneGrowthStrictness(_ strictness: Double) {
        planeSelection.updateStrictness(strictness)
        if planeSelection.hasSeed {
            updateSeedPlaneRegion(debounceNanoseconds: 120_000_000)
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
            await MainActor.run {
                guard let self else {
                    return
                }
                self.thumbnailTask = nil
                guard let image else {
                    return
                }
                self.thumbnailImage = image
                if self.input == nil, case .idle = self.phase {
                    self.phase = .thumbnailReady
                }
            }
        }
    }

    private func ensureInputLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        priority: TaskPriority
    ) {
        guard input == nil, inputTask == nil else {
            return
        }

        let source = entry.source
        phase = .originalLoading(progress: nil)
        errorMessage = nil
        inputTask = Task(priority: priority) { [weak self] in
            do {
                let loadedInput = try await loader.input(source: source) { progress in
                    self?.phase = .originalLoading(progress: progress)
                }
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.inputTask = nil
                    self.input = loadedInput
                    self.phase = .analysisReady
                    self.clearLoadError()
                    self.regionSelection.clear()
                    self.planeSelection.cancelDetection()
                    self.planeRequestCoordinator.resetForNewInput()
                    self.planeRequestCoordinator.prewarmGeometry(for: loadedInput.depthMap)
                }
            } catch {
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

    private func applyLoadError(_ error: Error) {
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        errorTitle = presentation.title
        errorSystemImage = presentation.systemImage
        errorMessage = presentation.message
        phase = .failed
        planeRequestCoordinator.resetForNewInput()
        planeSelection.cancelDetection()
    }

    private func updateSeedPlaneRegion(debounceNanoseconds: UInt64 = 0) {
        guard let input, let planeSeedPoint = planeSelection.seedPoint else {
            planeRequestCoordinator.cancelRegionRequest()
            planeSelection.clearDetection()
            return
        }

        planeRequestCoordinator.requestRegion(
            depthMap: input.depthMap,
            seed: planeSeedPoint,
            strictness: planeSelection.strictness,
            debounceNanoseconds: debounceNanoseconds,
            eventHandler: { [weak self] event in
                self?.applyPlaneRequestEvent(event)
            }
        )
    }

    private func applyPlaneRequestEvent(_ event: DepthAnalysisPlaneRegionRequestEvent) {
        switch event {
        case .started:
            planeSelection.startDetection()
        case .succeeded(let detection):
            planeSelection.finishDetection(detection)
        case .failed(let error):
            planeSelection.finishFailure(error)
        case .cancelled:
            planeSelection.cancelDetection()
        }
    }
}

@MainActor
final class DepthAnalysisCarouselStore: ObservableObject {
    @Published private(set) var currentItemID: String

    let entries: [DepthAnalysisCarouselEntry]
    private let loader: DepthAnalysisProgressivePhotoLoader
    private var slots: [String: AnalysisPhotoSlot] = [:]

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
    func move(offset: Int) -> DepthAnalysisCarouselEntry? {
        guard abs(offset) == 1,
              let entry = entry(offset: offset) else {
            return nil
        }
        currentItemID = entry.id
        ensureVisibleWindowLoaded()
        return entry
    }

    func slot(for entry: DepthAnalysisCarouselEntry) -> AnalysisPhotoSlot {
        if let existing = slots[entry.id] {
            return existing
        }
        let slot = AnalysisPhotoSlot(entry: entry)
        slots[entry.id] = slot
        return slot
    }

    func ensureVisibleWindowLoaded(pixelLength: Int = 960) {
        for item in windowEntries() {
            let slot = slot(for: item.entry)
            slot.ensureLoading(
                loader: loader,
                pixelLength: pixelLength,
                priority: item.offset == 0 ? .userInitiated : .utility
            )
        }
    }
}
