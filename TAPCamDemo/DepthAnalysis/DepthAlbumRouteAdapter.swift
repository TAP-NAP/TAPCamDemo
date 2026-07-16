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
