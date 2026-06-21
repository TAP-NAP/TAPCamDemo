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
    @State private var itemViewportYByID: [String: CGFloat] = [:]
    @State private var pendingReturnScrollBookmark: DepthAlbumReturnScrollBookmark?
    @State private var latestReturnScrollRowStride: CGFloat = 0
    @State private var selectedAnalysisRoute: DepthAlbumAnalysisRoute?
    @State private var isAnalysisPresented = false
    @State private var returnScrollRestoreToken = UUID()

    private static let columnCount = 5
    private static let gridSpacing: CGFloat = 3
    private static let gridPadding: CGFloat = 3
    private static let maximumThumbnailPixelLength = 320
    private static let scrollViewportCoordinateSpaceName = "DepthAlbumPickerScrollViewport"

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
            let containerWidth = geometry.size.width
            albumContent(
                thumbnailPixelLength: Self.thumbnailPixelLength(
                    containerWidth: containerWidth,
                    displayScale: displayScale
                ),
                returnScrollRowStride: Self.gridRowStride(containerWidth: containerWidth)
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
            await viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapLibraryDidChange).receive(on: RunLoop.main)) { _ in
            viewModel.scheduleRefresh()
        }
        .navigationDestination(isPresented: $isAnalysisPresented) {
            analysisDestination()
        }
        .onChange(of: isAnalysisPresented) { _, isPresented in
            handleAnalysisPresentationChange(isPresented: isPresented)
        }
    }

    @ViewBuilder
    private func albumContent(thumbnailPixelLength: Int, returnScrollRowStride: CGFloat) -> some View {
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
                        Button {
                            openAlbumItem(item, returnScrollRowStride: returnScrollRowStride)
                        } label: {
                            TAPLibraryItemCell(
                                item: item,
                                thumbnailPixelLength: thumbnailPixelLength
                            )
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.frame(in: .named(Self.scrollViewportCoordinateSpaceName)).minY
                        } action: { _, newViewportY in
                            itemViewportYByID[item.id] = newViewportY
                        }
                        .onAppear {
                            routeStore.recordVisibleDepthAlbumItem(item.routeAnchor)
                        }
                    }
                }
                .padding(Self.gridPadding)
            }
        }
        .scrollPosition($albumScrollPosition)
        .coordinateSpace(name: Self.scrollViewportCoordinateSpaceName)
        .onChange(of: viewModel.items.map(\.id)) { _, _ in
            pruneTrackedItemViewportPositions()
            restorePendingReturnScrollPosition(
                rowStride: returnScrollRowStride,
                clearAfterDelay: false
            )
        }
        .onAppear {
            restorePendingReturnScrollPosition(
                rowStride: returnScrollRowStride,
                clearAfterDelay: false
            )
        }
    }

    @ViewBuilder
    private func analysisDestination() -> some View {
        if let selectedAnalysisRoute {
            switch selectedAnalysisRoute.source {
            case .photosAsset(let assetID):
                DepthAnalysisView(assetID: assetID)
            case .pendingCapture(let captureID):
                DepthAnalysisView(pendingCaptureID: captureID)
            }
        } else {
            EmptyView()
        }
    }

    private func openAlbumItem(_ item: TAPLibraryItem, returnScrollRowStride: CGFloat) {
        latestReturnScrollRowStride = returnScrollRowStride
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: item.id,
            routeAnchor: item.routeAnchor,
            itemViewportY: itemViewportYByID[item.id] ?? 0
        )
        returnScrollRestoreToken = UUID()
        selectedAnalysisRoute = DepthAlbumAnalysisRoute(item: item)
        routeStore.openDepthAlbumItem(item.routeAnchor)
        isAnalysisPresented = true
    }

    private func handleAnalysisPresentationChange(isPresented: Bool) {
        guard !isPresented else {
            return
        }

        selectedAnalysisRoute = nil
        scheduleReturnScrollRestore(clearAfterDelay: true)
    }

    private func restorePendingReturnScrollPosition(rowStride: CGFloat, clearAfterDelay: Bool) {
        guard pendingReturnScrollBookmark != nil,
              !isAnalysisPresented else {
            return
        }

        scheduleReturnScrollRestore(
            rowStride: rowStride,
            clearAfterDelay: clearAfterDelay
        )
    }

    private func scheduleReturnScrollRestore(clearAfterDelay: Bool) {
        scheduleReturnScrollRestore(
            rowStride: latestReturnScrollRowStride,
            clearAfterDelay: clearAfterDelay
        )
    }

    private func scheduleReturnScrollRestore(rowStride: CGFloat, clearAfterDelay: Bool) {
        guard let bookmark = pendingReturnScrollBookmark else {
            return
        }

        let token = returnScrollRestoreToken
        Task { @MainActor in
            await Task.yield()
            guard pendingReturnScrollBookmark == bookmark,
                  returnScrollRestoreToken == token,
                  !isAnalysisPresented,
                  let offsetY = Self.returnScrollOffsetY(
                    bookmark: bookmark,
                    items: viewModel.items,
                    rowStride: rowStride
                  ) else {
                return
            }

            albumScrollPosition.scrollTo(y: offsetY)

            guard clearAfterDelay else {
                return
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            guard pendingReturnScrollBookmark == bookmark,
                  returnScrollRestoreToken == token,
                  !isAnalysisPresented else {
                return
            }
            pendingReturnScrollBookmark = nil
        }
    }

    private func pruneTrackedItemViewportPositions() {
        let currentItemIDs = Set(viewModel.items.map(\.id))
        itemViewportYByID = itemViewportYByID.filter { currentItemIDs.contains($0.key) }
    }

    static func returnScrollOffsetY(
        bookmark: DepthAlbumReturnScrollBookmark,
        items: [TAPLibraryItem],
        rowStride: CGFloat
    ) -> CGFloat? {
        guard let itemIndex = returnScrollBookmarkItemIndex(bookmark: bookmark, items: items) else {
            return nil
        }

        return returnScrollOffsetY(
            itemIndex: itemIndex,
            itemViewportY: bookmark.itemViewportY,
            rowStride: rowStride
        )
    }

    static func returnScrollBookmarkItemIndex(
        bookmark: DepthAlbumReturnScrollBookmark,
        items: [TAPLibraryItem]
    ) -> Int? {
        if let exactIndex = items.firstIndex(where: { $0.id == bookmark.itemID }) {
            return exactIndex
        }

        return items.firstIndex { item in
            routeAnchorsMatch(item.routeAnchor, bookmark.routeAnchor)
        }
    }

    static func returnScrollOffsetY(itemIndex: Int, itemViewportY: CGFloat, rowStride: CGFloat) -> CGFloat {
        let rowIndex = max(0, itemIndex) / columnCount
        let itemContentY = gridPadding + (CGFloat(rowIndex) * max(rowStride, 0))
        return max(0, itemContentY - itemViewportY)
    }

    private static func routeAnchorsMatch(
        _ currentAnchor: CameraRouteAlbumAnchor,
        _ bookmarkedAnchor: CameraRouteAlbumAnchor
    ) -> Bool {
        if currentAnchor.itemID == bookmarkedAnchor.itemID {
            return true
        }

        if let currentCaptureID = currentAnchor.captureID,
           let bookmarkedCaptureID = bookmarkedAnchor.captureID,
           currentCaptureID == bookmarkedCaptureID {
            return true
        }

        if let currentAssetID = currentAnchor.assetLocalIdentifier,
           let bookmarkedAssetID = bookmarkedAnchor.assetLocalIdentifier,
           currentAssetID == bookmarkedAssetID {
            return true
        }

        return false
    }

    private static func gridRowStride(containerWidth: CGFloat) -> CGFloat {
        gridCellPointLength(containerWidth: containerWidth) + gridSpacing
    }

    private static func gridCellPointLength(containerWidth: CGFloat) -> CGFloat {
        let spacingWidth = gridSpacing * CGFloat(columnCount - 1)
        let availableGridWidth = max(containerWidth - (gridPadding * 2) - spacingWidth, 1)
        return max(availableGridWidth / CGFloat(columnCount), 1)
    }

    private static func thumbnailPixelLength(containerWidth: CGFloat, displayScale: CGFloat) -> Int {
        let cellPointLength = gridCellPointLength(containerWidth: containerWidth)
        let targetPixelLength = Int(ceil(cellPointLength * displayScale))
        return min(max(targetPixelLength, 1), maximumThumbnailPixelLength)
    }
}

nonisolated struct DepthAlbumReturnScrollBookmark: Equatable, Sendable {
    let itemID: String
    let routeAnchor: CameraRouteAlbumAnchor
    let itemViewportY: CGFloat
}

private struct DepthAlbumAnalysisRoute: Hashable {
    let itemID: String
    let source: DepthAnalysisSource

    init(item: TAPLibraryItem) {
        itemID = item.id
        switch item.source {
        case .photos(let asset), .ownedPhoto(_, let asset):
            source = .photosAsset(asset.localIdentifier)
        case .pending(let record):
            source = .pendingCapture(record.captureID)
        }
    }
}

@MainActor
final class DepthAlbumPickerViewModel: ObservableObject {
    @Published private(set) var items: [TAPLibraryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let itemProvider: DepthAlbumItemProvider
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedSnapshot = false

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
            hasLoadedSnapshot = true
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

    func loadIfNeeded() async {
        guard !hasLoadedSnapshot,
              !isLoading else {
            return
        }

        await load()
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
