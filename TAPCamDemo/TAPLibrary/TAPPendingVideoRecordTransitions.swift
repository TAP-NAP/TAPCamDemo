//
//  TAPPendingVideoRecordTransitions.swift
//  TAPCamDemo
//

import Foundation

/// Pure durable-state transitions for TAP video signing and Photos export.
/// The actor store remains the sole writer and supplies the transition time.
nonisolated enum TAPPendingVideoRecordTransitions {
    static func markSigned(
        _ source: TAPPendingCaptureRecord,
        now: Date
    ) throws -> TAPPendingCaptureRecord {
        guard source.artifactKind == .tapVideo else {
            throw invalid("video signing state requires a TAP video artifact")
        }
        var record = source
        record.videoArtifactState = .signed
        record.status = .signed
        record.failureReason = nil
        record.failureCode = nil
        record.updatedAt = now
        return record
    }

    static func persistPreSignBinding(
        _ binding: CaptureContentBinding,
        in source: TAPPendingCaptureRecord,
        now: Date
    ) throws -> TAPPendingCaptureRecord {
        guard source.artifactKind == .tapVideo,
              binding.captureID == source.captureID else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "video pre-sign binding identity mismatch"
            )
        }
        if let existing = source.preSignContentBinding, existing != binding {
            throw TAPDepthCaptureError.pendingCaptureProofExternalMutation
        }
        var record = source
        record.preSignContentBinding = binding
        record.updatedAt = now
        return record
    }

    static func markExportIntent(
        _ source: TAPPendingCaptureRecord,
        now: Date
    ) throws -> TAPPendingCaptureRecord {
        try requireUncommittedSignedVideo(
            source,
            reason: "Photos export intent requires an uncommitted signed TAP video"
        )
        var record = source
        switch record.videoPhotosExportPhase {
        case nil, .preCommitIntent:
            record.videoPhotosExportPhase = .preCommitIntent
        case .commitAmbiguous, .committed:
            throw invalid("a TAP video beyond the Photos commit boundary cannot create again")
        }
        resetExportingState(&record, now: now)
        return record
    }

    static func markCommitAmbiguous(
        _ source: TAPPendingCaptureRecord,
        now: Date
    ) throws -> TAPPendingCaptureRecord {
        try requireUncommittedSignedVideo(
            source,
            reason: "Photos commit boundary requires an uncommitted signed TAP video"
        )
        var record = source
        switch record.videoPhotosExportPhase {
        case .preCommitIntent:
            record.videoPhotosExportPhase = .commitAmbiguous
        case .commitAmbiguous:
            return source
        case nil, .committed:
            throw invalid("Photos commit boundary requires a persisted pre-commit intent")
        }
        resetExportingState(&record, now: now)
        return record
    }

    static func markCommit(
        _ source: TAPPendingCaptureRecord,
        assetLocalIdentifier: String,
        now: Date
    ) throws -> TAPPendingCaptureRecord {
        guard source.artifactKind == .tapVideo,
              source.videoArtifactState == .signed,
              !assetLocalIdentifier.isEmpty else {
            throw invalid("Photos commit state requires a TAP video asset identifier")
        }
        if source.status == .exported {
            guard source.assetLocalIdentifier == assetLocalIdentifier else {
                throw invalid("an exported TAP video Photos identifier cannot change")
            }
            return source
        }
        guard source.status != .failedTerminal else {
            throw invalid("a terminal TAP video cannot re-enter Photos commit recovery")
        }
        if source.videoPhotosExportPhase == .committed {
            guard source.assetLocalIdentifier == assetLocalIdentifier else {
                throw invalid("a TAP video Photos commit identifier cannot change")
            }
            return source
        }
        guard source.videoPhotosExportPhase == .commitAmbiguous else {
            throw invalid("a TAP video Photos identifier requires the commit-ambiguous boundary")
        }
        if let existingAssetID = source.assetLocalIdentifier,
           existingAssetID != assetLocalIdentifier {
            throw invalid("a TAP video Photos commit identifier cannot change")
        }
        var record = source
        record.videoPhotosExportPhase = .committed
        record.assetLocalIdentifier = assetLocalIdentifier
        resetExportingState(&record, now: now)
        return record
    }

    static func markExported(
        _ source: TAPPendingCaptureRecord,
        assetLocalIdentifier: String,
        duplicateExportWarning: String?,
        now: Date
    ) -> TAPPendingCaptureRecord {
        var record = source
        record.status = .exported
        if record.artifactKind == .tapVideo {
            record.videoPhotosExportPhase = .committed
        }
        record.assetLocalIdentifier = assetLocalIdentifier
        record.failureReason = nil
        record.failureCode = nil
        record.preSignContentBinding = nil
        record.duplicateExportWarning = duplicateExportWarning
        record.location = nil
        record.updatedAt = now
        return record
    }

    private static func requireUncommittedSignedVideo(
        _ record: TAPPendingCaptureRecord,
        reason: String
    ) throws {
        guard record.artifactKind == .tapVideo,
              record.videoArtifactState == .signed,
              record.status != .failedTerminal,
              record.status != .exported,
              record.assetLocalIdentifier == nil else {
            throw invalid(reason)
        }
    }

    private static func resetExportingState(
        _ record: inout TAPPendingCaptureRecord,
        now: Date
    ) {
        record.status = .exporting
        record.failureReason = nil
        record.failureCode = nil
        record.updatedAt = now
    }

    private static func invalid(_ reason: String) -> TAPDepthCaptureError {
        .invalidPendingCaptureBundlePath(reason)
    }
}
