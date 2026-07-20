//
//  DepthAlbumPickerViewModel.swift
//  TAPCamDemo
//

import Combine
import Foundation
import OSLog

@MainActor
final class DepthAlbumPickerViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = "Loading TAP Library..."
    @Published private(set) var errorMessage: String?

    private let libraryStore: LibraryMediaStore
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedSnapshot = false

    var items: [TAPLibraryItem] {
        libraryStore.items
    }

    var shouldShowLoading: Bool {
        isLoading || !hasLoadedSnapshot
    }

    init(
        itemProvider: DepthAlbumItemProvider? = nil,
        libraryStore: LibraryMediaStore? = nil
    ) {
        self.libraryStore = libraryStore ?? LibraryMediaStore(
            itemProvider: itemProvider,
            observesChanges: false
        )
    }

    deinit {
        refreshTask?.cancel()
    }

    func load(
        showLoadingIndicator: Bool = true,
        lockedImportReason: String? = nil
    ) async {
        LockedCameraDiagnostics.logger.info(
            "tap_library_load_begin showLoading=\(showLoadingIndicator, privacy: .public) lockedImportReason=\(lockedImportReason ?? "none", privacy: .public)"
        )
        if showLoadingIndicator {
            loadingMessage = lockedImportReason == nil
                ? "Loading TAP Library..."
                : "Importing locked captures..."
            isLoading = true
        }
        defer {
            hasLoadedSnapshot = true
            if showLoadingIndicator {
                isLoading = false
                loadingMessage = "Loading TAP Library..."
            }
        }

        do {
            if let lockedImportReason {
                let summary = await LockedCaptureSessionContentImportCoordinator.shared
                    .importAvailableSessionContentAfterSessionContentSettles(reason: lockedImportReason)
                LockedCameraDiagnostics.logger.info(
                    "tap_library_locked_import_before_snapshot reason=\(lockedImportReason, privacy: .public) sessions=\(summary.scannedSessionCount, privacy: .public) found=\(summary.foundCaptureCount, privacy: .public) imported=\(summary.importedCount, privacy: .public) skipped=\(summary.skippedCount, privacy: .public) failed=\(summary.failedCount, privacy: .public) invalidated=\(summary.invalidatedSessionCount, privacy: .public)"
                )
            }
            if showLoadingIndicator, lockedImportReason != nil {
                loadingMessage = "Loading TAP Library..."
            }
            let snapshot = await libraryStore.refreshSharingInFlightLoad()
            if let loadError = libraryStore.loadError {
                throw loadError
            }
            errorMessage = snapshot?.photoAssetsError.flatMap { error in
                items.isEmpty ? DepthAnalysisErrorPresentation.emptyAlbumPhotosErrorMessage(for: error) : nil
            }
            LockedCameraDiagnostics.logger.info(
                "tap_library_load_finish itemCount=\(self.items.count, privacy: .public) itemSources=\(Self.itemSourceCountsDescription(self.items), privacy: .public) photoAssetsErrorPresent=\(snapshot?.photoAssetsError != nil, privacy: .public)"
            )
        } catch {
            errorMessage = DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
            LockedCameraDiagnostics.logger.error(
                "tap_library_load_failed error=\(Self.describe(error), privacy: .public)"
            )
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedSnapshot,
              !isLoading else {
            return
        }

        await load()
    }

    func loadForPresentation(lockedImportReason: String? = nil) async {
        await load(lockedImportReason: lockedImportReason)
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        LockedCameraDiagnostics.logger.info("tap_library_refresh_scheduled")
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.load(showLoadingIndicator: false)
        }
    }

    private static func itemSourceCountsDescription(_ items: [TAPLibraryItem]) -> String {
        var pendingCount = 0
        var ownedPhotoCount = 0
        var photosCount = 0
        for item in items {
            switch item.source {
            case .pending:
                pendingCount += 1
            case .ownedPhoto:
                ownedPhotoCount += 1
            case .photos:
                photosCount += 1
            }
        }
        return "pending:\(pendingCount)|owned:\(ownedPhotoCount)|photos:\(photosCount)"
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }
}
