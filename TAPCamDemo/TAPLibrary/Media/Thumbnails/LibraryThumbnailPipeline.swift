//
//  LibraryThumbnailPipeline.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import ImageIO
import Photos
import UIKit

/// In-memory revision keys for private thumbnails and PhotoKit presentation identity.
nonisolated enum LibraryThumbnailCacheKey {
    private static let version = "library-poster-v6"

    static func make(mediaID: LibraryMediaID, version mediaVersion: String, pixelLength: Int) -> String {
        [
            version,
            mediaID.storageValue,
            mediaVersion,
            "\(pixelLength)px"
        ].joined(separator: "|")
    }

    static func make(
        assetLocalIdentifier: String,
        pixelLength: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        versionDate: Date
    ) -> String {
        [
            version,
            "photos",
            assetLocalIdentifier,
            "\(pixelLength)px",
            "\(pixelWidth)x\(pixelHeight)",
            String(versionDate.timeIntervalSince1970)
        ].joined(separator: "|")
    }

    static func makePending(
        captureID: String,
        pixelLength: Int,
        capturedAt: Date,
        thumbnailFilename: String?,
        videoFilename: String? = nil,
        updatedAt: Date? = nil
    ) -> String {
        [
            version,
            "pending",
            captureID,
            "\(pixelLength)px",
            String(capturedAt.timeIntervalSince1970),
            thumbnailFilename ?? "no-thumbnail",
            videoFilename ?? "no-video",
            String((updatedAt ?? capturedAt).timeIntervalSince1970)
        ].joined(separator: "|")
    }
}

actor LibraryThumbnailLoader {
    static let shared = LibraryThumbnailLoader()

    private var inFlight: [String: Task<Data?, Never>] = [:]

    func videoData(for fileURL: URL, cacheKey: String, pixelLength: Int) async -> Data? {
        if let task = inFlight[cacheKey] {
            return await task.value
        }

        let task = Task<Data?, Never>.detached(priority: .utility) {
            let asset = AVURLAsset(url: fileURL)
            guard let image = await Self.image(from: asset, pixelLength: pixelLength),
                  let data = LibraryThumbnailJPEGRenderer.aspectPreservingData(
                    from: image,
                    maximumPixelLength: pixelLength
                  ) else {
                return nil
            }

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

/// Coalesces private Pending/video thumbnail decoding off the MainActor.
/// Photos images arrive ready for presentation and do not pass through here.
actor LibraryThumbnailDecoder {
    typealias Decode = @Sendable (Data) -> UIImage?

    static let shared = LibraryThumbnailDecoder()

    private struct InFlight {
        let token: UInt64
        let task: Task<UIImage?, Never>
    }

    private var inFlightByCacheKey: [String: InFlight] = [:]
    private var nextToken: UInt64 = 0
    private let decode: Decode

    init(decode: @escaping Decode = LibraryThumbnailDecoder.decodeForDisplay) {
        self.decode = decode
    }

    func decodedThumbnail(data: Data, cacheKey: String) async -> MediaPoster? {
        guard !Task.isCancelled else { return nil }
        if let cached = await MainActor.run(body: {
            LibraryThumbnailMemoryCache.shared.poster(for: cacheKey)
        }) {
            return Task.isCancelled ? nil : cached
        }

        let inFlight: InFlight
        if let existing = inFlightByCacheKey[cacheKey] {
            inFlight = existing
        } else {
            nextToken &+= 1
            let decode = self.decode
            inFlight = InFlight(
                token: nextToken,
                task: Task.detached(priority: .utility) { decode(data) }
            )
            inFlightByCacheKey[cacheKey] = inFlight
        }

        let image = await inFlight.task.value
        let poster = image.map { MediaPoster(cacheKey: cacheKey, image: $0) }
        if let poster {
            await MainActor.run { LibraryThumbnailMemoryCache.shared.insert(poster) }
        }
        if inFlightByCacheKey[cacheKey]?.token == inFlight.token {
            inFlightByCacheKey[cacheKey] = nil
        }
        return Task.isCancelled ? nil : poster
    }

    /// For short-lived viewer previews that do not need a second cache key.
    nonisolated static func image(data: Data) async -> UIImage? {
        let image = await Task.detached(priority: .utility) {
            decodeForDisplay(data)
        }.value
        return Task.isCancelled ? nil : image
    }

    private nonisolated static func decodeForDisplay(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            return nil
        }
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 1
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 1
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(max(pixelWidth, pixelHeight), 1)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

/// PhotoKit may omit its result callback after cancellation. The shared
/// lifecycle owns continuation, request-ID, and terminal-delivery races while
/// this bridge only interprets poster callbacks and retains a degraded preview.
nonisolated final class PhotoKitThumbnailRequestBridge: @unchecked Sendable {
    private let cacheKey: String
    private let acceptsDegradedResult: Bool
    private let lifecycle: PhotoKitRequestLifecycle<PHImageRequestID, MediaFetchPhase<MediaPoster, MediaPoster>>
    /// Accessed only from closures serialized by `lifecycle`.
    private var preview: MediaPoster?

    init(
        cacheKey: String,
        acceptsDegradedResult: Bool = false,
        cancelRequest: @escaping @Sendable (PHImageRequestID) -> Void
    ) {
        self.cacheKey = cacheKey
        self.acceptsDegradedResult = acceptsDegradedResult
        lifecycle = PhotoKitRequestLifecycle(cancelRequest: cancelRequest)
    }

    @discardableResult
    func install(
        continuation: CheckedContinuation<MediaFetchPhase<MediaPoster, MediaPoster>, Error>
    ) -> Bool {
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
        let poster = image.map { MediaPoster(cacheKey: cacheKey, image: $0) }
        let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool == true
        let isCloudOnly = info?[PHImageResultIsInCloudKey] as? Bool == true
        if isDegraded, !acceptsDegradedResult {
            if let poster {
                lifecycle.process({ preview = poster }, mapError: { $0 })
            }
            return
        }
        if let poster {
            // fastFormat has exactly one callback, even when degraded.
            lifecycle.finish {
                if isDegraded {
                    return isCloudOnly ? .cloudOnly(poster) : .localPreview(poster)
                }
                return .ready(poster)
            }
        } else if isCloudOnly {
            lifecycle.finish { .cloudOnly(preview) }
        } else {
            lifecycle.finish(.failure(MediaFetchFailure.decode))
        }
    }

    func cancel() {
        lifecycle.cancel()
    }
}

nonisolated enum LibraryThumbnailJPEGRenderer {
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
final class LibraryThumbnailMemoryCache {
    static let shared = LibraryThumbnailMemoryCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func poster(for key: String) -> MediaPoster? {
        cache.object(forKey: key as NSString).map { MediaPoster(cacheKey: key, image: $0) }
    }

    func insert(_ poster: MediaPoster) {
        let image = poster.image
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: poster.cacheKey as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
