//
//  TAPPendingCaptureWorkerReadiness.swift
//  TAPCamDemo
//

import Foundation

/// Preflight state for the pending-capture worker.
///
/// The worker reads private HEIC bundles, manifests, proofs, and Photos export
/// identifiers. Keep this decision separate from signing/export routing so
/// future protected-data policy changes have one small place to start.
nonisolated enum TAPPendingCaptureWorkerReadiness: Equatable, Sendable {
    case ready
    case protectedDataUnavailable

    init(protectedDataIsAvailable: Bool) {
        self = protectedDataIsAvailable ? .ready : .protectedDataUnavailable
    }

    var allowsPrivateArtifactAccess: Bool {
        self == .ready
    }
}
