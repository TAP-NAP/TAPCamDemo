//
//  TAPPendingCaptureStore.swift
//  TAPCamDemo
//

import Foundation
import OSLog

/// App-private staging store for unsigned/signed TAP depth photo files.
///
/// Each pending bundle stores one fixed container chosen at capture time. HEIC
/// and JPG share the same queue semantics; only their artifact filenames and
/// Photos UTType differ.
actor TAPPendingCaptureStore {
    static let shared = TAPPendingCaptureStore()

    private let storage: TAPPendingCaptureBundleStorage
    private var videoWorkspaces: TAPPendingVideoWorkspaceCoordinator
    private let maintenance: TAPPendingCaptureMaintenance
    private let lockedCaptureImporter: TAPPendingLockedCaptureImporter

    init(
        rootURL: URL = TAPPendingCaptureRoot.defaultURL,
        storagePolicy: TAPLocalArtifactStoragePolicy = .privatePhotoArtifact
    ) {
        let storage = TAPPendingCaptureBundleStorage(
            rootURL: rootURL,
            storagePolicy: storagePolicy
        )
        self.storage = storage
        self.videoWorkspaces = TAPPendingVideoWorkspaceCoordinator(storage: storage)
        self.maintenance = TAPPendingCaptureMaintenance(storage: storage)
        self.lockedCaptureImporter = TAPPendingLockedCaptureImporter(storage: storage)
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

    func ingestLockedCapture(
        _ lockedCapture: TAPPendingLockedCaptureImport
    ) throws -> TAPPendingCaptureRecord {
        try lockedCaptureImporter.validate(lockedCapture)
        try storage.ensureRootDirectoryExists()
        let captureID = lockedCapture.captureID
        let finalURL = try storage.bundleURL(captureID: captureID)
        if storage.bundleExists(at: finalURL),
           let existing = try? readRecord(captureID: captureID) {
            return existing
        }
        let result = try lockedCaptureImporter.ingest(lockedCapture)
        TAPLibraryChangeNotifier.post()
        return result.record
    }

    func allRecords() throws -> [TAPPendingCaptureRecord] {
        try storage.ensureRootDirectoryExists()
        return try storage.bundleURLs().compactMap { url in
            try? storage.readNormalizedRecord(in: url, expectedCaptureID: url.lastPathComponent)
        }
        .sorted { $0.capturedAt > $1.capturedAt }
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
        return try storage.videoURL(filename: filename, captureID: captureID)
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
        TAPLibraryChangeNotifier.post()
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

    func storeSignedPhoto(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        try storage.writeSignedPhoto(data, fileContainer: record.photoFileContainer, captureID: captureID)
        record.signedPhotoFilename = record.photoFileContainer.signedFilename
        record.status = .signed
        record.failureReason = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post()
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
        TAPDiagnostics.pendingCapture.info("store video signed in place captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
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
        TAPLibraryChangeNotifier.post()
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

    private func persistTransition(
        from source: TAPPendingCaptureRecord,
        to record: TAPPendingCaptureRecord
    ) throws {
        guard source != record else {
            return
        }
        try storage.writeRecord(record)
        TAPLibraryChangeNotifier.post()
    }

}
