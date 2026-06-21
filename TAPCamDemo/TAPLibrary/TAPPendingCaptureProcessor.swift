//
//  TAPPendingCaptureProcessor.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import Foundation
import OSLog
import UIKit

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

/// Serial background processor for staged TAP depth HEIC captures.
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
            protectedDataIsAvailable: Self.defaultProtectedDataIsAvailable
        )
    }

    func processPendingCaptures(
        store: TAPPendingCaptureStore,
        signer: any TAPPendingCaptureSigning,
        exporter: any TAPPendingCaptureExporting,
        protectedDataIsAvailable: @escaping @Sendable () async -> Bool
    ) async {
        TAPDiagnostics.pendingCapture.info("processPendingCaptures requested workerActive=\(self.workerTask != nil, privacy: .public)")
        while let currentWorkerTask = workerTask {
            TAPDiagnostics.pendingCapture.info("processPendingCaptures waiting for active worker")
            await currentWorkerTask.value
        }

        let task = Task { [store, signer, exporter, protectedDataIsAvailable] in
            await self.runWorker(
                store: store,
                signer: signer,
                exporter: exporter,
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
        protectedDataIsAvailable: @escaping @Sendable () async -> Bool
    ) async {
        defer { workerTask = nil }
        let workerID = UUID().uuidString
        TAPDiagnostics.pendingCapture.info("worker start workerID=\(workerID, privacy: .public)")
        let readiness = TAPPendingCaptureWorkerReadiness(
            protectedDataIsAvailable: await protectedDataIsAvailable()
        )
        guard readiness.allowsPrivateArtifactAccess else {
            let readinessDescription = readiness.diagnosticDescription
            TAPDiagnostics.pendingCapture.info(
                "worker stopped workerID=\(workerID, privacy: .public) readiness=\(readinessDescription, privacy: .public)"
            )
            return
        }

        do {
            try await reconcile(store: store)
            TAPDiagnostics.pendingCapture.info("worker reconcile complete workerID=\(workerID, privacy: .public)")
        } catch {
            TAPDiagnostics.pendingCapture.error("worker reconcile failed workerID=\(workerID, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
        }

        var processedCaptureIDs = Set<String>()
        while let candidate = await nextProcessingCandidate(store: store, excludingCaptureIDs: processedCaptureIDs) {
            TAPDiagnostics.pendingCapture.info("worker candidate workerID=\(workerID, privacy: .public) captureID=\(candidate.captureID, privacy: .private) status=\(candidate.status.rawValue, privacy: .public) retryCount=\(candidate.retryCount, privacy: .public) signedHEIC=\(candidate.signedHEICFilename != nil, privacy: .public)")
            processedCaptureIDs.insert(candidate.captureID)
            await process(candidate, store: store, signer: signer, exporter: exporter)
        }

        do {
            try await store.cleanupExportedLargeFiles()
        } catch {
            TAPDiagnostics.pendingCapture.error("worker cleanup failed workerID=\(workerID, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
        }
        TAPDiagnostics.pendingCapture.info("worker finish workerID=\(workerID, privacy: .public) processedCount=\(processedCaptureIDs.count, privacy: .public)")
    }

    private func nextProcessingCandidate(
        store: TAPPendingCaptureStore,
        excludingCaptureIDs: Set<String>
    ) async -> TAPPendingCaptureRecord? {
        do {
            return try await store.nextProcessingCandidate(excludingCaptureIDs: excludingCaptureIDs)
        } catch {
            TAPDiagnostics.pendingCapture.error("nextProcessingCandidate failed excludedCount=\(excludingCaptureIDs.count, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            return nil
        }
    }

    func reconcile(store: TAPPendingCaptureStore = .shared) async throws {
        try await store.normalizePersistedFailureReasons()
        let records = try await store.allRecords()
        for record in records {
            switch record.status {
            case .exported:
                continue
            case .exporting:
                if let assetID = try? await PhotoLibraryWriter.depthAssetIdentifier(captureID: record.captureID) {
                    _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)
                }
            case .pending, .waitingNetwork, .signing, .signed, .failedRetryable:
                continue
            }
        }
        try await store.cleanupExportedLargeFiles()
    }

    private func process(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore,
        signer: any TAPPendingCaptureSigning,
        exporter: any TAPPendingCaptureExporting
    ) async {
        TAPDiagnostics.pendingCapture.info("process start captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) retryCount=\(record.retryCount, privacy: .public)")
        do {
            switch record.processingRoute {
            case .signThenExport:
                TAPDiagnostics.pendingCapture.info("process route signThenExport captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                let signedRecord = try await signer.sign(record, store: store)
                try await exporter.export(signedRecord, store: store)

            case .exportSigned:
                if record.signedHEICFilename != nil,
                   record.status != .signed,
                   record.status != .exporting {
                    TAPDiagnostics.pendingCapture.info("process route export existing signedHEIC captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                } else {
                    TAPDiagnostics.pendingCapture.info("process route export captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                }
                try await exporter.export(record, store: store)

            case .skip:
                TAPDiagnostics.pendingCapture.info("process skipped exported captureID=\(record.captureID, privacy: .private)")
                return
            }
            TAPDiagnostics.pendingCapture.info("process success captureID=\(record.captureID, privacy: .private) previousStatus=\(record.status.rawValue, privacy: .public)")
        } catch {
            let status = TAPPendingCaptureRetryClassifier.status(for: error)
            let failureReason = TAPPendingCaptureFailureReasonPresentation.reason(for: status)
            TAPDiagnostics.pendingCapture.error("process failed captureID=\(record.captureID, privacy: .private) previousStatus=\(record.status.rawValue, privacy: .public) nextStatus=\(status.rawValue, privacy: .public) retryCount=\(record.retryCount + 1, privacy: .public) vpnHint=\(TAPDiagnostics.errorLooksVPNRelated(error), privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
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

private struct AppAttestPendingCaptureSigner: TAPPendingCaptureSigning {
    private let signer: AppAttestCaptureAssertionSigner
    private let provenanceWriter: TAPCaptureProvenanceWriter

    init(appAttestClient: any AppAttestClient) {
        self.signer = AppAttestCaptureAssertionSigner(client: appAttestClient)
        self.provenanceWriter = TAPCaptureProvenanceWriter()
    }

    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        TAPDiagnostics.pendingCapture.info("sign start captureID=\(record.captureID, privacy: .private)")
        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)
        TAPDiagnostics.pendingCapture.info("sign status updated captureID=\(record.captureID, privacy: .private) status=\(TAPPendingCaptureStatus.signing.rawValue, privacy: .public)")

        let unsignedData = try await store.unsignedHEICData(captureID: record.captureID)
        TAPDiagnostics.pendingCapture.info("sign unsigned data loaded captureID=\(record.captureID, privacy: .private) bytes=\(unsignedData.count, privacy: .public)")
        let signedHEIC = try await provenanceWriter.signedHEICData(
            from: unsignedData,
            expectedCaptureID: record.captureID,
            assertionSigner: signer
        )
        TAPDiagnostics.pendingCapture.info("sign provenance ready captureID=\(record.captureID, privacy: .private) manifestID=\(signedHEIC.manifest.payload.id, privacy: .private) keyID=\(signedHEIC.keyID, privacy: .private)")
        let signedRecord = try await store.storeSignedHEIC(signedHEIC.data, captureID: record.captureID)
        TAPDiagnostics.pendingCapture.info("sign success captureID=\(record.captureID, privacy: .private) signedBytes=\(signedHEIC.data.count, privacy: .public)")
        return signedRecord
    }
}

private struct PhotoLibraryPendingCaptureExporter: TAPPendingCaptureExporting {
    private let provenanceWriter = TAPCaptureProvenanceWriter()

    func export(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws {
        TAPDiagnostics.pendingCapture.info("export start captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
        if let existingAssetID = try? await PhotoLibraryWriter.depthAssetIdentifier(captureID: record.captureID) {
            _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: existingAssetID)
            TAPDiagnostics.pendingCapture.info("export skipped existing asset captureID=\(record.captureID, privacy: .private) assetID=\(existingAssetID, privacy: .private)")
            return
        }

        _ = try await store.updateStatus(captureID: record.captureID, status: .exporting)
        TAPDiagnostics.pendingCapture.info("export status updated captureID=\(record.captureID, privacy: .private) status=\(TAPPendingCaptureStatus.exporting.rawValue, privacy: .public)")
        let signedData = try await store.signedHEICData(captureID: record.captureID)
        TAPDiagnostics.pendingCapture.info("export signed data loaded captureID=\(record.captureID, privacy: .private) bytes=\(signedData.count, privacy: .public)")
        let validatedHEIC = try provenanceWriter.validateSignedExportHEIC(
            signedData,
            expectedCaptureID: record.captureID
        )
        TAPDiagnostics.pendingCapture.info("export validation passed captureID=\(record.captureID, privacy: .private) proofCount=\(validatedHEIC.manifest.proofs.count, privacy: .public)")
        let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
            validatedHEIC,
            capturedAt: record.capturedAt,
            location: record.location?.clLocation
        )
        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)
        TAPDiagnostics.pendingCapture.info("export success captureID=\(record.captureID, privacy: .private) assetID=\(assetID, privacy: .private)")
    }
}
