//
//  TAPPendingCaptureArtifactWriter.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct TAPPendingCaptureArtifactWriter: CaptureArtifactWriter {
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
        let record = try await store.ingest(artifact)
        return CaptureWriteResult(
            artifactID: artifact.packageID,
            publicDestinationSummary: "Pending TAP capture",
            assetLocalIdentifier: nil,
            pendingCaptureID: record.captureID,
            signatureStatus: .pending(reason: "Queued for App Attest signing.")
        )
    }
}
