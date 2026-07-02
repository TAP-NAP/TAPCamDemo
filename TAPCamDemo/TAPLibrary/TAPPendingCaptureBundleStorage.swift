//
//  TAPPendingCaptureBundleStorage.swift
//  TAPCamDemo
//

import Foundation

/// Filesystem adapter for one app-private pending-capture bundle tree.
///
/// `TAPPendingCaptureStore` owns queue semantics and actor serialization. This
/// helper owns only directory creation, fixed bundle paths, record JSON IO,
/// artifact IO, and cleanup. It should not post notifications, classify retry
/// state, or decide record status transitions.
nonisolated struct TAPPendingCaptureBundleStorage {
    let rootURL: URL

    private let fileManager: FileManager
    private let storagePolicy: TAPLocalArtifactStoragePolicy

    init(
        rootURL: URL,
        storagePolicy: TAPLocalArtifactStoragePolicy,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.storagePolicy = storagePolicy
        self.fileManager = fileManager
    }

    func ensureRootDirectoryExists() throws {
        try storagePolicy.createDirectoryIfNeeded(at: rootURL, fileManager: fileManager)
    }

    func bundleURL(captureID: String) throws -> URL {
        try TAPPendingCaptureBundlePathPolicy.bundleURL(rootURL: rootURL, captureID: captureID)
    }

    func temporaryBundleURL() -> URL {
        rootURL.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
    }

    func createFreshTemporaryBundle(at temporaryURL: URL) throws {
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try storagePolicy.createDirectoryIfNeeded(at: temporaryURL, fileManager: fileManager)
    }

    func bundleExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func commitTemporaryBundle(at temporaryURL: URL, to finalURL: URL) throws {
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        try storagePolicy.protectDirectoryTree(at: finalURL, fileManager: fileManager)
    }

    func bundleURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    func writeUnsignedPhoto(
        _ data: Data,
        fileContainer: CapturePhotoFileContainer,
        to bundleURL: URL
    ) throws {
        try storagePolicy.write(
            data,
            to: bundleURL.appendingPathComponent(fileContainer.unsignedFilename),
            fileManager: fileManager
        )
    }

    func writeUnsignedHEIC(_ data: Data, to bundleURL: URL) throws {
        try writeUnsignedPhoto(data, fileContainer: .heic, to: bundleURL)
    }

    func writeThumbnail(_ data: Data, to bundleURL: URL) throws {
        try storagePolicy.write(
            data,
            to: bundleURL.appendingPathComponent(TAPPendingCaptureBundlePathPolicy.thumbnailFilename),
            fileManager: fileManager
        )
    }

    func copyPairedVideo(from sourceURL: URL, to bundleURL: URL) throws {
        let destinationURL = bundleURL.appendingPathComponent(TAPPendingCaptureBundlePathPolicy.pairedVideoFilename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func writeSignedPhoto(
        _ data: Data,
        fileContainer: CapturePhotoFileContainer,
        captureID: String
    ) throws {
        try storagePolicy.write(
            data,
            to: TAPPendingCaptureBundlePathPolicy.artifactURL(
                rootURL: rootURL,
                captureID: captureID,
                filename: fileContainer.signedFilename
            ),
            fileManager: fileManager
        )
    }

    func writeSignedHEIC(_ data: Data, captureID: String) throws {
        try writeSignedPhoto(data, fileContainer: .heic, captureID: captureID)
    }

    func readRecord(captureID: String) throws -> TAPPendingCaptureRecord {
        try readNormalizedRecord(
            in: try bundleURL(captureID: captureID),
            expectedCaptureID: captureID
        )
    }

    func readStoredRecord(
        in bundleURL: URL,
        expectedCaptureID: String? = nil
    ) throws -> TAPPendingCaptureRecord {
        let data = try Data(contentsOf: TAPPendingCaptureBundlePathPolicy.recordURL(bundleURL: bundleURL))
        let record = try TAPPendingCaptureRecordCoding.decode(from: data)
        try TAPPendingCaptureBundlePathPolicy.validateRecord(record, expectedCaptureID: expectedCaptureID)
        return record
    }

    func readNormalizedRecord(
        in bundleURL: URL,
        expectedCaptureID: String? = nil
    ) throws -> TAPPendingCaptureRecord {
        var record = try readStoredRecord(in: bundleURL, expectedCaptureID: expectedCaptureID)
        record.failureReason = TAPPendingCaptureFailureReasonPresentation.normalizedLegacyFailureReason(
            record.failureReason,
            status: record.status
        )
        return record
    }

    func photoData(filename: String, captureID: String) throws -> Data {
        guard let data = try photoDataIfPresent(filename: filename, captureID: captureID) else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return data
    }

    func photoDataIfPresent(filename: String, captureID: String) throws -> Data? {
        let url = try TAPPendingCaptureBundlePathPolicy.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        )
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func heicData(filename: String, captureID: String) throws -> Data {
        try photoData(filename: filename, captureID: captureID)
    }

    func heicDataIfPresent(filename: String, captureID: String) throws -> Data? {
        try photoDataIfPresent(filename: filename, captureID: captureID)
    }

    func thumbnailData(filename: String, captureID: String) throws -> Data? {
        try? Data(contentsOf: TAPPendingCaptureBundlePathPolicy.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        ))
    }

    func pairedVideoURL(filename: String, captureID: String) throws -> URL {
        let url = try TAPPendingCaptureBundlePathPolicy.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        )
        guard fileManager.fileExists(atPath: url.path) else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return url
    }

    func writeRecord(_ record: TAPPendingCaptureRecord) throws {
        try writeRecord(record, in: try bundleURL(captureID: record.captureID))
    }

    func writeRecord(_ record: TAPPendingCaptureRecord, in bundleURL: URL) throws {
        try TAPPendingCaptureBundlePathPolicy.validateRecord(record)
        let data = try TAPPendingCaptureRecordCoding.encode(record)
        try storagePolicy.write(
            data,
            to: TAPPendingCaptureBundlePathPolicy.recordURL(bundleURL: bundleURL),
            fileManager: fileManager
        )
    }

    func cleanupLargeFiles(for record: TAPPendingCaptureRecord) throws {
        for filename in [
            record.unsignedPhotoFilename,
            record.signedPhotoFilename,
            record.pairedVideoFilename
        ].compactMap({ $0 }) {
            let url = try TAPPendingCaptureBundlePathPolicy.artifactURL(
                rootURL: rootURL,
                captureID: record.captureID,
                filename: filename
            )
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    func removeBundle(captureID: String) throws -> Bool {
        let url = try bundleURL(captureID: captureID)
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        try fileManager.removeItem(at: url)
        return true
    }
}
