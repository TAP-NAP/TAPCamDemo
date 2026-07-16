//
//  TAPPendingVideoWorkspaceCoordinator.swift
//  TAPCamDemo
//

import Foundation

/// Value-semantic workspace ownership kept inside `TAPPendingCaptureStore`'s
/// actor isolation. It cannot create a second filesystem writer.
nonisolated struct TAPPendingVideoWorkspaceCoordinator {
    private let storage: TAPPendingCaptureBundleStorage
    private var activeCaptureIDs: Set<String> = []

    init(storage: TAPPendingCaptureBundleStorage) {
        self.storage = storage
    }

    mutating func begin(captureID: String) throws -> TAPVideoRecordingWorkspace {
        try storage.ensureRootDirectoryExists()
        let bundleURL = try storage.createFreshVideoCaptureWorkspace(captureID: captureID)
        activeCaptureIDs.insert(captureID)
        return TAPVideoRecordingWorkspace(
            captureID: captureID,
            bundleURL: bundleURL,
            artifactURL: bundleURL.appendingPathComponent(
                TAPPendingCaptureBundlePathPolicy.videoArtifactFilename
            )
        )
    }

    mutating func abort(captureID: String) throws {
        defer { activeCaptureIDs.remove(captureID) }
        try storage.removeVideoCaptureWorkspace(captureID: captureID)
    }

    func workspaceURL(captureID: String) throws -> URL {
        try storage.videoCaptureWorkspaceURL(captureID: captureID)
    }

    mutating func discard(captureID: String) {
        try? storage.removeVideoCaptureWorkspace(captureID: captureID)
        activeCaptureIDs.remove(captureID)
    }

    mutating func didCommit(captureID: String) {
        activeCaptureIDs.remove(captureID)
    }

    mutating func removeStaleWorkspaces() throws -> Int {
        var removedCount = 0
        for workspaceURL in try storage.videoCaptureWorkspaceURLs() {
            let captureID = Self.captureID(for: workspaceURL)
            guard !captureID.isEmpty,
                  !activeCaptureIDs.contains(captureID) else {
                continue
            }
            try storage.removeVideoCaptureWorkspace(at: workspaceURL)
            removedCount += 1
        }
        return removedCount
    }

    private static func captureID(for workspaceURL: URL) -> String {
        String(workspaceURL.lastPathComponent.dropFirst(
            TAPPendingCaptureBundlePathPolicy.videoCaptureWorkspacePrefix.count
        ))
    }
}
