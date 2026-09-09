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
    let usesPendingCaptureResource: Bool

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
        if case .pendingCapture = entry.source {
            usesPendingCaptureResource = true
        } else {
            usesPendingCaptureResource = false
        }
    }

    init(videoSource: TAPVideoPlaybackSource, itemID: String) {
        id = itemID
        mediaID = videoSource.libraryMediaID
        switch videoSource {
        case .pendingCapture(let captureID):
            self.captureID = captureID
            assetID = nil
            usesPendingCaptureResource = true
        case .ownedCapture(let captureID, let assetID):
            self.captureID = captureID
            self.assetID = assetID
            usesPendingCaptureResource = false
        case .photosAsset(let assetID):
            captureID = nil
            self.assetID = assetID
            usesPendingCaptureResource = false
        #if DEBUG
        case .fixtureFile:
            captureID = nil
            assetID = nil
            usesPendingCaptureResource = false
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
        expectsPairedVideo: Bool = false,
        usesPendingCaptureResource: Bool? = nil
    ) {
        self.id = id
        self.mediaID = mediaID
        self.captureID = captureID
        self.assetID = assetID
        self.hasIdentityConflict = hasIdentityConflict
        self.mediaKind = mediaKind
        self.expectsPairedVideo = expectsPairedVideo
        self.usesPendingCaptureResource = usesPendingCaptureResource
            ?? (captureID != nil && assetID == nil)
    }

    private static func valuesConflict(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        return lhs != rhs
    }
}

/// Product-facing owned-capture Share state. The internal
/// `localIntegrityPassed` result is emitted only after the frozen Viewer
/// original matches its embedded digest and signing binding. The UI may map
/// that result to the approved `Verified` label, but the state itself means
/// byte integrity only—not independent App Attest assertion-signature
/// verification. The queue-only policy below classifies whether pending bytes
/// are eligible for the check and never contacts a backend.
nonisolated enum DepthAnalysisShareCertificationState: String, Equatable, Sendable {
    case localIntegrityPassed
    case retryPending
    case failed
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
            let record: TAPPendingCaptureRecord
            do {
                record = try await captureLoader(captureID)
            } catch where Self.isMissingRecord(error) {
                // Exported Photos/iCloud media can legitimately outlive its
                // private queue record. A genuine absence is not an identity
                // conflict; the frozen media remains self-describing.
                return nil
            }
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
        let expectedKind: TAPPendingCaptureArtifactKind = switch subject.mediaKind {
        case .photo:
            .photoDepth
        case .video:
            .tapVideo
        }
        guard record.artifactKind == expectedKind else {
            throw DepthAnalysisShareRecordResolutionError.identityConflict
        }
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

    private static func isMissingRecord(_ error: any Error) -> Bool {
        let cocoaError = error as NSError
        guard cocoaError.domain == NSCocoaErrorDomain else {
            return false
        }
        return cocoaError.code == CocoaError.Code.fileNoSuchFile.rawValue
            || cocoaError.code == CocoaError.Code.fileReadNoSuchFile.rawValue
    }
}
