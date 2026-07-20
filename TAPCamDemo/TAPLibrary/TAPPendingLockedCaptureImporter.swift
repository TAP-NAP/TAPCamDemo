//
//  TAPPendingLockedCaptureImporter.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct TAPPendingLockedCaptureImporter {
    struct Result: Sendable {
        let record: TAPPendingCaptureRecord
        let photoByteCount: Int
        let hasThumbnail: Bool
    }

    private let storage: TAPPendingCaptureBundleStorage

    init(storage: TAPPendingCaptureBundleStorage) {
        self.storage = storage
    }

    func ingest(_ capture: TAPPendingLockedCaptureImport) throws -> Result {
        try validate(capture)
        let photoData = try Data(contentsOf: capture.unsignedPhotoURL)
        let temporaryURL = storage.temporaryBundleURL()
        try storage.createFreshTemporaryBundle(at: temporaryURL)
        try storage.writeUnsignedPhoto(
            photoData,
            fileContainer: .heic,
            to: temporaryURL
        )
        let thumbnailFilename = try writeThumbnail(
            from: photoData,
            to: temporaryURL
        )
        let now = Date()
        let record = TAPPendingCaptureRecord(
            captureID: capture.captureID,
            packageID: UUID(uuidString: capture.captureID) ?? UUID(),
            capturedAt: capture.capturedAt,
            createdAt: now,
            updatedAt: now,
            status: .pending,
            photoFileContainer: .heic,
            photoQualityLevel: .quality,
            captureScoreSummary: CaptureScoreSummary.make(
                depthAvailability: .available,
                fileContainer: .heic,
                photoQualityLevel: .quality,
                signatureStatus: .pending(reason: "Queued for App Attest signing.")
            ),
            unsignedPhotoFilename: CapturePhotoFileContainer.heic.unsignedFilename,
            signedPhotoFilename: nil,
            pairedVideoFilename: nil,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: nil,
            failureReason: nil,
            retryCount: 0,
            location: nil
        )
        try storage.writeRecord(record, in: temporaryURL)
        try storage.commitTemporaryBundle(
            at: temporaryURL,
            to: try storage.bundleURL(captureID: capture.captureID)
        )
        return Result(
            record: record,
            photoByteCount: photoData.count,
            hasThumbnail: thumbnailFilename != nil
        )
    }

    func validate(_ capture: TAPPendingLockedCaptureImport) throws {
        guard capture.captureID == capture.metadata.captureID else {
            throw invalid("locked metadata captureID must match import captureID")
        }
        guard capture.metadata.photoFileName
                == CapturePhotoFileContainer.heic.unsignedFilename else {
            throw invalid("locked import must use unsigned.heic")
        }
        guard capture.metadata.artifactKind
                == TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind else {
            throw invalid("locked import must be an unsigned TAP artifact")
        }
        guard capture.metadata.depthDataPresent == true else {
            throw TAPDepthCaptureError.missingDepthData
        }
    }

    private func writeThumbnail(
        from photoData: Data,
        to bundleURL: URL
    ) throws -> String? {
        guard let data = TAPPendingCaptureThumbnailRenderer.thumbnailData(
            from: photoData
        ) else {
            return nil
        }
        try storage.writeThumbnail(data, to: bundleURL)
        return TAPPendingCaptureBundlePathPolicy.thumbnailFilename
    }

    private func invalid(_ reason: String) -> TAPDepthCaptureError {
        .invalidPendingCaptureBundlePath(reason)
    }
}
