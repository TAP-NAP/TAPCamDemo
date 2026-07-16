//
//  DepthAlbumThumbnailPipeline.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import Photos
import UIKit

/// Owns TAP Library thumbnail derivation and caching.
///
/// `DepthAlbumPickerView` should read as album UI. Keep Photos thumbnail
/// requests, JPEG normalization, and protected disk-cache writes here.
nonisolated enum DepthAlbumThumbnailCacheKey {
    private static let version = "library-poster-v6"

    static func make(mediaID: LibraryMediaID, version mediaVersion: String, pixelLength: Int) -> String {
        makeHash(from: [
            version,
            mediaID.storageValue,
            mediaVersion,
            "\(pixelLength)px"
        ])
    }

    static func make(
        assetLocalIdentifier: String,
        pixelLength: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        versionDate: Date
    ) -> String {
        makeHash(from: [
            version,
            "photos",
            assetLocalIdentifier,
            "\(pixelLength)px",
            "\(pixelWidth)x\(pixelHeight)",
            String(versionDate.timeIntervalSince1970)
        ])
    }

    static func makePending(
        captureID: String,
        pixelLength: Int,
        capturedAt: Date,
        thumbnailFilename: String?,
        videoFilename: String? = nil,
        updatedAt: Date? = nil
    ) -> String {
        makeHash(from: [
            version,
            "pending",
            captureID,
            "\(pixelLength)px",
            String(capturedAt.timeIntervalSince1970),
            thumbnailFilename ?? "no-thumbnail",
            videoFilename ?? "no-video",
            String((updatedAt ?? capturedAt).timeIntervalSince1970)
        ])
    }

    private static func makeHash(from parts: [String]) -> String {
        let source = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct DepthAlbumPhotoKitPosterResult: Sendable {
    let previewData: Data?
    let finalData: Data?
    let isCloudOnly: Bool
}

actor DepthAlbumThumbnailLoader {
    static let shared = DepthAlbumThumbnailLoader()

    private var inFlight: [String: Task<Data?, Never>] = [:]

    func videoData(for fileURL: URL, cacheKey: String, pixelLength: Int) async -> Data? {
        if let task = inFlight[cacheKey] {
            return await task.value
        }

        let task = Task<Data?, Never>.detached(priority: .utility) {
            if let cachedData = await DepthAlbumThumbnailDiskCache.shared.data(for: cacheKey) {
                return cachedData
            }

            let asset = AVURLAsset(url: fileURL)
            guard let image = await Self.image(from: asset, pixelLength: pixelLength),
                  let data = DepthAlbumThumbnailJPEGRenderer.aspectPreservingData(
                    from: image,
                    maximumPixelLength: pixelLength
                  ) else {
                return nil
            }

            await DepthAlbumThumbnailDiskCache.shared.store(data, for: cacheKey)
            return data
        }

        inFlight[cacheKey] = task
        let data = await task.value
        inFlight[cacheKey] = nil
        return data
    }

    private nonisolated static func image(from asset: AVAsset, pixelLength: Int) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let maximumPixelLength = CGFloat(max(pixelLength, 1))
        generator.maximumSize = CGSize(width: maximumPixelLength, height: maximumPixelLength)

        let duration = try? await asset.load(.duration)
        let durationSeconds = duration.map(CMTimeGetSeconds) ?? 0
        let firstUsefulSecond: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            firstUsefulSecond = min(0.12, max(0, durationSeconds - (1.0 / 600.0)))
        } else {
            firstUsefulSecond = 0.12
        }
        let times = [firstUsefulSecond, 0].reduce(into: [Double]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }

        for second in times {
            do {
                let image = try await withTaskCancellationHandler {
                    let result = try await generator.image(
                        at: CMTime(seconds: second, preferredTimescale: 600)
                    )
                    return UIImage(cgImage: result.image)
                } onCancel: {
                    generator.cancelAllCGImageGeneration()
                }
                return image
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
        }
        return nil
    }
}

/// PhotoKit may omit its result callback after cancellation. The shared
/// lifecycle owns continuation, request-ID, and terminal-delivery races while
/// this bridge only interprets poster callbacks and retains a degraded preview.
nonisolated final class DepthAlbumPhotoKitImageRequestBridge: @unchecked Sendable {
    private let pixelLength: Int
    private let lifecycle: PhotoKitRequestLifecycle<PHImageRequestID, DepthAlbumPhotoKitPosterResult>
    /// Accessed only from closures serialized by `lifecycle`.
    private var previewData: Data?

    init(manager: PHImageManager, pixelLength: Int) {
        self.pixelLength = max(pixelLength, 1)
        self.lifecycle = PhotoKitRequestLifecycle { requestID in
            manager.cancelImageRequest(requestID)
        }
    }

    init(
        pixelLength: Int,
        cancelRequest: @escaping @Sendable (PHImageRequestID) -> Void
    ) {
        self.pixelLength = max(pixelLength, 1)
        self.lifecycle = PhotoKitRequestLifecycle(cancelRequest: cancelRequest)
    }

    func install(continuation: CheckedContinuation<DepthAlbumPhotoKitPosterResult, Error>) {
        lifecycle.install(continuation: continuation)
    }

    func install(requestID: PHImageRequestID) {
        lifecycle.install(requestID: requestID)
    }

    func receive(image: UIImage?, info: [AnyHashable: Any]?) {
        if info?[PHImageCancelledKey] as? Bool == true {
            lifecycle.finish(.failure(CancellationError()))
            return
        }
        if let error = info?[PHImageErrorKey] as? Error {
            lifecycle.finish(.failure(error))
            return
        }

        let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool == true
        let isCloudOnly = info?[PHImageResultIsInCloudKey] as? Bool == true
        let imageData = image.flatMap {
            DepthAlbumThumbnailJPEGRenderer.aspectPreservingData(
                from: $0,
                maximumPixelLength: pixelLength
            )
        }

        if isDegraded {
            if let imageData {
                lifecycle.process({
                    previewData = imageData
                }, mapError: { $0 })
            }
            return
        }

        if let imageData {
            lifecycle.finish {
                DepthAlbumPhotoKitPosterResult(
                    previewData: previewData,
                    finalData: imageData,
                    isCloudOnly: false
                )
            }
        } else if isCloudOnly {
            lifecycle.finish {
                DepthAlbumPhotoKitPosterResult(
                    previewData: previewData,
                    finalData: nil,
                    isCloudOnly: true
                )
            }
        } else {
            lifecycle.finish(.failure(MediaFetchFailure.decode))
        }
    }

    func cancel() {
        lifecycle.cancel()
    }
}

nonisolated enum DepthAlbumThumbnailJPEGRenderer {
    private static let compressionQuality: CGFloat = 0.78

    /// Poster and display-preview bytes preserve the transformed media aspect
    /// ratio. The Library grid owns its square center crop; the viewer uses the
    /// same lightweight bytes with aspect-fit while the original resolves.
    static func aspectPreservingData(
        from image: UIImage,
        maximumPixelLength: Int
    ) -> Data? {
        // UIImage.size is already expressed in display orientation, including
        // images whose backing CGImage carries a left/right orientation.
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }
        let maximumPixelLength = CGFloat(max(maximumPixelLength, 1))
        let scale = maximumPixelLength / max(sourceSize.width, sourceSize.height)
        let outputSize = CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )
        let canvas = CGRect(origin: .zero, size: outputSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format)
            .jpegData(withCompressionQuality: compressionQuality) { context in
                context.cgContext.setFillColor(UIColor.black.cgColor)
                context.cgContext.fill(canvas)
                image.draw(in: canvas)
            }
    }
}

@MainActor
final class DepthAlbumThumbnailMemoryCache {
    static let shared = DepthAlbumThumbnailMemoryCache()

    private final class Entry: NSObject {
        let poster: MediaPoster
        let image: UIImage

        init(poster: MediaPoster, image: UIImage) {
            self.poster = poster
            self.image = image
        }
    }

    private let cache = NSCache<NSString, Entry>()

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func poster(for key: String) -> MediaPoster? {
        cache.object(forKey: key as NSString)?.poster
    }

    func insert(_ poster: MediaPoster) {
        guard let image = poster.image else {
            return
        }
        cache.setObject(
            Entry(poster: poster, image: image),
            forKey: poster.cacheKey as NSString,
            cost: imageCost(image)
        )
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

nonisolated struct DepthAlbumThumbnailDiskCacheConfiguration: Equatable, Sendable {
    let maximumByteCount: Int64
    let maximumFileAge: TimeInterval

    static let `default` = DepthAlbumThumbnailDiskCacheConfiguration(
        maximumByteCount: 128 * 1024 * 1024,
        maximumFileAge: 30 * 24 * 60 * 60
    )
}

actor DepthAlbumThumbnailDiskCache {
    static let shared = DepthAlbumThumbnailDiskCache()

    private let directoryURL: URL
    private let fileManager = FileManager.default
    private let storagePolicy = TAPLocalArtifactStoragePolicy.privatePhotoArtifact
    private let configuration: DepthAlbumThumbnailDiskCacheConfiguration
    private let now: @Sendable () -> Date
    private var didRunInitialMaintenance = false

    init(
        directoryURL: URL? = nil,
        configuration: DepthAlbumThumbnailDiskCacheConfiguration = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let rootURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directoryURL = directoryURL
            ?? rootURL.appendingPathComponent("DepthAlbumThumbnails", isDirectory: true)
        self.configuration = configuration
        self.now = now
    }

    func data(for key: String) -> Data? {
        ensureDirectoryExists()
        runInitialMaintenanceIfNeeded()
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, for key: String) {
        ensureDirectoryExists()
        runInitialMaintenanceIfNeeded()
        let url = fileURL(for: key)
        try? storagePolicy.write(data, to: url, fileManager: fileManager)
        try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        prune()
    }

    func removeAll() {
        try? fileManager.removeItem(at: directoryURL)
        didRunInitialMaintenance = false
    }

    func currentByteCount() -> Int64 {
        cacheEntries().reduce(0) { $0 + $1.byteCount }
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("jpg")
    }

    private func ensureDirectoryExists() {
        try? storagePolicy.createDirectoryIfNeeded(at: directoryURL, fileManager: fileManager)
    }

    private func runInitialMaintenanceIfNeeded() {
        guard !didRunInitialMaintenance else {
            return
        }
        didRunInitialMaintenance = true
        prune()
    }

    private func prune() {
        let expirationDate = now().addingTimeInterval(-configuration.maximumFileAge)
        var entries = cacheEntries()
        for entry in entries where entry.modifiedAt < expirationDate {
            try? fileManager.removeItem(at: entry.url)
        }

        entries = cacheEntries().sorted { lhs, rhs in
            lhs.modifiedAt < rhs.modifiedAt
        }
        var byteCount = entries.reduce(Int64(0)) { $0 + $1.byteCount }
        for entry in entries where byteCount > configuration.maximumByteCount {
            do {
                try fileManager.removeItem(at: entry.url)
                byteCount -= entry.byteCount
            } catch {
                continue
            }
        }
    }

    private func cacheEntries() -> [CacheEntry] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return CacheEntry(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private struct CacheEntry {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
    }
}
