//
//  TAPPendingCaptureRecord+Processing.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation

/// Describes the next worker action for one pending capture record.
///
/// The route is derived only from persisted queue state. Keeping it separate
/// from the processor makes retry ordering readable without changing the
/// signing/export implementation.
nonisolated enum TAPPendingCaptureProcessingRoute: Equatable, Sendable {
    case signThenExport
    case exportSigned
    case skip
}

nonisolated extension TAPPendingCaptureRecord {
    var processingRoute: TAPPendingCaptureProcessingRoute {
        switch status {
        case .pending, .waitingNetwork, .signing, .failedRetryable:
            if signedPhotoFilename != nil || videoArtifactState == .signed {
                return .exportSigned
            }
            return .signThenExport
        case .signed, .exporting:
            return .exportSigned
        case .exported, .failedTerminal:
            return .skip
        }
    }

    var processingPriority: Int? {
        switch status {
        case .signed, .exporting:
            return 0
        case .pending, .signing:
            return 1
        case .failedRetryable, .waitingNetwork:
            return 2
        case .exported, .failedTerminal:
            return nil
        }
    }

    var isProcessingCandidate: Bool {
        processingPriority != nil
    }

    var requiresVideoPhotosReadbackRecovery: Bool {
        guard artifactKind == .tapVideo else {
            return false
        }
        return videoPhotosExportPhase == .commitAmbiguous
            || videoPhotosExportPhase == .committed
            || assetLocalIdentifier != nil
    }

    var shouldAttemptExistingAssetRecoveryBeforeExport: Bool {
        switch artifactKind {
        case .photoDepth:
            return status == .exporting
        case .tapVideo:
            return requiresVideoPhotosReadbackRecovery
        }
    }

    /// Only persisted, already-signed video artifacts may become terminal for
    /// manifest/proof readback failures. Failures while preparing an unsigned
    /// capture stay retryable because the app still owns and trusts the file it
    /// just produced.
    func terminalFailureCode(for error: Error) -> TAPPendingCaptureFailureCode? {
        guard artifactKind == .tapVideo,
              let captureError = error as? TAPDepthCaptureError else {
            return nil
        }

        switch captureError {
        case .missingDepthData:
            return .missingDepthData
        case .pendingCaptureProofExternalMutation:
            return .proofExternalMutation
        case .pendingCaptureProofInvalid,
             .pendingCaptureProofMissing:
            return videoArtifactState == .signed
                ? .proofValidationFailed
                : nil
        case .invalidTAPManifest,
             .pendingCaptureManifestIDMismatch:
            return videoArtifactState == .signed
                ? .invalidVideoArtifact
                : nil
        default:
            return nil
        }
    }
}
