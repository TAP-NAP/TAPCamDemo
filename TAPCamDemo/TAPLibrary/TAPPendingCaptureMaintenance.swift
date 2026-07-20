//
//  TAPPendingCaptureMaintenance.swift
//  TAPCamDemo
//

import Foundation
import OSLog

nonisolated struct TAPPendingCaptureMaintenance {
    private let storage: TAPPendingCaptureBundleStorage

    init(storage: TAPPendingCaptureBundleStorage) {
        self.storage = storage
    }

    func normalizePersistedFailureReasons() throws -> Int {
        try storage.ensureRootDirectoryExists()
        var normalizedCount = 0
        for url in try storage.bundleURLs() {
            var record: TAPPendingCaptureRecord
            do {
                record = try storage.readStoredRecord(
                    in: url,
                    expectedCaptureID: url.lastPathComponent
                )
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.error("store skipped invalid bundle during failure-reason normalization bundle=\(url.lastPathComponent, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                continue
            }
            let reason = TAPPendingCaptureFailureReasonPresentation
                .normalizedLegacyFailureReason(
                    record.failureReason,
                    status: record.status
                )
            guard record.failureReason != reason else {
                continue
            }
            record.failureReason = reason
            try storage.writeRecord(record, in: url)
            normalizedCount += 1
        }
        return normalizedCount
    }

    func cleanupExportedLargeFiles(
        records: [TAPPendingCaptureRecord]
    ) throws {
        for record in records where record.status == .exported {
            try storage.cleanupLargeFiles(for: record)
        }
    }

    func removeUnshippedLegacyVideoBundles(
        records: [TAPPendingCaptureRecord]
    ) throws -> Int {
        let captureIDs = records.compactMap { record in
            record.artifactKind == .tapVideo && record.videoFormatRevision != 2
                ? record.captureID : nil
        }
        for captureID in captureIDs {
            _ = try storage.removeBundle(captureID: captureID)
        }
        return captureIDs.count
    }
}
