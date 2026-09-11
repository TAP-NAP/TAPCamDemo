//
//  TAPPendingCaptureProcessingSteps.swift
//  TAPCamDemo
//

import Foundation

nonisolated protocol TAPPendingCaptureSigning: Sendable {
    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord
}

nonisolated protocol TAPPendingCaptureExporting: Sendable {
    func export(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws
}

nonisolated protocol TAPPendingCaptureReadingBack: Sendable {
    func readBack(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws
}

nonisolated protocol TAPPendingCaptureCleaning: Sendable {
    func cleanup(store: TAPPendingCaptureStore) async throws
}

nonisolated struct TAPPendingCaptureLargeFileCleanup: TAPPendingCaptureCleaning {
    func cleanup(store: TAPPendingCaptureStore) async throws {
        let trace = TAPVideoPerformanceTrace.beginPendingCleanup()
        do {
            try await store.cleanupExportedLargeFiles()
            TAPVideoPerformanceTrace.endPendingCleanup(trace, succeeded: true)
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
                stage: "pending-cleanup-finished"
            )
        } catch {
            TAPVideoPerformanceTrace.endPendingCleanup(trace, succeeded: false)
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
                stage: "pending-cleanup-failed"
            )
            throw error
        }
    }
}
