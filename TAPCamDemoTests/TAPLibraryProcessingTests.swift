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
        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: signedRecord.captureID)
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
        #expect(unchangedRecord.signedHEICFilename != nil)
        #expect(await signer.signedCaptureIDs().isEmpty)
        #expect(await exporter.exportedCaptureIDs().isEmpty)
    }

    @Test func pendingCaptureProcessorDoesNotReconcileLegacyFailureReasonsWhenProtectedDataUnavailable() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let legacyReasonTokens = [
            "captureID=pending/private-capture-id",
            "url=https://secret.tapnap.net/export?token=secret-token",
            "path=/private/secret/signed.heic",
            "keyID=prepared-key-id"
        ]
        let legacyReason = legacyReasonTokens.joined(separator: " ")
        let legacyRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "locked-legacy-capture",
            capturedAt: Date(timeIntervalSince1970: 0),
            status: .failedRetryable,
            failureReason: legacyReason
        )
        try TAPCamDemoTestFixtures.writePendingRecord(legacyRecord, rootURL: rootURL)
        let signer = RecordingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { false }
        )

        let bundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(
            rootURL: rootURL,
            captureID: legacyRecord.captureID
        )
        #expect(bundleJSON.contains(legacyReason))
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
        _ = try await store.storeSignedHEIC(Data("already-signed".utf8), captureID: signedRecord.captureID)
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
        let signedRecord = try await store.storeSignedHEIC(
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
        _ = try await store.storeSignedHEIC(
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

    @Test func pendingCaptureProcessorSkipsRetryBacklogWhenAutomaticRetryIsDisabled() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let retryRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("retry".utf8),
            captureID: "retry-capture",
            capturedAt: Date(timeIntervalSince1970: 0)
        ))
        _ = try await store.updateStatus(
            captureID: retryRecord.captureID,
            status: .failedRetryable,
            failureReason: .retryableProcessingFailure,
            incrementsRetryCount: true
        )
        let pendingRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("pending".utf8),
            captureID: "pending-capture",
            capturedAt: Date(timeIntervalSince1970: 1)
        ))
        let signer = RecordingPendingCaptureSigner()
        let exporter = RecordingPendingCaptureExporter()
        let processor = TAPPendingCaptureProcessor()

        await processor.processPendingCaptures(
            store: store,
            signer: signer,
            exporter: exporter,
            protectedDataIsAvailable: { true },
            allowsRetryBacklogProcessing: false
        )

        #expect(await signer.signedCaptureIDs() == [pendingRecord.captureID])
        #expect(await exporter.exportedCaptureIDs() == [pendingRecord.captureID])
        #expect(try await store.readRecord(captureID: pendingRecord.captureID).status == .exported)
        #expect(try await store.readRecord(captureID: retryRecord.captureID).status == .failedRetryable)
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
        return try await store.storeSignedHEIC(
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
            saveValidatedSignedHEIC: { _, record in
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
