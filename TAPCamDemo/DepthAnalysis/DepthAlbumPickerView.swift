//
//  DepthAlbumPickerView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Combine
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
                            DepthAnalysisView(assetID: asset.id)
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

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
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

        thumbnail = image
    }
}
