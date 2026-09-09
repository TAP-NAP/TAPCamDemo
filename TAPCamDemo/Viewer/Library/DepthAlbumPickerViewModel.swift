//
//  DepthAlbumPickerViewModel.swift
//  TAPCamDemo
//

import Combine
import Foundation
import OSLog

nonisolated enum DepthAlbumLoadingPresentation: String, Equatable, Sendable {
    case library = "Loading TAP Library..."
}

@MainActor
final class DepthAlbumPickerViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var loadingPresentation = DepthAlbumLoadingPresentation.library
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

    var loadingMessage: String {
        loadingPresentation.rawValue
    }

    init(
        itemProvider: DepthAlbumItemProvider? = nil,
        libraryStore: LibraryMediaStore? = nil
    ) {
        let resolvedLibraryStore = libraryStore ?? LibraryMediaStore(
            itemProvider: itemProvider,
            observesChanges: false
        )
        self.libraryStore = resolvedLibraryStore
        self.hasLoadedSnapshot = resolvedLibraryStore.hasUsableSnapshot
    }

    deinit {
        refreshTask?.cancel()
    }

    func load(showLoadingIndicator: Bool = true) async {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info(
            "tap_library_load_begin showLoading=\(showLoadingIndicator, privacy: .public)"
        )
        #endif
        if showLoadingIndicator {
            loadingPresentation = .library
            isLoading = true
        }
        defer {
            hasLoadedSnapshot = true
            if showLoadingIndicator {
                isLoading = false
                loadingPresentation = .library
            }
        }

        do {
            let snapshot = await libraryStore.refreshSharingInFlightLoad()
            if let loadError = libraryStore.loadError {
                throw loadError
            }
            errorMessage = snapshot?.photoAssetsError.flatMap { error in
                items.isEmpty ? DepthAnalysisErrorPresentation.emptyAlbumPhotosErrorMessage(for: error) : nil
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info(
                "tap_library_load_finish itemCount=\(self.items.count, privacy: .public) itemSources=\(Self.itemSourceCountsDescription(self.items), privacy: .public) photoAssetsErrorPresent=\(snapshot?.photoAssetsError != nil, privacy: .public)"
            )
            #endif
        } catch {
            errorMessage = DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.error(
                "tap_library_load_failed error=\(TAPDiagnostics.describe(error), privacy: .public)"
            )
            #endif
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedSnapshot,
              !isLoading else {
            return
        }

        await load()
    }

    func loadForPresentation() async {
        // An empty snapshot is usable for startup readiness, but it is not a
        // durable presentation cache: captures may have arrived since the
        // prior scan without producing an in-process change notification.
        if libraryStore.hasUsableSnapshot,
           !libraryStore.items.isEmpty {
            hasLoadedSnapshot = true
            errorMessage = nil
            return
        }

        await load()
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("tap_library_refresh_scheduled")
        #endif
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
}
