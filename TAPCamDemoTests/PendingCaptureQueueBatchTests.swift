import Foundation
import Testing
@testable import TAPCamDemo

struct PendingCaptureQueueBatchTests {
    @Test(arguments: [1, 12])
    func workerScansOncePerBatchAndVisitsFailuresOnce(captureCount: Int) async throws {
        let root = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = QueueScanCountingFileManager()
        let store = TAPPendingCaptureStore(rootURL: root, fileManager: fileManager)
        let ids = (0..<captureCount).map { "capture-\($0)" }
        for (index, id) in ids.enumerated() {
            _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned".utf8), captureID: id,
                capturedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        let stages = QueueBatchStages(onExport: { record, _ in
            if record.captureID == ids[0] { throw URLError(.notConnectedToInternet) }
        })
        let processor = TAPPendingCaptureProcessor()
        await processor.processPendingCaptures(
            store: store, signer: stages, exporter: stages,
            readback: stages, cleanup: stages, protectedDataIsAvailable: { true }
        )

        #expect(await stages.signedIDs == ids)
        #expect(await stages.exportedIDs == ids)
        #expect(try await store.readRecord(captureID: ids[0]).retryCount == 1)
        // One reconciliation scan and one candidate scan, independent of N.
        #expect(fileManager.recordScans == 2)

        await processor.processPendingCaptures(
            store: store, signer: stages, exporter: stages,
            readback: stages, cleanup: stages, protectedDataIsAvailable: { true }
        )
        #expect(await stages.exportedIDs == ids + [ids[0]])
        #expect(try await store.readRecord(captureID: ids[0]).retryCount == 2)
        #expect(fileManager.recordScans == 4)
    }

    @Test(arguments: [false, true])
    func newIngestPreemptsRetryBacklogDuringWorker(video: Bool) async throws {
        let root = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = QueueScanCountingFileManager()
        let store = TAPPendingCaptureStore(rootURL: root, fileManager: fileManager)
        for id in ["first", "retry"] {
            _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned".utf8), captureID: id
            ))
        }
        _ = try await store.storeSignedPhoto(Data("signed".utf8), captureID: "first")
        _ = try await store.updateStatus(captureID: "retry", status: .waitingNetwork)
        let stages = QueueBatchStages(onExport: { record, store in
            guard record.captureID == "first" else { return }
            if video {
                _ = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
                    store: store, captureID: "new"
                )
            } else {
                _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                    photoData: Data("new".utf8), captureID: "new"
                ))
            }
        })
        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store, signer: stages, exporter: stages,
            readback: stages, cleanup: stages, protectedDataIsAvailable: { true }
        )

        #expect(await stages.exportedIDs == ["first", "new", "retry"])
        #expect(await stages.signedIDs == ["new", "retry"])
        #expect(try await store.readRecord(captureID: "new").status == .exported)
        #expect(fileManager.recordScans == 3)
    }

    @Test(arguments: ["deleted", "exported", "terminal", "signed"])
    func queuedCandidateUsesCurrentPersistedState(change: String) async throws {
        let root = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TAPPendingCaptureStore(rootURL: root)
        for (index, id) in ["first", "changed"].enumerated() {
            _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned".utf8), captureID: id,
                capturedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        let stages = QueueBatchStages(onExport: { record, store in
            guard record.captureID == "first" else { return }
            switch change {
            case "deleted": try await store.removeRecord(captureID: "changed")
            case "exported":
                _ = try await store.markExported(captureID: "changed", assetLocalIdentifier: "already-exported")
            case "terminal":
                _ = try await store.markTerminalFailure(captureID: "changed", code: .invalidVideoArtifact)
            default:
                _ = try await store.storeSignedPhoto(Data("signed".utf8), captureID: "changed")
            }
        })
        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store, signer: stages, exporter: stages,
            readback: stages, cleanup: stages, protectedDataIsAvailable: { true }
        )

        #expect(await stages.signedIDs == ["first"])
        #expect(await stages.exportedIDs == (change == "signed" ? ["first", "changed"] : ["first"]))
        if change == "deleted" {
            #expect((try? await store.readRecord(captureID: "changed")) == nil)
        } else if change == "terminal" {
            #expect(try await store.readRecord(captureID: "changed").status == .failedTerminal)
        } else if change == "exported" {
            #expect(try await store.readRecord(captureID: "changed").assetLocalIdentifier == "already-exported")
        }
    }

    @Test(arguments: [false, true])
    func cancellationStopsBatchWithoutRetryOrLaterStages(throwsCancellation: Bool) async throws {
        let root = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TAPPendingCaptureStore(rootURL: root)
        for (index, id) in ["first", "next"].enumerated() {
            _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned".utf8), captureID: id,
                capturedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        let original = try await store.allRecords()
        let stages = QueueBatchStages(onSign: { _ in
            if throwsCancellation { throw CancellationError() }
            withUnsafeCurrentTask { $0?.cancel() }
        })
        await TAPPendingCaptureProcessor().processPendingCaptures(
            store: store, signer: stages, exporter: stages,
            readback: stages, cleanup: stages, protectedDataIsAvailable: { true }
        )

        #expect(await stages.signedIDs == ["first"])
        #expect(await stages.exportedIDs.isEmpty)
        #expect(await stages.readbackIDs.isEmpty)
        #expect(await stages.cleanupCount == 1)
        #expect(try await store.allRecords() == original)
    }

    @Test @MainActor func librarySnapshotPartitionsOneQueueRead() async throws {
        let root = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = QueueScanCountingFileManager()
        let store = TAPPendingCaptureStore(rootURL: root, fileManager: fileManager)
        for (index, id) in ["pending", "exported"].enumerated() {
            _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned".utf8), captureID: id,
                capturedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        _ = try await store.markExported(captureID: "exported", assetLocalIdentifier: "photos-id")
        var loadCount = 0
        var photoIDs = Set<String>()
        let provider = DepthAlbumItemProvider(
            recordsLoader: {
                loadCount += 1
                return try await store.allRecords()
            },
            photoCatalogLoader: { ids in
                photoIDs = ids
                return .empty
            }
        )
        let snapshot = try await provider.loadSnapshot()
        #expect(loadCount == 1)
        #expect(fileManager.recordScans == 1)
        #expect(photoIDs == ["photos-id"])
        #expect(snapshot.items.map(\.id) == ["capture:exported", "capture:pending"])
    }
}

/// Runs the real worker/store queue decisions with deterministic stage effects.
private actor QueueBatchStages: TAPPendingCaptureSigning, TAPPendingCaptureExporting,
    TAPPendingCaptureReadingBack, TAPPendingCaptureCleaning {
    private let onSign: @Sendable (TAPPendingCaptureRecord) async throws -> Void
    private let onExport: @Sendable (TAPPendingCaptureRecord, TAPPendingCaptureStore) async throws -> Void
    private(set) var signedIDs: [String] = []
    private(set) var exportedIDs: [String] = []
    private(set) var readbackIDs: [String] = []
    private(set) var cleanupCount = 0

    init(
        onSign: @escaping @Sendable (TAPPendingCaptureRecord) async throws -> Void = { _ in },
        onExport: @escaping @Sendable (TAPPendingCaptureRecord, TAPPendingCaptureStore) async throws -> Void = { _, _ in }
    ) {
        self.onSign = onSign
        self.onExport = onExport
    }

    func sign(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws -> TAPPendingCaptureRecord {
        signedIDs.append(record.captureID)
        try await onSign(record)
        return record
    }

    func export(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws {
        exportedIDs.append(record.captureID)
        try await onExport(record, store)
        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: "asset-\(record.captureID)")
    }

    func readBack(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws {
        readbackIDs.append(record.captureID)
    }

    func cleanup(store: TAPPendingCaptureStore) async throws { cleanupCount += 1 }
}

/// Counts actual record-directory enumeration, excluding the hidden workspace
/// recovery scan. Individual readRecord calls do not enumerate this directory.
private final class QueueScanCountingFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var scans = 0
    var recordScans: Int { lock.withLock { scans } }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if mask.contains(.skipsHiddenFiles) { lock.withLock { scans += 1 } }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
