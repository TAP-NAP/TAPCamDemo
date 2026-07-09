//
//  DepthAnalysisAlbumContext.swift
//  TAPCamDemo
//

import Foundation

/// Lightweight ordered album context used by the analysis browser.
///
/// `DepthAnalysisView` only needs enough information to move to the previous or
/// next library item and keep camera route context in sync. Loaded image bytes,
/// Photos handles, and pending-capture stores still stay behind
/// `DepthAnalysisInputLoader`.
nonisolated struct DepthAnalysisAlbumContext: Equatable {
    nonisolated struct Entry: Identifiable, Equatable {
        let id: String
        let source: DepthAnalysisSource
        let routeAnchor: CameraRouteAlbumAnchor
    }

    let currentItemID: String
    let entries: [Entry]

    init(currentItemID: String, entries: [Entry]) {
        self.currentItemID = currentItemID
        self.entries = entries
    }

    init(currentItemID: String, items: [TAPLibraryItem]) {
        self.init(
            currentItemID: currentItemID,
            entries: items.compactMap(Entry.init(item:))
        )
    }

    var currentIndex: Int? {
        entries.firstIndex { $0.id == currentItemID }
    }

    func adjacentEntry(offset: Int) -> Entry? {
        guard let currentIndex else {
            return nil
        }
        let nextIndex = currentIndex + offset
        guard entries.indices.contains(nextIndex) else {
            return nil
        }
        return entries[nextIndex]
    }

    func selecting(_ entry: Entry) -> DepthAnalysisAlbumContext {
        DepthAnalysisAlbumContext(currentItemID: entry.id, entries: entries)
    }
}

private extension DepthAnalysisAlbumContext.Entry {
    nonisolated init?(item: TAPLibraryItem) {
        id = item.id
        routeAnchor = item.routeAnchor
        switch item.source {
        case .photos(let asset):
            guard !asset.isVideo else {
                return nil
            }
            source = .photosAsset(asset.localIdentifier)
        case .ownedPhoto(let record, let asset):
            guard record.artifactKind != .tapVideo,
                  !asset.isVideo else {
                return nil
            }
            source = .photosAsset(asset.localIdentifier)
        case .pending(let record):
            guard record.artifactKind != .tapVideo else {
                return nil
            }
            source = .pendingCapture(record.captureID)
        }
    }
}

extension DepthAnalysisSource {
    var loadID: String {
        switch self {
        case .photosAsset(let assetID):
            "photos:\(assetID)"
        case .pendingCapture(let captureID):
            "pending:\(captureID)"
        }
    }
}
