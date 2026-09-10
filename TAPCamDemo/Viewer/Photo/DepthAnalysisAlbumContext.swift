//
//  DepthAnalysisAlbumContext.swift
//  TAPCamDemo
//

import Foundation

/// Photo-specific metadata carried by the mixed-media Viewer resource slot.
/// Paging order and selection belong to `TAPLibraryViewerStore`.
nonisolated enum DepthAnalysisAlbumContext {
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
