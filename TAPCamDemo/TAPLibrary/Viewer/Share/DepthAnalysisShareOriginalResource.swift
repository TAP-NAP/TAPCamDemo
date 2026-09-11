//
//  DepthAnalysisShareOriginalResource.swift
//  TAPCamDemo
//

import Foundation

/// One complete Viewer original frozen at the instant Share opens.
///
/// The associated lease keeps its file-backed resource alive while local
/// content binding and payload preparation run. Callers never pass a detached
/// URL across either boundary.
nonisolated enum DepthAnalysisShareOriginalResource: @unchecked Sendable {
    case photo(TAPPhotoOriginalResourceLease)
    case video(TAPVideoOriginalResourceLease)

    var mediaID: LibraryMediaID {
        switch self {
        case .photo(let lease):
            lease.mediaID
        case .video(let lease):
            lease.mediaID
        }
    }

    var mediaKind: DepthAnalysisShareMediaKind {
        switch self {
        case .photo:
            .photo
        case .video:
            .video
        }
    }

    func matches(mediaID: LibraryMediaID) -> Bool {
        self.mediaID == mediaID
    }

    /// Binds the frozen original to both the stable Library identity and the
    /// concrete route that supplied its bytes. The asset check matters for an
    /// owned capture because its stable `.tapCapture` identity intentionally
    /// survives the pending-to-Photos transition.
    func matches(subject: DepthAnalysisShareSubject) -> Bool {
        guard mediaKind == subject.mediaKind,
              matches(mediaID: subject.mediaID) else {
            return false
        }
        switch self {
        case .photo(let lease):
            return lease.expectsPairedVideo == subject.expectsPairedVideo
                && Self.photoLease(lease, matches: subject)
        case .video(let lease):
            return Self.videoLease(lease, matches: subject)
        }
    }

    private static func photoLease(
        _ lease: TAPPhotoOriginalResourceLease,
        matches subject: DepthAnalysisShareSubject
    ) -> Bool {
        switch lease.origin {
        case .pendingCapture(let captureID, _):
            guard case .tapCapture(let mediaCaptureID) = lease.mediaID else {
                return false
            }
            return subject.usesPendingCaptureResource
                && subject.captureID == captureID
                && subject.assetID == nil
                && mediaCaptureID == captureID
        case .photosAsset(let assetID):
            guard !subject.usesPendingCaptureResource,
                  subject.assetID == assetID else {
                return false
            }
            switch lease.mediaID {
            case .tapCapture(let captureID):
                return subject.captureID == captureID
            case .photosAsset(let mediaAssetID):
                return subject.captureID == nil && mediaAssetID == assetID
            }
        }
    }

    private static func videoLease(
        _ lease: TAPVideoOriginalResourceLease,
        matches subject: DepthAnalysisShareSubject
    ) -> Bool {
        switch lease.origin {
        case .pendingCapture(let captureID):
            guard case .tapCapture(let mediaCaptureID) = lease.mediaID else {
                return false
            }
            return subject.usesPendingCaptureResource
                && subject.captureID == captureID
                && subject.assetID == nil
                && mediaCaptureID == captureID
        case .ownedPhotosAsset(let captureID, let assetID):
            guard case .tapCapture(let mediaCaptureID) = lease.mediaID else {
                return false
            }
            return !subject.usesPendingCaptureResource
                && subject.captureID == captureID
                && subject.assetID == assetID
                && mediaCaptureID == captureID
        case .photosAsset(let assetID):
            guard case .photosAsset(let mediaAssetID) = lease.mediaID else {
                return false
            }
            return !subject.usesPendingCaptureResource
                && subject.captureID == nil
                && subject.assetID == assetID
                && mediaAssetID == assetID
        case .debugFixture:
            return !subject.usesPendingCaptureResource
                && subject.captureID == nil
                && subject.assetID == nil
        }
    }
}

/// A capability for the source displayed when Share is tapped. The asynchronous
/// closure captures that source's owner, never a later current pager item, and
/// joins its existing original-resource request.
@MainActor
struct DepthAnalysisShareResourceAccess {
    let isReady: Bool
    private let acquireHandler: @MainActor () -> DepthAnalysisShareOriginalResource?
    private let preparedHandler: (@MainActor (Bool) async throws -> DepthAnalysisShareOriginalResource)?

    init(
        isReady: Bool,
        acquire: @escaping @MainActor () -> DepthAnalysisShareOriginalResource?,
        acquirePrepared: (@MainActor (Bool) async throws -> DepthAnalysisShareOriginalResource)? = nil
    ) {
        self.isReady = isReady
        acquireHandler = acquire
        preparedHandler = acquirePrepared
    }

    func acquire() -> DepthAnalysisShareOriginalResource? {
        guard isReady else { return nil }
        return acquireHandler()
    }

    func acquirePrepared(requiresSignedOriginal: Bool) async throws -> DepthAnalysisShareOriginalResource {
        if let preparedHandler {
            return try await preparedHandler(requiresSignedOriginal)
        }
        guard let resource = acquire(),
              !requiresSignedOriginal || resource.selectedSignedOriginal == true else {
            throw TAPNAPShareArtifactError.shareResourceUnavailable
        }
        return resource
    }
}

nonisolated extension DepthAnalysisShareOriginalResource {
    var selectedSignedOriginal: Bool? {
        switch self {
        case .photo(let lease):
            if case .pendingCapture(_, let signed) = lease.origin { return signed }
            return nil
        case .video(let lease):
            return lease.selectedSignedVideo
        }
    }
}

nonisolated protocol DepthAnalysisShareLocalIntegrityValidating: Sendable {
    @concurrent
    func validate(
        resource: DepthAnalysisShareOriginalResource,
        expectedCaptureID: String?,
        expectedPackageID: UUID?
    ) async throws
}

/// Local-only proof/content-binding validation. It recomputes byte binding but
/// cannot authenticate the App Attest assertion signature because the App does
/// not own the backend-registered public key. This type has no App Attest client
/// or backend dependency; any network use happened earlier only while Photos
/// resolved an iCloud original.
nonisolated struct DepthAnalysisShareLocalIntegrityValidator:
    DepthAnalysisShareLocalIntegrityValidating
{
    private let photoValidator: TAPPhotoLocalIntegrityValidator
    private let videoValidator: TAPVideoLocalIntegrityValidator

    init(
        photoValidator: TAPPhotoLocalIntegrityValidator = .init(),
        videoValidator: TAPVideoLocalIntegrityValidator = .init()
    ) {
        self.photoValidator = photoValidator
        self.videoValidator = videoValidator
    }

    func validate(
        resource: DepthAnalysisShareOriginalResource,
        expectedCaptureID: String?,
        expectedPackageID: UUID?
    ) async throws {
        switch resource {
        case .photo(let resource):
            _ = try photoValidator.validate(
                resource,
                expectedCaptureID: expectedCaptureID
            )
        case .video(let resource):
            _ = try await videoValidator.validate(
                resource,
                expectedCaptureID: expectedCaptureID,
                expectedPackageID: expectedPackageID
            )
        }
    }
}

nonisolated enum TAPPendingVideoShareDisposition: Equatable, Sendable {
    case validateSignedOriginal
    case needsRetry
    case failed
}

nonisolated enum TAPPendingVideoSharePolicy {
    static func disposition(
        for record: TAPPendingCaptureRecord?,
        selectedSignedVideo: Bool
    ) -> TAPPendingVideoShareDisposition {
        guard let record, record.artifactKind == .tapVideo else {
            return .failed
        }
        // The actor-owned Viewer snapshot is authoritative for the exact
        // bytes retained by this presentation. A later record transition
        // cannot promote an older unsigned snapshot to Verified.
        if selectedSignedVideo {
            return .validateSignedOriginal
        }
        switch record.status {
        case .pending, .waitingNetwork, .signing, .failedRetryable:
            return .needsRetry
        case .signed, .exporting, .exported, .failedTerminal:
            return .failed
        }
    }
}
