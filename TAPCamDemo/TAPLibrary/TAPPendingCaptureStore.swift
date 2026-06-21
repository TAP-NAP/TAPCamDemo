//
//  TAPPendingCaptureStore.swift
//  TAPCamDemo
//

import Foundation
import OSLog

/// App-private staging store for unsigned/signed TAP depth HEIC files.
///
/// This store is intentionally HEIC-only for this implementation slice. Future
/// multi-format resource bundles should be designed separately; see the P1 TODO
/// in `PACKAGING.md`.
actor TAPPendingCaptureStore {
    static let shared = TAPPendingCaptureStore()

    private let storage: TAPPendingCaptureBundleStorage

    init(
        rootURL: URL = TAPPendingCaptureStore.defaultRootURL(),
        storagePolicy: TAPLocalArtifactStoragePolicy = .privatePhotoArtifact
    ) {
        self.storage = TAPPendingCaptureBundleStorage(
            rootURL: rootURL,
            storagePolicy: storagePolicy
        )
    }

    func ingest(_ artifact: PackagedCaptureArtifact) throws -> TAPPendingCaptureRecord {
        try storage.ensureRootDirectoryExists()

        let captureID = artifact.manifest.payload.id
        let finalURL = try storage.bundleURL(captureID: captureID)
        if storage.bundleExists(at: finalURL),
           let existing = try? readRecord(captureID: captureID) {
            TAPDiagnostics.pendingCapture.info("store ingest existing captureID=\(captureID, privacy: .private) status=\(existing.status.rawValue, privacy: .public) retryCount=\(existing.retryCount, privacy: .public)")
            return existing
        }

        let temporaryURL = storage.temporaryBundleURL()
        try storage.createFreshTemporaryBundle(at: temporaryURL)

        try storage.writeUnsignedHEIC(artifact.photoData, to: temporaryURL)

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
            unsignedHEICFilename: TAPPendingCaptureBundlePathPolicy.unsignedHEICFilename,
            signedHEICFilename: nil,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: nil,
            failureReason: nil,
            retryCount: 0,
            location: artifact.location.map(TAPPendingCaptureLocation.init)
        )
        try storage.writeRecord(record, in: temporaryURL)

        try storage.commitTemporaryBundle(at: temporaryURL, to: finalURL)
        Self.postLibraryDidChange()
        TAPDiagnostics.pendingCapture.info("store ingest created captureID=\(captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) unsignedBytes=\(artifact.photoData.count, privacy: .public) hasThumbnail=\(thumbnailFilename != nil, privacy: .public)")
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

    func unsignedHEICData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.unsignedHEICFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return try storage.heicData(filename: filename, captureID: captureID)
    }

    func signedHEICData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.signedHEICFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return try storage.heicData(filename: filename, captureID: captureID)
    }

    func bestAvailableHEICData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        if let filename = record.signedHEICFilename {
            if let data = try storage.heicDataIfPresent(filename: filename, captureID: captureID) {
                return data
            }
        }
        if let filename = record.unsignedHEICFilename {
            if let data = try storage.heicDataIfPresent(filename: filename, captureID: captureID) {
                return data
            }
        }
        throw TAPDepthCaptureError.pendingCaptureDataMissing
    }

    func thumbnailData(captureID: String) throws -> Data? {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.thumbnailFilename else {
            return nil
        }
        return try storage.thumbnailData(filename: filename, captureID: captureID)
    }

    func updateStatus(
        captureID: String,
        status: TAPPendingCaptureStatus,
        failureReason: TAPPendingCaptureFailureReasonPresentation.Reason? = nil,
        incrementsRetryCount: Bool = false
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        record.status = status
        record.failureReason = TAPPendingCaptureFailureReasonPresentation.normalizedPersistedFailureReason(
            failureReason,
            status: status
        )
        record.updatedAt = Date()
        if incrementsRetryCount {
            record.retryCount += 1
        }
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        TAPDiagnostics.pendingCapture.info("store status updated captureID=\(captureID, privacy: .private) status=\(status.rawValue, privacy: .public) retryCount=\(record.retryCount, privacy: .public) hasFailureReason=\(failureReason != nil, privacy: .public)")
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
                TAPDiagnostics.pendingCapture.error("store skipped invalid bundle during failure-reason normalization bundle=\(url.lastPathComponent, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
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
            TAPDiagnostics.pendingCapture.info("store normalized persisted failure reasons count=\(normalizedCount, privacy: .public)")
        }
        return normalizedCount
    }

    func storeSignedHEIC(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        try storage.writeSignedHEIC(data, captureID: captureID)
        record.signedHEICFilename = TAPPendingCaptureBundlePathPolicy.signedHEICFilename
        record.status = .signed
        record.failureReason = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        Self.postLibraryDidChange()
        TAPDiagnostics.pendingCapture.info("store signedHEIC stored captureID=\(captureID, privacy: .private) bytes=\(data.count, privacy: .public) status=\(record.status.rawValue, privacy: .public)")
        return record
    }

    func markExported(captureID: String, assetLocalIdentifier: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        record.status = .exported
        record.assetLocalIdentifier = assetLocalIdentifier
        record.failureReason = nil
        record.location = nil
        record.updatedAt = Date()
        try storage.writeRecord(record)
        try storage.cleanupLargeFiles(for: record)
        Self.postLibraryDidChange()
        TAPDiagnostics.pendingCapture.info("store exported marked captureID=\(captureID, privacy: .private) assetID=\(assetLocalIdentifier, privacy: .private)")
        return record
    }

    func cleanupExportedLargeFiles() throws {
        for record in try allRecords() where record.status == .exported {
            try storage.cleanupLargeFiles(for: record)
        }
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
        NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
    }
}
