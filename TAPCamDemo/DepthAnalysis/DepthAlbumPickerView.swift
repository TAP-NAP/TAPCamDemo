//
//  DepthAlbumPickerView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Combine
import CryptoKit
import Photos
import SwiftUI
import UIKit

/// Browses the app-owned TAPCamDepth Photos album before analysis starts.
///
/// This keeps the camera surface clean: the lower-left camera control opens the
/// album, and only this saved-image flow exposes selection and analysis tools.
struct DepthAlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @StateObject private var viewModel = DepthAlbumPickerViewModel()

    private static let columnCount = 5
    private static let gridSpacing: CGFloat = 3
    private static let gridPadding: CGFloat = 3
    private static let maximumThumbnailPixelLength = 320

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: Self.gridSpacing),
            count: Self.columnCount
        )
    }

    var body: some View {
        GeometryReader { geometry in
            albumContent(
                thumbnailPixelLength: Self.thumbnailPixelLength(
                    containerWidth: geometry.size.width,
                    displayScale: displayScale
                )
            )
        }
        .navigationTitle(PhotoLibraryWriter.albumName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Camera", systemImage: "chevron.left")
                }
                .accessibilityLabel("Return to camera")
                .help("Close the analyzer and return to the camera.")
            }
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func albumContent(thumbnailPixelLength: Int) -> some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView("Loading TAPCamDepth...")
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView("Unable to load album", systemImage: "photo.on.rectangle.angled", description: Text(errorMessage))
                    .frame(minHeight: 320)
            } else if viewModel.assets.isEmpty {
                ContentUnavailableView("No depth photos yet", systemImage: "photo.stack", description: Text("Capture a TAP depth photo first, then return here to analyze it."))
                    .frame(minHeight: 320)
            } else {
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(viewModel.assets) { asset in
                        NavigationLink {
                            DepthAnalysisView(assetID: asset.id)
                        } label: {
                            DepthAlbumAssetCell(
                                asset: asset,
                                thumbnailPixelLength: thumbnailPixelLength
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Self.gridPadding)
            }
        }
    }

    private static func thumbnailPixelLength(containerWidth: CGFloat, displayScale: CGFloat) -> Int {
        let spacingWidth = gridSpacing * CGFloat(columnCount - 1)
        let availableGridWidth = max(containerWidth - (gridPadding * 2) - spacingWidth, 1)
        let cellPointLength = max(availableGridWidth / CGFloat(columnCount), 1)
        let targetPixelLength = Int(ceil(cellPointLength * displayScale))
        return min(max(targetPixelLength, 1), maximumThumbnailPixelLength)
    }
}

@MainActor
final class DepthAlbumPickerViewModel: ObservableObject {
    @Published private(set) var assets: [DepthAlbumAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            assets = try await PhotoLibraryWriter.depthAlbumAssets().map(DepthAlbumAsset.init(asset:))
            errorMessage = nil
        } catch {
            assets = []
            errorMessage = error.localizedDescription
        }
    }
}

struct DepthAlbumAsset: Identifiable, Equatable {
    let id: String
    let asset: PHAsset

    func thumbnailCacheKey(pixelLength: Int) -> String {
        DepthAlbumThumbnailCacheKey.make(for: asset, pixelLength: pixelLength)
    }

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
    }
}

private struct DepthAlbumAssetCell: View {
    let asset: DepthAlbumAsset
    let thumbnailPixelLength: Int
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color(uiColor: .secondarySystemBackground))
                .aspectRatio(1, contentMode: .fit)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
        .accessibilityLabel("Open depth photo")
    }

    private var thumbnailTaskID: String {
        "\(asset.id)|\(thumbnailPixelLength)"
    }

    private func loadThumbnail() async {
        let cacheKey = asset.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
        if let cachedThumbnail = DepthAlbumThumbnailMemoryCache.shared.image(for: cacheKey) {
            thumbnail = cachedThumbnail
            return
        }

        guard let data = await DepthAlbumThumbnailLoader.shared.data(
            for: asset.asset,
            cacheKey: cacheKey,
            pixelLength: thumbnailPixelLength
        ),
              !Task.isCancelled,
              let image = UIImage(data: data) else {
            return
        }

        DepthAlbumThumbnailMemoryCache.shared.insert(image, for: cacheKey)
        thumbnail = image
    }
}

private enum DepthAlbumThumbnailCacheKey {
    private static let version = "grid-v3-opaque-jpeg"

    static func make(for asset: PHAsset, pixelLength: Int) -> String {
        let versionDate = asset.modificationDate ?? asset.creationDate ?? .distantPast
        let source = [
            version,
            asset.localIdentifier,
            "\(pixelLength)px",
            "\(asset.pixelWidth)x\(asset.pixelHeight)",
            String(versionDate.timeIntervalSince1970)
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private actor DepthAlbumThumbnailLoader {
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
}

nonisolated private enum DepthAlbumThumbnailJPEGRenderer {
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
private final class DepthAlbumThumbnailMemoryCache {
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

private actor DepthAlbumThumbnailDiskCache {
    static let shared = DepthAlbumThumbnailDiskCache()

    private let directoryURL: URL
    private let fileManager = FileManager.default

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
        try? data.write(to: fileURL(for: key), options: [.atomic])
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("jpg")
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
