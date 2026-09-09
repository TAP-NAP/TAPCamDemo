//
//  PhotoLibraryPendingCaptureExporter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import OSLog

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

    static func live(
        provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()
    ) -> Self {
        Self(
            existingAssetIdentifier: { captureID in
                try await PhotoLibraryWriter.depthAssetIdentifier(captureID: captureID)
            },
            saveValidatedSignedPhoto: { signedData, record, pairedVideoURL in
                let input = try TAPPhotoValidationInput(
                    data: signedData, expectedContainer: record.outputProfile.fileContainer
                )
                if let pairedVideoURL {
                    let validatedLivePhoto = try provenanceWriter.validateSignedExportLivePhoto(
                        input,
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
                        input,
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
    let validateLocalFile: @Sendable (URL, TAPPendingCaptureRecord) async throws -> ValidatedTAPVideoFile
    let saveVideoFile: @Sendable (
        URL,
        TAPPendingCaptureRecord,
        TAPVideoManifest,
        PhotoLibraryPendingVideoCommitBoundary
    ) async throws -> String

    static func live() -> Self {
        Self(
            validateLocalFile: { fileURL, record in
                try await TAPCaptureProvenanceWriter().validateSignedExportVideoFile(
                    .init(fileURL: fileURL),
                    expectedCaptureID: record.captureID,
                    expectedPackageID: record.packageID,
                    validatesDepthTrack: false
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
            }
        )
    }
}

nonisolated struct PhotoLibraryPendingVideoReadbackActions: Sendable {
    let candidateIdentifiers: @Sendable (UUID) async throws -> [String]
    let validateReadback: @Sendable (String, TAPPendingCaptureRecord) async throws -> Void

    static func live() -> Self {
        Self(
            candidateIdentifiers: { packageID in
                try await PhotoLibraryWriter.tapVideoAssetCandidateIdentifiers(packageID: packageID)
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
                // The injected readback stage owns candidate lookup and
                // validation. Returning here preserves the no-duplicate
                // boundary after Photos commit may already have begun.
                return
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
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("export save passed captureID=\(record.captureID, privacy: .private)")
        #endif
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

}

struct PhotoLibraryPendingCaptureReadback: TAPPendingCaptureReadingBack {
    private let actions: PhotoLibraryPendingVideoReadbackActions

    init(actions: PhotoLibraryPendingVideoReadbackActions = .live()) {
        self.actions = actions
    }

    func readBack(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws {
        guard record.artifactKind == .tapVideo else {
            return
        }
        let persistedRecord = try await store.readRecord(captureID: record.captureID)
        guard persistedRecord.status != .exported,
              persistedRecord.status != .failedTerminal else {
            return
        }

        let candidateIDs: [String]
        if let committedAssetID = persistedRecord.assetLocalIdentifier {
            candidateIDs = [committedAssetID]
        } else if persistedRecord.shouldAttemptExistingAssetRecoveryBeforeExport {
            candidateIDs = try await actions.candidateIdentifiers(persistedRecord.packageID)
        } else {
            throw TAPDepthCaptureError.assetNotFound
        }
        guard !candidateIDs.isEmpty else {
            // Photos may not expose a just-committed asset immediately.
            // Remaining in recovery is safer than creating a duplicate.
            throw TAPDepthCaptureError.assetNotFound
        }

        var validCandidateIDs: [String] = []
        for candidateID in candidateIDs {
            do {
                try await validateWithTrace(
                    assetID: candidateID,
                    record: persistedRecord
                )
                validCandidateIDs.append(candidateID)
            } catch {
                if Self.isTerminalValidationError(error) {
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
    }

    private func validateWithTrace(
        assetID: String,
        record: TAPPendingCaptureRecord
    ) async throws {
        let trace = TAPVideoPerformanceTrace.beginPhotosReadback()
        do {
            try await actions.validateReadback(assetID, record)
            TAPVideoPerformanceTrace.endPhotosReadback(trace, succeeded: true)
        } catch {
            TAPVideoPerformanceTrace.endPhotosReadback(trace, succeeded: false)
            throw error
        }
    }

    private static func isTerminalValidationError(_ error: Error) -> Bool {
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
}
