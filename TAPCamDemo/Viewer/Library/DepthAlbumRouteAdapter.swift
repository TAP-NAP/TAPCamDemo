//
//  DepthAlbumRouteAdapter.swift
//  TAPCamDemo
//

/// Converts Library identities into the route payload required by each viewer.
nonisolated enum DepthAlbumRouteAdapter {
    enum Destination: Hashable {
        case analysis(DepthAlbumAnalysisRoute)
        case video(TAPVideoPlaybackRoute)

        var itemID: String {
            switch self {
            case .analysis(let route):
                route.itemID
            case .video(let route):
                route.itemID
            }
        }
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

/// Ordered mixed-media context shared by photo, Live Photo, and video viewers.
///
/// This context is the canonical cursor for the shared visual pager and
/// deletion advancement, so neither renderer can skip an item of another
/// media type.
nonisolated struct DepthAlbumDeletionContext: Equatable {
    nonisolated struct Entry: Identifiable, Equatable {
        let id: String
        let destination: DepthAlbumRouteAdapter.Destination
        let routeAnchor: CameraRouteAlbumAnchor
        let expectsPairedVideo: Bool

        init(item: TAPLibraryItem) {
            id = item.id
            destination = DepthAlbumRouteAdapter.destination(for: item)
            routeAnchor = item.routeAnchor
            expectsPairedVideo = item.isLivePhoto
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

    func adjacentEntry(offset: Int, excluding removedIDs: Set<String> = []) -> Entry? {
        adjacentEntry(
            from: currentItemID,
            offset: offset,
            excluding: removedIDs
        )
    }

    func adjacentEntry(
        from itemID: String,
        offset: Int,
        excluding removedIDs: Set<String> = []
    ) -> Entry? {
        guard abs(offset) == 1 else {
            return nil
        }
        let visibleEntries = entries.filter { !removedIDs.contains($0.id) }
        guard let currentIndex = visibleEntries.firstIndex(where: {
            $0.id == itemID
        }) else {
            return nil
        }
        let targetIndex = currentIndex + offset
        return visibleEntries.indices.contains(targetIndex)
            ? visibleEntries[targetIndex]
            : nil
    }

    /// Returns the canonical previous/current/next window used by the visual
    /// TAP Library pager. Media type is deliberately ignored: a video beside a
    /// still photo is just as adjacent as two still photos.
    func pagingEntries(
        from itemID: String,
        excluding removedIDs: Set<String> = []
    ) -> [Entry] {
        let visibleEntries = entries.filter { !removedIDs.contains($0.id) }
        guard let currentIndex = visibleEntries.firstIndex(where: {
            $0.id == itemID
        }) else {
            return []
        }

        let lowerBound = max(currentIndex - 1, visibleEntries.startIndex)
        let upperBound = min(
            currentIndex + 1,
            visibleEntries.index(before: visibleEntries.endIndex)
        )
        return Array(visibleEntries[lowerBound...upperBound])
    }

    func entryAfterDeletingCurrent(excluding removedIDs: Set<String>) -> Entry? {
        entryAfterDeleting(currentItemID, excluding: removedIDs)
    }

    func entryAfterDeleting(
        _ itemID: String,
        excluding removedIDs: Set<String>
    ) -> Entry? {
        guard let deletedIndex = entries.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }
        let remaining = entries.filter { !removedIDs.contains($0.id) }
        guard !remaining.isEmpty else {
            return nil
        }
        let remainingBeforeDeleted = entries[..<deletedIndex].reduce(into: 0) { count, entry in
            if !removedIDs.contains(entry.id) {
                count += 1
            }
        }
        return remaining[min(remainingBeforeDeleted, remaining.count - 1)]
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

    init(itemID: String, source: DepthAnalysisSource) {
        self.itemID = itemID
        self.source = source
    }
}
