//
//  CaptureArtifactWriter.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// Result of persisting one packaged artifact.
nonisolated struct CaptureWriteResult: Equatable, Sendable {
    let artifactID: UUID
    let destinationDescription: String
    let assetLocalIdentifier: String?
}

/// Persists a packaged capture artifact.
///
/// Writers do not inspect hardware, mutate sessions, run hooks, or decide
/// packaging strategy. Release uses a single-photo writer only.
protocol CaptureArtifactWriter: Sendable {
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult
}

/// Release-safe writer that saves the final single HEIC into Photos.
nonisolated struct PhotoLibraryCaptureArtifactWriter: CaptureArtifactWriter {
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult {
        let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
            artifact.photoData,
            capturedAt: artifact.capturedAt,
            location: artifact.location
        )

        return CaptureWriteResult(
            artifactID: artifact.packageID,
            destinationDescription: "Photos asset: \(assetID)",
            assetLocalIdentifier: assetID
        )
    }
}
