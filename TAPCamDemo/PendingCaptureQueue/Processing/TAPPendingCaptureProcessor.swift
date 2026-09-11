//
//  TAPPendingCaptureProcessor.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import OSLog
import UIKit

/// Serial background processor for staged TAP depth photo captures.
///
/// The worker only reads bundle state from `TAPPendingCaptureStore`; it does not
/// depend on the current camera UI selection. This is the important split that
/// lets captures survive locked-screen intake, no-network sessions, and app
/// restarts before App Attest is available.
actor TAPPendingCaptureProcessor {
    static let shared = TAPPendingCaptureProcessor()

    private var workerTask: Task<Void, Never>?

    func processPendingCaptures(
        store: TAPPendingCaptureStore = .shared,
        appAttestClient: any AppAttestClient
    ) async {
        await processPendingCaptures(
            store: store,
            signer: AppAttestPendingCaptureSigner(appAttestClient: appAttestClient),
            exporter: PhotoLibraryPendingCaptureExporter(),
            readback: PhotoLibraryPendingCaptureReadback(),
            cleanup: TAPPendingCaptureLargeFileCleanup(),
            protectedDataIsAvailable: Self.defaultProtectedDataIsAvailable
        )
    }

    func processPendingCaptures(
        store: TAPPendingCaptureStore,
        signer: any TAPPendingCaptureSigning,
        exporter: any TAPPendingCaptureExporting,
        readback: any TAPPendingCaptureReadingBack = PhotoLibraryPendingCaptureReadback(),
        cleanup: any TAPPendingCaptureCleaning = TAPPendingCaptureLargeFileCleanup(),
        protectedDataIsAvailable: @escaping @Sendable () async -> Bool
    ) async {
        while let currentWorkerTask = workerTask {
            await currentWorkerTask.value
        }

        let task = Task { [store, signer, exporter, readback, cleanup, protectedDataIsAvailable] in
            await self.runWorker(
                store: store,
                signer: signer,
                exporter: exporter,
                readback: readback,
                cleanup: cleanup,
                protectedDataIsAvailable: protectedDataIsAvailable
            )
        }
        workerTask = task
        await task.value
    }

    private func runWorker(
        store: TAPPendingCaptureStore,
        signer: any TAPPendingCaptureSigning,
        exporter: any TAPPendingCaptureExporting,
        readback: any TAPPendingCaptureReadingBack,
        cleanup: any TAPPendingCaptureCleaning,
        protectedDataIsAvailable: @escaping @Sendable () async -> Bool
    ) async {
        defer { workerTask = nil }
        let readiness = TAPPendingCaptureWorkerReadiness(
            protectedDataIsAvailable: await protectedDataIsAvailable()
        )
        guard readiness.allowsPrivateArtifactAccess else {
            return
        }

        do {
            try await reconcile(store: store, cleanup: cleanup)
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            TAPDiagnostics.pendingCapture.error("worker reconcile failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }

        var processedCaptureIDs = Set<String>()
        var ingestionGeneration: UInt64?
        var candidates = Array<TAPPendingCaptureRecord>().makeIterator()
        do {
            while !Task.isCancelled {
                let currentGeneration = await store.ingestionGeneration
                if ingestionGeneration != currentGeneration {
                    // Worker-owned status changes do not require another full
                    // scan. New captures do: fresh work must still precede the
                    // retry backlog even when it arrives during this run.
                    candidates = try await store.processingCandidates().makeIterator()
                    ingestionGeneration = currentGeneration
                }
                guard let snapshot = candidates.next() else { break }
                guard !processedCaptureIDs.contains(snapshot.captureID),
                      let candidate = try? await store.readRecord(captureID: snapshot.captureID),
                      candidate.isProcessingCandidate else { continue }
                try Task.checkCancellation()
                processedCaptureIDs.insert(candidate.captureID)
                try await process(
                    candidate,
                    store: store,
                    signer: signer,
                    exporter: exporter,
                    readback: readback
                )
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            TAPDiagnostics.pendingCapture.error("processingCandidates failed processedCount=\(processedCaptureIDs.count, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }

        do {
            try await cleanup.cleanup(store: store)
        } catch {
            #if DEBUG
            TAPDiagnostics.pendingCapture.error("worker cleanup failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
    }

    func reconcile(
        store: TAPPendingCaptureStore = .shared,
        cleanup: any TAPPendingCaptureCleaning = TAPPendingCaptureLargeFileCleanup(),
        existingPhotoAssetIdentifier: @Sendable (String) async throws -> String? = PhotoLibraryWriter.depthAssetIdentifier
    ) async throws {
        try Task.checkCancellation()
        try await store.removeStaleVideoCaptureWorkspaces()
        let records = try await store.allRecords()
        for record in records {
            try Task.checkCancellation()
            switch record.status {
            case .exported, .failedTerminal:
                continue
            case .exporting:
                // Photo recovery has a dedicated signed-photo lookup. TAP
                // video recovery must stay in the exporter so deterministic
                // filename candidates receive full manifest/proof readback.
                guard record.artifactKind == .photoDepth else {
                    continue
                }
                let assetID: String?
                do {
                    assetID = try await existingPhotoAssetIdentifier(record.captureID)
                } catch let error as CancellationError {
                    throw error
                } catch {
                    assetID = nil
                }
                try Task.checkCancellation()
                if let assetID {
                    _ = try await store.markExported(
                        captureID: record.captureID,
                        assetLocalIdentifier: assetID
                    )
                }
            case .pending, .waitingNetwork, .signing, .signed, .failedRetryable:
                continue
            }
        }
        try Task.checkCancellation()
        try await cleanup.cleanup(store: store)
    }

    private func process(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore,
        signer: any TAPPendingCaptureSigning,
        exporter: any TAPPendingCaptureExporting,
        readback: any TAPPendingCaptureReadingBack
    ) async throws {
        do {
            try Task.checkCancellation()
            switch record.processingRoute {
            case .signThenExport:
                let signedRecord = try await signer.sign(record, store: store)
                try Task.checkCancellation()
                try await exporter.export(signedRecord, store: store)
                try Task.checkCancellation()
                try await readback.readBack(signedRecord, store: store)

            case .exportSigned:
                try await exporter.export(record, store: store)
                try Task.checkCancellation()
                try await readback.readBack(record, store: store)

            case .skip:
                return
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            try Task.checkCancellation()
            let persistedRecord = try? await store.readRecord(captureID: record.captureID)
            let failureRecord = persistedRecord ?? record
            if let terminalCode = failureRecord.terminalFailureCode(for: error) {
                _ = try? await store.markTerminalFailure(
                    captureID: record.captureID,
                    code: terminalCode
                )
                #if DEBUG
                TAPDiagnostics.pendingCapture.error("process terminal failure captureID=\(record.captureID, privacy: .private) code=\(terminalCode.rawValue, privacy: .public)")
                #endif
                return
            }
            let mustRemainInVideoRecovery = record.artifactKind == .tapVideo
                && (record.requiresVideoPhotosReadbackRecovery
                    || persistedRecord?.requiresVideoPhotosReadbackRecovery == true)
            let status: TAPPendingCaptureStatus = mustRemainInVideoRecovery
                ? .exporting
                : TAPPendingCaptureRetryClassifier.status(for: error)
            let failureReason = TAPPendingCaptureFailureReason.reason(for: status)
            #if DEBUG
            TAPDiagnostics.pendingCapture.error("process failed captureID=\(record.captureID, privacy: .private) previousStatus=\(record.status.rawValue, privacy: .public) nextStatus=\(status.rawValue, privacy: .public) retryCount=\(record.retryCount + 1, privacy: .public) vpnHint=\(TAPDiagnostics.errorLooksVPNRelated(error), privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            _ = try? await store.updateStatus(
                captureID: record.captureID,
                status: status,
                failureReason: failureReason,
                incrementsRetryCount: true
            )
        }
    }

    private static func defaultProtectedDataIsAvailable() async -> Bool {
        await MainActor.run {
            UIApplication.shared.isProtectedDataAvailable
        }
    }
}
