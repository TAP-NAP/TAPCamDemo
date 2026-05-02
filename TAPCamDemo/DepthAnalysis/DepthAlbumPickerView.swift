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
    @StateObject private var viewModel = DepthAlbumPickerViewModel()
    @ObservedObject private var appAttestController: AppAttestRuntimeController

    init(appAttestController: AppAttestRuntimeController) {
        self.appAttestController = appAttestController
    }

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 3),
        count: 5
    )

    var body: some View {
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
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(viewModel.assets) { asset in
                        NavigationLink {
                            DepthAnalysisView(
                                assetID: asset.id,
                                appAttestController: appAttestController
                            )
                        } label: {
                            DepthAlbumAssetCell(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
            }
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

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.load()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload album")
            }
        }
        .task {
            await viewModel.load()
        }
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
    let thumbnailCacheKey: String

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.thumbnailCacheKey = DepthAlbumThumbnailCacheKey.make(for: asset)
    }
}

private struct DepthAlbumAssetCell: View {
    let asset: DepthAlbumAsset
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
        .task(id: asset.id) {
            await loadThumbnail()
        }
        .accessibilityLabel("Open depth photo")
    }

    private func loadThumbnail() async {
        if let cachedThumbnail = DepthAlbumThumbnailMemoryCache.shared.image(for: asset.thumbnailCacheKey) {
            thumbnail = cachedThumbnail
            return
        }

        if let cachedData = await DepthAlbumThumbnailDiskCache.shared.data(for: asset.thumbnailCacheKey),
           let cachedThumbnail = UIImage(data: cachedData) {
            DepthAlbumThumbnailMemoryCache.shared.insert(cachedThumbnail, for: asset.thumbnailCacheKey)
            thumbnail = cachedThumbnail
            return
        }

        let image: UIImage? = await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset.asset,
                targetSize: CGSize(width: 720, height: 720),
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

                guard info?[PHImageResultIsDegradedKey] as? Bool != true else {
                    return
                }

                didResume = true
                continuation.resume(returning: image)
            }
        }

        guard !Task.isCancelled, let image else {
            return
        }

        DepthAlbumThumbnailMemoryCache.shared.insert(image, for: asset.thumbnailCacheKey)
        thumbnail = image

        if let data = image.jpegData(compressionQuality: 0.88) {
            await DepthAlbumThumbnailDiskCache.shared.store(data, for: asset.thumbnailCacheKey)
        }
    }
}

private enum DepthAlbumThumbnailCacheKey {
    static func make(for asset: PHAsset) -> String {
        let versionDate = asset.modificationDate ?? asset.creationDate ?? .distantPast
        let source = [
            asset.localIdentifier,
            "\(asset.pixelWidth)x\(asset.pixelHeight)",
            String(versionDate.timeIntervalSince1970)
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
