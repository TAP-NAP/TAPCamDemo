//
//  TAPLibraryViewModel.swift
//  TAPCamDemo
//

import Combine
import Foundation

@MainActor
final class TAPLibraryViewModel: ObservableObject {
    private let libraryStore: LibraryMediaStore

    var items: [TAPLibraryItem] {
        libraryStore.items
    }

    var shouldShowLoading: Bool {
        libraryStore.snapshot.revision == 0
            || (libraryStore.isRefreshing && items.isEmpty)
    }

    var errorMessage: String? {
        if let error = libraryStore.loadError {
            return DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
        }
        guard items.isEmpty, let error = libraryStore.photoAssetsError else {
            return nil
        }
        return DepthAnalysisErrorPresentation.emptyAlbumPhotosErrorMessage(for: error)
    }

    init(
        catalogReconciler: LibraryCatalogReconciler? = nil,
        libraryStore: LibraryMediaStore? = nil
    ) {
        self.libraryStore = libraryStore ?? LibraryMediaStore(
            catalogReconciler: catalogReconciler,
            observesChanges: false
        )
    }

    func loadForPresentation() async {
        // An empty snapshot is usable for startup readiness, but it is not a
        // durable presentation cache: captures may have arrived since the
        // prior scan without producing an in-process change notification.
        if libraryStore.hasUsableSnapshot, !items.isEmpty {
            return
        }
        await libraryStore.refreshSharingInFlightLoad()
    }
}
