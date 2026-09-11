//
//  TAPPendingCaptureArtifactWriter.swift
//  TAPCamDemo
//

import Foundation

/// Result of staging one packaged capture in the Pending Capture Queue.
nonisolated struct CaptureWriteResult: Equatable, Sendable {
    let signatureStatus: CaptureSignatureStatus
    let depthAvailability: CaptureDepthAvailability
}

nonisolated struct TAPPendingCaptureArtifactWriter: Sendable {
    let store: TAPPendingCaptureStore

    init(store: TAPPendingCaptureStore = .shared) {
        self.store = store
    }

    /// Persists one unsigned capture artifact into the app-private pending store.
    ///
    /// Foreground capture work ends here. App Attest signing and Photos export are
    /// owned by `TAPPendingCaptureProcessor` so TAP Library can show pending state.
    ///
    /// - Tag: WritePackagedArtifactToPendingStore
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult {
        _ = try await store.ingest(artifact)
        return CaptureWriteResult(
            signatureStatus: .pending(reason: "Queued for App Attest signing."),
            depthAvailability: artifact.depthAvailability
        )
    }
}
