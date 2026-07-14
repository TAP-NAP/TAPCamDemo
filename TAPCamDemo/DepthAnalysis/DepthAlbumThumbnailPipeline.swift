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
    private static let version = "library-poster-v5"

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
                  let data = DepthAlbumThumbnailJPEGRenderer.videoPosterData(
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

/// PhotoKit may omit its result callback after cancellation. This bridge owns
/// both the request identifier and continuation so cancellation always
/// completes exactly once, including cancel-before-ID-assignment races.
nonisolated final class DepthAlbumPhotoKitImageRequestBridge: @unchecked Sendable {
    private let cancelRequest: (PHImageRequestID) -> Void
    private let pixelLength: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DepthAlbumPhotoKitPosterResult, Error>?
    private var requestID: PHImageRequestID?
    private var previewData: Data?
    private var didFinish = false
    private var cancellationRequested = false

    init(manager: PHImageManager, pixelLength: Int) {
        self.cancelRequest = { requestID in
            manager.cancelImageRequest(requestID)
        }
        self.pixelLength = max(pixelLength, 1)
    }

    init(
        pixelLength: Int,
        cancelRequest: @escaping (PHImageRequestID) -> Void
    ) {
        self.cancelRequest = cancelRequest
        self.pixelLength = max(pixelLength, 1)
    }

    func install(continuation: CheckedContinuation<DepthAlbumPhotoKitPosterResult, Error>) {
        lock.lock()
        if cancellationRequested {
            didFinish = true
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(requestID: PHImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel {
            cancelRequest(requestID)
        }
    }

    func receive(image: UIImage?, info: [AnyHashable: Any]?) {
        lock.lock()
        let alreadyFinished = didFinish
        lock.unlock()
        guard !alreadyFinished else {
            return
        }

        if info?[PHImageCancelledKey] as? Bool == true {
            finish(.failure(CancellationError()))
            return
        }
        if let error = info?[PHImageErrorKey] as? Error {
            finish(.failure(error))
            return
        }

        let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool == true
        let isCloudOnly = info?[PHImageResultIsInCloudKey] as? Bool == true
        let imageData = image.flatMap {
            DepthAlbumThumbnailJPEGRenderer.data(from: $0, pixelLength: pixelLength)
        }

        if isDegraded {
            if let imageData {
                lock.lock()
                if !didFinish {
                    previewData = imageData
                }
                lock.unlock()
            }
            return
        }

        lock.lock()
        let previewData = self.previewData
        lock.unlock()
        if let imageData {
            finish(.success(DepthAlbumPhotoKitPosterResult(
                previewData: previewData,
                finalData: imageData,
                isCloudOnly: false
            )))
        } else if isCloudOnly {
            finish(.success(DepthAlbumPhotoKitPosterResult(
                previewData: previewData,
                finalData: nil,
                isCloudOnly: true
            )))
        } else {
            finish(.failure(MediaFetchFailure.decode))
        }
    }

    func cancel() {
        lock.lock()
        guard !cancellationRequested else {
            lock.unlock()
            return
        }
        cancellationRequested = true
        let requestID = requestID
        let continuation = continuation
        if continuation != nil, !didFinish {
            didFinish = true
            self.continuation = nil
        }
        lock.unlock()

        if let requestID {
            cancelRequest(requestID)
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<DepthAlbumPhotoKitPosterResult, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

nonisolated enum DepthAlbumThumbnailJPEGRenderer {
    private static let compressionQuality: CGFloat = 0.78

    static func data(from image: UIImage, pixelLength: Int) -> Data? {
        let pixelLength = max(pixelLength, 1)
        let canvas = CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas.size, format: format)
            .jpegData(withCompressionQuality: compressionQuality) { context in
                context.cgContext.setFillColor(UIColor.black.cgColor)
                context.cgContext.fill(canvas)
                image.draw(in: aspectFillRect(imageSize: image.size, targetSize: canvas.size))
            }
    }

    /// TAP Video posters preserve the transformed frame aspect ratio and cap
    /// the long edge, leaving aspect-fill/cropping to the consuming UI.
    static func videoPosterData(
        from image: UIImage,
        maximumPixelLength: Int
    ) -> Data? {
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
            .jpegData(withCompressionQuality: compressionQuality) { _ in
                image.draw(in: canvas)
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
