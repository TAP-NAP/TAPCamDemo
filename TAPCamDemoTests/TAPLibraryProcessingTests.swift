//
//  TAPLibraryProcessingTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPLibraryProcessingTests {
    @Test func pendingCaptureWorkerReadinessRequiresProtectedData() throws {
        let ready = TAPPendingCaptureWorkerReadiness(protectedDataIsAvailable: true)
        let locked = TAPPendingCaptureWorkerReadiness(protectedDataIsAvailable: false)

        #expect(ready == .ready)
        #expect(locked == .protectedDataUnavailable)
        #expect(ready.allowsPrivateArtifactAccess)
        #expect(!locked.allowsPrivateArtifactAccess)
    }

    @Test func pendingCaptureProcessorStopsWhenProtectedDataIsUnavailable() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8)))
        let signer = RecordingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { false }
        )

        let unchangedRecord = try await store.readRecord(captureID: record.captureID)
        #expect(unchangedRecord.status == .pending)
        #expect(unchangedRecord.retryCount == 0)
        #expect(unchangedRecord.failureReason == nil)
        #expect(await signer.signedCaptureIDs().isEmpty)
        #expect(await exporter.exportedCaptureIDs().isEmpty)
    }

    @Test func pendingCaptureProcessorLeavesSignedRecordUntouchedWhenProtectedDataIsUnavailable() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let signedRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "signed-capture"
        ))
        _ = try await store.storeSignedPhoto(Data("signed".utf8), captureID: signedRecord.captureID)
        let signer = RecordingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { false }
        )

        let unchangedRecord = try await store.readRecord(captureID: signedRecord.captureID)
        #expect(unchangedRecord.status == .signed)
        #expect(unchangedRecord.retryCount == 0)
        #expect(unchangedRecord.failureReason == nil)
        #expect(unchangedRecord.signedPhotoFilename != nil)
        #expect(await signer.signedCaptureIDs().isEmpty)
        #expect(await exporter.exportedCaptureIDs().isEmpty)
    }

    @Test func pendingCaptureProcessorSignsAndExportsInCandidatePriorityOrder() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let retryRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("retry".utf8),
            captureID: "retry-capture",
            capturedAt: Date(timeIntervalSince1970: 0)
        ))
        _ = try await store.updateStatus(
            captureID: retryRecord.captureID,
            status: .waitingNetwork,
            failureReason: .waitingNetwork,
            incrementsRetryCount: true
        )
        let pendingRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("pending".utf8),
            captureID: "pending-capture",
            capturedAt: Date(timeIntervalSince1970: 1)
        ))
        let signedRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("signed-source".utf8),
            captureID: "signed-capture",
            capturedAt: Date(timeIntervalSince1970: 2)
        ))
        _ = try await store.storeSignedPhoto(Data("already-signed".utf8), captureID: signedRecord.captureID)
        let signer = RecordingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { true }
        )

        #expect(await signer.signedCaptureIDs() == [
            pendingRecord.captureID,
            retryRecord.captureID
        ])
        #expect(await exporter.exportedCaptureIDs() == [
            signedRecord.captureID,
            pendingRecord.captureID,
            retryRecord.captureID
        ])
        #expect(try await store.readRecord(captureID: pendingRecord.captureID).status == .exported)
        #expect(try await store.readRecord(captureID: signedRecord.captureID).status == .exported)
        #expect(try await store.readRecord(captureID: retryRecord.captureID).status == .exported)
    }

    @Test func pendingCaptureProcessorRunsInjectedPipelineStagesInOrder() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "injected-pipeline"
        ))
        let recorder = PendingCaptureStageRecorder()

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: StageRecordingPendingCaptureSigner(recorder: recorder),
            exporter: StageRecordingPendingCaptureExporter(recorder: recorder),
            readback: StageRecordingPendingCaptureReadback(recorder: recorder),
            cleanup: StageRecordingPendingCaptureCleanup(recorder: recorder),
            protectedDataIsAvailable: { true }
        )

        #expect(await recorder.recordedStages() == [
            "cleanup",
            "sign",
            "export",
            "readback",
            "cleanup"
        ])
        #expect(try await store.readRecord(captureID: record.captureID).status == .exported)
    }

    @Test func pendingCaptureProcessorClassifiesNetworkExportFailureAsWaitingNetwork() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8)))
        let signer = RecordingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter(failingCaptureIDs: [record.captureID])
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { true }
        )

        let failedRecord = try await store.readRecord(captureID: record.captureID)
        #expect(failedRecord.status == .waitingNetwork)
        #expect(failedRecord.retryCount == 1)
        #expect(failedRecord.failureReason == "Network unavailable. Capture will retry.")
    }

    @Test func photoLibraryPendingCaptureExporterSkipsExistingAssetLookupForSignedFirstExport() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "signed-first-export"
        ))
        let signedRecord = try await store.storeSignedPhoto(
            Data("signed-first-export-data".utf8),
            captureID: record.captureID
        )
        let actions = RecordingPhotoLibraryExportActions()
        let exporter = PhotoLibraryPendingCaptureExporter(actions: actions.actions())

        try await exporter.export(signedRecord, store: store)

        #expect(await actions.existingLookupCaptureIDs().isEmpty)
        #expect(await actions.savedCaptureIDs() == [signedRecord.captureID])
        let exportedRecord = try await store.readRecord(captureID: signedRecord.captureID)
        #expect(exportedRecord.status == .exported)
        #expect(exportedRecord.assetLocalIdentifier == "saved-\(signedRecord.captureID)")
    }

    @Test func photoLibraryPendingCaptureExporterUsesExistingAssetLookupOnlyForExportingRecovery() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "exporting-recovery"
        ))
        _ = try await store.storeSignedPhoto(
            Data("exporting-recovery-data".utf8),
            captureID: record.captureID
        )
        let exportingRecord = try await store.updateStatus(captureID: record.captureID, status: .exporting)
        let actions = RecordingPhotoLibraryExportActions()
        let exporter = PhotoLibraryPendingCaptureExporter(actions: actions.actions(existingAssetID: "existing-asset"))

        try await exporter.export(exportingRecord, store: store)

        #expect(await actions.existingLookupCaptureIDs() == [exportingRecord.captureID])
        #expect(await actions.savedCaptureIDs().isEmpty)
        let exportedRecord = try await store.readRecord(captureID: exportingRecord.captureID)
        #expect(exportedRecord.status == .exported)
        #expect(exportedRecord.assetLocalIdentifier == "existing-asset")
    }

    @Test func pendingCaptureRetryClassifierMapsTypedNetworkErrorsToWaitingNetwork() throws {
        let networkErrors: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .timedOut,
            .internationalRoamingOff,
            .dataNotAllowed,
            .secureConnectionFailed
        ]

        for code in networkErrors {
            #expect(TAPPendingCaptureRetryClassifier.status(for: URLError(code)) == .waitingNetwork)
        }
    }

    @Test func pendingCaptureRetryClassifierReadsUnderlyingNSErrorCodes() throws {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [
                NSLocalizedDescriptionKey: "timed out at https://secret.tapnap.net/export?token=secret-token"
            ]
        )
        let wrapped = NSError(
            domain: "TAPWrappedWorkerError",
            code: 7,
            userInfo: [
                NSUnderlyingErrorKey: underlying,
                NSLocalizedDescriptionKey: "captureID=pending/private-capture-id path=/private/secret/signed.heic"
            ]
        )

        #expect(TAPPendingCaptureRetryClassifier.status(for: wrapped) == .waitingNetwork)
    }

    @Test func pendingCaptureRetryClassifierReadsMultipleUnderlyingNSErrorCodes() throws {
        let nonNetworkError = NSError(
            domain: "TAPNonNetworkError",
            code: 19,
            userInfo: [
                NSLocalizedDescriptionKey: "offline network path /private/secret url=https://secret.tapnap.net"
            ]
        )
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorDataNotAllowed,
            userInfo: [
                NSLocalizedDescriptionKey: "data not allowed at https://secret.tapnap.net/export?token=secret-token"
            ]
        )
        let wrapped = NSError(
            domain: "TAPMultipleWrappedWorkerError",
            code: 8,
            userInfo: [
                NSMultipleUnderlyingErrorsKey: [nonNetworkError, networkError],
                NSLocalizedDescriptionKey: "captureID=pending/private-capture-id path=/private/secret/signed.heic"
            ]
        )

        #expect(TAPPendingCaptureRetryClassifier.status(for: wrapped) == .waitingNetwork)
    }

    @Test func pendingCaptureRetryClassifierDoesNotClassifyByLocalizedDescription() throws {
        let localizedOnlyError = NSError(
            domain: "TAPNonNetworkError",
            code: 19,
            userInfo: [
                NSLocalizedDescriptionKey: "offline network path /private/secret url=https://secret.tapnap.net"
            ]
        )

        #expect(TAPPendingCaptureRetryClassifier.status(for: localizedOnlyError) == .failedRetryable)
    }

    @Test func pendingCaptureFailureReasonPresentationOmitsRawIdentifiersAndPaths() throws {
        let reasons = [
            TAPPendingCaptureFailureReasonPresentation.persistedFailureReason(
                for: TAPPendingCaptureStatus.waitingNetwork
            ),
            TAPPendingCaptureFailureReasonPresentation.persistedFailureReason(
                for: TAPPendingCaptureStatus.failedRetryable
            )
        ]
        let forbiddenTokens = [
            "pending/private-capture-id",
            "actual-manifest-id-2",
            "asset-private-id",
            "/private/",
            "unsigned.heic",
            "signed.heic",
            "bundle.json",
            "https://secret.tapnap.net",
            "token=secret-token",
            "prepared-key-id",
            "secret-proof"
        ]

        #expect(reasons == [
            "Network unavailable. Capture will retry.",
            "Capture processing failed. It will retry."
        ])
        for reason in reasons {
            for token in forbiddenTokens {
                #expect(!reason.contains(token))
            }
        }
    }

    @Test func pendingCaptureProcessorPersistsPublicSafeNetworkFailureReason() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "safe-network-capture-id"
        ))
        let signer = RecordingPendingCaptureSigner()
        let exporter = SensitiveNetworkFailingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { true }
        )

        let failedRecord = try await store.readRecord(captureID: record.captureID)
        let reason = try #require(failedRecord.failureReason)
        let bundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(rootURL: rootURL, captureID: record.captureID)
        let forbiddenTokens = [
            "pending/private-capture-id",
            "/private/var/mobile/Containers/Data/Application/secret/unsigned.heic",
            "https://secret.tapnap.net",
            "token=secret-token",
            "prepared-key-id"
        ]

        #expect(failedRecord.status == .waitingNetwork)
        #expect(reason == "Network unavailable. Capture will retry.")
        for token in forbiddenTokens {
            #expect(!reason.contains(token))
            #expect(!bundleJSON.contains(token))
        }
    }

    @Test func pendingCaptureProcessorPersistsPublicSafeRetryFailureReason() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "safe-retry-capture-id"
        ))
        let signer = SensitiveFailingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { true }
        )

        let failedRecord = try await store.readRecord(captureID: record.captureID)
        let reason = try #require(failedRecord.failureReason)
        let bundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(rootURL: rootURL, captureID: record.captureID)
        let forbiddenTokens = [
            "pending/private-capture-id",
            "actual-manifest-id-2",
            "/private/var/mobile/Containers/Data/Application/secret/signed.heic",
            "prepared-key-id",
            "secret-proof"
        ]

        #expect(failedRecord.status == .failedRetryable)
        #expect(reason == "Capture processing failed. It will retry.")
        for token in forbiddenTokens {
            #expect(!reason.contains(token))
            #expect(!bundleJSON.contains(token))
        }
    }

    @Test func unsignedVideoManifestFailureRemainsRetryable() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "unsigned-video-validation-failure"
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: InvalidManifestPendingVideoSigner(),
            exporter: RecordingPendingCaptureExporter(),
            protectedDataIsAvailable: { true }
        )

        let failed = try await store.readRecord(captureID: record.captureID)
        #expect(failed.status == .failedRetryable)
        #expect(failed.failureCode == nil)
        #expect(failed.videoArtifactState == .unsigned)
    }

    @Test func persistedSignedVideoBindingFailureIsTerminal() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "signed-video-binding-failure"
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: MarkingPendingVideoSigner(),
            exporter: InvalidManifestPendingCaptureExporter(),
            protectedDataIsAvailable: { true }
        )

        let failed = try await store.readRecord(captureID: record.captureID)
        #expect(failed.status == .failedTerminal)
        #expect(failed.failureCode == .invalidVideoArtifact)
        #expect(failed.videoArtifactState == .signed)
    }

    @Test func videoReadbackTransportFailureKeepsCommittedAssetInRecovery() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
        let pending = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-readback-transport"
        )
        _ = try await store.markVideoSigned(captureID: pending.captureID)
        _ = try await store.markVideoPhotosExportIntent(captureID: pending.captureID)
        _ = try await store.markVideoPhotosCommitAmbiguous(captureID: pending.captureID)
        let committed = try await store.markVideoPhotosCommit(
            captureID: pending.captureID,
            assetLocalIdentifier: "committed-video-asset"
        )
        let videoActions = RecordingVideoExportActions(
            candidates: ["must-not-query-candidates"],
            readbackResult: .transportFailure
        )
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(videoActions: videoActions.actions()),
            readback: PhotoLibraryPendingCaptureReadback(actions: videoActions.readbackActions()),
            protectedDataIsAvailable: { true }
        )

        let recovered = try await store.readRecord(captureID: committed.captureID)
        #expect(recovered.status == .exporting)
        #expect(recovered.assetLocalIdentifier == "committed-video-asset")
        #expect(recovered.retryCount == 1)
        #expect(await videoActions.candidatePackageIDs().isEmpty)
        #expect(await videoActions.savedCaptureIDs().isEmpty)
        #expect(await videoActions.validatedAssetIDs() == ["committed-video-asset"])
    }

    @Test func videoReadbackDecodingFailureIsTerminalIntegrityFailure() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
        let pending = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-readback-integrity"
        )
        _ = try await store.markVideoSigned(captureID: pending.captureID)
        _ = try await store.markVideoPhotosExportIntent(captureID: pending.captureID)
        _ = try await store.markVideoPhotosCommitAmbiguous(captureID: pending.captureID)
        _ = try await store.markVideoPhotosCommit(
            captureID: pending.captureID,
            assetLocalIdentifier: "corrupt-video-asset"
        )
        let videoActions = RecordingVideoExportActions(
            candidates: [],
            readbackResult: .decodingIntegrityFailure
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(videoActions: videoActions.actions()),
            readback: PhotoLibraryPendingCaptureReadback(actions: videoActions.readbackActions()),
            protectedDataIsAvailable: { true }
        )

        let failed = try await store.readRecord(captureID: pending.captureID)
        #expect(failed.status == .failedTerminal)
        #expect(failed.failureCode == .photosReadbackFailed)
        #expect(failed.assetLocalIdentifier == "corrupt-video-asset")
        #expect(await videoActions.savedCaptureIDs().isEmpty)
    }

    @Test func interruptedVideoExportWithNoCandidateNeverCreatesAnotherAsset() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
        let pending = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-empty-recovery"
        )
        _ = try await store.markVideoSigned(captureID: pending.captureID)
        _ = try await store.markVideoPhotosExportIntent(captureID: pending.captureID)
        _ = try await store.markVideoPhotosCommitAmbiguous(captureID: pending.captureID)
        let videoActions = RecordingVideoExportActions(
            candidates: [],
            readbackResult: .success
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(videoActions: videoActions.actions()),
            readback: PhotoLibraryPendingCaptureReadback(actions: videoActions.readbackActions()),
            protectedDataIsAvailable: { true }
        )

        let recovery = try await store.readRecord(captureID: pending.captureID)
        #expect(recovery.status == .exporting)
        #expect(recovery.assetLocalIdentifier == nil)
        #expect(recovery.retryCount == 1)
        #expect(await videoActions.candidatePackageIDs() == [pending.packageID])
        #expect(await videoActions.savedCaptureIDs().isEmpty)
        #expect(await videoActions.validatedAssetIDs().isEmpty)
    }

    @Test func interruptedVideoExportChoosesEarliestValidCandidateAndWarnsOnDuplicates() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
        let pending = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-duplicate-recovery"
        )
        _ = try await store.markVideoSigned(captureID: pending.captureID)
        _ = try await store.markVideoPhotosExportIntent(captureID: pending.captureID)
        _ = try await store.markVideoPhotosCommitAmbiguous(captureID: pending.captureID)
        let videoActions = RecordingVideoExportActions(
            candidates: ["earliest-valid-asset", "later-valid-asset"],
            readbackResult: .success
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(videoActions: videoActions.actions()),
            readback: PhotoLibraryPendingCaptureReadback(actions: videoActions.readbackActions()),
            protectedDataIsAvailable: { true }
        )

        let exported = try await store.readRecord(captureID: pending.captureID)
        #expect(exported.status == .exported)
        #expect(exported.assetLocalIdentifier == "earliest-valid-asset")
        #expect(exported.duplicateExportWarning != nil)
        #expect(await videoActions.candidatePackageIDs() == [pending.packageID])
        #expect(await videoActions.savedCaptureIDs().isEmpty)
        #expect(await videoActions.validatedAssetIDs() == [
            "earliest-valid-asset",
            "later-valid-asset"
        ])
    }

    @Test func preCommitVideoExportCrashCanSafelyCreateAfterRestart() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
        let pending = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-pre-commit-crash"
        )
        _ = try await store.markVideoSigned(captureID: pending.captureID)
        let interruptedActions = RecordingVideoExportActions(
            candidates: ["must-not-recover-before-commit"],
            readbackResult: .success,
            saveResult: .transportFailureBeforeCommit
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(
                videoActions: interruptedActions.actions()
            ),
            readback: PhotoLibraryPendingCaptureReadback(
                actions: interruptedActions.readbackActions()
            ),
            protectedDataIsAvailable: { true }
        )

        let intent = try await store.readRecord(captureID: pending.captureID)
        #expect(intent.status == .waitingNetwork)
        #expect(intent.videoPhotosExportPhase == .preCommitIntent)
        #expect(intent.assetLocalIdentifier == nil)
        #expect(!intent.shouldAttemptExistingAssetRecoveryBeforeExport)
        #expect(await interruptedActions.candidatePackageIDs().isEmpty)
        #expect(await interruptedActions.savedCaptureIDs() == [pending.captureID])

        let restartedActions = RecordingVideoExportActions(
            candidates: ["must-still-not-recover-before-commit"],
            readbackResult: .success
        )
        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(
                videoActions: restartedActions.actions()
            ),
            readback: PhotoLibraryPendingCaptureReadback(
                actions: restartedActions.readbackActions()
            ),
            protectedDataIsAvailable: { true }
        )

        let exported = try await store.readRecord(captureID: pending.captureID)
        #expect(exported.status == .exported)
        #expect(exported.videoPhotosExportPhase == .committed)
        #expect(exported.assetLocalIdentifier == "created-\(pending.captureID)")
        #expect(await restartedActions.candidatePackageIDs().isEmpty)
        #expect(await restartedActions.savedCaptureIDs() == [pending.captureID])
        #expect(await restartedActions.validatedAssetIDs() == ["created-\(pending.captureID)"])
    }

    @Test func postCommitVideoExportCrashOnlyRecoversAndNeverCreatesAgain() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
        let pending = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-post-commit-crash"
        )
        _ = try await store.markVideoSigned(captureID: pending.captureID)
        let interruptedActions = RecordingVideoExportActions(
            candidates: [],
            readbackResult: .success,
            saveResult: .transportFailureAfterCommit
        )

        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(
                videoActions: interruptedActions.actions()
            ),
            readback: PhotoLibraryPendingCaptureReadback(
                actions: interruptedActions.readbackActions()
            ),
            protectedDataIsAvailable: { true }
        )

        let ambiguous = try await store.readRecord(captureID: pending.captureID)
        #expect(ambiguous.status == .exporting)
        #expect(ambiguous.videoPhotosExportPhase == .commitAmbiguous)
        #expect(ambiguous.assetLocalIdentifier == nil)
        #expect(ambiguous.shouldAttemptExistingAssetRecoveryBeforeExport)
        #expect(await interruptedActions.savedCaptureIDs() == [pending.captureID])

        let restartedActions = RecordingVideoExportActions(
            candidates: ["recovered-post-commit-asset"],
            readbackResult: .success
        )
        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store,
            signer: RecordingPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(
                videoActions: restartedActions.actions()
            ),
            readback: PhotoLibraryPendingCaptureReadback(
                actions: restartedActions.readbackActions()
            ),
            protectedDataIsAvailable: { true }
        )

        let exported = try await store.readRecord(captureID: pending.captureID)
        #expect(exported.status == .exported)
        #expect(exported.videoPhotosExportPhase == .committed)
        #expect(exported.assetLocalIdentifier == "recovered-post-commit-asset")
        #expect(await restartedActions.candidatePackageIDs() == [pending.packageID])
        #expect(await restartedActions.savedCaptureIDs().isEmpty)
        #expect(await restartedActions.validatedAssetIDs() == ["recovered-post-commit-asset"])
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable))
    func videoCommitAmbiguousBoundaryImmediatelyPrecedesPhotosPerformChanges() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift"
        )
        let createVideoAsset = try #require(TAPCamDemoTestSourceInspection.substring(
            in: source,
            from: "private static func createVideoAsset(",
            to: "private static func fetchAlbum("
        ))

        #expect(createVideoAsset.contains(
            "try await commitWillBegin()\n        try await PHPhotoLibrary.shared().performChanges {"
        ))
    }

}

private actor RecordingPendingCaptureSigner: TAPPendingCaptureSigning {
    private var captureIDs: [String] = []

    func signedCaptureIDs() -> [String] {
        captureIDs
    }

    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        captureIDs.append(record.captureID)
        return try await store.storeSignedPhoto(
            Data("signed-\(record.captureID)".utf8),
            captureID: record.captureID
        )
    }
}

private struct SensitiveFailingPendingCaptureSigner: TAPPendingCaptureSigning {
    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        throw TAPDepthCaptureError.pendingCaptureProofInvalid(
            "captureID=pending/private-capture-id actual=actual-manifest-id-2 keyID=prepared-key-id proof=secret-proof path=/private/var/mobile/Containers/Data/Application/secret/signed.heic"
        )
    }
}

private struct InvalidManifestPendingVideoSigner: TAPPendingCaptureSigning {
    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        throw TAPDepthCaptureError.invalidTAPManifest(
            "unsigned capture health check must not become terminal"
        )
    }
}

private struct MarkingPendingVideoSigner: TAPPendingCaptureSigning {
    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        try await store.markVideoSigned(captureID: record.captureID)
    }
}

private struct InvalidManifestPendingCaptureExporter: TAPPendingCaptureExporting {
    func export(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws {
        throw TAPDepthCaptureError.invalidTAPManifest(
            "signed artifact no longer matches its persisted identity"
        )
    }
}

private actor PendingCaptureStageRecorder {
    private var stages: [String] = []

    func record(_ stage: String) {
        stages.append(stage)
    }

    func recordedStages() -> [String] {
        stages
    }
}

private struct StageRecordingPendingCaptureSigner: TAPPendingCaptureSigning {
    let recorder: PendingCaptureStageRecorder

    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        await recorder.record("sign")
        return try await store.storeSignedPhoto(
            Data("signed-\(record.captureID)".utf8),
            captureID: record.captureID
        )
    }
}

private struct StageRecordingPendingCaptureExporter: TAPPendingCaptureExporting {
    let recorder: PendingCaptureStageRecorder

    func export(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws {
        await recorder.record("export")
        _ = try await store.markExported(
            captureID: record.captureID,
            assetLocalIdentifier: "asset-\(record.captureID)"
        )
    }
}

private struct StageRecordingPendingCaptureReadback: TAPPendingCaptureReadingBack {
    let recorder: PendingCaptureStageRecorder

    func readBack(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws {
        await recorder.record("readback")
    }
}

private struct StageRecordingPendingCaptureCleanup: TAPPendingCaptureCleaning {
    let recorder: PendingCaptureStageRecorder

    func cleanup(store: TAPPendingCaptureStore) async throws {
        await recorder.record("cleanup")
    }
}

private actor RecordingPendingCaptureExporter: TAPPendingCaptureExporting {
    private let failingCaptureIDs: Set<String>
    private var captureIDs: [String] = []

    init(failingCaptureIDs: Set<String> = []) {
        self.failingCaptureIDs = failingCaptureIDs
    }

    func exportedCaptureIDs() -> [String] {
        captureIDs
    }

    func export(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws {
        captureIDs.append(record.captureID)
        if failingCaptureIDs.contains(record.captureID) {
            throw URLError(.notConnectedToInternet)
        }
        _ = try await store.markExported(
            captureID: record.captureID,
            assetLocalIdentifier: "asset-\(record.captureID)"
        )
    }
}

private actor RecordingPhotoLibraryExportActions {
    private var existingLookupIDs: [String] = []
    private var savedIDs: [String] = []

    nonisolated func actions(existingAssetID: String? = nil) -> PhotoLibraryPendingCaptureExportActions {
        PhotoLibraryPendingCaptureExportActions(
            existingAssetIdentifier: { captureID in
                await self.recordExistingLookup(captureID)
                return existingAssetID
            },
            saveValidatedSignedPhoto: { _, record in
                await self.recordSave(record.captureID)
                return "saved-\(record.captureID)"
            }
        )
    }

    func existingLookupCaptureIDs() -> [String] {
        existingLookupIDs
    }

    func savedCaptureIDs() -> [String] {
        savedIDs
    }

    private func recordExistingLookup(_ captureID: String) {
        existingLookupIDs.append(captureID)
    }

    private func recordSave(_ captureID: String) {
        savedIDs.append(captureID)
    }
}

private enum RecordingVideoReadbackResult: Sendable {
    case success
    case transportFailure
    case decodingIntegrityFailure
}

private enum RecordingVideoSaveResult: Sendable {
    case success
    case transportFailureBeforeCommit
    case transportFailureAfterCommit
}

private actor RecordingVideoExportActions {
    private let candidates: [String]
    private let readbackResult: RecordingVideoReadbackResult
    private let saveResult: RecordingVideoSaveResult
    private var candidatePackages: [UUID] = []
    private var savedCaptures: [String] = []
    private var validatedAssets: [String] = []

    init(
        candidates: [String],
        readbackResult: RecordingVideoReadbackResult,
        saveResult: RecordingVideoSaveResult = .success
    ) {
        self.candidates = candidates
        self.readbackResult = readbackResult
        self.saveResult = saveResult
    }

    nonisolated func actions() -> PhotoLibraryPendingVideoExportActions {
        PhotoLibraryPendingVideoExportActions(
            validateLocalFile: { fileURL, _ in
                ValidatedTAPVideoFile(
                    fileURL: fileURL,
                    manifest: try TAPVideoManifestBox.decodedManifest(fromFileAt: fileURL)
                )
            },
            saveVideoFile: { _, record, _, commitWillBegin in
                try await self.recordSave(
                    record.captureID,
                    commitWillBegin: commitWillBegin
                )
            }
        )
    }

    nonisolated func readbackActions() -> PhotoLibraryPendingVideoReadbackActions {
        PhotoLibraryPendingVideoReadbackActions(
            candidateIdentifiers: { packageID in
                await self.recordCandidateLookup(packageID)
            },
            validateReadback: { assetID, _ in
                try await self.recordValidation(assetID)
            }
        )
    }

    func candidatePackageIDs() -> [UUID] {
        candidatePackages
    }

    func savedCaptureIDs() -> [String] {
        savedCaptures
    }

    func validatedAssetIDs() -> [String] {
        validatedAssets
    }

    private func recordCandidateLookup(_ packageID: UUID) -> [String] {
        candidatePackages.append(packageID)
        return candidates
    }

    private func recordSave(
        _ captureID: String,
        commitWillBegin: PhotoLibraryPendingVideoCommitBoundary
    ) async throws -> String {
        savedCaptures.append(captureID)
        switch saveResult {
        case .success:
            try await commitWillBegin()
            return "created-\(captureID)"
        case .transportFailureBeforeCommit:
            throw URLError(.networkConnectionLost)
        case .transportFailureAfterCommit:
            try await commitWillBegin()
            throw URLError(.networkConnectionLost)
        }
    }

    private func recordValidation(_ assetID: String) throws {
        validatedAssets.append(assetID)
        switch readbackResult {
        case .success:
            return
        case .transportFailure:
            throw URLError(.networkConnectionLost)
        case .decodingIntegrityFailure:
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "signed video manifest JSON is corrupt"
            ))
        }
    }
}

private struct SensitiveNetworkFailingPendingCaptureExporter: TAPPendingCaptureExporting {
    func export(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws {
        throw NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [
                NSLocalizedDescriptionKey: "offline captureID=pending/private-capture-id keyID=prepared-key-id path=/private/var/mobile/Containers/Data/Application/secret/unsigned.heic url=https://secret.tapnap.net/export?token=secret-token",
                NSURLErrorFailingURLErrorKey: URL(string: "https://secret.tapnap.net/export?token=secret-token")!
            ]
        )
    }
}
