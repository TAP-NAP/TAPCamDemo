//
//  DepthAlbumRouteAdapter.swift
//  TAPCamDemo
//

/// Converts Library identities into the route payload required by each viewer.
nonisolated enum DepthAlbumRouteAdapter {
    enum Destination: Hashable {
        case analysis(DepthAlbumAnalysisRoute)
        case video(TAPVideoPlaybackRoute)
    }

    static func destination(for item: TAPLibraryItem) -> Destination {
        if item.isVideo,
           let videoRoute = TAPVideoPlaybackRoute(item: item) {
            return .video(videoRoute)
        }
        return .analysis(DepthAlbumAnalysisRoute(item: item))
    }

    static func analysisRoute(
        for entry: DepthAnalysisAlbumContext.Entry
    ) -> DepthAlbumAnalysisRoute {
        DepthAlbumAnalysisRoute(entry: entry)
    }

    static func videoRoute(for entry: TAPVideoAlbumContext.Entry) -> TAPVideoPlaybackRoute {
        TAPVideoPlaybackRoute(entry: entry)
    }
}

/// Ordered mixed-media context used when a viewer deletes its current item.
///
/// Photo and video viewers keep specialized swipe implementations, but delete
/// advancement follows the canonical TAP Library order even when the neighbor
/// uses the other viewer.
nonisolated struct DepthAlbumDeletionContext: Equatable {
    nonisolated struct Entry: Identifiable, Equatable {
        let id: String
        let destination: DepthAlbumRouteAdapter.Destination
        let routeAnchor: CameraRouteAlbumAnchor

        init(item: TAPLibraryItem) {
            id = item.id
            destination = DepthAlbumRouteAdapter.destination(for: item)
            routeAnchor = item.routeAnchor
        }
    }

    let currentItemID: String
    let entries: [Entry]

    init(currentItemID: String, items: [TAPLibraryItem]) {
        self.currentItemID = currentItemID
        entries = items.map(Entry.init(item:))
    }

    init(currentItemID: String, entries: [Entry]) {
        self.currentItemID = currentItemID
        self.entries = entries
    }

    func entryAfterDeletingCurrent(excluding removedIDs: Set<String>) -> Entry? {
        let deletedIndex = entries.firstIndex { $0.id == currentItemID } ?? 0
        let remaining = entries.filter { !removedIDs.contains($0.id) }
        guard !remaining.isEmpty else {
            return nil
        }
        return remaining[min(deletedIndex, remaining.count - 1)]
    }
}

nonisolated struct DepthAlbumAnalysisRoute: Hashable {
    let itemID: String
    let source: DepthAnalysisSource

    init(entry: DepthAnalysisAlbumContext.Entry) {
        itemID = entry.id
        source = entry.source
    }

    init(item: TAPLibraryItem) {
        itemID = item.id
        switch item.source {
        case .photos(let asset), .ownedPhoto(_, let asset):
            source = .photosAsset(asset.localIdentifier)
        case .pending(let record):
            source = .pendingCapture(record.captureID)
        }
    }
}
