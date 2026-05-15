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

/// Browses pending TAP captures and the app-owned TAPCamDepth Photos album.
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
        .navigationTitle("TAP Library")
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
        .onReceive(NotificationCenter.default.publisher(for: .tapLibraryDidChange).receive(on: RunLoop.main)) { _ in
            viewModel.scheduleRefresh()
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
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No depth photos yet", systemImage: "photo.stack", description: Text("Capture a TAP depth photo first, then return here to analyze it."))
                    .frame(minHeight: 320)
            } else {
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(viewModel.items) { item in
                        NavigationLink {
                            switch item.source {
                            case .photos(let asset):
                                DepthAnalysisView(assetID: asset.localIdentifier)
                            case .ownedPhoto(_, let asset):
                                DepthAnalysisView(assetID: asset.localIdentifier)
                            case .pending(let record):
                                DepthAnalysisView(pendingCaptureID: record.captureID)
                            }
                        } label: {
                            TAPLibraryItemCell(
                                item: item,
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
    @Published private(set) var items: [TAPLibraryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func load(showLoadingIndicator: Bool = true) async {
        if showLoadingIndicator {
            isLoading = true
        }
        defer {
            if showLoadingIndicator {
                isLoading = false
            }
        }

        do {
            let pendingRecords = try await TAPPendingCaptureStore.shared.visiblePendingRecords()
            let exportedRecords = try await TAPPendingCaptureStore.shared.exportedRecords()
            let photoAssets: [PHAsset]
            let photoAssetsError: Error?
            do {
                photoAssets = try await PhotoLibraryWriter.depthAlbumAssets()
                photoAssetsError = nil
            } catch {
                photoAssets = []
                photoAssetsError = error
            }
            items = TAPLibraryItem.merged(
                pendingRecords: pendingRecords,
                exportedRecords: exportedRecords,
                photoAssets: photoAssets
            )
            errorMessage = photoAssetsError.flatMap { error in
                items.isEmpty ? error.localizedDescription : nil
            }
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.load(showLoadingIndicator: false)
        }
    }
}

struct TAPLibraryItem: Identifiable {
    enum Source {
        case pending(TAPPendingCaptureRecord)
        case ownedPhoto(TAPPendingCaptureRecord, PHAsset)
        case photos(PHAsset)
    }

    let id: String
    let source: Source
    let capturedAt: Date

    func thumbnailCacheKey(pixelLength: Int) -> String {
        switch source {
        case .photos(let asset):
            DepthAlbumThumbnailCacheKey.make(for: asset, pixelLength: pixelLength)
        case .ownedPhoto(let record, _):
            "owned|\(record.captureID)|\(pixelLength)"
        case .pending(let record):
            "pending|\(record.captureID)|\(pixelLength)"
        }
    }

    static func merged(
        pendingRecords: [TAPPendingCaptureRecord],
        exportedRecords: [TAPPendingCaptureRecord],
        photoAssets: [PHAsset]
    ) -> [TAPLibraryItem] {
        let pendingItems = pendingRecords
            .filter(\.isVisiblePendingItem)
            .map { record in
                TAPLibraryItem(
                    id: "pending:\(record.captureID)",
                    source: .pending(record),
                    capturedAt: record.capturedAt
                )
            }

        let ownedPhotoItems = exportedRecords.compactMap { record -> TAPLibraryItem? in
            guard let assetID = record.assetLocalIdentifier,
                  let asset = PhotoLibraryWriter.asset(localIdentifier: assetID) else {
                return nil
            }

            return TAPLibraryItem(
                id: "owned:\(asset.localIdentifier)",
                source: .ownedPhoto(record, asset),
                capturedAt: asset.creationDate ?? record.capturedAt
            )
        }
        let ownedAssetIDs = Set(ownedPhotoItems.compactMap(\.assetLocalIdentifier))

        let photoItems = photoAssets
            .filter { !ownedAssetIDs.contains($0.localIdentifier) }
            .map { asset in
                TAPLibraryItem(
                    id: "photos:\(asset.localIdentifier)",
                    source: .photos(asset),
                    capturedAt: asset.creationDate ?? .distantPast
                )
            }

        return (pendingItems + ownedPhotoItems + photoItems).sorted { $0.capturedAt > $1.capturedAt }
    }

    private var assetLocalIdentifier: String? {
        switch source {
        case .photos(let asset), .ownedPhoto(_, let asset):
            asset.localIdentifier
        case .pending:
            nil
        }
    }
}

private struct TAPLibraryItemCell: View {
    let item: TAPLibraryItem
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

            if let badge = item.pendingBadge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.yellow, in: Capsule())
                    .padding(5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var thumbnailTaskID: String {
        "\(item.id)|\(thumbnailPixelLength)"
    }

    private func loadThumbnail() async {
        let cacheKey = item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
        if let cachedThumbnail = DepthAlbumThumbnailMemoryCache.shared.image(for: cacheKey) {
            thumbnail = cachedThumbnail
            return
        }

        guard let data = await thumbnailData(cacheKey: cacheKey),
              !Task.isCancelled,
              let image = UIImage(data: data) else {
            return
        }

        DepthAlbumThumbnailMemoryCache.shared.insert(image, for: cacheKey)
        thumbnail = image
    }

    private func thumbnailData(cacheKey: String) async -> Data? {
        switch item.source {
        case .photos(let asset):
            return await DepthAlbumThumbnailLoader.shared.data(
                for: asset,
                cacheKey: cacheKey,
                pixelLength: thumbnailPixelLength
            )
        case .ownedPhoto(let record, let asset):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID) {
                return data
            }
            return await DepthAlbumThumbnailLoader.shared.data(
                for: asset,
                cacheKey: cacheKey,
                pixelLength: thumbnailPixelLength
            )
        case .pending(let record):
            return try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID)
        }
    }
}

private extension TAPLibraryItem {
    var pendingBadge: String? {
        guard case .pending(let record) = source else {
            return nil
        }

        switch record.status {
        case .pending:
            return "PENDING"
        case .waitingNetwork:
            return "WAIT"
        case .signing:
            return "SIGN"
        case .signed:
            return "SIGNED"
        case .exporting:
            return "SAVE"
        case .failedRetryable:
            return "RETRY"
        case .exported:
            return nil
        }
    }

    var accessibilityLabel: String {
        switch source {
        case .photos, .ownedPhoto:
            return "Open saved depth photo"
        case .pending(let record):
            return "Open pending depth photo, \(record.status.rawValue)"
        }
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
