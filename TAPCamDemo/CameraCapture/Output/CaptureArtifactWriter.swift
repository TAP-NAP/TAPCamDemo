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
    /// Public-safe destination label. Raw Photos and pending identifiers live in
    /// the dedicated private identifier fields below.
    let publicDestinationSummary: String
    let assetLocalIdentifier: String?
    let pendingCaptureID: String?
    let signatureStatus: CaptureSignatureStatus
}

/// Persists a packaged capture artifact.
///
/// Writers do not inspect hardware, mutate sessions, or decide packaging
/// strategy. The demo uses a single-photo writer only.
protocol CaptureArtifactWriter: Sendable {
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult
}

/// Direct Photos writer retained for flows that already have a final HEIC.
///
/// The camera UI now uses `TAPPendingCaptureArtifactWriter` so capture writes
/// finish at the app-private pending store before async signing/export.
nonisolated struct PhotoLibraryCaptureArtifactWriter: CaptureArtifactWriter {
    /// Persists one packaged artifact and returns the Photos asset identifier.
    ///
    /// - Tag: WritePackagedArtifactToPhotos
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult {
        let validatedHEIC = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
            artifact.photoData,
            expectedCaptureID: artifact.manifest.payload.id
        )
        let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
            validatedHEIC,
            capturedAt: artifact.capturedAt,
            location: artifact.location
        )

        return CaptureWriteResult(
            artifactID: artifact.packageID,
            publicDestinationSummary: "Photos asset",
            assetLocalIdentifier: assetID,
            pendingCaptureID: nil,
            signatureStatus: artifact.signatureStatus
        )
    }
}
