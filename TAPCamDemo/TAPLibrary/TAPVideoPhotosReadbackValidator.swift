//
//  TAPVideoPhotosReadbackValidator.swift
//  TAPCamDemo
//

import Foundation

/// Streams the original Photos resource to a disk-backed accumulator, then
/// runs the same URL-only proof and byte-binding gate used before export.
nonisolated enum TAPVideoPhotosReadbackValidator {
    static func validate(
        assetLocalIdentifier: String,
        captureID: String,
        packageID: UUID,
        provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()
    ) async throws -> TAPVideoManifest {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPVideoReadback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let fileURL = directoryURL.appendingPathComponent("artifact.mp4")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let accumulator = try TAPVideoReadbackFileAccumulator(fileURL: fileURL)
        do {
            try await PhotoLibraryWriter.readOriginalVideoResource(
                localIdentifier: assetLocalIdentifier,
                dataReceivedHandler: { chunk in
                    try accumulator.append(chunk)
                }
            )
            try accumulator.finish()
        } catch {
            accumulator.cancel()
            throw error
        }

        return try await provenanceWriter.validateSignedExportVideoFile(
            at: fileURL,
            expectedCaptureID: captureID,
            expectedPackageID: packageID
        ).manifest
    }
}

nonisolated private final class TAPVideoReadbackFileAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var terminalError: Error?

    init(fileURL: URL) throws {
        fileHandle = try FileHandle(forWritingTo: fileURL)
    }

    func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        if let terminalError {
            throw terminalError
        }
        guard let fileHandle else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        do {
            try fileHandle.write(contentsOf: data)
        } catch {
            terminalError = error
            throw error
        }
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        if let terminalError {
            throw terminalError
        }
        guard let fileHandle else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        do {
            try fileHandle.synchronize()
            try fileHandle.close()
            self.fileHandle = nil
        } catch {
            terminalError = error
            throw error
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        try? fileHandle?.close()
        fileHandle = nil
    }
}
