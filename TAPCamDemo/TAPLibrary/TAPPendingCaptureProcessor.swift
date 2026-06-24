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
            protectedDataIsAvailable: Self.defaultProtectedDataIsAvailable
        )
    }

    func processPendingCaptures(
        store: TAPPendingCaptureStore,
        signer: any TAPPendingCaptureSigning,
        exporter: any TAPPendingCaptureExporting,
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
            try await reconcile(store: store)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("worker reconcile complete workerID=\(workerID, privacy: .public)")
            #endif
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("worker reconcile failed workerID=\(workerID, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }

        var processedCaptureIDs = Set<String>()
        while let candidate = await nextProcessingCandidate(store: store, excludingCaptureIDs: processedCaptureIDs) {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("worker candidate workerID=\(workerID, privacy: .public) captureID=\(candidate.captureID, privacy: .private) status=\(candidate.status.rawValue, privacy: .public) retryCount=\(candidate.retryCount, privacy: .public) container=\(candidate.photoFileContainer.rawValue, privacy: .public) signedPhoto=\(candidate.signedPhotoFilename != nil, privacy: .public)")
            #endif
            processedCaptureIDs.insert(candidate.captureID)
            await process(candidate, store: store, signer: signer, exporter: exporter)
        }

        do {
            try await store.cleanupExportedLargeFiles()
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("worker cleanup failed workerID=\(workerID, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("worker finish workerID=\(workerID, privacy: .public) processedCount=\(processedCaptureIDs.count, privacy: .public)")
        #endif
    }

    private func nextProcessingCandidate(
        store: TAPPendingCaptureStore,
        excludingCaptureIDs: Set<String>
    ) async -> TAPPendingCaptureRecord? {
        do {
            return try await store.nextProcessingCandidate(excludingCaptureIDs: excludingCaptureIDs)
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.error("nextProcessingCandidate failed excludedCount=\(excludingCaptureIDs.count, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("process start captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public) retryCount=\(record.retryCount, privacy: .public)")
        #endif
        do {
            switch record.processingRoute {
            case .signThenExport:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("process route signThenExport captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
                #endif
                let signedRecord = try await signer.sign(record, store: store)
                try await exporter.export(signedRecord, store: store)

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

            case .skip:
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("process skipped exported captureID=\(record.captureID, privacy: .private)")
                #endif
                return
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("process success captureID=\(record.captureID, privacy: .private) previousStatus=\(record.status.rawValue, privacy: .public)")
            #endif
        } catch {
            let status = TAPPendingCaptureRetryClassifier.status(for: error)
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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign start captureID=\(record.captureID, privacy: .private)")
        #endif
        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign status updated captureID=\(record.captureID, privacy: .private) status=\(TAPPendingCaptureStatus.signing.rawValue, privacy: .public)")
        #endif

        let unsignedData = try await store.unsignedPhotoData(captureID: record.captureID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign unsigned data loaded captureID=\(record.captureID, privacy: .private) bytes=\(unsignedData.count, privacy: .public)")
        #endif
        let signedPhoto = try await provenanceWriter.signedPhotoData(
            from: unsignedData,
            expectedCaptureID: record.captureID,
            expectedProfile: record.outputProfile,
            assertionSigner: signer
        )
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign provenance ready captureID=\(record.captureID, privacy: .private) container=\(signedPhoto.fileContainer.rawValue, privacy: .public) manifestID=\(signedPhoto.manifest.payload.id, privacy: .private) keyID=\(signedPhoto.keyID, privacy: .private)")
        #endif
        let signedRecord = try await store.storeSignedPhoto(signedPhoto.data, captureID: record.captureID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign success captureID=\(record.captureID, privacy: .private) signedBytes=\(signedPhoto.data.count, privacy: .public)")
        #endif
        return signedRecord
    }
}

nonisolated struct PhotoLibraryPendingCaptureExportActions: Sendable {
    let existingAssetIdentifier: @Sendable (String) async throws -> String?
    let saveValidatedSignedPhoto: @Sendable (Data, TAPPendingCaptureRecord) async throws -> String

    init(
        existingAssetIdentifier: @escaping @Sendable (String) async throws -> String?,
        saveValidatedSignedPhoto: @escaping @Sendable (Data, TAPPendingCaptureRecord) async throws -> String
    ) {
        self.existingAssetIdentifier = existingAssetIdentifier
        self.saveValidatedSignedPhoto = saveValidatedSignedPhoto
    }

    init(
        existingAssetIdentifier: @escaping @Sendable (String) async throws -> String?,
        saveValidatedSignedHEIC: @escaping @Sendable (Data, TAPPendingCaptureRecord) async throws -> String
    ) {
        self.init(
            existingAssetIdentifier: existingAssetIdentifier,
            saveValidatedSignedPhoto: saveValidatedSignedHEIC
        )
    }

    static func live(
        provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()
    ) -> Self {
        Self(
            existingAssetIdentifier: { captureID in
                try await PhotoLibraryWriter.depthAssetIdentifier(captureID: captureID)
            },
            saveValidatedSignedPhoto: { signedData, record in
                let validatedPhoto = try provenanceWriter.validateSignedExportPhoto(
                    signedData,
                    expectedCaptureID: record.captureID,
                    expectedProfile: record.outputProfile
                )
                return try await PhotoLibraryWriter.saveDepthPhoto(
                    validatedPhoto,
                    capturedAt: record.capturedAt,
                    location: record.location?.clLocation
                )
            }
        )
    }
}

struct PhotoLibraryPendingCaptureExporter: TAPPendingCaptureExporting {
    private let actions: PhotoLibraryPendingCaptureExportActions

    init(actions: PhotoLibraryPendingCaptureExportActions = .live()) {
        self.actions = actions
    }

    func export(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export start captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
        #endif
        if record.shouldAttemptExistingAssetRecoveryBeforeExport,
           let existingAssetID = try? await actions.existingAssetIdentifier(record.captureID) {
            _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: existingAssetID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("export skipped existing asset captureID=\(record.captureID, privacy: .private) assetID=\(existingAssetID, privacy: .private)")
            #endif
            return
        }

        _ = try await store.updateStatus(captureID: record.captureID, status: .exporting)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export status updated captureID=\(record.captureID, privacy: .private) status=\(TAPPendingCaptureStatus.exporting.rawValue, privacy: .public)")
        #endif
        let signedData = try await store.signedPhotoData(captureID: record.captureID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export signed data loaded captureID=\(record.captureID, privacy: .private) bytes=\(signedData.count, privacy: .public)")
        #endif
        let assetID = try await actions.saveValidatedSignedPhoto(signedData, record)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export validation and save passed captureID=\(record.captureID, privacy: .private)")
        #endif
        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export success captureID=\(record.captureID, privacy: .private) assetID=\(assetID, privacy: .private)")
        #endif
    }
}
