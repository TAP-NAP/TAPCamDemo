//
//  DepthAnalysisSharePresentation.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum DepthAnalysisShareMediaKind: Equatable, Sendable {
    case photo
    case video
}

/// Lightweight identity captured at the instant the viewer Share button is
/// pressed. Heavy Photos handles and media bytes stay out of sheet routing.
nonisolated struct DepthAnalysisShareSubject: Identifiable, Equatable, Sendable {
    let id: String
    let mediaID: LibraryMediaID
    let captureID: String?
    let assetID: String?
    let hasIdentityConflict: Bool
    let mediaKind: DepthAnalysisShareMediaKind
    let expectsPairedVideo: Bool

    init(entry: DepthAnalysisCarouselEntry) {
        let mediaCaptureID: String?
        switch entry.mediaID {
        case .tapCapture(let captureID):
            mediaCaptureID = captureID
        case .photosAsset:
            mediaCaptureID = nil
        }

        let sourceAssetID: String?
        switch entry.source {
        case .photosAsset(let assetID):
            sourceAssetID = assetID
        case .pendingCapture:
            sourceAssetID = nil
        }

        let routeCaptureID = entry.albumEntry?.routeAnchor.captureID
        let routeAssetID = entry.albumEntry?.routeAnchor.assetLocalIdentifier

        id = entry.id
        mediaID = entry.mediaID
        captureID = mediaCaptureID ?? routeCaptureID
        assetID = sourceAssetID ?? routeAssetID
        hasIdentityConflict = Self.valuesConflict(mediaCaptureID, routeCaptureID)
            || Self.valuesConflict(sourceAssetID, routeAssetID)
        mediaKind = .photo
        expectsPairedVideo = entry.albumEntry?.expectsPairedVideo ?? false
    }

    init(videoSource: TAPVideoPlaybackSource, itemID: String) {
        id = itemID
        mediaID = videoSource.libraryMediaID
        switch videoSource {
        case .pendingCapture(let captureID):
            self.captureID = captureID
            assetID = nil
        case .ownedCapture(let captureID, let assetID):
            self.captureID = captureID
            self.assetID = assetID
        case .photosAsset(let assetID):
            captureID = nil
            self.assetID = assetID
        #if DEBUG
        case .fixtureFile:
            captureID = nil
            assetID = nil
        #endif
        }
        hasIdentityConflict = false
        mediaKind = .video
        expectsPairedVideo = false
    }

    init(
        id: String,
        mediaID: LibraryMediaID,
        captureID: String?,
        assetID: String?,
        hasIdentityConflict: Bool = false,
        mediaKind: DepthAnalysisShareMediaKind = .photo,
        expectsPairedVideo: Bool = false
    ) {
        self.id = id
        self.mediaID = mediaID
        self.captureID = captureID
        self.assetID = assetID
        self.hasIdentityConflict = hasIdentityConflict
        self.mediaKind = mediaKind
        self.expectsPairedVideo = expectsPairedVideo
    }

    private static func valuesConflict(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        return lhs != rhs
    }
}

/// Product-facing TAPNAP state. `verified` means signing completion is already
/// durably recorded; this policy intentionally performs no cryptographic work.
nonisolated enum DepthAnalysisShareCertificationState: String, Equatable, Sendable {
    case verified
    case retryPending
    case failed
}

nonisolated enum DepthAnalysisShareCertificationPolicy {
    static func state(
        for record: TAPPendingCaptureRecord?
    ) -> DepthAnalysisShareCertificationState {
        state(for: record, mediaKind: .photo)
    }

    static func state(
        for record: TAPPendingCaptureRecord?,
        mediaKind: DepthAnalysisShareMediaKind
    ) -> DepthAnalysisShareCertificationState {
        guard let record else {
            return .failed
        }

        switch mediaKind {
        case .photo:
            guard record.artifactKind == .photoDepth else {
                return .failed
            }
            if record.signedPhotoFilename != nil
                || record.status.hasDurablePhotoSignatureEvidence {
                return .verified
            }
        case .video:
            guard record.artifactKind == .tapVideo else {
                return .failed
            }
            // A persisted signed artifact is sufficient evidence. Sharing must
            // never reopen the MP4 merely to verify it again.
            if record.videoArtifactState == .signed {
                return .verified
            }
        }

        switch record.status {
        case .pending, .waitingNetwork, .signing, .failedRetryable:
            return .retryPending
        case .failedTerminal:
            return .failed
        case .signed, .exporting, .exported:
            // Photo records reached here only when their durable signature
            // fields are inconsistent; video requires its explicit signed
            // artifact state. Treat either mismatch as a terminal failure.
            return mediaKind == .photo ? .verified : .failed
        }
    }
}

nonisolated private extension TAPPendingCaptureStatus {
    var hasDurablePhotoSignatureEvidence: Bool {
        switch self {
        case .signed, .exporting, .exported:
            true
        case .pending, .waitingNetwork, .signing, .failedRetryable, .failedTerminal:
            false
        }
    }
}

nonisolated enum DepthAnalysisShareRecordResolutionError: Error, Equatable {
    case identityConflict
}

/// Resolves only app-private scalar records. It never reads Photos resources or
/// opens media files, which keeps sheet presentation independent from iCloud.
nonisolated struct DepthAnalysisShareRecordResolver: Sendable {
    typealias CaptureLoader = @Sendable (String) async throws -> TAPPendingCaptureRecord
    typealias AssetLoader = @Sendable (String) async throws -> TAPPendingCaptureRecord?

    private let captureLoader: CaptureLoader
    private let assetLoader: AssetLoader

    init(
        captureLoader: @escaping CaptureLoader = { captureID in
            try TAPPendingCaptureStore.shared.readRecord(captureID: captureID)
        },
        assetLoader: @escaping AssetLoader = { assetID in
            try TAPPendingCaptureStore.shared.record(assetLocalIdentifier: assetID)
        }
    ) {
        self.captureLoader = captureLoader
        self.assetLoader = assetLoader
    }

    func record(for subject: DepthAnalysisShareSubject) async throws -> TAPPendingCaptureRecord? {
        guard !subject.hasIdentityConflict else {
            throw DepthAnalysisShareRecordResolutionError.identityConflict
        }

        if let captureID = subject.captureID {
            let record = try await captureLoader(captureID)
            try Self.requireMatchingIdentity(record: record, subject: subject)
            return record
        }

        guard let assetID = subject.assetID else {
            return nil
        }
        return try await resolvedAssetRecord(assetID: assetID, subject: subject)
    }

    private func resolvedAssetRecord(
        assetID: String,
        subject: DepthAnalysisShareSubject
    ) async throws -> TAPPendingCaptureRecord? {
        let record = try await assetLoader(assetID)
        if let record {
            try Self.requireMatchingIdentity(record: record, subject: subject)
        }
        return record
    }

    private static func requireMatchingIdentity(
        record: TAPPendingCaptureRecord,
        subject: DepthAnalysisShareSubject
    ) throws {
        if let expectedCaptureID = subject.captureID,
           record.captureID != expectedCaptureID {
            throw DepthAnalysisShareRecordResolutionError.identityConflict
        }
        guard let expectedAssetID = subject.assetID else {
            return
        }
        guard record.assetLocalIdentifier == expectedAssetID else {
            throw DepthAnalysisShareRecordResolutionError.identityConflict
        }
    }
}
