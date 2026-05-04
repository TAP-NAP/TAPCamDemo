//
//  TAPPendingCaptureStore.swift
//  TAPCamDemo
//

@preconcurrency import CoreLocation
@preconcurrency import ImageIO
import Foundation
import UIKit

nonisolated extension Notification.Name {
    static let tapLibraryDidChange = Notification.Name("tapLibraryDidChange")
}

nonisolated enum TAPPendingCaptureStatus: String, Codable, Equatable, Sendable {
    case pending
    case waitingNetwork
    case signing
    case signed
    case exporting
    case exported
    case failedRetryable
}

nonisolated struct TAPPendingCaptureLocation: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.timestamp = location.timestamp
    }

    var clLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }
}

nonisolated struct TAPPendingCaptureRecord: Codable, Equatable, Identifiable, Sendable {
    let captureID: String
    let packageID: UUID
    let capturedAt: Date
    let createdAt: Date
    var updatedAt: Date
    var status: TAPPendingCaptureStatus
    var unsignedHEICFilename: String?
    var signedHEICFilename: String?
    var thumbnailFilename: String?
    var assetLocalIdentifier: String?
    var failureReason: String?
    var retryCount: Int
    var location: TAPPendingCaptureLocation?

    var id: String {
        captureID
    }

    var isVisiblePendingItem: Bool {
        status != .exported
    }
}

/// App-private staging store for unsigned/signed TAP depth HEIC files.
///
/// This store is intentionally HEIC-only for this implementation slice. Future
/// multi-format resource bundles should be designed separately; see the P1 TODO
/// in `PACKAGING.md`.
actor TAPPendingCaptureStore {
    static let shared = TAPPendingCaptureStore()

    private static let recordsDirectoryName = "Pending"
    private static let recordFilename = "bundle.json"
    private static let unsignedHEICFilename = "unsigned.heic"
    private static let signedHEICFilename = "signed.heic"
    private static let thumbnailFilename = "thumbnail.jpg"

    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL = TAPPendingCaptureStore.defaultRootURL()) {
        self.rootURL = rootURL
    }

    func ingest(_ artifact: PackagedCaptureArtifact) throws -> TAPPendingCaptureRecord {
        try ensureRootDirectoryExists()

        let captureID = artifact.manifest.payload.id
        let finalURL = bundleURL(captureID: captureID)
        if fileManager.fileExists(atPath: finalURL.path),
           let existing = try? readRecord(captureID: captureID) {
            return existing
        }

        let temporaryURL = rootURL.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        let unsignedURL = temporaryURL.appendingPathComponent(Self.unsignedHEICFilename)
        try artifact.photoData.write(to: unsignedURL, options: [.atomic])

        let thumbnailFilename: String?
        if let thumbnailData = TAPPendingCaptureThumbnailRenderer.thumbnailData(from: artifact.photoData) {
            try thumbnailData.write(to: temporaryURL.appendingPathComponent(Self.thumbnailFilename), options: [.atomic])
            thumbnailFilename = Self.thumbnailFilename
        } else {
            thumbnailFilename = nil
        }

        let now = Date()
        let record = TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: artifact.packageID,
            capturedAt: artifact.capturedAt,
            createdAt: now,
            updatedAt: now,
            status: .pending,
            unsignedHEICFilename: Self.unsignedHEICFilename,
            signedHEICFilename: nil,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: nil,
            failureReason: nil,
            retryCount: 0,
            location: artifact.location.map(TAPPendingCaptureLocation.init)
        )
        try writeRecord(record, in: temporaryURL)

        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        try protectBundle(at: finalURL)
        Self.postLibraryDidChange()
        return record
    }

    func allRecords() throws -> [TAPPendingCaptureRecord] {
        try ensureRootDirectoryExists()
        return try bundleURLs().compactMap { url in
            try? readRecord(in: url)
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }

    func visiblePendingRecords() throws -> [TAPPendingCaptureRecord] {
        try allRecords().filter(\.isVisiblePendingItem)
    }

    func processingCandidates() throws -> [TAPPendingCaptureRecord] {
        try allRecords()
            .filter { record in
                switch record.status {
                case .pending, .waitingNetwork, .signing, .signed, .exporting, .failedRetryable:
                    true
                case .exported:
                    false
                }
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func readRecord(captureID: String) throws -> TAPPendingCaptureRecord {
        try readRecord(in: bundleURL(captureID: captureID))
    }

    func unsignedHEICData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.unsignedHEICFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return try heicData(filename: filename, captureID: captureID)
    }

    func signedHEICData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.signedHEICFilename else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return try heicData(filename: filename, captureID: captureID)
    }

    func bestAvailableHEICData(captureID: String) throws -> Data {
        let record = try readRecord(captureID: captureID)
        if let filename = record.signedHEICFilename {
            if let data = try heicDataIfPresent(filename: filename, captureID: captureID) {
                return data
            }
        }
        if let filename = record.unsignedHEICFilename {
            if let data = try heicDataIfPresent(filename: filename, captureID: captureID) {
                return data
            }
        }
        throw TAPDepthCaptureError.pendingCaptureDataMissing
    }

    func thumbnailData(captureID: String) throws -> Data? {
        let record = try readRecord(captureID: captureID)
        guard let filename = record.thumbnailFilename else {
            return nil
        }
        return try? Data(contentsOf: bundleURL(captureID: captureID).appendingPathComponent(filename))
    }

    func updateStatus(
        captureID: String,
        status: TAPPendingCaptureStatus,
        failureReason: String? = nil,
        incrementsRetryCount: Bool = false
    ) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        record.status = status
        record.failureReason = failureReason
        record.updatedAt = Date()
        if incrementsRetryCount {
            record.retryCount += 1
        }
        try writeRecord(record)
        Self.postLibraryDidChange()
        return record
    }

    func storeSignedHEIC(_ data: Data, captureID: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        try data.write(to: bundleURL(captureID: captureID).appendingPathComponent(Self.signedHEICFilename), options: [.atomic])
        record.signedHEICFilename = Self.signedHEICFilename
        record.status = .signed
        record.failureReason = nil
        record.updatedAt = Date()
        try writeRecord(record)
        Self.postLibraryDidChange()
        return record
    }

    func markExported(captureID: String, assetLocalIdentifier: String) throws -> TAPPendingCaptureRecord {
        var record = try readRecord(captureID: captureID)
        record.status = .exported
        record.assetLocalIdentifier = assetLocalIdentifier
        record.failureReason = nil
        record.updatedAt = Date()
        try writeRecord(record)
        try cleanupLargeFiles(for: record)
        Self.postLibraryDidChange()
        return record
    }

    func cleanupExportedLargeFiles() throws {
        for record in try allRecords() where record.status == .exported {
            try cleanupLargeFiles(for: record)
        }
    }

    func removeRecord(captureID: String) throws {
        let url = bundleURL(captureID: captureID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            Self.postLibraryDidChange()
        }
    }

    private nonisolated static func defaultRootURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("TAPCaptureLibrary", isDirectory: true)
            .appendingPathComponent(recordsDirectoryName, isDirectory: true)
    }

    private func ensureRootDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: rootURL.path) else {
            return
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try protectBundle(at: rootURL)
    }

    private func protectBundle(at url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func bundleURL(captureID: String) -> URL {
        rootURL.appendingPathComponent(captureID, isDirectory: true)
    }

    private func bundleURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func readRecord(in bundleURL: URL) throws -> TAPPendingCaptureRecord {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(Self.recordFilename))
        return try JSONDecoder.tapPendingCapture.decode(TAPPendingCaptureRecord.self, from: data)
    }

    private func heicData(filename: String, captureID: String) throws -> Data {
        guard let data = try heicDataIfPresent(filename: filename, captureID: captureID) else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return data
    }

    private func heicDataIfPresent(filename: String, captureID: String) throws -> Data? {
        let url = bundleURL(captureID: captureID).appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func writeRecord(_ record: TAPPendingCaptureRecord) throws {
        try writeRecord(record, in: bundleURL(captureID: record.captureID))
    }

    private func writeRecord(_ record: TAPPendingCaptureRecord, in bundleURL: URL) throws {
        let data = try JSONEncoder.tapPendingCapture.encode(record)
        try data.write(to: bundleURL.appendingPathComponent(Self.recordFilename), options: [.atomic])
    }

    private func cleanupLargeFiles(for record: TAPPendingCaptureRecord) throws {
        let directory = bundleURL(captureID: record.captureID)
        for filename in [record.unsignedHEICFilename, record.signedHEICFilename].compactMap({ $0 }) {
            let url = directory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private nonisolated static func postLibraryDidChange() {
        NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
    }
}

nonisolated struct TAPPendingCaptureArtifactWriter: CaptureArtifactWriter {
    let store: TAPPendingCaptureStore

    init(store: TAPPendingCaptureStore = .shared) {
        self.store = store
    }

    /// Persists one unsigned capture artifact into the app-private pending store.
    ///
    /// Foreground capture work ends here. App Attest signing and Photos export are
    /// owned by `TAPPendingCaptureProcessor` so TAP Library can show pending state.
    ///
    /// - Tag: WritePackagedArtifactToPendingStore
    func write(_ artifact: PackagedCaptureArtifact) async throws -> CaptureWriteResult {
        let record = try await store.ingest(artifact)
        return CaptureWriteResult(
            artifactID: artifact.packageID,
            destinationDescription: "Pending TAP capture: \(record.captureID)",
            assetLocalIdentifier: nil,
            pendingCaptureID: record.captureID,
            signatureStatus: .pending(reason: "Queued for App Attest signing.")
        )
    }
}

nonisolated private enum TAPPendingCaptureThumbnailRenderer {
    private static let pixelLength = 320
    private static let compressionQuality: CGFloat = 0.78

    static func thumbnailData(from heicData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelLength
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelLength, height: pixelLength), format: format)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { context in
            let canvas = CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(canvas)
            UIImage(cgImage: image).draw(in: aspectFillRect(imageSize: CGSize(width: image.width, height: image.height), targetSize: canvas.size))
        }
    }

    private static func aspectFillRect(imageSize: CGSize, targetSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: targetSize)
        }
        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

nonisolated private extension JSONEncoder {
    static var tapPendingCapture: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

nonisolated private extension JSONDecoder {
    static var tapPendingCapture: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
