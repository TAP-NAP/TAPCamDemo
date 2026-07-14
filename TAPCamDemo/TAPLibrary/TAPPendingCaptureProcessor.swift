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
            TAPDiagnostics.pendingCapture.info("worker candidate workerID=\(workerID, privacy: .public) captureID=\(candidate.captureID, privacy: .private) status=\(candidate.status.rawValue, privacy: .public) artifactKind=\(candidate.artifactKind.rawValue, privacy: .public) retryCount=\(candidate.retryCount, privacy: .public) container=\(candidate.photoFileContainer.rawValue, privacy: .public) signedPhoto=\(candidate.signedPhotoFilename != nil, privacy: .public) videoState=\(candidate.videoArtifactState?.rawValue ?? "none", privacy: .public)")
            #endif
            processedCaptureIDs.insert(candidate.captureID)
            await process(candidate, store: store, signer: signer, exporter: exporter)
        }

        do {
            try await cleanupExportedLargeFilesWithTrace(store: store)
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
        try await store.removeStaleVideoCaptureWorkspaces()
        try await store.removeUnshippedLegacyVideoBundles()
        try await store.normalizePersistedFailureReasons()
        let records = try await store.allRecords()
        for record in records {
            switch record.status {
            case .exported, .failedTerminal:
                continue
            case .exporting:
                // Photo recovery has a dedicated signed-photo lookup. TAP
                // video recovery must stay in the exporter so deterministic
                // filename candidates receive full manifest/proof readback.
                if record.artifactKind == .photoDepth,
                   let assetID = try? await PhotoLibraryWriter.depthAssetIdentifier(
                    captureID: record.captureID
                   ) {
                    _ = try await store.markExported(
                        captureID: record.captureID,
                        assetLocalIdentifier: assetID
                    )
                }
            case .pending, .waitingNetwork, .signing, .signed, .failedRetryable:
                continue
            }
        }
        try await cleanupExportedLargeFilesWithTrace(store: store)
    }

    private func cleanupExportedLargeFilesWithTrace(
        store: TAPPendingCaptureStore
    ) async throws {
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
            if let terminalCode = Self.terminalFailureCode(for: error, record: record) {
                _ = try? await store.markTerminalFailure(
                    captureID: record.captureID,
                    code: terminalCode
                )
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.error("process terminal failure captureID=\(record.captureID, privacy: .private) code=\(terminalCode.rawValue, privacy: .public)")
                #endif
                return
            }
            let persistedRecord = try? await store.readRecord(captureID: record.captureID)
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

    private nonisolated static func terminalFailureCode(
        for error: Error,
        record: TAPPendingCaptureRecord
    ) -> TAPPendingCaptureFailureCode? {
        guard record.artifactKind == .tapVideo,
              let captureError = error as? TAPDepthCaptureError else {
            return nil
        }
        switch captureError {
        case .missingDepthData:
            return .missingDepthData
        case .pendingCaptureProofExternalMutation:
            return .proofExternalMutation
        case .pendingCaptureProofInvalid,
             .pendingCaptureProofMissing:
            return .proofValidationFailed
        case .invalidTAPManifest,
             .pendingCaptureManifestIDMismatch:
            return .invalidVideoArtifact
        default:
            return nil
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

        switch record.artifactKind {
        case .photoDepth:
            let unsignedData = try await store.unsignedPhotoData(captureID: record.captureID)
            let pairedVideoURL = try await store.pairedVideoURL(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign unsigned photo data loaded captureID=\(record.captureID, privacy: .private) bytes=\(unsignedData.count, privacy: .public) hasPairedVideo=\(pairedVideoURL != nil, privacy: .public)")
            #endif
            let signedPhoto = try await provenanceWriter.signedPhotoData(
                from: unsignedData,
                expectedCaptureID: record.captureID,
                expectedProfile: record.outputProfile,
                assertionSigner: signer,
                pairedVideoURL: pairedVideoURL
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign photo provenance ready captureID=\(record.captureID, privacy: .private) container=\(signedPhoto.fileContainer.rawValue, privacy: .public) manifestID=\(signedPhoto.manifest.payload.id, privacy: .private) keyID=\(signedPhoto.keyID, privacy: .private)")
            #endif
            let signedRecord = try await store.storeSignedPhoto(signedPhoto.data, captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign photo success captureID=\(record.captureID, privacy: .private) signedBytes=\(signedPhoto.data.count, privacy: .public)")
            #endif
            return signedRecord

        case .tapVideo:
            let videoFileURL = try await store.videoArtifactURL(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            let byteCount = (try? videoFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            TAPDiagnostics.pendingCapture.info("sign video file loaded captureID=\(record.captureID, privacy: .private) bytes=\(byteCount, privacy: .public)")
            #endif
            let signedVideo = try await provenanceWriter.signedVideoFile(
                at: videoFileURL,
                expectedCaptureID: record.captureID,
                expectedPackageID: record.packageID,
                expectedPreSignContentBinding: record.preSignContentBinding,
                contentBindingPrepared: { binding in
                    _ = try await store.persistVideoPreSignContentBinding(
                        binding,
                        captureID: record.captureID
                    )
                },
                assertionSigner: signer
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign video provenance ready captureID=\(record.captureID, privacy: .private) manifestID=\(signedVideo.manifest.payload.id, privacy: .private) keyID=\(signedVideo.keyID, privacy: .private) depthSamples=\(signedVideo.manifest.payload.depthCoverage.sampleCount, privacy: .public)")
            #endif
            let signedRecord = try await store.markVideoSigned(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign video success captureID=\(record.captureID, privacy: .private) file=\(signedVideo.fileURL.lastPathComponent, privacy: .public)")
            #endif
            return signedRecord
        }
    }
}

nonisolated struct PhotoLibraryPendingCaptureExportActions: Sendable {
    let existingAssetIdentifier: @Sendable (String) async throws -> String?
    let saveValidatedSignedPhoto: @Sendable (Data, TAPPendingCaptureRecord, URL?) async throws -> String

    init(
        existingAssetIdentifier: @escaping @Sendable (String) async throws -> String?,
        saveValidatedSignedPhoto: @escaping @Sendable (Data, TAPPendingCaptureRecord) async throws -> String
    ) {
        self.existingAssetIdentifier = existingAssetIdentifier
        self.saveValidatedSignedPhoto = { data, record, _ in
            try await saveValidatedSignedPhoto(data, record)
        }
    }

    init(
        existingAssetIdentifier: @escaping @Sendable (String) async throws -> String?,
        saveValidatedSignedPhoto: @escaping @Sendable (Data, TAPPendingCaptureRecord, URL?) async throws -> String
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
            saveValidatedSignedPhoto: { signedData, record, pairedVideoURL in
                if let pairedVideoURL {
                    let validatedLivePhoto = try provenanceWriter.validateSignedExportLivePhoto(
                        signedData,
                        pairedVideoURL: pairedVideoURL,
                        expectedCaptureID: record.captureID,
                        expectedProfile: record.outputProfile
                    )
                    return try await PhotoLibraryWriter.saveDepthLivePhoto(
                        validatedLivePhoto,
                        capturedAt: record.capturedAt,
                        location: record.location?.clLocation
                    )
                } else {
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
            }
        )
    }
}

typealias PhotoLibraryPendingVideoCommitBoundary = @Sendable () async throws -> Void

nonisolated struct PhotoLibraryPendingVideoExportActions: Sendable {
    let candidateIdentifiers: @Sendable (UUID) async throws -> [String]
    let validateLocalFile: @Sendable (URL, TAPPendingCaptureRecord) async throws -> ValidatedTAPVideoFile
    let saveVideoFile: @Sendable (
        URL,
        TAPPendingCaptureRecord,
        TAPVideoManifest,
        PhotoLibraryPendingVideoCommitBoundary
    ) async throws -> String
    let validateReadback: @Sendable (String, TAPPendingCaptureRecord) async throws -> Void

    static func live() -> Self {
        Self(
            candidateIdentifiers: { packageID in
                try await PhotoLibraryWriter.tapVideoAssetCandidateIdentifiers(packageID: packageID)
            },
            validateLocalFile: { fileURL, record in
                try await TAPCaptureProvenanceWriter().validateSignedExportVideoFile(
                    at: fileURL,
                    expectedCaptureID: record.captureID,
                    expectedPackageID: record.packageID
                )
            },
            saveVideoFile: { fileURL, record, manifest, commitWillBegin in
                try await PhotoLibraryWriter.saveTAPVideoFile(
                    at: fileURL,
                    packageID: record.packageID,
                    manifest: manifest,
                    capturedAt: record.capturedAt,
                    location: record.location?.clLocation,
                    commitWillBegin: commitWillBegin
                )
            },
            validateReadback: { assetID, record in
                _ = try await TAPVideoPhotosReadbackValidator.validate(
                    assetLocalIdentifier: assetID,
                    captureID: record.captureID,
                    packageID: record.packageID
                )
            }
        )
    }
}

struct PhotoLibraryPendingCaptureExporter: TAPPendingCaptureExporting {
    private let actions: PhotoLibraryPendingCaptureExportActions
    private let videoActions: PhotoLibraryPendingVideoExportActions

    init(
        actions: PhotoLibraryPendingCaptureExportActions = .live(),
        videoActions: PhotoLibraryPendingVideoExportActions = .live()
    ) {
        self.actions = actions
        self.videoActions = videoActions
    }

    func export(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export start captureID=\(record.captureID, privacy: .private) status=\(record.status.rawValue, privacy: .public)")
        #endif
        if record.shouldAttemptExistingAssetRecoveryBeforeExport {
            switch record.artifactKind {
            case .photoDepth:
                if let existingAssetID = try? await actions.existingAssetIdentifier(record.captureID) {
                    _ = try await store.markExported(
                        captureID: record.captureID,
                        assetLocalIdentifier: existingAssetID
                    )
                    return
                }
            case .tapVideo:
                if try await recoverExistingVideoAsset(record, store: store) {
                    return
                }
                // Photos may not expose a just-committed asset immediately.
                // Remaining in recovery is safer than creating a duplicate.
                throw TAPDepthCaptureError.assetNotFound
            }
        }

        switch record.artifactKind {
        case .photoDepth:
            _ = try await store.updateStatus(captureID: record.captureID, status: .exporting)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("export status updated captureID=\(record.captureID, privacy: .private) status=\(TAPPendingCaptureStatus.exporting.rawValue, privacy: .public)")
            #endif
            let signedData = try await store.signedPhotoData(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("export signed photo data loaded captureID=\(record.captureID, privacy: .private) bytes=\(signedData.count, privacy: .public)")
            #endif
            let pairedVideoURL = try await store.pairedVideoURL(captureID: record.captureID)
            let assetID = try await actions.saveValidatedSignedPhoto(signedData, record, pairedVideoURL)
            _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)

        case .tapVideo:
            _ = try await store.markVideoPhotosExportIntent(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("video export intent persisted captureID=\(record.captureID, privacy: .private) phase=\(TAPPendingVideoPhotosExportPhase.preCommitIntent.rawValue, privacy: .public)")
            #endif
            let videoFileURL = try await store.videoArtifactURL(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            let byteCount = (try? videoFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            TAPDiagnostics.pendingCapture.info("export signed video file loaded captureID=\(record.captureID, privacy: .private) bytes=\(byteCount, privacy: .public)")
            #endif
            let validatedVideo = try await videoActions.validateLocalFile(videoFileURL, record)
            let expectedFilename = PhotoLibraryWriter.tapVideoResourceFilename(packageID: record.packageID)
            guard record.exportResourceFilename == expectedFilename else {
                _ = try await store.markTerminalFailure(
                    captureID: record.captureID,
                    code: .invalidVideoArtifact
                )
                return
            }
            let assetID = try await saveVideoWithTrace(
                validatedVideo,
                record: record,
                store: store
            )
            _ = try await store.markVideoPhotosCommit(
                captureID: record.captureID,
                assetLocalIdentifier: assetID
            )
            do {
                try await validateReadbackWithTrace(assetID: assetID, record: record)
            } catch {
                if Self.isTerminalVideoReadbackValidationError(error) {
                    _ = try await store.markTerminalFailure(
                        captureID: record.captureID,
                        code: .photosReadbackFailed,
                        assetLocalIdentifier: assetID
                    )
                    return
                }
                throw error
            }
            _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export validation and save passed captureID=\(record.captureID, privacy: .private)")
        #endif
    }

    private func recoverExistingVideoAsset(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> Bool {
        let candidateIDs: [String]
        if let committedAssetID = record.assetLocalIdentifier {
            candidateIDs = [committedAssetID]
        } else {
            candidateIDs = try await videoActions.candidateIdentifiers(record.packageID)
        }
        guard !candidateIDs.isEmpty else {
            return false
        }
        var validCandidateIDs: [String] = []
        for candidateID in candidateIDs {
            do {
                try await validateReadbackWithTrace(assetID: candidateID, record: record)
                validCandidateIDs.append(candidateID)
            } catch {
                if Self.isTerminalVideoReadbackValidationError(error) {
                    continue
                }
                throw error
            }
        }
        if let earliestValidID = validCandidateIDs.first {
            let duplicateWarning = validCandidateIDs.count > 1
                ? "Multiple fully valid TAP video assets matched this package. The earliest was retained."
                : nil
            _ = try await store.markExported(
                captureID: record.captureID,
                assetLocalIdentifier: earliestValidID,
                duplicateExportWarning: duplicateWarning
            )
        } else {
            _ = try await store.markTerminalFailure(
                captureID: record.captureID,
                code: .photosReadbackFailed,
                assetLocalIdentifier: candidateIDs.first
            )
        }
        return true
    }

    private static func isTerminalVideoReadbackValidationError(_ error: Error) -> Bool {
        if error is DecodingError {
            return true
        }
        guard let captureError = error as? TAPDepthCaptureError else {
            return false
        }
        switch captureError {
        case .invalidTAPManifest,
             .pendingCaptureManifestIDMismatch,
             .pendingCaptureProofMissing,
             .pendingCaptureProofInvalid,
             .pendingCaptureProofExternalMutation,
             .missingDepthData:
            return true
        default:
            return false
        }
    }

    private func saveVideoWithTrace(
        _ validatedVideo: ValidatedTAPVideoFile,
        record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> String {
        let trace = TAPVideoPerformanceTrace.beginPhotosExport()
        do {
            let assetID = try await videoActions.saveVideoFile(
                validatedVideo.fileURL,
                record,
                validatedVideo.manifest,
                {
                    _ = try await store.markVideoPhotosCommitAmbiguous(
                        captureID: record.captureID
                    )
                }
            )
            TAPVideoPerformanceTrace.endPhotosExport(trace, succeeded: true)
            return assetID
        } catch {
            TAPVideoPerformanceTrace.endPhotosExport(trace, succeeded: false)
            throw error
        }
    }

    private func validateReadbackWithTrace(
        assetID: String,
        record: TAPPendingCaptureRecord
    ) async throws {
        let trace = TAPVideoPerformanceTrace.beginPhotosReadback()
        do {
            try await videoActions.validateReadback(assetID, record)
            TAPVideoPerformanceTrace.endPhotosReadback(trace, succeeded: true)
        } catch {
            TAPVideoPerformanceTrace.endPhotosReadback(trace, succeeded: false)
            throw error
        }
    }
}
