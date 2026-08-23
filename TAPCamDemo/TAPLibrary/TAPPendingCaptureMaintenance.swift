//
//  TAPPendingCaptureMaintenance.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct TAPPendingCaptureMaintenance {
    private let storage: TAPPendingCaptureBundleStorage

    init(storage: TAPPendingCaptureBundleStorage) {
        self.storage = storage
    }

    func cleanupExportedLargeFiles(
        records: [TAPPendingCaptureRecord]
    ) throws {
        for record in records where record.status == .exported {
            try storage.cleanupLargeFiles(for: record)
        }
    }

}
