//
//  TAPVideoPlaybackDeletion.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPVideoDeletionService {
    static func delete(source: TAPVideoPlaybackSource) async throws {
        switch source {
        case .pendingCapture(let captureID):
            try await TAPPendingCaptureStore.shared.removeRecord(captureID: captureID)
        case .ownedCapture(_, let assetID), .photosAsset(let assetID):
            try await PhotoLibraryWriter.deleteAsset(localIdentifier: assetID)
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        #if DEBUG
        case .fixtureFile:
            return
        #endif
        }
    }
}
