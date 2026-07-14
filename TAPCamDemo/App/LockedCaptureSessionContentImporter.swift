//
//  LockedCaptureSessionContentImporter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Combine
import Foundation
import LockedCameraCapture
import OSLog

nonisolated struct LockedCaptureSessionContentCaptureProbe: Equatable, Sendable {
    let metadata: TAPCamLockedRawCaptureMetadata
    let photoURL: URL
}

nonisolated struct LockedCaptureSessionContentScan: Equatable, Sendable {
    let captures: [LockedCaptureSessionContentCaptureProbe]
    let unexpectedEntryCount: Int
}

nonisolated struct LockedCaptureSessionContentImportSummary: Equatable, Sendable {
    var foundCaptureCount = 0
    var importedCount = 0
    var failedCount = 0
    var unexpectedEntryCount = 0
    var invalidatedSessionCount = 0
}

nonisolated enum LockedCaptureSessionContentScanner {
    static func scan(sessionContentURL: URL) throws -> LockedCaptureSessionContentScan {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionContentURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var captures: [LockedCaptureSessionContentCaptureProbe] = []
        var unexpectedEntryCount = 0

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true,
                  url.pathExtension.caseInsensitiveCompare("heic") == .orderedSame,
                  let captureID = flatHEICCaptureID(from: url) else {
                unexpectedEntryCount += 1
                continue
            }

            let capturedAt = values.creationDate
                ?? values.contentModificationDate
                ?? Date(timeIntervalSince1970: 0)
            let metadata = TAPCamLockedRawCaptureMetadata(
                captureID: captureID,
                capturedAt: capturedAt,
                artifactKind: TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind,
                lens: fallbackLens(),
                photoFileName: url.lastPathComponent,
                byteCount: values.fileSize ?? fileSize(at: url) ?? 0,
                depthDataPresent: true,
                source: "locked-camera-r2b-flat-heic"
            )
            captures.append(
                LockedCaptureSessionContentCaptureProbe(
                    metadata: metadata,
                    photoURL: url
                )
            )
        }

        return LockedCaptureSessionContentScan(
            captures: captures.sorted { $0.metadata.capturedAt < $1.metadata.capturedAt },
            unexpectedEntryCount: unexpectedEntryCount
        )
    }

    static func flatHEICCaptureID(from fileURL: URL) -> String? {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let prefix = TAPCamLockedSessionContentPathPolicy.flatHEICFilePrefix
        guard filename.hasPrefix(prefix) else {
            return nil
        }

        let captureID = String(filename.dropFirst(prefix.count))
        guard UUID(uuidString: captureID) != nil else {
            return nil
        }
        return captureID
    }

    private static func fallbackLens() -> TAPCamLockedCameraLensRecord {
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
}

actor LockedCaptureSessionContentImporter {
    static let shared = LockedCaptureSessionContentImporter()

    private let store: TAPPendingCaptureStore

    init(store: TAPPendingCaptureStore = .shared) {
        self.store = store
    }

    @discardableResult
    func importSessionContent(
        at sessionContentURL: URL,
        trigger: String
    ) async -> LockedCaptureSessionContentImportSummary {
        var summary = LockedCaptureSessionContentImportSummary()
        LockedCameraDiagnostics.logger.notice(
            "r3_import_begin trigger=\(trigger, privacy: .public) session=\(sessionContentURL.path, privacy: .private(mask: .hash))"
        )

        let scan: LockedCaptureSessionContentScan
        do {
            scan = try LockedCaptureSessionContentScanner.scan(
                sessionContentURL: sessionContentURL
            )
        } catch {
            summary.failedCount = 1
            LockedCameraDiagnostics.logger.error(
                "r3_scan_failed trigger=\(trigger, privacy: .public) error=\(Self.describe(error), privacy: .public) session=\(sessionContentURL.path, privacy: .private(mask: .hash))"
            )
            return summary
        }

        summary.foundCaptureCount = scan.captures.count
        summary.unexpectedEntryCount = scan.unexpectedEntryCount
        LockedCameraDiagnostics.logger.notice(
            "r3_scan_finished trigger=\(trigger, privacy: .public) captureCount=\(scan.captures.count, privacy: .public) unexpectedEntryCount=\(scan.unexpectedEntryCount, privacy: .public) session=\(sessionContentURL.path, privacy: .private(mask: .hash))"
        )

        for probe in scan.captures {
            do {
                let packagedProbe = try LockedCaptureTAPArtifactPackager
                    .packageStagingCapture(probe)
                defer {
                    Self.discardTemporaryPackagedArtifact(
                        packagedProbe,
                        originalProbe: probe
                    )
                }

                let record = try await store.ingestLockedCapture(
                    TAPPendingLockedCaptureImport(
                        captureID: packagedProbe.metadata.captureID,
                        capturedAt: packagedProbe.metadata.capturedAt,
                        unsignedPhotoURL: packagedProbe.photoURL,
                        metadata: packagedProbe.metadata
                    )
                )
                summary.importedCount += 1
                LockedCameraDiagnostics.logger.notice(
                    "r3_capture_imported captureID=\(record.captureID, privacy: .public) status=\(record.status.rawValue, privacy: .public)"
                )
            } catch {
                summary.failedCount += 1
                LockedCameraDiagnostics.logger.error(
                    "r3_capture_import_failed captureID=\(probe.metadata.captureID, privacy: .public) error=\(Self.describe(error), privacy: .public)"
                )
            }
        }

        if summary.importedCount > 0 {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .tapCamLockedCaptureImportDidAddPendingCaptures,
                    object: nil
                )
            }
        }

        guard summary.failedCount == 0,
              summary.unexpectedEntryCount == 0 else {
            LockedCameraDiagnostics.logger.error(
                "r3_session_retained imported=\(summary.importedCount, privacy: .public) failed=\(summary.failedCount, privacy: .public) unexpectedEntryCount=\(summary.unexpectedEntryCount, privacy: .public) session=\(sessionContentURL.path, privacy: .private(mask: .hash))"
            )
            return summary
        }

        do {
            try await LockedCameraCaptureManager.shared.invalidateSessionContent(
                at: sessionContentURL
            )
            summary.invalidatedSessionCount = 1
            LockedCameraDiagnostics.logger.notice(
                "r3_session_invalidated captureCount=\(summary.foundCaptureCount, privacy: .public) session=\(sessionContentURL.path, privacy: .private(mask: .hash))"
            )
        } catch {
            LockedCameraDiagnostics.logger.error(
                "r3_session_invalidate_failed error=\(Self.describe(error), privacy: .public) session=\(sessionContentURL.path, privacy: .private(mask: .hash))"
            )
        }

        return summary
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

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }
}

@MainActor
final class LockedCaptureSessionContentImportRuntime: ObservableObject {
    private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else {
            return
        }

        LockedCameraDiagnostics.logger.notice("r3_runtime_start")
        updatesTask = Task {
            await LockedCaptureSessionContentImportScheduler().run()
        }
    }

    deinit {
        updatesTask?.cancel()
    }
}

nonisolated struct LockedCaptureSessionContentImportScheduler: Sendable {
    let importer: LockedCaptureSessionContentImporter

    init(importer: LockedCaptureSessionContentImporter = .shared) {
        self.importer = importer
    }

    func run() async {
        let manager = LockedCameraCaptureManager.shared

        for await update in manager.sessionContentUpdates {
            guard !Task.isCancelled else {
                return
            }

            switch update {
            case .initial(let urls):
                LockedCameraDiagnostics.logger.notice(
                    "r3_session_update kind=initial sessionCount=\(urls.count, privacy: .public)"
                )
                for url in urls {
                    guard !Task.isCancelled else { return }
                    await importer.importSessionContent(at: url, trigger: "initial")
                }
            case .added(let url):
                LockedCameraDiagnostics.logger.notice("r3_session_update kind=added")
                await importer.importSessionContent(at: url, trigger: "added")
            case .removed:
                LockedCameraDiagnostics.logger.notice("r3_session_update kind=removed")
            @unknown default:
                LockedCameraDiagnostics.logger.notice("r3_session_update kind=unknown")
            }
        }
    }
}
