//
//  TAPVideoPhotosReadbackValidator.swift
//  TAPCamDemo
//

import Foundation

/// Streams the original Photos resource to a temporary file, then
/// runs the same URL-only proof and byte-binding gate used before export.
nonisolated enum TAPVideoPhotosReadbackValidator {
    static func validate(
        assetLocalIdentifier: String,
        captureID: String,
        packageID: UUID,
        provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()
    ) async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPVideoReadback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let fileURL = directoryURL.appendingPathComponent("artifact.mp4")
        try await PhotoLibraryWriter.writeOriginalVideoResource(
            localIdentifier: assetLocalIdentifier,
            to: fileURL
        )

        _ = try await provenanceWriter.validateSignedExportVideoFile(
            .init(fileURL: fileURL),
            expectedCaptureID: captureID,
            expectedPackageID: packageID
        )
    }
}
