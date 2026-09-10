//
//  DepthAnalysisAlbumContext.swift
//  TAPCamDemo
//

import Foundation

/// Lightweight ordered album context used by the analysis browser.
///
/// `TAPLibraryViewer` only needs enough information to move to the previous or
/// next library item and keep camera route context in sync. Loaded image bytes,
/// Photos handles, and pending-capture stores still stay behind
/// `DepthAnalysisProgressivePhotoLoader`.
nonisolated struct DepthAnalysisAlbumContext: Equatable {
    nonisolated struct Entry: Identifiable, Equatable {
        let id: String
        let mediaID: LibraryMediaID
        let source: DepthAnalysisSource
        let routeAnchor: CameraRouteAlbumAnchor
        /// Album-level media classification survives after the item is
        /// reduced to a lightweight viewer route. This is important for
        /// legacy exported records whose optional local paired-video filename
        /// may be absent even though the Photos asset is a Live Photo.
        let expectsPairedVideo: Bool
        let mediaVersion: LibraryMediaVersion?

        init(
            id: String,
            mediaID: LibraryMediaID,
            source: DepthAnalysisSource,
            routeAnchor: CameraRouteAlbumAnchor,
            expectsPairedVideo: Bool = false,
            mediaVersion: LibraryMediaVersion? = nil
        ) {
            self.id = id
            self.mediaID = mediaID
            self.source = source
            self.routeAnchor = routeAnchor
            self.expectsPairedVideo = expectsPairedVideo
            self.mediaVersion = mediaVersion
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

        // Keep only the contiguous run that this renderer can display. The
        // mixed-media viewer context owns transitions across a video boundary;
        // filtering the entire album here would make a photo swipe silently
        // skip over intervening videos.
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
        let source: DepthAnalysisSource
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
        self.init(
            id: item.id,
            mediaID: item.summary.id,
            source: source,
            routeAnchor: item.routeAnchor,
            expectsPairedVideo: item.isLivePhoto,
            mediaVersion: item.summary.version
        )
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
