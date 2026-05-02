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
    let signatureStatus: CaptureSignatureStatus
}

/// Persists a packaged capture artifact.
///
/// Writers do not inspect hardware, mutate sessions, or decide packaging
/// strategy. The demo uses a single-photo writer only.
protocol CaptureArtifactWriter: Sendable {
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult
}

/// Release-safe writer that saves the final single HEIC into Photos.
nonisolated struct PhotoLibraryCaptureArtifactWriter: CaptureArtifactWriter {
    /// Persists one packaged artifact and returns the Photos asset identifier.
    ///
    /// - Tag: WritePackagedArtifactToPhotos
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult {
        let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
            artifact.photoData,
            capturedAt: artifact.capturedAt,
            location: artifact.location
        )

        return CaptureWriteResult(
            artifactID: artifact.packageID,
            destinationDescription: "Photos asset: \(assetID)",
            assetLocalIdentifier: assetID,
            signatureStatus: artifact.signatureStatus
        )
    }
}
