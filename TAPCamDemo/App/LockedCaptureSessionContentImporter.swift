//
//  LockedCaptureSessionContentImporter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Combine
import CoreVideo
import Foundation
import ImageIO
import LockedCameraCapture
import OSLog

nonisolated struct LockedCaptureSessionContentInspection: Equatable, Sendable {
    var sessionContentURL: URL
    var captures: [TAPCamLockedRawCaptureMetadata]
}

nonisolated struct LockedCaptureSessionContentCaptureProbe: Equatable, Sendable {
    var metadata: TAPCamLockedRawCaptureMetadata
    var metadataURL: URL
    var photoURL: URL
    var layout: String
}

nonisolated struct LockedCaptureSessionContentImportSummary: Equatable, Sendable {
    var scannedSessionCount = 0
    var foundCaptureCount = 0
    var importedCount = 0
    var skippedCount = 0
    var failedCount = 0
    var invalidatedSessionCount = 0

    var didImportCaptures: Bool {
        importedCount > 0
    }
}

nonisolated struct LockedCaptureSessionContentImporter: Sendable {
    func inspectAvailableSessionContent() -> [LockedCaptureSessionContentInspection] {
        LockedCameraCaptureManager.shared.sessionContentURLs.map { sessionURL in
            let readResults = Self.inspectCaptures(in: sessionURL)
            for result in readResults {
                let diskByteCount = Self.fileSize(at: result.photoURL)
                LockedCameraDiagnostics.logger.info(
                    "locked_camera_session_capture_found layout=\(result.layout, privacy: .public) captureID=\(result.metadata.captureID, privacy: .public) photo=\(result.metadata.photoFileName, privacy: .public) metadataBytes=\(result.metadata.byteCount, privacy: .public) diskBytes=\(diskByteCount ?? -1, privacy: .public) depth=\(result.metadata.depthDataPresent ?? false, privacy: .public) artifactKind=\(result.metadata.artifactKind ?? "legacy", privacy: .public)"
                )
            }
            let captures = readResults.map(\.metadata)
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_content_found url=\(sessionURL.path, privacy: .private(mask: .hash)) captureCount=\(captures.count, privacy: .public)"
            )
            return LockedCaptureSessionContentInspection(
                sessionContentURL: sessionURL,
                captures: captures
            )
        }
    }

    func logAvailableSessionContent() {
        _ = inspectAvailableSessionContent()
    }

    @discardableResult
    func importAvailableSessionContent(reason: String = "unspecified") async -> LockedCaptureSessionContentImportSummary {
        let manager = LockedCameraCaptureManager.shared
        let sessionURLs = manager.sessionContentURLs
        var summary = LockedCaptureSessionContentImportSummary()
        LockedCameraDiagnostics.logger.info(
            "locked_camera_session_import_begin reason=\(reason, privacy: .public) sessionCount=\(sessionURLs.count, privacy: .public) sessionURLCount=\(sessionURLs.count, privacy: .public)"
        )
        for (index, sessionURL) in sessionURLs.enumerated() {
            let readResults = Self.inspectCaptures(in: sessionURL)
            summary.scannedSessionCount += 1
            summary.foundCaptureCount += readResults.count
            let importableCount = readResults.filter(Self.isImportableLockedCapture).count
            let stagingCount = readResults.filter(Self.isPackageableLockedCaptureStaging).count
            let skippedProbeCount = readResults.count - importableCount - stagingCount
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_scan_result reason=\(reason, privacy: .public) sessionIndex=\(index + 1, privacy: .public) sessionURLCount=\(sessionURLs.count, privacy: .public) captureProbeCount=\(readResults.count, privacy: .public) importableCount=\(importableCount, privacy: .public) stagingCount=\(stagingCount, privacy: .public) skippedProbeCount=\(skippedProbeCount, privacy: .public) url=\(sessionURL.path, privacy: .private(mask: .hash))"
            )
            var importedCount = 0
            var skippedCount = 0
            var failedCount = 0

            for result in readResults {
                let importProbe: LockedCaptureSessionContentCaptureProbe
                if Self.isImportableLockedCapture(result) {
                    importProbe = result
                } else if Self.isPackageableLockedCaptureStaging(result) {
                    do {
                        importProbe = try LockedCaptureTAPArtifactPackager.packageStagingCapture(result)
                        LockedCameraDiagnostics.logger.info(
                            "locked_camera_session_staging_packaged captureID=\(importProbe.metadata.captureID, privacy: .public) bytes=\(importProbe.metadata.byteCount, privacy: .public)"
                        )
                    } catch {
                        failedCount += 1
                        summary.failedCount += 1
                        LockedCameraDiagnostics.logger.error(
                            "locked_camera_session_staging_package_failed captureID=\(result.metadata.captureID, privacy: .public) error=\(Self.describe(error), privacy: .public)"
                        )
                        continue
                    }
                } else {
                    skippedCount += 1
                    summary.skippedCount += 1
                    LockedCameraDiagnostics.logger.info(
                        "locked_camera_session_import_skipped captureID=\(result.metadata.captureID, privacy: .public) layout=\(result.layout, privacy: .public) photo=\(result.metadata.photoFileName, privacy: .public) depth=\(result.metadata.depthDataPresent ?? false, privacy: .public) artifactKind=\(result.metadata.artifactKind ?? "legacy", privacy: .public)"
                    )
                    continue
                }

                do {
                    let record = try await TAPPendingCaptureStore.shared.ingestLockedCapture(
                        TAPPendingLockedCaptureImport(
                            captureID: importProbe.metadata.captureID,
                            capturedAt: importProbe.metadata.capturedAt,
                            unsignedPhotoURL: importProbe.photoURL,
                            metadata: importProbe.metadata
                        )
                    )
                    Self.discardTemporaryPackagedArtifact(importProbe, originalProbe: result)
                    importedCount += 1
                    summary.importedCount += 1
                    LockedCameraDiagnostics.logger.info(
                        "locked_camera_session_import_succeeded captureID=\(record.captureID, privacy: .public) status=\(record.status.rawValue, privacy: .public)"
                    )
                } catch {
                    Self.discardTemporaryPackagedArtifact(importProbe, originalProbe: result)
                    failedCount += 1
                    summary.failedCount += 1
                    LockedCameraDiagnostics.logger.error(
                        "locked_camera_session_import_failed captureID=\(result.metadata.captureID, privacy: .public) error=\(Self.describe(error), privacy: .public)"
                    )
                }
            }

            guard importedCount > 0 else {
                continue
            }

            guard skippedCount == 0, failedCount == 0 else {
                LockedCameraDiagnostics.logger.info(
                    "locked_camera_session_content_retained url=\(sessionURL.path, privacy: .private(mask: .hash)) imported=\(importedCount, privacy: .public) skipped=\(skippedCount, privacy: .public) failed=\(failedCount, privacy: .public)"
                )
                continue
            }

            do {
                try await manager.invalidateSessionContent(at: sessionURL)
                summary.invalidatedSessionCount += 1
                LockedCameraDiagnostics.logger.info(
                    "locked_camera_session_content_invalidated url=\(sessionURL.path, privacy: .private(mask: .hash)) imported=\(importedCount, privacy: .public)"
                )
            } catch {
                LockedCameraDiagnostics.logger.error(
                    "locked_camera_session_content_invalidate_failed url=\(sessionURL.path, privacy: .private(mask: .hash)) error=\(Self.describe(error), privacy: .public)"
                )
            }
        }
        LockedCameraDiagnostics.logger.info(
            "locked_camera_session_import_finish reason=\(reason, privacy: .public) sessions=\(summary.scannedSessionCount, privacy: .public) found=\(summary.foundCaptureCount, privacy: .public) imported=\(summary.importedCount, privacy: .public) skipped=\(summary.skippedCount, privacy: .public) failed=\(summary.failedCount, privacy: .public) invalidated=\(summary.invalidatedSessionCount, privacy: .public)"
        )
        if summary.didImportCaptures {
            await Self.logPendingStoreSnapshot(reason: reason)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .tapCamLockedCaptureImportDidAddPendingCaptures,
                    object: nil
                )
            }
        }
        return summary
    }

    static func inspectCaptures(in sessionURL: URL) -> [LockedCaptureSessionContentCaptureProbe] {
        let flatHEICCaptures = flatHEICFiles(in: sessionURL)
        let directCaptureDirectories = captureDirectories(
            in: sessionURL,
            excludingNames: [TAPCamLockedSessionContentPathPolicy.legacyCapturesDirectoryName],
            layout: "direct"
        )
        let capturesURL = TAPCamLockedSessionContentPathPolicy.legacyCapturesDirectory(
            sessionContentURL: sessionURL
        )
        let legacyCaptureDirectories = captureDirectories(in: capturesURL, layout: "legacy-captures")

        let directoryCaptures: [LockedCaptureSessionContentCaptureProbe] = (directCaptureDirectories + legacyCaptureDirectories)
            .compactMap { candidate in
                let directory = candidate.url
                let metadataURL = TAPCamLockedSessionContentPathPolicy.metadataURL(in: directory)
                guard let data = try? Data(contentsOf: metadataURL) else {
                    return nil
                }
                guard let metadata = try? JSONDecoder.tapLockedCamera.decode(
                    TAPCamLockedRawCaptureMetadata.self,
                    from: data
                ) else {
                    return nil
                }
                return LockedCaptureSessionContentCaptureProbe(
                    metadata: metadata,
                    metadataURL: metadataURL,
                    photoURL: directory.appendingPathComponent(metadata.photoFileName),
                    layout: candidate.layout
                )
            }

        return (flatHEICCaptures + directoryCaptures)
            .sorted { $0.metadata.capturedAt < $1.metadata.capturedAt }
    }

    private static func captureDirectories(
        in parentURL: URL,
        excludingNames: Set<String> = [],
        layout: String
    ) -> [(url: URL, layout: String)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard !excludingNames.contains(url.lastPathComponent) else {
                return nil
            }
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else {
                return nil
            }
            return (url, layout)
        }
    }

    private static func flatHEICFiles(in sessionURL: URL) -> [LockedCaptureSessionContentCaptureProbe] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sessionURL,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare("heic") == .orderedSame,
                  url.lastPathComponent.hasPrefix(TAPCamLockedSessionContentPathPolicy.flatHEICFilePrefix) else {
                return nil
            }
            let resourceValues = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]
            )
            guard resourceValues?.isRegularFile == true else {
                return nil
            }

            let capturedAt = resourceValues?.creationDate
                ?? resourceValues?.contentModificationDate
                ?? Date(timeIntervalSince1970: 0)
            let captureID = flatHEICCaptureID(from: url) ?? UUID().uuidString
            let metadata = TAPCamLockedRawCaptureMetadata(
                captureID: captureID,
                capturedAt: capturedAt,
                artifactKind: TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind,
                lens: flatHEICFallbackLens(),
                photoFileName: url.lastPathComponent,
                byteCount: resourceValues?.fileSize ?? fileSize(at: url) ?? 0,
                depthDataPresent: true,
                source: "locked-camera-capture-e2a-flat-heic"
            )
            return LockedCaptureSessionContentCaptureProbe(
                metadata: metadata,
                metadataURL: url,
                photoURL: url,
                layout: "flat-heic"
            )
        }
    }

    private static func flatHEICCaptureID(from fileURL: URL) -> String? {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let prefix = TAPCamLockedSessionContentPathPolicy.flatHEICFilePrefix
        guard filename.hasPrefix(prefix) else {
            return nil
        }
        let captureID = String(filename.dropFirst(prefix.count))
        return captureID.isEmpty ? nil : captureID
    }

    private static func flatHEICFallbackLens() -> TAPCamLockedCameraLensRecord {
        TAPCamLockedCameraLensRecord(
            id: "locked-flat-heic-unknown",
            displayName: "Locked Camera",
            numericLabel: "1",
            unitLabel: "x",
            equivalentFocalLength35mmMillimeters: 24,
            captureDeviceUniqueID: "locked-flat-heic-unknown",
            captureDeviceTypeRawValue: AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue,
            captureDevicePosition: "back",
            zoomFactor: 1
        )
    }

    private static func fileSize(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private static func isImportableLockedCapture(_ result: LockedCaptureSessionContentCaptureProbe) -> Bool {
        result.layout == "direct"
            && result.metadata.photoFileName == TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName
            && result.metadata.depthDataPresent == true
            && result.metadata.artifactKind == TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind
    }

    private static func isPackageableLockedCaptureStaging(_ result: LockedCaptureSessionContentCaptureProbe) -> Bool {
        (result.layout == "direct" || result.layout == "flat-heic")
            && (result.layout == "flat-heic" || result.metadata.photoFileName == TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName)
            && result.metadata.depthDataPresent == true
            && result.metadata.artifactKind == TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }

    private static func logPendingStoreSnapshot(reason: String) async {
        do {
            let records = try await TAPPendingCaptureStore.shared.visiblePendingRecords()
            let latest = records
                .prefix(6)
                .map { "\($0.captureID):\($0.status.rawValue)" }
                .joined(separator: "|")
            LockedCameraDiagnostics.logger.info(
                "locked_camera_pending_snapshot reason=\(reason, privacy: .public) visiblePendingCount=\(records.count, privacy: .public) latest=\(latest, privacy: .public)"
            )
        } catch {
            LockedCameraDiagnostics.logger.error(
                "locked_camera_pending_snapshot_failed reason=\(reason, privacy: .public) error=\(Self.describe(error), privacy: .public)"
            )
        }
    }

    private static func discardTemporaryPackagedArtifact(
        _ probe: LockedCaptureSessionContentCaptureProbe,
        originalProbe: LockedCaptureSessionContentCaptureProbe
    ) {
        guard probe.photoURL != originalProbe.photoURL else {
            return
        }
        try? FileManager.default.removeItem(at: probe.photoURL.deletingLastPathComponent())
    }
}

actor LockedCaptureSessionContentImportCoordinator {
    static let shared = LockedCaptureSessionContentImportCoordinator()

    private static let initialSessionContentUpdateWaitNanoseconds: UInt64 = 1_200_000_000
    private static let lateSessionContentPollIntervalNanoseconds: UInt64 = 500_000_000
    private static let lateSessionContentPollAttempts = 8
    private static let lateSessionContentImportReasons: Set<String> = [
        "locked_camera_handoff",
        "locked_camera_handoff_route"
    ]

    private var activeImportTask: Task<LockedCaptureSessionContentImportSummary, Never>?
    private var activeImportReason: String?
    private var observedSessionContentUpdateCount = 0
    private var sessionContentUpdateWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    @discardableResult
    func importAvailableSessionContent(reason: String) async -> LockedCaptureSessionContentImportSummary {
        await importAvailableSessionContent(
            reason: reason,
            waitsForInitialSessionContentUpdate: false
        )
    }

    @discardableResult
    func importAvailableSessionContentAfterSessionContentSettles(reason: String) async -> LockedCaptureSessionContentImportSummary {
        await importAvailableSessionContent(
            reason: reason,
            waitsForInitialSessionContentUpdate: true
        )
    }

    func markSessionContentUpdateObserved() {
        observedSessionContentUpdateCount += 1
        LockedCameraDiagnostics.logger.info(
            "locked_camera_session_update_observed count=\(self.observedSessionContentUpdateCount, privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
        )
        let waiters = sessionContentUpdateWaiters.values
        sessionContentUpdateWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func importAvailableSessionContent(
        reason: String,
        waitsForInitialSessionContentUpdate: Bool
    ) async -> LockedCaptureSessionContentImportSummary {
        if let activeImportTask {
            let coalescedActiveImportReason = activeImportReason
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_import_coalesced reason=\(reason, privacy: .public)"
            )
            let summary = await activeImportTask.value
            let activeReasonAlreadyRunsLatePoll = coalescedActiveImportReason.map {
                Self.lateSessionContentImportReasons.contains($0)
            } ?? false
            return await importLateSessionContentIfNeeded(
                after: summary,
                reason: reason,
                allowsLateSessionContentPoll: waitsForInitialSessionContentUpdate && !activeReasonAlreadyRunsLatePoll
            )
        }

        let task = Task<LockedCaptureSessionContentImportSummary, Never> {
            if waitsForInitialSessionContentUpdate {
                await self.waitForInitialSessionContentUpdateIfNeeded(
                    reason: reason,
                    timeoutNanoseconds: Self.initialSessionContentUpdateWaitNanoseconds
                )
            }
            let summary = await LockedCaptureSessionContentImporter()
                .importAvailableSessionContent(reason: reason)
            return await self.importLateSessionContentIfNeeded(
                after: summary,
                reason: reason,
                allowsLateSessionContentPoll: waitsForInitialSessionContentUpdate
            )
        }
        activeImportTask = task
        activeImportReason = reason
        let summary = await task.value
        activeImportTask = nil
        activeImportReason = nil
        return summary
    }

    private func importLateSessionContentIfNeeded(
        after summary: LockedCaptureSessionContentImportSummary,
        reason: String,
        allowsLateSessionContentPoll: Bool
    ) async -> LockedCaptureSessionContentImportSummary {
        guard allowsLateSessionContentPoll,
              summary.scannedSessionCount == 0,
              summary.foundCaptureCount == 0,
              Self.lateSessionContentImportReasons.contains(reason) else {
            return summary
        }

        for attempt in 1...Self.lateSessionContentPollAttempts {
            try? await Task.sleep(nanoseconds: Self.lateSessionContentPollIntervalNanoseconds)
            let sessionCount = LockedCameraCaptureManager.shared.sessionContentURLs.count
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_import_late_poll reason=\(reason, privacy: .public) attempt=\(attempt, privacy: .public) sessionCount=\(sessionCount, privacy: .public) observedUpdateCount=\(self.observedSessionContentUpdateCount, privacy: .public)"
            )
            guard sessionCount > 0 else {
                continue
            }

            return await LockedCaptureSessionContentImporter()
                .importAvailableSessionContent(reason: "\(reason)_late_session_content")
        }

        LockedCameraDiagnostics.logger.info(
            "locked_camera_session_import_late_poll_timeout reason=\(reason, privacy: .public) attempts=\(Self.lateSessionContentPollAttempts, privacy: .public)"
        )
        return summary
    }

    private func waitForInitialSessionContentUpdateIfNeeded(
        reason: String,
        timeoutNanoseconds: UInt64
    ) async {
        guard LockedCameraCaptureManager.shared.sessionContentURLs.isEmpty,
              observedSessionContentUpdateCount == 0 else {
            return
        }

        LockedCameraDiagnostics.logger.info(
            "locked_camera_session_import_wait_for_initial_update reason=\(reason, privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public) observedUpdateCount=\(self.observedSessionContentUpdateCount, privacy: .public)"
        )
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.waitForNextSessionContentUpdate()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func waitForNextSessionContentUpdate() async {
        guard LockedCameraCaptureManager.shared.sessionContentURLs.isEmpty else {
            return
        }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sessionContentUpdateWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelSessionContentUpdateWaiter(id: waiterID)
            }
        }
    }

    private func cancelSessionContentUpdateWaiter(id: UUID) {
        guard let waiter = sessionContentUpdateWaiters.removeValue(forKey: id) else {
            return
        }
        waiter.resume()
    }
}

@MainActor
final class LockedCaptureSessionContentImportRuntime: ObservableObject {
    private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else {
            return
        }

        LockedCameraDiagnostics.logger.info(
            "locked_camera_session_import_runtime_start managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
        )
        updatesTask = Task {
            await LockedCaptureSessionContentImportScheduler().run()
        }
    }

    func stop() {
        guard updatesTask != nil else {
            return
        }

        LockedCameraDiagnostics.logger.info("locked_camera_session_import_runtime_stop")
        updatesTask?.cancel()
        updatesTask = nil
    }

    deinit {
        updatesTask?.cancel()
    }
}

nonisolated struct LockedCaptureSessionContentImportScheduler: Sendable {
    func run() async {
        let manager = LockedCameraCaptureManager.shared

        for await update in manager.sessionContentUpdates {
            Self.log(update)
            await LockedCaptureSessionContentImportCoordinator.shared
                .markSessionContentUpdateObserved()
            await LockedCaptureSessionContentImportCoordinator.shared
                .importAvailableSessionContent(reason: "session_content_update")
        }
    }

    private static func log(_ update: LockedCameraCaptureManager.SessionContentUpdate) {
        switch update {
        case .initial(let urls):
            let captureProbeCount = urls.reduce(0) { count, url in
                count + LockedCaptureSessionContentImporter.inspectCaptures(in: url).count
            }
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_content_update kind=initial count=\(urls.count, privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public) captureProbeCount=\(captureProbeCount, privacy: .public)"
            )
        case .added(let url):
            let captureProbeCount = LockedCaptureSessionContentImporter.inspectCaptures(in: url).count
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_content_update kind=added managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public) captureProbeCount=\(captureProbeCount, privacy: .public) url=\(url.path, privacy: .private(mask: .hash))"
            )
        case .removed(let url):
            LockedCameraDiagnostics.logger.info(
                "locked_camera_session_content_update kind=removed managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public) url=\(url.path, privacy: .private(mask: .hash))"
            )
        @unknown default:
            LockedCameraDiagnostics.logger.info("locked_camera_session_content_update kind=unknown")
        }
    }
}

private nonisolated enum LockedCaptureTAPArtifactPackager {
    private static let profile = CaptureOutputProfile.releasePhotoDepthHEIC

    static func packageStagingCapture(
        _ probe: LockedCaptureSessionContentCaptureProbe
    ) throws -> LockedCaptureSessionContentCaptureProbe {
        let stagingData = try Data(contentsOf: probe.photoURL)
        try TAPDepthPhotoFileReader.validateContainer(stagingData, expected: .heic)
        guard let depthData = try TAPDepthPhotoFileReader.depthData(from: stagingData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let photoInfo = try PhotoInfo(photoData: stagingData)
        let manifest = try makeManifest(
            metadata: probe.metadata,
            photoInfo: photoInfo,
            depthData: depthData
        )
        try CaptureOutputManifestPolicy(profile: profile).validate(manifest.payload.capture)

        let finalData = try TAPCaptureProvenanceWriter()
            .writeManifest(manifest, into: stagingData)
            .data
        let finalManifest = try TAPDepthPhotoFileReader.decodedManifest(from: finalData)
        guard finalManifest.payload.id == probe.metadata.captureID else {
            throw TAPDepthCaptureError.pendingCaptureManifestIDMismatch(
                expected: probe.metadata.captureID,
                actual: finalManifest.payload.id
            )
        }
        guard let finalDepthData = try TAPDepthPhotoFileReader.depthData(from: finalData) else {
            throw TAPDepthCaptureError.missingDepthData
        }
        _ = try TAPProofSlot.locate(in: finalData, fileContainer: .heic)

        var metadata = probe.metadata
        metadata.artifactKind = TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind
        metadata.photoFileName = TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName
        metadata.byteCount = finalData.count
        metadata.depthDataPresent = true
        metadata.depthDataType = finalDepthData.depthDataType
        metadata.isDepthDataFiltered = finalDepthData.isDepthDataFiltered
        metadata.resolvedPhotoWidth = Int(photoInfo.width)
        metadata.resolvedPhotoHeight = Int(photoInfo.height)

        let outputURL = try writeTemporaryArtifact(finalData)

        return LockedCaptureSessionContentCaptureProbe(
            metadata: metadata,
            metadataURL: probe.metadataURL,
            photoURL: outputURL,
            layout: probe.layout
        )
    }

    private static func makeManifest(
        metadata: TAPCamLockedRawCaptureMetadata,
        photoInfo: PhotoInfo,
        depthData: AVDepthData
    ) throws -> TAPDepthManifest {
        let captureID = metadata.captureID
        let capturedAt = TAPDateFormatting.iso8601.string(from: metadata.capturedAt)
        let deviceName = metadata.lensDisplayName
        let deviceType = metadata.captureDeviceTypeRawValue
        let deviceID = metadata.captureDeviceUniqueID
        let devicePosition = metadata.captureDevicePosition ?? "back"
        let zoomFactor = metadata.zoomFactor
        let sessionMode = "lockedCameraCapture"
        let pairingMode = "singleCamPhotoDepth"
        let alignmentStatus = "appleAuxiliaryDepthNative"
        let depthSource = TAPDepthSourceClassifier.source(
            forDeviceType: deviceType,
            localizedName: deviceName
        )
        let depthPixelBuffer = depthData.depthDataMap
        let depthFormat = TAPDepthManifest.CameraFormat(
            mediaSubType: TAPFourCharCode.string(
                from: CVPixelBufferGetPixelFormatType(depthPixelBuffer)
            ),
            width: Int32(CVPixelBufferGetWidth(depthPixelBuffer)),
            height: Int32(CVPixelBufferGetHeight(depthPixelBuffer)),
            maxFrameRate: nil
        )

        let payload = TAPDepthManifest.Payload(
            id: captureID,
            capturedAt: capturedAt,
            sessionMode: sessionMode,
            pairingMode: pairingMode,
            alignmentStatus: alignmentStatus,
            sourceAPIs: .avFoundationPhotoDepth,
            capture: TAPDepthManifest.Capture(
                resolvedSettingsUniqueID: 0,
                requestedCodec: AVVideoCodecType.hevc.rawValue,
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: true,
                depthDataFiltered: true,
                depthAvailability: .available,
                photoQualityPrioritization: profile.photoQualityPolicy.requested.manifestDescription
            ),
            rgbSource: TAPDepthManifest.RGBSource(
                id: metadata.lensID,
                displayName: metadata.lensDisplayName,
                deviceType: deviceType,
                deviceName: deviceName,
                position: devicePosition,
                sourceKind: "lockedCameraCaptureLens",
                requestedReferenceZoomFactor: zoomFactor
            ),
            depthSource: TAPDepthManifest.DepthSourceSelection(
                selectionMode: "lockedCameraAppContext",
                requestedDepthSourceID: nil,
                requestedDepthSourceDisplayName: nil,
                requestedDepthSourceKind: nil,
                compatibilityStatus: "compatible",
                compatibilityReason: nil,
                resolvedDeviceID: deviceID,
                resolvedDeviceType: deviceType,
                resolvedDeviceName: deviceName
            ),
            pairing: TAPDepthManifest.Pairing(
                mode: pairingMode,
                status: "compatible",
                requiresMultiCam: false,
                releaseAllowed: true,
                alignmentStatus: alignmentStatus
            ),
            zoom: TAPDepthManifest.Zoom(
                requestedZoomID: metadata.lensID,
                requestedZoomFactor: zoomFactor,
                actualVideoZoomFactor: zoomFactor,
                depthSafeRanges: [],
                isContinuous: false,
                isDiscrete: true
            ),
            crop: TAPDepthManifest.Crop(
                mode: "fullFrame",
                cropRectNormalized: .fullFrame,
                destructiveFinalCropApplied: false,
                sourceAPI: "LockedCameraCapture"
            ),
            resolvedSession: TAPDepthManifest.ResolvedSession(
                mode: sessionMode,
                resolvedCaptureDeviceID: deviceID,
                resolvedCaptureDeviceType: deviceType,
                resolvedCaptureDeviceName: deviceName,
                activePrimaryConstituentDeviceType: nil,
                activePrimaryConstituentDeviceName: nil
            ),
            selectedDepthCamera: TAPDepthManifest.SelectedDepthCamera(
                id: deviceID,
                displayName: deviceName,
                deviceType: deviceType,
                deviceName: deviceName,
                position: devicePosition
            ),
            selectedZoom: TAPDepthManifest.SelectedZoom(
                id: metadata.lensID,
                displayName: metadata.lensDisplayName,
                zoomFactor: zoomFactor
            ),
            photoLens: TAPDepthManifest.PhotoLens(
                requestedLensID: metadata.lensID,
                requestedDisplayName: metadata.lensDisplayName,
                requestedFocalLengthLabel: "\(Int(metadata.zoomFactor.rounded()))x",
                labelSource: "lockedCameraAppContext",
                requestedZoomFactor: zoomFactor,
                requestedReferenceZoomFactor: zoomFactor,
                requestedEquivalentFocalLength35mmMillimeters: nil,
                position: devicePosition,
                resolvedCaptureDeviceType: deviceType,
                resolvedCaptureDeviceName: deviceName,
                resolvedActivePrimaryConstituentDeviceType: nil,
                resolvedActivePrimaryConstituentDeviceName: nil
            ),
            depthBackend: TAPDepthManifest.DepthBackendSelection(
                selectionMode: "lockedCameraAppContext",
                requestedBackendID: nil,
                requestedBackendDisplayName: nil,
                resolvedBackendID: deviceID,
                resolvedBackendDisplayName: deviceName,
                resolvedCaptureDeviceType: deviceType,
                resolvedCaptureDeviceName: deviceName,
                actualVideoZoomFactor: zoomFactor
            ),
            camera: TAPDepthManifest.Camera(
                localizedName: deviceName,
                uniqueID: deviceID,
                modelID: "unknown",
                deviceType: deviceType,
                position: devicePosition,
                activePrimaryConstituentDeviceType: nil,
                activePrimaryConstituentDeviceName: nil,
                activeFormat: TAPDepthManifest.CameraFormat(
                    mediaSubType: CapturePhotoFileContainer.heic.uniformTypeIdentifier,
                    width: photoInfo.width,
                    height: photoInfo.height,
                    maxFrameRate: nil
                ),
                activeDepthFormat: depthFormat,
                lensPosition: nil,
                minimumFocusDistanceMillimeters: nil,
                nominalFocalLengthIn35mmFilmMillimeters: nil
            ),
            photo: TAPDepthManifest.Photo(
                width: photoInfo.width,
                height: photoInfo.height,
                orientation: photoInfo.orientation,
                metadataKeys: photoInfo.metadataKeys
            ),
            depth: makeDepth(
                depthData: depthData,
                source: depthSource
            ),
            alignment: TAPDepthManifest.Alignment(depthToImage: alignmentStatus),
            location: nil,
            software: .current
        )
        return TAPDepthManifest(payload: payload)
    }

    private static func makeDepth(
        depthData: AVDepthData,
        source: TAPDepthManifest.DepthSource
    ) -> TAPDepthManifest.Depth {
        let pixelBuffer = depthData.depthDataMap
        let auxiliaryKind = TAPDepthAuxiliaryKind(kind: depthData.depthDataType)

        return TAPDepthManifest.Depth(
            availability: .available,
            auxiliaryDataKind: auxiliaryKind.rawValue,
            depthDataType: TAPFourCharCode.string(from: depthData.depthDataType),
            metricUnit: auxiliaryKind == .depth ? "meters" : "convertDisparityToDepthMeters",
            conversionPath: auxiliaryKind == .depth ? "nativeDepthMeters" : "AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)",
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: TAPFourCharCode.string(from: CVPixelBufferGetPixelFormatType(pixelBuffer)),
            orientation: "appleAuxiliaryDepthNative",
            accuracy: depthData.depthDataAccuracy.tapDescription,
            quality: depthData.depthDataQuality.tapDescription,
            isFiltered: depthData.isDepthDataFiltered,
            source: source,
            cameraCalibration: depthData.cameraCalibrationData.map(makeCalibration)
        )
    }

    private static func makeCalibration(
        _ calibration: AVCameraCalibrationData
    ) -> TAPDepthManifest.CameraCalibration {
        let intrinsic = calibration.intrinsicMatrix
        let extrinsic = calibration.extrinsicMatrix

        return TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: calibration.intrinsicMatrixReferenceDimensions.width,
            intrinsicMatrixReferenceHeight: calibration.intrinsicMatrixReferenceDimensions.height,
            pixelSizeMillimeters: calibration.pixelSize,
            lensDistortionLookupTablePresent: calibration.lensDistortionLookupTable != nil,
            inverseLensDistortionLookupTablePresent: calibration.inverseLensDistortionLookupTable != nil,
            lensDistortionCenterX: calibration.lensDistortionCenter.x,
            lensDistortionCenterY: calibration.lensDistortionCenter.y,
            intrinsicMatrix: [
                intrinsic.columns.0.x, intrinsic.columns.0.y, intrinsic.columns.0.z,
                intrinsic.columns.1.x, intrinsic.columns.1.y, intrinsic.columns.1.z,
                intrinsic.columns.2.x, intrinsic.columns.2.y, intrinsic.columns.2.z
            ],
            extrinsicMatrix: [
                extrinsic.columns.0.x, extrinsic.columns.0.y, extrinsic.columns.0.z,
                extrinsic.columns.1.x, extrinsic.columns.1.y, extrinsic.columns.1.z,
                extrinsic.columns.2.x, extrinsic.columns.2.y, extrinsic.columns.2.z,
                extrinsic.columns.3.x, extrinsic.columns.3.y, extrinsic.columns.3.z
            ]
        )
    }

    private static func writeTemporaryArtifact(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPLockedImportArtifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(
            TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName
        )
        try data.write(to: url, options: [.atomic])
        return url
    }
}

private nonisolated struct PhotoInfo {
    let width: Int32
    let height: Int32
    let orientation: String
    let metadataKeys: [String]

    init(photoData: Data) throws {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let widthValue = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.int32Value ?? 0
        let heightValue = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.int32Value ?? 0
        self.width = widthValue
        self.height = heightValue
        if let orientation = properties[kCGImagePropertyOrientation as String] {
            self.orientation = "cgImagePropertyOrientation:\(orientation)"
        } else {
            self.orientation = "unspecified"
        }
        self.metadataKeys = properties.keys.sorted()
    }
}

private extension JSONDecoder {
    nonisolated static var tapLockedCamera: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
