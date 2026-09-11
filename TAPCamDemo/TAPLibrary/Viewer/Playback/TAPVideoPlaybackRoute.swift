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
