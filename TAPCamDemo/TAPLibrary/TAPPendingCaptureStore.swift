//
//  TAPPendingCaptureStore.swift
//  TAPCamDemo
//

import Foundation
import OSLog

nonisolated struct TAPVideoRecordingWorkspace: Equatable, Sendable {
    let captureID: String
    let bundleURL: URL
    let artifactURL: URL
}

nonisolated struct TAPPendingVideoCaptureArtifact: Sendable {
    let captureID: String
    let packageID: UUID
    let capturedAt: Date
    let videoURL: URL
    let captureScoreSummary: CaptureScoreSummary
    let location: TAPPendingCaptureLocation?

    init(
        captureID: String,
        packageID: UUID = UUID(),
        capturedAt: Date,
        videoURL: URL,
        captureScoreSummary: CaptureScoreSummary = .unknown,
        location: TAPPendingCaptureLocation? = nil
    ) {
        self.captureID = captureID
        self.packageID = packageID
        self.capturedAt = capturedAt
        self.videoURL = videoURL
        self.captureScoreSummary = captureScoreSummary
        self.location = location
    }
}

nonisolated struct TAPPendingLockedCaptureImport: Sendable {
    let captureID: String
    let capturedAt: Date
    let unsignedPhotoURL: URL
    let metadata: TAPCamLockedRawCaptureMetadata

    init(
        captureID: String,
        capturedAt: Date,
        unsignedPhotoURL: URL,
        metadata: TAPCamLockedRawCaptureMetadata
    ) {
        self.captureID = captureID
        self.capturedAt = capturedAt
        self.unsignedPhotoURL = unsignedPhotoURL
        self.metadata = metadata
    }
}

/// App-private staging store for unsigned/signed TAP depth photo files.
///
/// Each pending bundle stores one fixed container chosen at capture time. HEIC
/// and JPG share the same queue semantics; only their artifact filenames and
/// Photos UTType differ.
actor TAPPendingCaptureStore {
    static let shared = TAPPendingCaptureStore()

    private let storage: TAPPendingCaptureBundleStorage
    private var activeVideoCaptureIDs: Set<String> = []

    init(
        rootURL: URL = TAPPendingCaptureStore.defaultRootURL(),
        storagePolicy: TAPLocalArtifactStoragePolicy = .privatePhotoArtifact
    ) {
        self.storage = TAPPendingCaptureBundleStorage(
            rootURL: rootURL,
            storagePolicy: storagePolicy
        )
    }

    func beginVideoCaptureWorkspace(captureID: String) throws -> TAPVideoRecordingWorkspace {
        try storage.ensureRootDirectoryExists()
        let workspaceURL = try storage.createFreshVideoCaptureWorkspace(captureID: captureID)
        activeVideoCaptureIDs.insert(captureID)
        return TAPVideoRecordingWorkspace(
            captureID: captureID,
            bundleURL: workspaceURL,
            artifactURL: workspaceURL.appendingPathComponent(
                TAPPendingCaptureBundlePathPolicy.videoArtifactFilename
            )
        )
    }

    func abortVideoCaptureWorkspace(captureID: String) throws {
        defer { activeVideoCaptureIDs.remove(captureID) }
        try storage.removeVideoCaptureWorkspace(captureID: captureID)
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
        Self.postLibraryDidChange()
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
        let workspaceURL = try storage.videoCaptureWorkspaceURL(captureID: captureID)
        let expectedArtifactURL = workspaceURL.appendingPathComponent(
            TAPPendingCaptureBundlePathPolicy.videoArtifactFilename
        )
        guard artifact.videoURL.standardizedFileURL == expectedArtifactURL.standardizedFileURL else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video recorder output must be inside its pending capture workspace"
            )
        }
        let manifest = try TAPVideoManifestBox.decodedManifest(fromFileAt: artifact.videoURL)
        guard manifest.schema == TAPVideoManifest.Schema(),
              manifest.payload.id == captureID,
              UUID(uuidString: manifest.payload.packageID) == artifact.packageID else {
            throw TAPDepthCaptureError.invalidTAPManifest("pending video identity does not match its manifest")
        }
        let hasRecordedDepth = manifest.payload.depthCoverage.sampleCount > 0
            && manifest.payload.depthCoverage.trackID != nil
            && manifest.payload.depthCoverage.format != nil
        if hasRecordedDepth {
            guard terminalFailureCode == nil else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "video with recorded depth cannot enter a terminal ingest state"
                )
            }
        } else {
            guard terminalFailureCode == .missingDepthData else {
                throw TAPDepthCaptureError.missingDepthData
            }
        }
        let finalURL = try storage.bundleURL(captureID: captureID)
        if storage.bundleExists(at: finalURL),
           let existing = try? readRecord(captureID: captureID) {
            try? storage.removeVideoCaptureWorkspace(captureID: captureID)
            activeVideoCaptureIDs.remove(captureID)
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
        activeVideoCaptureIDs.remove(captureID)
        Self.postLibraryDidChange()
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
        var removedCount = 0
        for workspaceURL in try storage.videoCaptureWorkspaceURLs() {
            let name = workspaceURL.lastPathComponent
            let captureID = String(name.dropFirst(
                TAPPendingCaptureBundlePathPolicy.videoCaptureWorkspacePrefix.count
            ))
            guard !captureID.isEmpty,
                  !activeVideoCaptureIDs.contains(captureID) else {
                continue
            }
            try storage.removeVideoCaptureWorkspace(at: workspaceURL)
            removedCount += 1
        }
        return removedCount
    }

    func ingestLockedCapture(_ lockedCapture: TAPPendingLockedCaptureImport) throws -> TAPPendingCaptureRecord {
        guard lockedCapture.captureID == lockedCapture.metadata.captureID else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("locked metadata captureID must match import captureID")
        }
        guard lockedCapture.metadata.photoFileName == CapturePhotoFileContainer.heic.unsignedFilename else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("locked import must use unsigned.heic")
        }
        guard lockedCapture.metadata.artifactKind == TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("locked import must be an unsigned TAP artifact")
        }
        guard lockedCapture.metadata.depthDataPresent == true else {
            throw TAPDepthCaptureError.missingDepthData
        }

        try storage.ensureRootDirectoryExists()

        let captureID = lockedCapture.captureID
        let finalURL = try storage.bundleURL(captureID: captureID)
        if storage.bundleExists(at: finalURL),
           let existing = try? readRecord(captureID: captureID) {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("store locked ingest existing captureID=\(captureID, privacy: .private) status=\(existing.status.rawValue, privacy: .public) retryCount=\(existing.retryCount, privacy: .public)")
            #endif
            return existing
        }

        let photoData = try Data(contentsOf: lockedCapture.unsignedPhotoURL)
        let temporaryURL = storage.temporaryBundleURL()
        try storage.createFreshTemporaryBundle(at: temporaryURL)
        try storage.writeUnsignedPhoto(photoData, fileContainer: .heic, to: temporaryURL)

        let thumbnailFilename: String?
        if let thumbnailData = TAPPendingCaptureThumbnailRenderer.thumbnailData(from: photoData) {
            try storage.writeThumbnail(thumbnailData, to: temporaryURL)
            thumbnailFilename = TAPPendingCaptureBundlePathPolicy.thumbnailFilename
        } else {
            thumbnailFilename = nil
        }

        let now = Date()
        let record = TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: UUID(uuidString: captureID) ?? UUID(),
            capturedAt: lockedCapture.capturedAt,
            createdAt: now,
            updatedAt: now,
            status: .pending,
            photoFileContainer: .heic,
            photoQualityLevel: .quality,
            captureScoreSummary: CaptureScoreSummary.make(
                depthAvailability: .available,
                fileContainer: .heic,
                photoQualityLevel: .quality,
                signatureStatus: .pending(reason: "Queued for App Attest signing.")
            ),
            unsignedPhotoFilename: CapturePhotoFileContainer.heic.unsignedFilename,
            signedPhotoFilename: nil,
            pairedVideoFilename: nil,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: nil,
            failureReason: nil,
            retryCount: 0,
            location: nil
        )
        try storage.writeRecord(record, in: temporaryURL)
        try storage.commitTemporaryBundle(at: temporaryURL, to: finalURL)
        Self.postLibraryDidChange()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store locked ingest created captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) unsignedBytes=\(photoData.count, privacy: .public) hasThumbnail=\(thumbnailFilename != nil, privacy: .public)")
        #endif
        return record
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
        Self.postLibraryDidChange()
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
        Self.postLibraryDidChange()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store status updated captureID=\(captureID, privacy: .private) status=\(status.rawValue, privacy: .public) retryCount=\(record.retryCount, privacy: .public) hasFailureReason=\(failureReason != nil, privacy: .public)")
        #endif
        return record
    }

    @discardableResult
    func normalizePersistedFailureReasons() throws -> Int {
        try storage.ensureRootDirectoryExists()
        var normalizedCount = 0
        for url in try storage.bundleURLs() {
            var record: TAPPendingCaptureRecord
            do {
                record = try storage.readStoredRecord(in: url, expectedCaptureID: url.lastPathComponent)
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.error("store skipped invalid bundle during failure-reason normalization bundle=\(url.lastPathComponent, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                continue
            }

            let normalizedReason = TAPPendingCaptureFailureReasonPresentation.normalizedLegacyFailureReason(
                record.failureReason,
                status: record.status
            )
            guard record.failureReason != normalizedReason else {
                continue
            }

            record.failureReason = normalizedReason
            try storage.writeRecord(record, in: url)
            normalizedCount += 1
        }
        if normalizedCount > 0 {
            Self.postLibraryDidChange()
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("store normalized persisted failure reasons count=\(normalizedCount, privacy: .public)")
            #endif
        }
        return normalizedCount
    }

    func storeSignedPhoto(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        try storage.writeSignedPhoto(data, fileContainer: record.photoFileContainer, captureID: captureID)
        record.signedPhotoFilename = record.photoFileContainer.signedFilename
        record.status = .signed
        record.failureReason = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store signedPhoto stored captureID=\(captureID, privacy: .private) container=\(record.photoFileContainer.rawValue, privacy: .public) bytes=\(data.count, privacy: .public) status=\(record.status.rawValue, privacy: .public)")
        #endif
        return record
    }

    func storeSignedHEIC(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        try storeSignedPhoto(data, captureID: captureID)
    }

    func markVideoSigned(captureID: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("video signing state requires a TAP video artifact")
        }
        _ = try videoArtifactURL(captureID: captureID)
        record.videoArtifactState = .signed
        record.status = .signed
        record.failureReason = nil
        record.failureCode = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store video signed in place captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
        #endif
        return record
    }

    func persistVideoPreSignContentBinding(
        _ binding: CaptureContentBinding,
        captureID: String
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo,
              binding.captureID == captureID else {
            throw TAPDepthCaptureError.invalidTAPManifest("video pre-sign binding identity mismatch")
        }
        if let existing = record.preSignContentBinding, existing != binding {
            throw TAPDepthCaptureError.pendingCaptureProofExternalMutation
        }
        record.preSignContentBinding = binding
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
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
        Self.postLibraryDidChange()
        return record
    }

    /// Persists safe-to-repeat export intent before any Photos asset creation
    /// begins. A restart in this phase may validate and create again.
    func markVideoPhotosExportIntent(
        captureID: String
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo,
              record.videoArtifactState == .signed,
              record.status != .failedTerminal,
              record.status != .exported,
              record.assetLocalIdentifier == nil else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "Photos export intent requires an uncommitted signed TAP video"
            )
        }
        switch record.videoPhotosExportPhase {
        case nil, .preCommitIntent:
            record.videoPhotosExportPhase = .preCommitIntent
        case .commitAmbiguous, .committed:
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "a TAP video beyond the Photos commit boundary cannot create again"
            )
        }
        record.status = .exporting
        record.failureReason = nil
        record.failureCode = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        return record
    }

    /// Must be called immediately before entering Photos `performChanges`.
    /// From this durable boundary onward, a missing completion callback is
    /// commit-ambiguous and restart recovery may only probe/read back.
    func markVideoPhotosCommitAmbiguous(
        captureID: String
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo,
              record.videoArtifactState == .signed,
              record.status != .failedTerminal,
              record.status != .exported,
              record.assetLocalIdentifier == nil else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "Photos commit boundary requires an uncommitted signed TAP video"
            )
        }
        switch record.videoPhotosExportPhase {
        case .preCommitIntent:
            record.videoPhotosExportPhase = .commitAmbiguous
        case .commitAmbiguous:
            return record
        case nil, .committed:
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "Photos commit boundary requires a persisted pre-commit intent"
            )
        }
        record.status = .exporting
        record.failureReason = nil
        record.failureCode = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        return record
    }

    /// Persists the Photos identifier returned after the commit-ambiguous
    /// boundary. Retries must only re-read this asset; they must never create a
    /// second asset automatically.
    func markVideoPhotosCommit(
        captureID: String,
        assetLocalIdentifier: String
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        guard record.artifactKind == .tapVideo,
              record.videoArtifactState == .signed,
              !assetLocalIdentifier.isEmpty else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "Photos commit state requires a TAP video asset identifier"
            )
        }
        if record.status == .exported {
            guard record.assetLocalIdentifier == assetLocalIdentifier else {
                throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                    "an exported TAP video Photos identifier cannot change"
                )
            }
            return record
        }
        guard record.status != .failedTerminal else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "a terminal TAP video cannot re-enter Photos commit recovery"
            )
        }
        if record.videoPhotosExportPhase == .committed {
            guard record.assetLocalIdentifier == assetLocalIdentifier else {
                throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                    "a TAP video Photos commit identifier cannot change"
                )
            }
            return record
        }
        guard record.videoPhotosExportPhase == .commitAmbiguous else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "a TAP video Photos identifier requires the commit-ambiguous boundary"
            )
        }
        if let existingAssetID = record.assetLocalIdentifier,
           existingAssetID != assetLocalIdentifier {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "a TAP video Photos commit identifier cannot change"
            )
        }
        record.status = .exporting
        record.videoPhotosExportPhase = .committed
        record.assetLocalIdentifier = assetLocalIdentifier
        record.failureReason = nil
        record.failureCode = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        return record
    }

    func markExported(
        captureID: String,
        assetLocalIdentifier: String,
        duplicateExportWarning: String? = nil
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
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
        record.updatedAt = Date()
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
        Self.postLibraryDidChange()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("store exported marked captureID=\(captureID, privacy: .private) assetID=\(assetLocalIdentifier, privacy: .private)")
        #endif
        return persistedRecord
    }

    func cleanupExportedLargeFiles() throws {
        for record in try allRecords() where record.status == .exported {
            try storage.cleanupLargeFiles(for: record)
        }
    }

    @discardableResult
    func removeUnshippedLegacyVideoBundles() throws -> Int {
        let legacyCaptureIDs = try allRecords().compactMap { record in
            record.artifactKind == .tapVideo && record.videoFormatRevision != 2
                ? record.captureID
                : nil
        }
        for captureID in legacyCaptureIDs {
            _ = try storage.removeBundle(captureID: captureID)
        }
        if !legacyCaptureIDs.isEmpty {
            Self.postLibraryDidChange()
        }
        return legacyCaptureIDs.count
    }

    func removeRecord(captureID: String) throws {
        if try storage.removeBundle(captureID: captureID) {
            Self.postLibraryDidChange()
        }
    }

    private nonisolated static func defaultRootURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("TAPCaptureLibrary", isDirectory: true)
            .appendingPathComponent(TAPPendingCaptureBundlePathPolicy.recordsDirectoryName, isDirectory: true)
    }

    private nonisolated static func postLibraryDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
            }
        }
    }
}
