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

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 3)
    ]

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
    let creationDate: Date?

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
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

            if let creationDate = asset.creationDate {
                Text(creationDate.formatted(date: .numeric, time: .shortened))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
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
        let image = await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset.asset,
                targetSize: CGSize(width: 260, height: 260),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }

        thumbnail = image
    }
}
