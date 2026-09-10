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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("processPendingCaptures requested workerActive=\(self.workerTask != nil, privacy: .public)")
        #endif
        while let currentWorkerTask = workerTask {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("processPendingCaptures waiting for active worker")
            #endif
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
        let workerID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("worker start workerID=\(workerID, privacy: .public)")
        #endif
        let readiness = TAPPendingCaptureWorkerReadiness(
            protectedDataIsAvailable: await protectedDataIsAvailable()
        )
        guard readiness.allowsPrivateArtifactAccess else {
            let readinessDescription = readiness.diagnosticDescription
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info(
                "worker stopped workerID=\(workerID, privacy: .public) readiness=\(readinessDescription, privacy: .public)"
            )
            #endif
            return
        }

        do {
            try await reconcile(store: store, cleanup: cleanup)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("worker reconcile complete workerID=\(workerID, privacy: .public)")
            #endif
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("worker reconcile failed workerID=\(workerID, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
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
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("worker candidate workerID=\(workerID, privacy: .public) captureID=\(candidate.captureID, privacy: .private) status=\(candidate.status.rawValue, privacy: .public) artifactKind=\(candidate.artifactKind.rawValue, privacy: .public) retryCount=\(candidate.retryCount, privacy: .public) container=\(candidate.photoFileContainer.rawValue, privacy: .public) signedPhoto=\(candidate.signedPhotoFilename != nil, privacy: .public) videoState=\(candidate.videoArtifactState?.rawValue ?? "none", privacy: .public)")
                #endif
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
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("processingCandidates failed processedCount=\(processedCaptureIDs.count, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }

        do {
            try await cleanup.cleanup(store: store)
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("worker cleanup failed workerID=\(workerID, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("worker finish workerID=\(workerID, privacy: .public) processedCount=\(processedCaptureIDs.count, privacy: .public)")
        #endif
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("process start captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) retryCount=\(record.retryCount, privacy: .public)")
        #endif
        do {
            try Task.checkCancellation()
            switch record.processingRoute {
            case .signThenExport:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("process route signThenExport captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                #endif
                let signedRecord = try await signer.sign(record, store: store)
                try Task.checkCancellation()
                try await exporter.export(signedRecord, store: store)
                try Task.checkCancellation()
                try await readback.readBack(signedRecord, store: store)

            case .exportSigned:
                if record.signedPhotoFilename != nil,
                   record.status != .signed,
                   record.status != .exporting {
                    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                    TAPDiagnostics.pendingCapture.info("process route export existing signedPhoto captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                    #endif
                } else {
                    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                    TAPDiagnostics.pendingCapture.info("process route export captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                    #endif
                }
                try await exporter.export(record, store: store)
                try Task.checkCancellation()
                try await readback.readBack(record, store: store)

            case .skip:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("process skipped exported captureID=\(record.captureID, privacy: .private)")
                #endif
                return
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("process success captureID=\(record.captureID, privacy: .private) previousStatus=\(record.status.rawValue, privacy: .public)")
            #endif
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
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
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
            let failureReason = TAPPendingCaptureFailureReasonPresentation.reason(for: status)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
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
