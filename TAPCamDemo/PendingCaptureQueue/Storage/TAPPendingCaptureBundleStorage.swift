//
//  TAPPendingCaptureBundleStorage.swift
//  TAPCamDemo
//

import Darwin
import Foundation

/// Filesystem adapter for one app-private pending-capture bundle tree.
///
/// `TAPPendingCaptureStore` owns queue semantics and actor serialization. This
/// helper owns only directory creation, fixed bundle paths, record JSON IO,
/// artifact IO, and cleanup. It should not post notifications, classify retry
/// state, or decide record status transitions.
nonisolated struct TAPPendingCaptureBundleStorage {
    private static let videoSigningArtifactPrefix = ".tap-signing-"
    private static let videoSigningArtifactSuffix = ".mp4"
    private static let videoSigningRecordPrefix = ".tap-signing-record-"
    private static let videoSigningRecordSuffix = ".json"

    let rootURL: URL

    private let fileManager: FileManager
    private let storagePolicy: TAPLocalArtifactFileProtection

    init(
        rootURL: URL,
        storagePolicy: TAPLocalArtifactFileProtection,
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
        try TAPPendingCaptureBundlePaths.bundleURL(rootURL: rootURL, captureID: captureID)
    }

    func temporaryBundleURL() -> URL {
        rootURL.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
    }

    func videoCaptureWorkspaceURL(captureID: String) throws -> URL {
        try TAPPendingCaptureBundlePaths.videoCaptureWorkspaceURL(
            rootURL: rootURL,
            captureID: captureID
        )
    }

    func createFreshVideoCaptureWorkspace(captureID: String) throws -> URL {
        let workspaceURL = try videoCaptureWorkspaceURL(captureID: captureID)
        try createFreshTemporaryBundle(at: workspaceURL)
        return workspaceURL
    }

    func removeVideoCaptureWorkspace(captureID: String) throws {
        let workspaceURL = try videoCaptureWorkspaceURL(captureID: captureID)
        if fileManager.fileExists(atPath: workspaceURL.path) {
            try fileManager.removeItem(at: workspaceURL)
        }
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

    func videoCaptureWorkspaceURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        .filter { url in
            url.lastPathComponent.hasPrefix(
                TAPPendingCaptureBundlePaths.videoCaptureWorkspacePrefix
            ) && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    func removeVideoCaptureWorkspace(at workspaceURL: URL) throws {
        guard workspaceURL.deletingLastPathComponent().standardizedFileURL
                == rootURL.standardizedFileURL,
              workspaceURL.lastPathComponent.hasPrefix(
                TAPPendingCaptureBundlePaths.videoCaptureWorkspacePrefix
              ) else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "stale video workspace must remain inside the pending root"
            )
        }
        if fileManager.fileExists(atPath: workspaceURL.path) {
            try fileManager.removeItem(at: workspaceURL)
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

    func writeThumbnail(_ data: Data, to bundleURL: URL) throws {
        try storagePolicy.write(
            data,
            to: bundleURL.appendingPathComponent(TAPPendingCaptureBundlePaths.thumbnailFilename),
            fileManager: fileManager
        )
    }

    func copyPairedVideo(from sourceURL: URL, to bundleURL: URL) throws {
        let destinationURL = bundleURL.appendingPathComponent(TAPPendingCaptureBundlePaths.pairedVideoFilename)
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
            to: TAPPendingCaptureBundlePaths.artifactURL(
                rootURL: rootURL,
                captureID: captureID,
                filename: fileContainer.signedFilename
            ),
            fileManager: fileManager
        )
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
        let data = try Data(contentsOf: TAPPendingCaptureBundlePaths.recordURL(bundleURL: bundleURL))
        let record = try TAPPendingCaptureRecordCoding.decode(from: data)
        try TAPPendingCaptureBundlePaths.validateRecord(record, expectedCaptureID: expectedCaptureID)
        return record
    }

    func readNormalizedRecord(
        in bundleURL: URL,
        expectedCaptureID: String? = nil
    ) throws -> TAPPendingCaptureRecord {
        var record = try readStoredRecord(in: bundleURL, expectedCaptureID: expectedCaptureID)
        record.failureReason = TAPPendingCaptureFailureReason.normalizedStoredFailureReason(
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
        guard let url = try photoURLIfPresent(filename: filename, captureID: captureID) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func photoURLIfPresent(filename: String, captureID: String) throws -> URL? {
        let url = try TAPPendingCaptureBundlePaths.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        )
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func thumbnailData(filename: String, captureID: String) throws -> Data? {
        try? Data(contentsOf: TAPPendingCaptureBundlePaths.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        ))
    }

    func pairedVideoURL(filename: String, captureID: String) throws -> URL {
        let url = try TAPPendingCaptureBundlePaths.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        )
        guard fileManager.fileExists(atPath: url.path) else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return url
    }

    func videoURLIfPresent(filename: String, captureID: String) throws -> URL? {
        let url = try TAPPendingCaptureBundlePaths.artifactURL(
            rootURL: rootURL,
            captureID: captureID,
            filename: filename
        )
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func videoURL(filename: String, captureID: String) throws -> URL {
        guard let url = try videoURLIfPresent(filename: filename, captureID: captureID) else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return url
    }

    /// Creates a private signing generation next to the durable video.
    ///
    /// `copyItem` may use a filesystem clone, but it always creates a distinct
    /// inode. A hard link is explicitly rejected because proof-slot writes to a
    /// linked staging path would still mutate Viewer/Share readers of the
    /// durable generation.
    func createVideoSigningArtifactCopy(
        captureID: String,
        sourceFilename: String,
        attemptID: UUID
    ) throws -> URL {
        let sourceURL = try videoURL(
            filename: sourceFilename,
            captureID: captureID
        )
        let destinationURL = try videoSigningArtifactURL(
            captureID: captureID,
            attemptID: attemptID
        )
        try requireRegularNonemptyFile(at: sourceURL)
        try Task.checkCancellation()

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try Task.checkCancellation()
            try requireRegularNonemptyFile(at: destinationURL)
            try requireIndependentInode(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
            try storagePolicy.protectDirectoryTree(
                at: destinationURL,
                fileManager: fileManager
            )
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Atomically exchanges one completely written signing generation with the
    /// fixed durable path. Both paths are in the same bundle directory, and
    /// `RENAME_SWAP` leaves the complete previous generation at `stagingURL`
    /// for rollback until the record commit succeeds.
    func publishVideoSigningArtifact(
        captureID: String,
        sourceFilename: String,
        attemptID: UUID
    ) throws -> URL {
        let stagingURL = try videoSigningArtifactURL(
            captureID: captureID,
            attemptID: attemptID
        )
        let durableURL = try videoURL(
            filename: sourceFilename,
            captureID: captureID
        )
        try requireRegularNonemptyFile(at: stagingURL)
        try requireRegularNonemptyFile(at: durableURL)
        try requireIndependentInode(
            sourceURL: durableURL,
            destinationURL: stagingURL
        )
        try Task.checkCancellation()

        let handle = try FileHandle(forWritingTo: stagingURL)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try storagePolicy.protectDirectoryTree(
            at: stagingURL,
            fileManager: fileManager
        )
        try Task.checkCancellation()

        try posixRenameSwap(stagingURL, durableURL)
        return stagingURL
    }

    func commitPublishedVideoSigningArtifact(previousGenerationURL: URL) throws {
        guard Self.isVideoSigningArtifactFilename(
            previousGenerationURL.lastPathComponent
        ) else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing previous-generation path is invalid"
            )
        }
        if fileManager.fileExists(atPath: previousGenerationURL.path) {
            try fileManager.removeItem(at: previousGenerationURL)
        }
    }

    func rollbackPublishedVideoSigningArtifact(
        captureID: String,
        sourceFilename: String,
        attemptID: UUID,
        previousGenerationURL: URL
    ) throws {
        let expectedPreviousGenerationURL = try videoSigningArtifactURL(
            captureID: captureID,
            attemptID: attemptID
        )
        guard previousGenerationURL.standardizedFileURL
                == expectedPreviousGenerationURL.standardizedFileURL,
              fileManager.fileExists(atPath: previousGenerationURL.path) else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing rollback generation is unavailable"
            )
        }
        let durableURL = try videoURL(
            filename: sourceFilename,
            captureID: captureID
        )
        try posixRenameSwap(previousGenerationURL, durableURL)
    }

    func discardVideoSigningArtifact(
        captureID: String,
        attemptID: UUID
    ) throws {
        let url = try videoSigningArtifactURL(
            captureID: captureID,
            attemptID: attemptID
        )
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func removeStaleVideoSigningArtifacts(captureID: String) throws {
        let bundleURL = try bundleURL(captureID: captureID)
        guard fileManager.fileExists(atPath: bundleURL.path) else {
            return
        }
        for url in try fileManager.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) where Self.isVideoSigningArtifactFilename(url.lastPathComponent)
            || Self.isVideoSigningRecordFilename(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
        }
    }

    func videoSigningArtifactURL(
        captureID: String,
        attemptID: UUID
    ) throws -> URL {
        try bundleURL(captureID: captureID).appendingPathComponent(
            Self.videoSigningArtifactPrefix
                + attemptID.uuidString.lowercased()
                + Self.videoSigningArtifactSuffix
        )
    }

    private static func isVideoSigningArtifactFilename(_ filename: String) -> Bool {
        isVideoSigningTemporaryFilename(
            filename,
            prefix: videoSigningArtifactPrefix,
            suffix: videoSigningArtifactSuffix
        )
    }

    private static func isVideoSigningRecordFilename(_ filename: String) -> Bool {
        isVideoSigningTemporaryFilename(
            filename,
            prefix: videoSigningRecordPrefix,
            suffix: videoSigningRecordSuffix
        )
    }

    private static func isVideoSigningTemporaryFilename(
        _ filename: String,
        prefix: String,
        suffix: String
    ) -> Bool {
        guard filename.hasPrefix(prefix),
              filename.hasSuffix(suffix) else {
            return false
        }
        let start = filename.index(
            filename.startIndex,
            offsetBy: prefix.count
        )
        let end = filename.index(
            filename.endIndex,
            offsetBy: -suffix.count
        )
        return UUID(uuidString: String(filename[start..<end])) != nil
    }

    private func posixRenameSwap(_ firstURL: URL, _ secondURL: URL) throws {
        let result = firstURL.path.withCString { firstPath in
            secondURL.path.withCString { secondPath in
                Darwin.renamex_np(firstPath, secondPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: nil
            )
        }
    }

    private func requireRegularNonemptyFile(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0 else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
    }

    private func requireIndependentInode(
        sourceURL: URL,
        destinationURL: URL
    ) throws {
        let sourceAttributes = try fileManager.attributesOfItem(
            atPath: sourceURL.path
        )
        let destinationAttributes = try fileManager.attributesOfItem(
            atPath: destinationURL.path
        )
        let sourceDevice = sourceAttributes[.systemNumber] as? NSNumber
        let destinationDevice = destinationAttributes[.systemNumber] as? NSNumber
        let sourceInode = sourceAttributes[.systemFileNumber] as? NSNumber
        let destinationInode = destinationAttributes[.systemFileNumber] as? NSNumber
        guard sourceDevice != destinationDevice || sourceInode != destinationInode else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video signing artifact must not share the durable inode"
            )
        }
    }

    func writeRecord(_ record: TAPPendingCaptureRecord) throws {
        try writeRecord(record, in: try bundleURL(captureID: record.captureID))
    }

    func writeRecord(_ record: TAPPendingCaptureRecord, in bundleURL: URL) throws {
        try TAPPendingCaptureBundlePaths.validateRecord(record)
        let data = try TAPPendingCaptureRecordCoding.encode(record)
        try storagePolicy.write(
            data,
            to: TAPPendingCaptureBundlePaths.recordURL(bundleURL: bundleURL),
            fileManager: fileManager
        )
    }

    /// Commits the signed-video record with one unambiguous filesystem commit
    /// point. Encoding, file protection, synchronization, and injected
    /// preparation failures all happen on a private sibling file. The final
    /// POSIX rename atomically replaces the canonical record and is the last
    /// throwable operation, so callers never roll back media after the signed
    /// record has already become durable at its canonical path.
    func commitVideoSigningRecord(
        _ record: TAPPendingCaptureRecord,
        attemptID: UUID,
        preparationFault: @Sendable (TAPPendingCaptureRecord) throws -> Void
    ) throws {
        try TAPPendingCaptureBundlePaths.validateRecord(record)
        let bundleURL = try bundleURL(captureID: record.captureID)
        let recordURL = TAPPendingCaptureBundlePaths.recordURL(
            bundleURL: bundleURL
        )
        let temporaryURL = bundleURL.appendingPathComponent(
            Self.videoSigningRecordPrefix
                + attemptID.uuidString.lowercased()
                + Self.videoSigningRecordSuffix
        )
        let data = try TAPPendingCaptureRecordCoding.encode(record)

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        do {
            try data.write(to: temporaryURL, options: [.atomic])
            // This seam represents file-protection/preparation failure. It is
            // deliberately before touching the canonical record.
            try preparationFault(record)
            try storagePolicy.protectDirectoryTree(
                at: temporaryURL,
                fileManager: fileManager
            )
            try requireRegularNonemptyFile(at: temporaryURL)

            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            // Do not add a throwable operation below this line. A zero return
            // is the record commit point observed by crash recovery.
            try posixRenameReplacing(temporaryURL, recordURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func posixRenameReplacing(_ sourceURL: URL, _ destinationURL: URL) throws {
        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: nil
            )
        }
    }

    func cleanupLargeFiles(for record: TAPPendingCaptureRecord) throws {
        for filename in [
            record.unsignedPhotoFilename,
            record.signedPhotoFilename,
            record.videoArtifactFilename,
            record.pairedVideoFilename
        ].compactMap({ $0 }) {
            let url = try TAPPendingCaptureBundlePaths.artifactURL(
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
