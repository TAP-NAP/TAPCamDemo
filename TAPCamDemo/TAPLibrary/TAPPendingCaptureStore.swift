//
//  TAPPendingCaptureStore.swift
//  TAPCamDemo
//

import Foundation
import OSLog

nonisolated enum TAPPendingCaptureStoreLookupError: LocalizedError, Equatable, Sendable {
    case ambiguousAssetLocalIdentifier

    var errorDescription: String? {
        switch self {
        case .ambiguousAssetLocalIdentifier:
            "More than one TAP capture record refers to the selected Photos asset."
        }
    }
}

nonisolated struct TAPPendingCaptureShareResourceSnapshot: Sendable {
    let photoURL: URL
    let pairedVideoURL: URL?
    let fileContainer: CapturePhotoFileContainer
    /// Describes the exact photo selected by the actor-owned snapshot, not a
    /// status inferred later by a presentation layer. Ordinary Viewer loading
    /// may select an unsigned fallback; TAPNAP preparation still requests a
    /// signed-only snapshot and therefore always receives `true` here.
    let selectedSignedPhoto: Bool

    init(
        photoURL: URL,
        pairedVideoURL: URL?,
        fileContainer: CapturePhotoFileContainer,
        selectedSignedPhoto: Bool = false
    ) {
        self.photoURL = photoURL
        self.pairedVideoURL = pairedVideoURL
        self.fileContainer = fileContainer
        self.selectedSignedPhoto = selectedSignedPhoto
    }
}

nonisolated struct TAPPendingVideoShareResourceSnapshot: Sendable {
    let videoURL: URL
}

nonisolated struct TAPPendingVideoPlaybackResourceSnapshot: Sendable {
    let videoURL: URL
    let selectedSignedVideo: Bool

    init(videoURL: URL, selectedSignedVideo: Bool = false) {
        self.videoURL = videoURL
        self.selectedSignedVideo = selectedSignedVideo
    }
}

/// One actor-issued, single-use working generation for pending TAP Video
/// signing. The file is an independent inode inside the pending bundle; only
/// the store that issued the attempt may publish or discard it.
nonisolated struct TAPPendingVideoSigningArtifact: Sendable {
    let captureID: String
    let packageID: UUID
    let attemptID: UUID
    let fileURL: URL
    let expectedPreSignContentBinding: CaptureContentBinding?
}

nonisolated enum TAPPendingVideoShareSnapshotError: Error, Equatable, Sendable {
    case notVideo
    case identityMismatch
    case signatureEvidenceUnavailable
    case sourceUnavailable
}

nonisolated enum TAPPendingCaptureShareResourceLinkPolicy: Equatable, Sendable {
    /// The snapshot remains app-internal and is consumed read-only while a
    /// TAPNAP archive is written.
    case allowReadOnlyHardLink

    /// The snapshot may cross the process boundary through the system share
    /// sheet, so it must not share an inode with durable signed source media.
    case requireIndependentFile
}

/// App-private staging store for unsigned/signed TAP depth photo files.
///
/// Each pending bundle stores one fixed container chosen at capture time. HEIC
/// and JPG share the same queue semantics; only their artifact filenames and
/// Photos UTType differ.
actor TAPPendingCaptureStore {
    static let shared = TAPPendingCaptureStore()

    private enum ShareResourceRole: String {
        case photo
        case pairedVideo
        case video
    }

    private static let shareSnapshotCopyBufferSize = 512 * 1_024

    private let storage: TAPPendingCaptureBundleStorage
    private var videoWorkspaces: TAPPendingVideoWorkspaceCoordinator
    private let maintenance: TAPPendingCaptureMaintenance
    private let shareSnapshotLinker: @Sendable (URL, URL) throws -> Void
    private let videoSigningRecordPreparationFault: @Sendable (TAPPendingCaptureRecord) throws -> Void
    private var activeVideoSigningAttempts: [String: UUID] = [:]

    init(
        rootURL: URL = TAPPendingCaptureRoot.defaultURL,
        storagePolicy: TAPLocalArtifactStoragePolicy = .privatePhotoArtifact,
        shareSnapshotLinker: @escaping @Sendable (URL, URL) throws -> Void = { sourceURL, destinationURL in
            try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
        },
        videoSigningRecordPreparationFault: @escaping @Sendable (TAPPendingCaptureRecord) throws -> Void = { _ in }
    ) {
        let storage = TAPPendingCaptureBundleStorage(
            rootURL: rootURL,
            storagePolicy: storagePolicy
        )
        self.storage = storage
        self.videoWorkspaces = TAPPendingVideoWorkspaceCoordinator(storage: storage)
        self.maintenance = TAPPendingCaptureMaintenance(storage: storage)
        self.shareSnapshotLinker = shareSnapshotLinker
        self.videoSigningRecordPreparationFault = videoSigningRecordPreparationFault
    }

    func beginVideoCaptureWorkspace(captureID: String) throws -> TAPVideoRecordingWorkspace {
        try videoWorkspaces.begin(captureID: captureID)
    }

    func abortVideoCaptureWorkspace(captureID: String) throws {
        try videoWorkspaces.abort(captureID: captureID)
    }

    func ingest(_ artifact: PackagedCaptureArtifact) throws -> TAPPendingCaptureRecord {
        try storage.ensureRootDirectoryExists()

        let captureID = artifact.manifest.payload.id
        let finalURL = try storage.bundleURL(captureID: captureID)
        if storage.bundleExists(at: finalURL),
           let existing = try? readRecord(captureID: captureID) {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("store ingest existing captureID=\(captureID, privacy: .private) status=\(existing.status.rawValue, privacy: .public) retryCount=\(existing.retryCount, privacy: .public)")
            #endif
            return existing
        }

        let temporaryURL = storage.temporaryBundleURL()
        try storage.createFreshTemporaryBundle(at: temporaryURL)

        try storage.writeUnsignedPhoto(
            artifact.photoData,
            fileContainer: artifact.fileContainer,
            to: temporaryURL
        )
        let pairedVideoFilename: String?
        if let livePhotoMovie = artifact.livePhotoMovie {
            try storage.copyPairedVideo(from: livePhotoMovie.fileURL, to: temporaryURL)
            pairedVideoFilename = TAPPendingCaptureBundlePathPolicy.pairedVideoFilename
        } else {
            pairedVideoFilename = nil
        }

        let thumbnailFilename: String?
        if let thumbnailData = TAPPendingCaptureThumbnailRenderer.thumbnailData(from: artifact.photoData) {
            try storage.writeThumbnail(thumbnailData, to: temporaryURL)
            thumbnailFilename = TAPPendingCaptureBundlePathPolicy.thumbnailFilename
        } else {
            thumbnailFilename = nil
        }

        let now = Date()
        let record = TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: artifact.packageID,
            capturedAt: artifact.capturedAt,
            createdAt: now,
            updatedAt: now,
            status: .pending,
            photoFileContainer: artifact.fileContainer,
            photoQualityLevel: artifact.photoQualityLevel,
            captureScoreSummary: artifact.captureScoreSummary,
            unsignedPhotoFilename: artifact.fileContainer.unsignedFilename,
            signedPhotoFilename: nil,
            pairedVideoFilename: pairedVideoFilename,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: nil,
            failureReason: nil,
            retryCount: 0,
            location: artifact.location.map(TAPPendingCaptureLocation.init)
        )
        try storage.writeRecord(record, in: temporaryURL)

        try storage.commitTemporaryBundle(at: temporaryURL, to: finalURL)
        TAPLibraryChangeNotifier.post()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store ingest created captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) unsignedBytes=\(artifact.photoData.count, privacy: .public) hasThumbnail=\(thumbnailFilename != nil, privacy: .public) hasPairedVideo=\(pairedVideoFilename != nil, privacy: .public)")
        #endif
        return record
    }

    func ingestVideo(
        _ artifact: TAPPendingVideoCaptureArtifact,
        terminalFailureCode: TAPPendingCaptureFailureCode? = nil
    ) throws -> TAPPendingCaptureRecord {
        try storage.ensureRootDirectoryExists()

        let captureID = artifact.captureID
        let workspaceURL = try videoWorkspaces.workspaceURL(captureID: captureID)
        _ = try TAPPendingVideoIngestValidator.validate(
            artifact: artifact,
            expectedWorkspaceURL: workspaceURL,
            terminalFailureCode: terminalFailureCode
        )
        let finalURL = try storage.bundleURL(captureID: captureID)
        if storage.bundleExists(at: finalURL),
           let existing = try? readRecord(captureID: captureID) {
            videoWorkspaces.discard(captureID: captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("store video ingest existing captureID=\(captureID, privacy: .private) status=\(existing.status.rawValue, privacy: .public) retryCount=\(existing.retryCount, privacy: .public)")
            #endif
            return existing
        }

        let byteCount = (try? artifact.videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        let now = Date()
        let record = TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: artifact.packageID,
            capturedAt: artifact.capturedAt,
            createdAt: now,
            updatedAt: now,
            status: terminalFailureCode == nil ? .pending : .failedTerminal,
            artifactKind: .tapVideo,
            captureScoreSummary: artifact.captureScoreSummary,
            unsignedPhotoFilename: nil,
            signedPhotoFilename: nil,
            videoArtifactFilename: TAPPendingCaptureBundlePathPolicy.videoArtifactFilename,
            videoFormatRevision: 2,
            videoArtifactState: .unsigned,
            posterRevision: 1,
            exportResourceFilename: PhotoLibraryWriter.tapVideoResourceFilename(
                packageID: artifact.packageID
            ),
            failureCode: terminalFailureCode,
            pairedVideoFilename: nil,
            thumbnailFilename: nil,
            assetLocalIdentifier: nil,
            failureReason: terminalFailureCode == nil
                ? nil
                : TAPPendingCaptureFailureReasonPresentation.persistedFailureReason(
                    for: .terminalFailure
                ),
            retryCount: 0,
            location: artifact.location
        )
        try storage.writeRecord(record, in: workspaceURL)

        try storage.commitTemporaryBundle(at: workspaceURL, to: finalURL)
        videoWorkspaces.didCommit(captureID: captureID)
        TAPLibraryChangeNotifier.post()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store video ingest created captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) videoBytes=\(byteCount, privacy: .public) formatRevision=2")
        #endif
        return record
    }

    /// On a fresh launch there are no in-memory owners, so any hidden video
    /// workspace is an interrupted recording. During the same process active
    /// capture IDs are excluded to avoid racing the recorder.
    @discardableResult
    func removeStaleVideoCaptureWorkspaces() throws -> Int {
        try videoWorkspaces.removeStaleWorkspaces()
    }

    func allRecords() throws -> [TAPPendingCaptureRecord] {
        try storage.ensureRootDirectoryExists()
        return try storage.bundleURLs().compactMap { url in
            try? storage.readNormalizedRecord(in: url, expectedCaptureID: url.lastPathComponent)
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// Resolves the durable queue record for a Photos asset without silently
    /// picking one side of a corrupt identity collision.
    func record(assetLocalIdentifier: String) throws -> TAPPendingCaptureRecord? {
        let matches = try allRecords().filter { record in
            record.assetLocalIdentifier == assetLocalIdentifier
        }
        guard matches.count <= 1 else {
            throw TAPPendingCaptureStoreLookupError.ambiguousAssetLocalIdentifier
        }
        return matches.first
    }

    func visiblePendingRecords() throws -> [TAPPendingCaptureRecord] {
        try allRecords().filter(\.isVisiblePendingItem)
    }

    func exportedRecords() throws -> [TAPPendingCaptureRecord] {
        try allRecords().filter { record in
            record.status == .exported && record.assetLocalIdentifier != nil
        }
    }

    func tapVideoRecordsMissingPoster() throws -> [TAPPendingCaptureRecord] {
        try allRecords().filter { record in
            guard record.artifactKind == .tapVideo,
                  record.status != .exported,
                  record.thumbnailFilename == nil,
                  record.videoArtifactFilename != nil else {
                return false
            }
            return (try? storage.videoURL(
                filename: TAPPendingCaptureBundlePathPolicy.videoArtifactFilename,
                captureID: record.captureID
            )) != nil
        }
    }

    func storeVideoPoster(
        _ data: Data,
        captureID: String,
        posterRevision: Int
    ) throws -> TAPPendingCaptureRecord {
        guard posterRevision > 0 else {
            throw TAPDepthCaptureError.invalidTAPManifest("video poster revision must be positive")
        }
        var record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video posters require a TAP video record"
            )
        }
        let bundleURL = try storage.bundleURL(captureID: captureID)
        try storage.writeThumbnail(data, to: bundleURL)
        record.thumbnailFilename = TAPPendingCaptureBundlePathPolicy.thumbnailFilename
        record.posterRevision = posterRevision
        record.updatedAt = Date()
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post()
        return record
    }

    func processingCandidates() throws -> [TAPPendingCaptureRecord] {
        try allRecords()
            .filter(\.isProcessingCandidate)
            .sorted { lhs, rhs in
                let lhsPriority = lhs.processingPriority ?? Int.max
                let rhsPriority = rhs.processingPriority ?? Int.max
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.capturedAt < rhs.capturedAt
            }
    }

    func nextProcessingCandidate(excludingCaptureIDs excludedCaptureIDs: Set<String> = []) throws -> TAPPendingCaptureRecord? {
        try processingCandidates().first { record in
            !excludedCaptureIDs.contains(record.captureID)
        }
    }

    func readRecord(captureID: String) throws -> TAPPendingCaptureRecord {
        try storage.readRecord(captureID: captureID)
    }

    func unsignedPhotoData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.unsignedPhotoFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return try storage.photoData(filename: filename, captureID: captureID)
    }

    func unsignedHEICData(captureID: String) throws -> Data {
        try unsignedPhotoData(captureID: captureID)
    }

    func signedPhotoData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.signedPhotoFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return try storage.photoData(filename: filename, captureID: captureID)
    }

    func signedHEICData(captureID: String) throws -> Data {
        try signedPhotoData(captureID: captureID)
    }

    func videoArtifactURL(captureID: String) throws -> URL {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.videoArtifactFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        if activeVideoSigningAttempts[captureID] == nil {
            // Completes cleanup after a crash between the durable record write
            // and removal of the swapped-out previous generation. Never touch
            // this path while a live signing attempt owns its working file.
            try storage.removeStaleVideoSigningArtifacts(captureID: captureID)
        }
        return try storage.videoURL(filename: filename, captureID: captureID)
    }

    /// Freezes the durable unsigned generation into an independent working
    /// inode before proof generation begins. This synchronous actor boundary
    /// may copy bytes, but it never waits for App Attest or the network.
    func beginVideoSigningArtifact(
        captureID: String
    ) throws -> TAPPendingVideoSigningArtifact {
        let record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo,
              record.status == .signing,
              record.videoArtifactState == .unsigned,
              let sourceFilename = record.videoArtifactFilename else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing artifact requires one unsigned signing record"
            )
        }
        guard activeVideoSigningAttempts[captureID] == nil else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing artifact attempt is already active"
            )
        }

        try storage.removeStaleVideoSigningArtifacts(captureID: captureID)
        let attemptID = UUID()
        let fileURL = try storage.createVideoSigningArtifactCopy(
            captureID: captureID,
            sourceFilename: sourceFilename,
            attemptID: attemptID
        )
        activeVideoSigningAttempts[captureID] = attemptID
        return TAPPendingVideoSigningArtifact(
            captureID: captureID,
            packageID: record.packageID,
            attemptID: attemptID,
            fileURL: fileURL,
            expectedPreSignContentBinding: record.preSignContentBinding
        )
    }

    /// Publishes a fully signed and locally validated working generation.
    /// Snapshot operations and this transition are actor-serialized, while the
    /// same-directory rename changes `artifact.mp4` from the complete old inode
    /// to the complete new inode atomically.
    func publishVideoSigningArtifact(
        _ artifact: TAPPendingVideoSigningArtifact
    ) throws -> TAPPendingCaptureRecord {
        guard activeVideoSigningAttempts[artifact.captureID] == artifact.attemptID else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing artifact attempt is stale"
            )
        }
        let source = try readRecord(captureID: artifact.captureID)
        guard source.artifactKind == .tapVideo,
              source.packageID == artifact.packageID,
              source.status == .signing,
              source.videoArtifactState == .unsigned,
              let sourceFilename = source.videoArtifactFilename else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing artifact cannot publish into the current record"
            )
        }
        let expectedFileURL = try storage.videoSigningArtifactURL(
            captureID: artifact.captureID,
            attemptID: artifact.attemptID
        )
        guard artifact.fileURL.standardizedFileURL == expectedFileURL.standardizedFileURL else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing artifact URL does not match its attempt"
            )
        }

        let record = try TAPPendingVideoRecordTransitions.markSigned(
            source,
            now: Date()
        )
        let previousGenerationURL = try storage.publishVideoSigningArtifact(
            captureID: artifact.captureID,
            sourceFilename: sourceFilename,
            attemptID: artifact.attemptID
        )
        do {
            try storage.commitVideoSigningRecord(
                record,
                attemptID: artifact.attemptID,
                preparationFault: videoSigningRecordPreparationFault
            )
        } catch {
            try? storage.rollbackPublishedVideoSigningArtifact(
                captureID: artifact.captureID,
                sourceFilename: sourceFilename,
                attemptID: artifact.attemptID,
                previousGenerationURL: previousGenerationURL
            )
            throw error
        }
        try? storage.commitPublishedVideoSigningArtifact(
            previousGenerationURL: previousGenerationURL
        )
        activeVideoSigningAttempts[artifact.captureID] = nil
        TAPLibraryChangeNotifier.post(captureID: record.captureID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info(
            "store video signed generation published captureID=\(artifact.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)"
        )
        #endif
        return record
    }

    /// Removes an unpublished generation after assertion, validation,
    /// cancellation, or stale-attempt failure. A generation already moved over
    /// the durable path is harmlessly treated as absent.
    func discardVideoSigningArtifact(
        _ artifact: TAPPendingVideoSigningArtifact
    ) throws {
        guard activeVideoSigningAttempts[artifact.captureID] == artifact.attemptID else {
            return
        }
        defer { activeVideoSigningAttempts[artifact.captureID] = nil }
        try storage.discardVideoSigningArtifact(
            captureID: artifact.captureID,
            attemptID: artifact.attemptID
        )
    }

    func bestAvailableVideoURL(captureID: String) throws -> URL {
        try videoArtifactURL(captureID: captureID)
    }

    func bestAvailablePhotoData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        if let filename = record.signedPhotoFilename {
            if let data = try storage.photoDataIfPresent(filename: filename, captureID: captureID) {
                return data
            }
        }
        if let filename = record.unsignedPhotoFilename {
            if let data = try storage.photoDataIfPresent(filename: filename, captureID: captureID) {
                return data
            }
        }
        throw TAPDepthCaptureError.pendingCaptureDataMissing
    }

    func bestAvailablePhotoURL(captureID: String) throws -> URL {
        let record = try readRecord(captureID: captureID)
        if let filename = record.signedPhotoFilename {
            if let url = try storage.photoURLIfPresent(filename: filename, captureID: captureID) {
                return url
            }
        }
        if let filename = record.unsignedPhotoFilename {
            if let url = try storage.photoURLIfPresent(filename: filename, captureID: captureID) {
                return url
            }
        }
        throw TAPDepthCaptureError.pendingCaptureDataMissing
    }

    /// Creates one stable photo resource snapshot while the store actor owns
    /// the pending bundle. Eligible same-volume files use hard links so this
    /// phase is effectively constant-time. Other filesystems fall back to a
    /// cancellable, progress-reporting streamed copy. Holding the actor for
    /// either path prevents the export worker from deleting a source midway.
    ///
    /// `requiresSignedPhoto` is deliberately explicit: TAPNAP packages and
    /// verified image sharing must never fall back to the unsigned staging
    /// file. Ordinary image sharing may opt into the existing signed-first
    /// fallback behavior. Hard links are only safe for app-internal,
    /// read-only package preparation; externally shared images require an
    /// independent file.
    func snapshotPhotoShareResources(
        captureID: String,
        to destinationDirectoryURL: URL,
        requiresSignedPhoto: Bool,
        includesPairedVideo: Bool,
        linkPolicy: TAPPendingCaptureShareResourceLinkPolicy = .requireIndependentFile,
        progressHandler: @escaping @Sendable (Double?) -> Void = { _ in }
    ) throws -> TAPPendingCaptureShareResourceSnapshot {
        let record = try readRecord(captureID: captureID)
        guard record.artifactKind == .photoDepth else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }

        let sourcePhotoURL: URL
        let selectedSignedPhoto: Bool
        if requiresSignedPhoto {
            guard let signedFilename = record.signedPhotoFilename,
                  let signedURL = try storage.photoURLIfPresent(
                    filename: signedFilename,
                    captureID: captureID
                  ) else {
                throw TAPDepthCaptureError.pendingCaptureDataMissing
            }
            sourcePhotoURL = signedURL
            selectedSignedPhoto = true
        } else if let signedFilename = record.signedPhotoFilename,
                  let signedURL = try storage.photoURLIfPresent(
                    filename: signedFilename,
                    captureID: captureID
                  ) {
            sourcePhotoURL = signedURL
            selectedSignedPhoto = true
        } else if let unsignedFilename = record.unsignedPhotoFilename,
                  let unsignedURL = try storage.photoURLIfPresent(
                    filename: unsignedFilename,
                    captureID: captureID
                  ) {
            sourcePhotoURL = unsignedURL
            selectedSignedPhoto = false
        } else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }

        let photoURL = destinationDirectoryURL.appendingPathComponent(
            "source-photo.\(record.photoFileContainer.tapnapFileExtension)"
        )
        let destinationPairedVideoURL = includesPairedVideo
            ? destinationDirectoryURL.appendingPathComponent("source-paired-video.mov")
            : nil

        let sourcePairedVideoURL: URL?
        if includesPairedVideo, let filename = record.pairedVideoFilename {
            do {
                sourcePairedVideoURL = try storage.pairedVideoURL(
                    filename: filename,
                    captureID: captureID
                )
            } catch TAPDepthCaptureError.pendingCaptureDataMissing {
                sourcePairedVideoURL = nil
            }
        } else {
            sourcePairedVideoURL = nil
        }

        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: destinationDirectoryURL,
                withIntermediateDirectories: true
            )

            let photoByteCount = try checkedShareResourceByteCount(at: sourcePhotoURL)
            let pairedVideoByteCount = try sourcePairedVideoURL.map {
                try checkedShareResourceByteCount(at: $0)
            } ?? 0
            let totalByteCount = max(photoByteCount + pairedVideoByteCount, 1)
            progressHandler(0)

            try createStableShareResourceSnapshot(
                from: sourcePhotoURL,
                to: photoURL,
                byteCount: photoByteCount,
                role: .photo,
                linkPolicy: linkPolicy,
                progressHandler: { copiedByteCount in
                    progressHandler(
                        min(1, Double(copiedByteCount) / Double(totalByteCount))
                    )
                }
            )

            let copiedPairedVideoURL: URL?
            if let sourcePairedVideoURL, let destinationPairedVideoURL {
                try createStableShareResourceSnapshot(
                    from: sourcePairedVideoURL,
                    to: destinationPairedVideoURL,
                    byteCount: pairedVideoByteCount,
                    role: .pairedVideo,
                    linkPolicy: linkPolicy,
                    progressHandler: { copiedByteCount in
                        progressHandler(
                            min(
                                1,
                                Double(photoByteCount + copiedByteCount)
                                    / Double(totalByteCount)
                            )
                        )
                    }
                )
                copiedPairedVideoURL = destinationPairedVideoURL
            } else {
                // Preserve the stable photo snapshot so the package builder
                // can report the more specific missing-pair error.
                copiedPairedVideoURL = nil
            }

            try Task.checkCancellation()
            progressHandler(1)
            return TAPPendingCaptureShareResourceSnapshot(
                photoURL: photoURL,
                pairedVideoURL: copiedPairedVideoURL,
                fileContainer: record.photoFileContainer,
                selectedSignedPhoto: selectedSignedPhoto
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectoryURL)
            throw error
        }
    }

    /// Creates an independent, byte-for-byte video snapshot while the store
    /// actor owns the pending bundle. This prevents an export worker from
    /// cleaning the source midway and avoids exposing durable media directly
    /// to another process through the system activity controller.
    func snapshotVideoShareResource(
        captureID: String,
        expectedAssetLocalIdentifier: String? = nil,
        to destinationDirectoryURL: URL,
        requiresSignedVideo: Bool,
        progressHandler: @escaping @Sendable (Double?) -> Void = { _ in }
    ) throws -> TAPPendingVideoShareResourceSnapshot {
        let record: TAPPendingCaptureRecord
        do {
            record = try readRecord(captureID: captureID)
        } catch TAPDepthCaptureError.pendingCaptureDataMissing {
            throw TAPPendingVideoShareSnapshotError.sourceUnavailable
        }
        guard record.artifactKind == .tapVideo else {
            throw TAPPendingVideoShareSnapshotError.notVideo
        }
        if let expectedAssetLocalIdentifier,
           record.assetLocalIdentifier != expectedAssetLocalIdentifier {
            throw TAPPendingVideoShareSnapshotError.identityMismatch
        }
        guard !requiresSignedVideo || record.videoArtifactState == .signed else {
            throw TAPPendingVideoShareSnapshotError.signatureEvidenceUnavailable
        }
        guard let filename = record.videoArtifactFilename else {
            throw TAPPendingVideoShareSnapshotError.sourceUnavailable
        }

        let sourceVideoURL: URL
        do {
            sourceVideoURL = try storage.videoURL(
                filename: filename,
                captureID: captureID
            )
        } catch TAPDepthCaptureError.pendingCaptureDataMissing {
            throw TAPPendingVideoShareSnapshotError.sourceUnavailable
        }
        let fileExtension = sourceVideoURL.pathExtension.isEmpty
            ? "mp4"
            : sourceVideoURL.pathExtension.lowercased()
        let destinationVideoURL = destinationDirectoryURL.appendingPathComponent(
            "source-video.\(fileExtension)"
        )

        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: destinationDirectoryURL,
                withIntermediateDirectories: true
            )
            let byteCount = try checkedShareResourceByteCount(at: sourceVideoURL)
            progressHandler(0)
            try createStableShareResourceSnapshot(
                from: sourceVideoURL,
                to: destinationVideoURL,
                byteCount: byteCount,
                role: .video,
                linkPolicy: .requireIndependentFile,
                progressHandler: { copiedByteCount in
                    progressHandler(
                        min(1, Double(copiedByteCount) / Double(max(byteCount, 1)))
                    )
                }
            )
            try Task.checkCancellation()
            progressHandler(1)
            return TAPPendingVideoShareResourceSnapshot(videoURL: destinationVideoURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectoryURL)
            throw error
        }
    }

    /// Creates a stable, independent original for Viewer playback. Resolving
    /// the queue path and starting the copy stay inside the store actor instead
    /// of exposing a detached durable URL to the Viewer. Later proof-slot writes
    /// or queue cleanup cannot mutate or unlink the returned copy. The caller
    /// owns the destination directory.
    func snapshotVideoPlaybackResource(
        captureID: String,
        to destinationDirectoryURL: URL,
        progressHandler: @escaping @Sendable (Double?) -> Void = { _ in }
    ) throws -> TAPPendingVideoPlaybackResourceSnapshot {
        let record: TAPPendingCaptureRecord
        do {
            record = try readRecord(captureID: captureID)
        } catch TAPDepthCaptureError.pendingCaptureDataMissing {
            throw TAPPendingVideoShareSnapshotError.sourceUnavailable
        }
        guard record.artifactKind == .tapVideo,
              let filename = record.videoArtifactFilename else {
            throw TAPPendingVideoShareSnapshotError.sourceUnavailable
        }

        let sourceVideoURL: URL
        do {
            sourceVideoURL = try storage.videoURL(
                filename: filename,
                captureID: captureID
            )
        } catch TAPDepthCaptureError.pendingCaptureDataMissing {
            throw TAPPendingVideoShareSnapshotError.sourceUnavailable
        }
        let fileExtension = sourceVideoURL.pathExtension.isEmpty
            ? "mp4"
            : sourceVideoURL.pathExtension.lowercased()
        let destinationVideoURL = destinationDirectoryURL.appendingPathComponent(
            "playback-source.\(fileExtension)"
        )

        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: destinationDirectoryURL,
                withIntermediateDirectories: true
            )
            let byteCount = try checkedShareResourceByteCount(at: sourceVideoURL)
            progressHandler(0)
            try createStableShareResourceSnapshot(
                from: sourceVideoURL,
                to: destinationVideoURL,
                byteCount: byteCount,
                role: .video,
                // A hard link survives unlinking but not in-place proof-slot
                // writes. Pending signing can mutate the same inode, so
                // playback needs an independent byte snapshot.
                linkPolicy: .requireIndependentFile,
                progressHandler: { copiedByteCount in
                    progressHandler(
                        min(1, Double(copiedByteCount) / Double(max(byteCount, 1)))
                    )
                }
            )
            try Task.checkCancellation()
            progressHandler(1)
            return TAPPendingVideoPlaybackResourceSnapshot(
                videoURL: destinationVideoURL,
                selectedSignedVideo: record.videoArtifactState == .signed
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectoryURL)
            throw error
        }
    }

    private func checkedShareResourceByteCount(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return size.int64Value
    }

    private func createStableShareResourceSnapshot(
        from sourceURL: URL,
        to destinationURL: URL,
        byteCount: Int64,
        role: ShareResourceRole,
        linkPolicy: TAPPendingCaptureShareResourceLinkPolicy,
        progressHandler: (Int64) -> Void
    ) throws {
        let startedAt = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()

        if linkPolicy == .allowReadOnlyHardLink {
            do {
                try shareSnapshotLinker(sourceURL, destinationURL)
                try Task.checkCancellation()
                progressHandler(byteCount)
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                let durationMilliseconds = max(
                    0,
                    (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                )
                TAPDiagnostics.sharePackaging.info(
                    "tapnap local snapshot completed role=\(role.rawValue, privacy: .public) strategy=hardLink durationMs=\(durationMilliseconds, privacy: .public) bytes=\(byteCount, privacy: .public)"
                )
                #endif
                return
            } catch {
                if error is CancellationError {
                    throw error
                }
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }

        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destinationHandle: FileHandle
        do {
            destinationHandle = try FileHandle(forWritingTo: destinationURL)
        } catch {
            try? sourceHandle.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        do {
            var copiedByteCount: Int64 = 0
            while true {
                try Task.checkCancellation()
                guard let chunk = try sourceHandle.read(
                    upToCount: Self.shareSnapshotCopyBufferSize
                ), !chunk.isEmpty else {
                    break
                }
                try destinationHandle.write(contentsOf: chunk)
                copiedByteCount += Int64(chunk.count)
                progressHandler(min(copiedByteCount, byteCount))
            }
            guard copiedByteCount == byteCount else {
                throw CocoaError(.fileReadUnknown)
            }
            try destinationHandle.synchronize()
            try Task.checkCancellation()
            try sourceHandle.close()
            try destinationHandle.close()

            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            let durationMilliseconds = max(
                0,
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
            TAPDiagnostics.sharePackaging.info(
                "tapnap local snapshot completed role=\(role.rawValue, privacy: .public) strategy=streamedCopy durationMs=\(durationMilliseconds, privacy: .public) bytes=\(byteCount, privacy: .public)"
            )
            #endif
        } catch {
            try? sourceHandle.close()
            try? destinationHandle.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    func bestAvailableHEICData(captureID: String) throws -> Data {
        try bestAvailablePhotoData(captureID: captureID)
    }

    func thumbnailData(captureID: String) throws -> Data? {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.thumbnailFilename else {
            return nil
        }
        return try storage.thumbnailData(filename: filename, captureID: captureID)
    }

    func pairedVideoURL(captureID: String) throws -> URL? {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.pairedVideoFilename else {
            return nil
        }
        return try storage.pairedVideoURL(filename: filename, captureID: captureID)
    }

    func updateStatus(
        captureID: String,
        status: TAPPendingCaptureStatus,
        failureReason: TAPPendingCaptureFailureReasonPresentation.Reason? = nil,
        failureCode: TAPPendingCaptureFailureCode? = nil,
        incrementsRetryCount: Bool = false
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        // Export is a durable terminal commit. A later cleanup or stale worker
        // error must never put the record back on an export route and create a
        // duplicate Photos asset.
        guard record.status != .exported || status == .exported else {
            return record
        }
        record.status = status
        record.failureReason = TAPPendingCaptureFailureReasonPresentation.normalizedPersistedFailureReason(
            failureReason,
            status: status
        )
        record.failureCode = status == .failedTerminal ? failureCode : nil
        record.updatedAt = Date()
        if incrementsRetryCount {
            record.retryCount += 1
        }
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post(captureID: captureID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store status updated captureID=\(captureID, privacy: .private) status=\(status.rawValue, privacy: .public) retryCount=\(record.retryCount, privacy: .public) hasFailureReason=\(failureReason != nil, privacy: .public)")
        #endif
        return record
    }

    @discardableResult
    func normalizePersistedFailureReasons() throws -> Int {
        let count = try maintenance.normalizePersistedFailureReasons()
        if count > 0 {
            TAPLibraryChangeNotifier.post()
        }
        return count
    }

    @discardableResult
    func reopenLegacyUnsignedVideoValidationFailures() throws -> Int {
        let count = try maintenance.reopenLegacyUnsignedVideoValidationFailures()
        if count > 0 {
            TAPLibraryChangeNotifier.post()
        }
        return count
    }

    func storeSignedPhoto(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        try storage.writeSignedPhoto(data, fileContainer: record.photoFileContainer, captureID: captureID)
        record.signedPhotoFilename = record.photoFileContainer.signedFilename
        record.status = .signed
        record.failureReason = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post(captureID: captureID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store signedPhoto stored captureID=\(captureID, privacy: .private) container=\(record.photoFileContainer.rawValue, privacy: .public) bytes=\(data.count, privacy: .public) status=\(record.status.rawValue, privacy: .public)")
        #endif
        return record
    }

    func storeSignedHEIC(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        try storeSignedPhoto(data, captureID: captureID)
    }

    func markVideoSigned(captureID: String) throws -> TAPPendingCaptureRecord {
        let source = try readRecord(captureID: captureID)
        let record = try TAPPendingVideoRecordTransitions.markSigned(
            source,
            now: Date()
        )
        _ = try videoArtifactURL(captureID: captureID)
        try persistTransition(from: source, to: record)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store video signed state updated captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
        #endif
        return record
    }

    func persistVideoPreSignContentBinding(
        _ binding: CaptureContentBinding,
        captureID: String
    ) throws -> TAPPendingCaptureRecord {
        let source = try readRecord(captureID: captureID)
        let record = try TAPPendingVideoRecordTransitions.persistPreSignBinding(
            binding,
            in: source,
            now: Date()
        )
        try persistTransition(from: source, to: record)
        return record
    }

    func markTerminalFailure(
        captureID: String,
        code: TAPPendingCaptureFailureCode,
        assetLocalIdentifier: String? = nil
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        record.status = .failedTerminal
        record.failureCode = code
        record.failureReason = TAPPendingCaptureFailureReasonPresentation.persistedFailureReason(
            for: .terminalFailure
        )
        if let assetLocalIdentifier {
            record.assetLocalIdentifier = assetLocalIdentifier
        }
        record.updatedAt = Date()
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post(captureID: captureID)
        return record
    }

    /// Persists safe-to-repeat export intent before any Photos asset creation
    /// begins. A restart in this phase may validate and create again.
    func markVideoPhotosExportIntent(
        captureID: String
    ) throws -> TAPPendingCaptureRecord {
        let source = try readRecord(captureID: captureID)
        let record = try TAPPendingVideoRecordTransitions.markExportIntent(
            source,
            now: Date()
        )
        try persistTransition(from: source, to: record)
        return record
    }

    /// Must be called immediately before entering Photos `performChanges`.
    /// From this durable boundary onward, a missing completion callback is
    /// commit-ambiguous and restart recovery may only probe/read back.
    func markVideoPhotosCommitAmbiguous(
        captureID: String
    ) throws -> TAPPendingCaptureRecord {
        let source = try readRecord(captureID: captureID)
        let record = try TAPPendingVideoRecordTransitions.markCommitAmbiguous(
            source,
            now: Date()
        )
        try persistTransition(from: source, to: record)
        return record
    }

    /// Persists the Photos identifier returned after the commit-ambiguous
    /// boundary. Retries must only re-read this asset; they must never create a
    /// second asset automatically.
    func markVideoPhotosCommit(
        captureID: String,
        assetLocalIdentifier: String
    ) throws -> TAPPendingCaptureRecord {
        let source = try readRecord(captureID: captureID)
        let record = try TAPPendingVideoRecordTransitions.markCommit(
            source,
            assetLocalIdentifier: assetLocalIdentifier,
            now: Date()
        )
        try persistTransition(from: source, to: record)
        return record
    }

    func markExported(
        captureID: String,
        assetLocalIdentifier: String,
        duplicateExportWarning: String? = nil
    ) throws -> TAPPendingCaptureRecord {
        let source = try readRecord(captureID: captureID)
        let record = TAPPendingVideoRecordTransitions.markExported(
            source,
            assetLocalIdentifier: assetLocalIdentifier,
            duplicateExportWarning: duplicateExportWarning,
            now: Date()
        )
        try storage.writeRecord(record)
        // Return the exact persisted representation so a stale, idempotent
        // Photos callback observes the same timestamp value after JSON
        // round-trip instead of an in-memory sub-precision variant.
        let persistedRecord = try readRecord(captureID: captureID)
        do {
            try storage.cleanupLargeFiles(for: persistedRecord)
        } catch {
            // The authoritative Photos readback has already passed and the
            // exported state is persisted. Startup cleanup can retry local file
            // removal; cleanup failure must not roll back the export commit.
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error(
                "store exported cleanup deferred captureID=\(captureID, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)"
            )
            #endif
        }
        TAPLibraryChangeNotifier.post()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store exported marked captureID=\(captureID, privacy: .private) assetID=\(assetLocalIdentifier, privacy: .private)")
        #endif
        return persistedRecord
    }

    func cleanupExportedLargeFiles() throws {
        try maintenance.cleanupExportedLargeFiles(records: allRecords())
    }

    @discardableResult
    func removeUnshippedLegacyVideoBundles() throws -> Int {
        let removedCount = try maintenance.removeUnshippedLegacyVideoBundles(
            records: allRecords()
        )
        if removedCount > 0 {
            TAPLibraryChangeNotifier.post()
        }
        return removedCount
    }

    func removeRecord(captureID: String) throws {
        if try storage.removeBundle(captureID: captureID) {
            TAPLibraryChangeNotifier.post()
        }
    }

    /// Removes app-private exported records that refer to a Photos asset after
    /// that asset has been deleted. Older viewer routes only retained the
    /// Photos identifier, so lookup by asset ID keeps their cleanup complete.
    @discardableResult
    func removeExportedRecords(assetLocalIdentifier: String) throws -> Int {
        let matchingCaptureIDs = try exportedRecords().compactMap { record in
            record.assetLocalIdentifier == assetLocalIdentifier ? record.captureID : nil
        }
        var removedCount = 0
        for captureID in matchingCaptureIDs where try storage.removeBundle(captureID: captureID) {
            removedCount += 1
        }
        if removedCount > 0 {
            TAPLibraryChangeNotifier.post()
        }
        return removedCount
    }

    private func persistTransition(
        from source: TAPPendingCaptureRecord,
        to record: TAPPendingCaptureRecord
    ) throws {
        guard source != record else {
            return
        }
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post(captureID: record.captureID)
    }

}
