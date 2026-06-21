//
//  DepthAlbumPickerView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Combine
import SwiftUI
import UIKit

/// Browses pending TAP captures and the app-owned TAPCamDepth Photos album.
///
/// This keeps the camera surface clean: the lower-left camera control opens the
/// album, and only this saved-image flow exposes selection and analysis tools.
struct DepthAlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var routeStore: CameraRouteStore
    @StateObject private var viewModel = DepthAlbumPickerViewModel()
    @State private var albumScrollPosition = ScrollPosition(idType: String.self)
    @State private var latestObservedScrollOffsetY: CGFloat = 0
    @State private var pendingReturnScrollOffsetY: CGFloat?
    @State private var didApplyInitialAnchorRestore = false

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

    init(routeStore: CameraRouteStore) {
        self.routeStore = routeStore
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
                    routeStore.returnToCamera()
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
        ScrollViewReader { scrollProxy in
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
                            .id(item.id)
                            .simultaneousGesture(TapGesture().onEnded {
                                openAlbumItem(item)
                            })
                            .onAppear {
                                routeStore.recordVisibleDepthAlbumItem(item.routeAnchor)
                            }
                        }
                    }
                    .padding(Self.gridPadding)
                }
            }
            .scrollPosition($albumScrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y)
            } action: { _, newOffsetY in
                latestObservedScrollOffsetY = newOffsetY
            }
            .onChange(of: viewModel.items.map(\.id)) { _, _ in
                restoreAlbumScrollPosition(scrollProxy)
            }
            .onAppear {
                restoreAlbumScrollPosition(scrollProxy)
            }
        }
    }

    private func openAlbumItem(_ item: TAPLibraryItem) {
        pendingReturnScrollOffsetY = latestObservedScrollOffsetY
        routeStore.openDepthAlbumItem(item.routeAnchor)
    }

    private func restoreAlbumScrollPosition(_ scrollProxy: ScrollViewProxy) {
        if restorePendingReturnScrollPosition() {
            return
        }

        guard !didApplyInitialAnchorRestore else {
            return
        }

        guard let anchorID = routeStore.validDepthAlbumRestoreAnchorID(
            availableItems: viewModel.items.map(\.routeAnchor)
        ) else {
            return
        }

        didApplyInitialAnchorRestore = true
        scrollProxy.scrollTo(anchorID, anchor: .center)
    }

    private func restorePendingReturnScrollPosition() -> Bool {
        guard let offsetY = pendingReturnScrollOffsetY else {
            return false
        }

        didApplyInitialAnchorRestore = true
        pendingReturnScrollOffsetY = nil
        albumScrollPosition.scrollTo(y: offsetY)
        return true
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

    private let itemProvider: DepthAlbumItemProvider
    private var refreshTask: Task<Void, Never>?

    init(itemProvider: DepthAlbumItemProvider? = nil) {
        self.itemProvider = itemProvider ?? DepthAlbumItemProvider()
    }

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
            let snapshot = try await itemProvider.loadSnapshot()
            items = snapshot.items
            errorMessage = snapshot.photoAssetsError.flatMap { error in
                items.isEmpty ? DepthAnalysisErrorPresentation.emptyAlbumPhotosErrorMessage(for: error) : nil
            }
        } catch {
            items = []
            errorMessage = DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
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
            guard let phAsset = asset.phAsset else {
                return nil
            }
            return await DepthAlbumThumbnailLoader.shared.data(
                for: phAsset,
                cacheKey: cacheKey,
                pixelLength: thumbnailPixelLength
            )
        case .ownedPhoto(let record, let asset):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID) {
                return data
            }
            guard let phAsset = asset.phAsset else {
                return nil
            }
            return await DepthAlbumThumbnailLoader.shared.data(
                for: phAsset,
                cacheKey: cacheKey,
                pixelLength: thumbnailPixelLength
            )
        case .pending(let record):
            return try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID)
        }
    }
}
