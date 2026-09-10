//
//  LibraryMediaStore.swift
//  TAPCamDemo
//

import Foundation
import Observation
import Photos

/// The one ordered Library snapshot consumed by the grid and camera cover.
@MainActor
@Observable
final class LibraryMediaStore: NSObject, PHPhotoLibraryChangeObserver {
    typealias SnapshotLoader = @MainActor () async throws -> DepthAlbumItemSnapshot

    private(set) var snapshot: LibraryMediaSnapshot = .empty
    private(set) var items: [TAPLibraryItem] = []
    private(set) var photoAssetsError: Error?
    private(set) var loadError: Error?
    private(set) var isRefreshing = false

    @ObservationIgnored
    private let snapshotLoader: SnapshotLoader
    @ObservationIgnored
    private let notificationCenter: NotificationCenter
    @ObservationIgnored
    private var refreshGeneration: UInt64 = 0
    @ObservationIgnored
    private var inFlightRefreshTask: Task<DepthAlbumItemSnapshot?, Never>?
    @ObservationIgnored
    private var scheduledRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var libraryChangeObserver: NSObjectProtocol?
    @ObservationIgnored
    private(set) var isObservingChanges = false
    @ObservationIgnored
    private let registerPhotoLibraryChangeObserver: (any PHPhotoLibraryChangeObserver) -> Void
    @ObservationIgnored
    private let unregisterPhotoLibraryChangeObserver: (any PHPhotoLibraryChangeObserver) -> Void

    init(
        itemProvider: DepthAlbumItemProvider? = nil,
        photoCatalog: PhotoKitLibraryMediaFetcher? = nil,
        notificationCenter: NotificationCenter = .default,
        observesChanges: Bool = false,
        registerPhotoLibraryChangeObserver: @escaping (any PHPhotoLibraryChangeObserver) -> Void = {
            PHPhotoLibrary.shared().register($0)
        },
        unregisterPhotoLibraryChangeObserver: @escaping (any PHPhotoLibraryChangeObserver) -> Void = {
            PHPhotoLibrary.shared().unregisterChangeObserver($0)
        }
    ) {
        let provider = itemProvider ?? DepthAlbumItemProvider(
            photoCatalog: photoCatalog ?? PhotoKitLibraryMediaFetcher()
        )
        self.snapshotLoader = {
            try await provider.loadSnapshot()
        }
        self.notificationCenter = notificationCenter
        self.registerPhotoLibraryChangeObserver = registerPhotoLibraryChangeObserver
        self.unregisterPhotoLibraryChangeObserver = unregisterPhotoLibraryChangeObserver
        super.init()

        if observesChanges {
            startObservingChangesIfNeeded()
        }
    }

    /// Activates both TAP Library notifications and PhotoKit observation as one
    /// idempotent boundary. Startup owns when this becomes eligible.
    @discardableResult
    func startObservingChangesIfNeeded() -> Bool {
        guard !isObservingChanges else {
            return false
        }

        libraryChangeObserver = notificationCenter.addObserver(
            forName: .tapLibraryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.isObservingChanges == true else { return }
                self?.scheduleRefresh()
            }
        }
        registerPhotoLibraryChangeObserver(self)
        isObservingChanges = true
        return true
    }

    @discardableResult
    func stopObservingChangesIfNeeded() -> Bool {
        guard isObservingChanges else {
            return false
        }

        cancelRefresh()
        if let libraryChangeObserver {
            notificationCenter.removeObserver(libraryChangeObserver)
            self.libraryChangeObserver = nil
        }
        unregisterPhotoLibraryChangeObserver(self)
        isObservingChanges = false
        return true
    }

    deinit {
        inFlightRefreshTask?.cancel()
        scheduledRefreshTask?.cancel()
        if let libraryChangeObserver {
            notificationCenter.removeObserver(libraryChangeObserver)
        }
        if isObservingChanges {
            unregisterPhotoLibraryChangeObserver(self)
        }
    }

    var latestItem: TAPLibraryItem? {
        items.first
    }

    var hasUsableSnapshot: Bool {
        snapshot.revision > 0 && loadError == nil && photoAssetsError == nil
    }

    /// Starts a new snapshot generation. Only the newest generation may
    /// publish, so a slow Photos callback cannot restore a deleted or
    /// superseded item.
    @discardableResult
    func refresh() async -> DepthAlbumItemSnapshot? {
        await startRefresh()
    }

    /// Shares the current load when multiple UI surfaces request the same
    /// catalog at once. Callers that intentionally need a newer generation use
    /// `refresh()` instead.
    @discardableResult
    func refreshSharingInFlightLoad() async -> DepthAlbumItemSnapshot? {
        if let inFlightRefreshTask {
            return await inFlightRefreshTask.value
        }

        return await startRefresh()
    }

    /// Returns the current observer-maintained snapshot without rescanning
    /// PhotoKit. A missing or failed snapshot joins the current load or starts
    /// one; explicit change notifications continue to use `refresh()`.
    @discardableResult
    func cachedSnapshotOrRefresh() async -> DepthAlbumItemSnapshot? {
        if hasUsableSnapshot {
            return DepthAlbumItemSnapshot(
                items: items,
                summaries: snapshot.items,
                photoAssetsError: photoAssetsError
            )
        }

        return await refreshSharingInFlightLoad()
    }

    private func startRefresh() async -> DepthAlbumItemSnapshot? {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isRefreshing = true

        let task = Task<DepthAlbumItemSnapshot?, Never> { @MainActor [weak self] in
            guard let self else {
                return nil
            }
            return await self.performRefresh(generation: generation)
        }
        inFlightRefreshTask = task
        return await task.value
    }

    private func performRefresh(generation: UInt64) async -> DepthAlbumItemSnapshot? {
        defer {
            if refreshGeneration == generation {
                inFlightRefreshTask = nil
                isRefreshing = false
            }
        }

        do {
            let loaded = try await snapshotLoader()
            guard !Task.isCancelled, refreshGeneration == generation else {
                return nil
            }

            let loadedSummaries = loaded.summaries
            let shouldPublish = snapshot.revision == 0
                || snapshot.items != loadedSummaries
                || Self.errorSignature(photoAssetsError)
                    != Self.errorSignature(loaded.photoAssetsError)
                || loadError != nil
            guard shouldPublish else {
                return loaded
            }

            items = loaded.items
            snapshot = LibraryMediaSnapshot(
                revision: snapshot.revision &+ 1,
                items: loadedSummaries
            )
            photoAssetsError = loaded.photoAssetsError
            loadError = nil
            return loaded
        } catch is CancellationError {
            return nil
        } catch {
            guard refreshGeneration == generation else {
                return nil
            }
            let shouldPublishFailure = snapshot.revision == 0
                || !snapshot.items.isEmpty
                || photoAssetsError != nil
                || Self.errorSignature(loadError) != Self.errorSignature(error)
            guard shouldPublishFailure else {
                return nil
            }

            items = []
            snapshot = LibraryMediaSnapshot(revision: snapshot.revision &+ 1, items: [])
            photoAssetsError = nil
            loadError = error
            return nil
        }
    }

    /// Error instances returned by Photos are frequently recreated for the
    /// same failure. Compare their stable NSError identity so an equivalent
    /// partial snapshot does not invalidate every Library consumer.
    private static func errorSignature(_ error: Error?) -> ErrorSignature? {
        guard let error else {
            return nil
        }
        let nsError = error as NSError
        return ErrorSignature(domain: nsError.domain, code: nsError.code)
    }

    func scheduleRefresh(after delay: Duration = .milliseconds(150)) {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.refreshAfterInFlightRefresh()
        }
    }

    /// A change notification that arrives during a catalog load must not start
    /// another scan immediately. Wait for the shared load, then perform at most
    /// one debounced follow-up so a change that landed mid-snapshot is retained.
    private func refreshAfterInFlightRefresh() async {
        if let inFlightRefreshTask {
            _ = await inFlightRefreshTask.value
        }
        guard !Task.isCancelled else {
            return
        }
        await refresh()
    }

    func cancelRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
        refreshGeneration &+= 1
        isRefreshing = false
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard self?.isObservingChanges == true else { return }
            self?.scheduleRefresh()
        }
    }
}

private struct ErrorSignature: Equatable {
    let domain: String
    let code: Int
}
