//
//  TAPVideoPlaybackRoute.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPVideoPlaybackSource: Hashable {
    case pendingCapture(String)
    case ownedCapture(captureID: String, assetLocalIdentifier: String)
    case photosAsset(String)
    #if DEBUG
    case fixtureFile(
        URL,
        automaticSeekScheduleSeconds: [Double],
        autoPlay: Bool
    )
    #endif

    var libraryMediaID: LibraryMediaID {
        switch self {
        case .pendingCapture(let captureID), .ownedCapture(let captureID, _):
            .tapCapture(captureID)
        case .photosAsset(let assetID):
            .photosAsset(assetID)
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            .photosAsset("fixture:\(fileURL.lastPathComponent)")
        #endif
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .pendingCapture:
            "pending"
        case .ownedCapture:
            "owned"
        case .photosAsset:
            "photos"
        #if DEBUG
        case .fixtureFile:
            "fixture"
        #endif
        }
    }

    var requiresUnsavedDeleteConfirmation: Bool {
        if case .pendingCapture = self {
            return true
        }
        return false
    }
}

nonisolated struct TAPVideoPlaybackRoute: Hashable {
    let itemID: String
    let source: TAPVideoPlaybackSource

    nonisolated init(entry: TAPVideoAlbumContext.Entry) {
        itemID = entry.id
        source = entry.source
    }

    nonisolated init(itemID: String, source: TAPVideoPlaybackSource) {
        self.itemID = itemID
        self.source = source
    }

    nonisolated init?(item: TAPLibraryItem) {
        itemID = item.id
        switch item.source {
        case .pending(let record):
            guard record.artifactKind == .tapVideo else {
                return nil
            }
            source = .pendingCapture(record.captureID)
        case .ownedPhoto(let record, let asset):
            guard record.artifactKind == .tapVideo || asset.isVideo else {
                return nil
            }
            source = .ownedCapture(
                captureID: record.captureID,
                assetLocalIdentifier: asset.localIdentifier
            )
        case .photos(let asset):
            guard asset.isVideo else {
                return nil
            }
            source = .photosAsset(asset.localIdentifier)
        }
    }
}

nonisolated struct TAPVideoAlbumContext: Equatable {
    nonisolated struct Entry: Identifiable, Equatable {
        let id: String
        let source: TAPVideoPlaybackSource
        let routeAnchor: CameraRouteAlbumAnchor

        nonisolated init(
            id: String,
            source: TAPVideoPlaybackSource,
            routeAnchor: CameraRouteAlbumAnchor
        ) {
            self.id = id
            self.source = source
            self.routeAnchor = routeAnchor
        }

        nonisolated init?(item: TAPLibraryItem) {
            guard let route = TAPVideoPlaybackRoute(item: item) else {
                return nil
            }
            id = route.itemID
            source = route.source
            routeAnchor = item.routeAnchor
        }
    }

    let currentItemID: String
    let entries: [Entry]

    init(currentItemID: String, entries: [Entry]) {
        self.currentItemID = currentItemID
        self.entries = entries
    }

    init(currentItemID: String, items: [TAPLibraryItem]) {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItemID }),
              Entry(item: items[currentIndex]) != nil else {
            self.init(currentItemID: currentItemID, entries: [])
            return
        }

        // A video viewer may page through consecutive videos, but it must stop
        // at a photo/Live Photo boundary. Cross-renderer movement is resolved
        // by the canonical mixed-media context instead of compact-mapping the
        // whole album and jumping over non-video items.
        var lowerBound = currentIndex
        while lowerBound > items.startIndex,
              Entry(item: items[items.index(before: lowerBound)]) != nil {
            lowerBound = items.index(before: lowerBound)
        }
        var upperBound = currentIndex
        while upperBound < items.index(before: items.endIndex),
              Entry(item: items[items.index(after: upperBound)]) != nil {
            upperBound = items.index(after: upperBound)
        }

        self.init(
            currentItemID: currentItemID,
            entries: items[lowerBound...upperBound].compactMap(Entry.init(item:))
        )
    }

    func adjacentEntry(offset: Int, excluding removedIDs: Set<String>) -> Entry? {
        guard abs(offset) == 1 else {
            return nil
        }
        let visibleEntries = entries.filter { !removedIDs.contains($0.id) }
        guard let currentIndex = visibleEntries.firstIndex(where: {
            $0.id == currentItemID
        }) else {
            return nil
        }
        let targetIndex = currentIndex + offset
        return visibleEntries.indices.contains(targetIndex)
            ? visibleEntries[targetIndex]
            : nil
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
