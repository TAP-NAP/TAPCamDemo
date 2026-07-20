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
    private let observesChanges: Bool

    init(
        itemProvider: DepthAlbumItemProvider? = nil,
        photoCatalog: (any DepthAlbumPhotoCataloging)? = nil,
        notificationCenter: NotificationCenter = .default,
        observesChanges: Bool = true
    ) {
        let provider = itemProvider ?? DepthAlbumItemProvider(
            photoCatalog: photoCatalog ?? PhotoKitLibraryMediaFetcher()
        )
        self.snapshotLoader = {
            try await provider.loadSnapshot()
        }
        self.notificationCenter = notificationCenter
        self.observesChanges = observesChanges
        super.init()

        guard observesChanges else {
            return
        }
        libraryChangeObserver = notificationCenter.addObserver(
            forName: .tapLibraryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        inFlightRefreshTask?.cancel()
        scheduledRefreshTask?.cancel()
        if let libraryChangeObserver {
            notificationCenter.removeObserver(libraryChangeObserver)
        }
        if observesChanges {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    var latestItem: TAPLibraryItem? {
        items.first
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
            items = loaded.items
            snapshot = LibraryMediaSnapshot(
                revision: generation,
                items: loaded.summaries
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
            items = []
            snapshot = LibraryMediaSnapshot(revision: generation, items: [])
            photoAssetsError = nil
            loadError = error
            return nil
        }
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
            self?.scheduleRefresh()
        }
    }
}
