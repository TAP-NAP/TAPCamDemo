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
    private static let version = "grid-v4-video-frame-jpeg"

    static func make(for asset: PHAsset, pixelLength: Int) -> String {
        make(
            assetLocalIdentifier: asset.localIdentifier,
            pixelLength: pixelLength,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            versionDate: asset.modificationDate ?? asset.creationDate ?? .distantPast
        )
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

actor DepthAlbumThumbnailLoader {
    static let shared = DepthAlbumThumbnailLoader()

    private var inFlight: [String: Task<Data?, Never>] = [:]

    func data(for asset: PHAsset, cacheKey: String, pixelLength: Int) async -> Data? {
        if let task = inFlight[cacheKey] {
            return await task.value
        }

        let task = Task<Data?, Never>.detached(priority: .utility) {
            if let cachedData = await DepthAlbumThumbnailDiskCache.shared.data(for: cacheKey) {
                return cachedData
            }

            guard let image = await Self.requestImage(for: asset, pixelLength: pixelLength),
                  let data = DepthAlbumThumbnailJPEGRenderer.data(from: image, pixelLength: pixelLength) else {
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

    func videoData(for asset: PHAsset, cacheKey: String, pixelLength: Int) async -> Data? {
        if let task = inFlight[cacheKey] {
            return await task.value
        }

        let task = Task<Data?, Never>.detached(priority: .utility) {
            if let cachedData = await DepthAlbumThumbnailDiskCache.shared.data(for: cacheKey) {
                return cachedData
            }

            guard let image = await Self.requestVideoImage(for: asset, pixelLength: pixelLength),
                  let data = DepthAlbumThumbnailJPEGRenderer.data(from: image, pixelLength: pixelLength) else {
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
                  let data = DepthAlbumThumbnailJPEGRenderer.data(from: image, pixelLength: pixelLength) else {
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

    private nonisolated static func requestImage(for asset: PHAsset, pixelLength: Int) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: pixelLength, height: pixelLength),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else {
                    return
                }

                if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                guard let image else {
                    if info?[PHImageResultIsDegradedKey] as? Bool != true {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                    return
                }

                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    private nonisolated static func requestVideoImage(for asset: PHAsset, pixelLength: Int) async -> UIImage? {
        guard let avAsset = await requestAVAsset(for: asset) else {
            return nil
        }
        return await image(from: avAsset, pixelLength: pixelLength)
    }

    private nonisolated static func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                guard !didResume else {
                    return
                }

                if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                guard let avAsset else {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                didResume = true
                continuation.resume(returning: avAsset)
            }
        }
    }

    private nonisolated static func image(from asset: AVAsset, pixelLength: Int) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let maximumPixelLength = CGFloat(max(pixelLength * 2, 1))
        generator.maximumSize = CGSize(width: maximumPixelLength, height: maximumPixelLength)
        let time = CMTime(seconds: 0.12, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                guard error == nil, let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(cgImage: cgImage))
            }
        }
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

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 700
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: imageCost(image))
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

actor DepthAlbumThumbnailDiskCache {
    static let shared = DepthAlbumThumbnailDiskCache()

    private let directoryURL: URL
    private let fileManager = FileManager.default
    private let storagePolicy = TAPLocalArtifactStoragePolicy.privatePhotoArtifact

    private init() {
        let rootURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directoryURL = rootURL.appendingPathComponent("DepthAlbumThumbnails", isDirectory: true)
    }

    func data(for key: String) -> Data? {
        ensureDirectoryExists()
        return try? Data(contentsOf: fileURL(for: key), options: .mappedIfSafe)
    }

    func store(_ data: Data, for key: String) {
        ensureDirectoryExists()
        try? storagePolicy.write(data, to: fileURL(for: key), fileManager: fileManager)
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("jpg")
    }

    private func ensureDirectoryExists() {
        try? storagePolicy.createDirectoryIfNeeded(at: directoryURL, fileManager: fileManager)
    }
}
