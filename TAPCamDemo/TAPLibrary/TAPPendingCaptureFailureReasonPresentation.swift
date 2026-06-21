//
//  TAPPendingCaptureFailureReasonPresentation.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation

/// Public-safe failure text persisted with pending capture records.
///
/// Pending worker errors can contain capture IDs, file paths, App Attest key
/// IDs, proof state, backend URLs, or Photos identifiers. The worker may still
/// inspect raw errors for retry classification and diagnostics, but
/// `TAPPendingCaptureRecord.failureReason` should keep only fixed status text.
nonisolated enum TAPPendingCaptureFailureReasonPresentation {
    enum Reason: Equatable, Sendable {
        case waitingNetwork
        case retryableProcessingFailure
    }

    static func reason(for status: TAPPendingCaptureStatus) -> Reason? {
        switch status {
        case .waitingNetwork:
            return .waitingNetwork
        case .failedRetryable:
            return .retryableProcessingFailure
        case .pending, .signing, .signed, .exporting, .exported:
            return nil
        }
    }

    static func persistedFailureReason(for reason: Reason) -> String {
        switch reason {
        case .waitingNetwork:
            return "Network unavailable. Capture will retry."
        case .retryableProcessingFailure:
            return "Capture processing failed. It will retry."
        }
    }

    static func persistedFailureReason(for status: TAPPendingCaptureStatus) -> String {
        guard let reason = reason(for: status) else {
            return persistedFailureReason(for: .retryableProcessingFailure)
        }
        return persistedFailureReason(for: reason)
    }

    static func normalizedPersistedFailureReason(
        _ reason: Reason?,
        status: TAPPendingCaptureStatus
    ) -> String? {
        guard reason != nil, let statusReason = self.reason(for: status) else {
            return nil
        }
        return persistedFailureReason(for: statusReason)
    }

    static func normalizedLegacyFailureReason(
        _ failureReason: String?,
        status: TAPPendingCaptureStatus
    ) -> String? {
        guard failureReason != nil, let reason = reason(for: status) else {
            return nil
        }
        return persistedFailureReason(for: reason)
    }
}
