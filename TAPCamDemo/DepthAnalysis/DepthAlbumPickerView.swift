//
//  DepthAlbumPickerView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Combine
import OSLog
import SwiftUI
import UIKit

/// Browses pending TAP captures and the app-owned TAPCamDepth Photos album.
///
/// This keeps the camera surface clean: the lower-left camera control opens the
/// album, and only this saved-image flow exposes selection and analysis tools.
struct DepthAlbumPickerView: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var routeStore: CameraRouteStore
    @StateObject private var viewModel: DepthAlbumPickerViewModel
    private let libraryStore: LibraryMediaStore
    private let mediaFetcher: any LibraryMediaFetching
    @State private var albumScrollPosition = ScrollPosition(idType: String.self)
    @State private var itemViewportYByID: [String: CGFloat] = [:]
    @State private var pendingReturnScrollBookmark: DepthAlbumReturnScrollBookmark?
    @State private var latestReturnScrollRowStride: CGFloat = 0
    @State private var selectedAnalysisRoute: DepthAlbumAnalysisRoute?
    @State private var selectedVideoRoute: TAPVideoPlaybackRoute?
    @State private var isAnalysisPresented = false
    @State private var isVideoPresented = false
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

    init(
        routeStore: CameraRouteStore,
        libraryStore: LibraryMediaStore? = nil,
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()
    ) {
        self.routeStore = routeStore
        self.mediaFetcher = mediaFetcher
        let resolvedLibraryStore = libraryStore ?? LibraryMediaStore(observesChanges: false)
        self.libraryStore = resolvedLibraryStore
        _viewModel = StateObject(
            wrappedValue: DepthAlbumPickerViewModel(libraryStore: resolvedLibraryStore)
        )
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
                    returnToCameraWithoutAnimation()
                } label: {
                    Label("Camera", systemImage: "chevron.left")
                }
                .accessibilityLabel("Return to camera")
                .help("Close the analyzer and return to the camera.")
            }
        }
        .task(id: routeStore.isDepthAlbumPresented) {
            guard routeStore.isDepthAlbumPresented else {
                return
            }
            let lockedImportReason = routeStore.consumePendingLockedImportReason()
            await viewModel.loadForPresentation(lockedImportReason: lockedImportReason)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapCamLockedCaptureImportDidAddPendingCaptures).receive(on: RunLoop.main)) { _ in
            routeStore.finishAwaitingLockedCaptureImport()
            viewModel.scheduleRefresh()
        }
        .navigationDestination(isPresented: $isAnalysisPresented) {
            analysisDestination()
        }
        .navigationDestination(isPresented: $isVideoPresented) {
            videoDestination()
        }
        .onChange(of: isAnalysisPresented) { _, isPresented in
            handleAnalysisPresentationChange(isPresented: isPresented)
        }
        .onChange(of: isVideoPresented) { _, isPresented in
            handleVideoPresentationChange(isPresented: isPresented)
        }
        .modifier(DepthAlbumEdgeBackModifier(onReturn: returnToCameraWithoutAnimation))
    }

    @ViewBuilder
    private func albumContent(thumbnailPixelLength: Int, returnScrollRowStride: CGFloat) -> some View {
        ScrollView {
            if routeStore.isAwaitingLockedCaptureImport {
                lockedImportWaitingBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            if viewModel.shouldShowLoading {
                ProgressView(viewModel.loadingMessage)
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView("Unable to load album", systemImage: "photo.on.rectangle.angled", description: Text(errorMessage))
                    .frame(minHeight: 320)
            } else if libraryStore.items.isEmpty {
                ContentUnavailableView("No depth photos yet", systemImage: "photo.stack", description: Text("Capture a TAP depth photo first, then return here to analyze it."))
                    .frame(minHeight: 320)
            } else {
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(libraryStore.items) { item in
                        Button {
                            openAlbumItem(item, returnScrollRowStride: returnScrollRowStride)
                        } label: {
                            TAPLibraryItemCell(
                                item: item,
                                thumbnailPixelLength: thumbnailPixelLength,
                                mediaFetcher: mediaFetcher
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
        .onChange(of: libraryStore.items.map(\.id)) { _, _ in
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

    private var lockedImportWaitingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for locked captures")
                    .font(.footnote.weight(.semibold))
                Text("TAP Library will refresh when iOS finishes the transfer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func returnToCameraWithoutAnimation() {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            routeStore.returnToCamera()
        }
    }

    @ViewBuilder
    private func analysisDestination() -> some View {
        if let selectedAnalysisRoute {
            DepthAnalysisView(
                source: selectedAnalysisRoute.source,
                albumContext: DepthAnalysisAlbumContext(
                    currentItemID: selectedAnalysisRoute.itemID,
                    items: libraryStore.items
                ),
                onCurrentAlbumEntryChanged: { entry in
                    updatePresentedAnalysisRoute(entry)
                },
                mediaFetcher: mediaFetcher
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func videoDestination() -> some View {
        if let selectedVideoRoute {
            TAPVideoDepthPlaybackView(
                source: selectedVideoRoute.source,
                albumContext: TAPVideoAlbumContext(
                    currentItemID: selectedVideoRoute.itemID,
                    items: libraryStore.items
                ),
                onCurrentAlbumEntryChanged: { entry in
                    updatePresentedVideoRoute(entry)
                },
                mediaFetcher: mediaFetcher
            )
            .id(selectedVideoRoute.itemID)
        } else {
            EmptyView()
        }
    }

    private func updatePresentedAnalysisRoute(_ entry: DepthAnalysisAlbumContext.Entry) {
        selectedAnalysisRoute = DepthAlbumAnalysisRoute(entry: entry)
        routeStore.openDepthAlbumItem(entry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: entry.id,
            routeAnchor: entry.routeAnchor,
            itemViewportY: itemViewportYByID[entry.id] ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func updatePresentedVideoRoute(_ entry: TAPVideoAlbumContext.Entry) {
        selectedVideoRoute = TAPVideoPlaybackRoute(entry: entry)
        routeStore.openDepthAlbumItem(entry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: entry.id,
            routeAnchor: entry.routeAnchor,
            itemViewportY: itemViewportYByID[entry.id] ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func openAlbumItem(_ item: TAPLibraryItem, returnScrollRowStride: CGFloat) {
        latestReturnScrollRowStride = returnScrollRowStride
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: item.id,
            routeAnchor: item.routeAnchor,
            itemViewportY: itemViewportYByID[item.id] ?? 0
        )
        returnScrollRestoreToken = UUID()
        routeStore.openDepthAlbumItem(item.routeAnchor)
        if item.isVideo,
           let videoRoute = TAPVideoPlaybackRoute(item: item) {
            selectedVideoRoute = videoRoute
            isVideoPresented = true
        } else {
            selectedAnalysisRoute = DepthAlbumAnalysisRoute(item: item)
            isAnalysisPresented = true
        }
    }

    private func handleAnalysisPresentationChange(isPresented: Bool) {
        guard !isPresented else {
            return
        }

        selectedAnalysisRoute = nil
        scheduleReturnScrollRestore(clearAfterDelay: true)
    }

    private func handleVideoPresentationChange(isPresented: Bool) {
        guard !isPresented else {
            return
        }

        selectedVideoRoute = nil
        scheduleReturnScrollRestore(clearAfterDelay: true)
    }

    private func restorePendingReturnScrollPosition(rowStride: CGFloat, clearAfterDelay: Bool) {
        guard pendingReturnScrollBookmark != nil,
              !isAnalysisPresented,
              !isVideoPresented else {
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
                  !isVideoPresented,
                  let offsetY = Self.returnScrollOffsetY(
                    bookmark: bookmark,
                    items: libraryStore.items,
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
                  !isAnalysisPresented,
                  !isVideoPresented else {
                return
            }
            pendingReturnScrollBookmark = nil
        }
    }

    private func pruneTrackedItemViewportPositions() {
        let currentItemIDs = Set(libraryStore.items.map(\.id))
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

private struct DepthAlbumEdgeBackModifier: ViewModifier {
    let onReturn: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(edgeBackGesture(), including: .gesture)
    }

    private func edgeBackGesture() -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard value.startLocation.x <= AnalysisEdgeBackPolicy.edgeActivationWidth else {
                    return
                }
            }
            .onEnded { value in
                guard AnalysisEdgeBackPolicy.shouldReturn(
                    startX: value.startLocation.x,
                    translation: value.translation,
                    predictedTranslation: value.predictedEndTranslation
                ) else {
                    return
                }
                onReturn()
            }
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

    init(entry: DepthAnalysisAlbumContext.Entry) {
        itemID = entry.id
        source = entry.source
    }

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
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = "Loading TAP Library..."
    @Published private(set) var errorMessage: String?

    private let libraryStore: LibraryMediaStore
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedSnapshot = false

    var items: [TAPLibraryItem] {
        libraryStore.items
    }

    var shouldShowLoading: Bool {
        isLoading || !hasLoadedSnapshot
    }

    init(
        itemProvider: DepthAlbumItemProvider? = nil,
        libraryStore: LibraryMediaStore? = nil
    ) {
        self.libraryStore = libraryStore ?? LibraryMediaStore(
            itemProvider: itemProvider,
            observesChanges: false
        )
    }

    deinit {
        refreshTask?.cancel()
    }

    func load(
        showLoadingIndicator: Bool = true,
        lockedImportReason: String? = nil
    ) async {
        LockedCameraDiagnostics.logger.info(
            "tap_library_load_begin showLoading=\(showLoadingIndicator, privacy: .public) lockedImportReason=\(lockedImportReason ?? "none", privacy: .public)"
        )
        if showLoadingIndicator {
            loadingMessage = lockedImportReason == nil
                ? "Loading TAP Library..."
                : "Importing locked captures..."
            isLoading = true
        }
        defer {
            hasLoadedSnapshot = true
            if showLoadingIndicator {
                isLoading = false
                loadingMessage = "Loading TAP Library..."
            }
        }

        do {
            if let lockedImportReason {
                let summary = await LockedCaptureSessionContentImportCoordinator.shared
                    .importAvailableSessionContentAfterSessionContentSettles(reason: lockedImportReason)
                LockedCameraDiagnostics.logger.info(
                    "tap_library_locked_import_before_snapshot reason=\(lockedImportReason, privacy: .public) sessions=\(summary.scannedSessionCount, privacy: .public) found=\(summary.foundCaptureCount, privacy: .public) imported=\(summary.importedCount, privacy: .public) skipped=\(summary.skippedCount, privacy: .public) failed=\(summary.failedCount, privacy: .public) invalidated=\(summary.invalidatedSessionCount, privacy: .public)"
                )
            }
            if showLoadingIndicator, lockedImportReason != nil {
                loadingMessage = "Loading TAP Library..."
            }
            let snapshot = await libraryStore.refresh()
            if let loadError = libraryStore.loadError {
                throw loadError
            }
            errorMessage = snapshot?.photoAssetsError.flatMap { error in
                items.isEmpty ? DepthAnalysisErrorPresentation.emptyAlbumPhotosErrorMessage(for: error) : nil
            }
            LockedCameraDiagnostics.logger.info(
                "tap_library_load_finish itemCount=\(self.items.count, privacy: .public) itemSources=\(Self.itemSourceCountsDescription(self.items), privacy: .public) photoAssetsErrorPresent=\(snapshot?.photoAssetsError != nil, privacy: .public)"
            )
        } catch {
            errorMessage = DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
            LockedCameraDiagnostics.logger.error(
                "tap_library_load_failed error=\(Self.describe(error), privacy: .public)"
            )
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedSnapshot,
              !isLoading else {
            return
        }

        await load()
    }

    func loadForPresentation(lockedImportReason: String? = nil) async {
        await load(lockedImportReason: lockedImportReason)
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        LockedCameraDiagnostics.logger.info("tap_library_refresh_scheduled")
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.load(showLoadingIndicator: false)
        }
    }

    private static func itemSourceCountsDescription(_ items: [TAPLibraryItem]) -> String {
        var pendingCount = 0
        var ownedPhotoCount = 0
        var photosCount = 0
        for item in items {
            switch item.source {
            case .pending:
                pendingCount += 1
            case .ownedPhoto:
                ownedPhotoCount += 1
            case .photos:
                photosCount += 1
            }
        }
        return "pending:\(pendingCount)|owned:\(ownedPhotoCount)|photos:\(photosCount)"
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }
}

private struct TAPLibraryItemCell: View {
    let item: TAPLibraryItem
    let thumbnailPixelLength: Int
    let mediaFetcher: any LibraryMediaFetching
    @State private var fetchPhase: MediaFetchPhase<MediaPoster, MediaPoster> = .idle(nil)

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(uiColor: .secondarySystemBackground))
                .aspectRatio(1, contentMode: .fit)

            if let posterImage = displayedPoster?.image {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Image(systemName: item.isVideo ? "video" : "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if item.isLivePhoto {
                VStack {
                    HStack {
                        Spacer()
                        DepthAnalysisLivePhotoBadge(size: .thumbnail)
                    }
                    Spacer()
                }
                .padding(5)
                .allowsHitTesting(false)
            }

            if item.isVideo {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "video.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 18)
                            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer()
                }
                .padding(5)
                .allowsHitTesting(false)
            }

            if isCloudOnly {
                VStack {
                    HStack {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 18)
                            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .accessibilityLabel(LibraryMediaCopy.storedInICloud)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(5)
                .allowsHitTesting(false)
            } else if isResolving {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .allowsHitTesting(false)
            } else if hasFailure {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 18)
                            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(5)
                .allowsHitTesting(false)
            }

            if let badge = item.pendingBadge {
                VStack {
                    Spacer()
                    HStack {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.yellow, in: Capsule())
                        Spacer()
                    }
                }
                .padding(5)
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(isCloudOnly ? LibraryMediaCopy.storedInICloud : "")
    }

    private var thumbnailTaskID: String {
        // Stable media identity deliberately survives pending -> exported. The
        // revision-bearing cache key still changes when the poster/source does.
        item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
    }

    private func loadThumbnail() async {
        let cacheKey = item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
        fetchPhase = .resolving(nil)
        if let cachedPoster = DepthAlbumThumbnailMemoryCache.shared.poster(for: cacheKey) {
            fetchPhase = .ready(cachedPoster)
            return
        }

        do {
            let phase = try await thumbnailPhase(cacheKey: cacheKey)
            guard !Task.isCancelled else {
                return
            }
            if case .ready(let poster) = phase {
                DepthAlbumThumbnailMemoryCache.shared.insert(poster)
            }
            fetchPhase = phase
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            fetchPhase = .failed(nil, reason: .decode, retryable: false)
        }
    }

    private func thumbnailPhase(
        cacheKey: String
    ) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> {
        switch item.source {
        case .photos:
            guard let request = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: thumbnailPixelLength
            ) else {
                return .failed(nil, reason: .assetRemoved, retryable: false)
            }
            let phase = try await mediaFetcher.posterPhase(
                for: request,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
            return posterPhase(from: phase, cacheKey: cacheKey)
        case .ownedPhoto(let record, _):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID) {
                return .ready(MediaPoster(cacheKey: cacheKey, jpegData: data))
            }
            guard let request = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: thumbnailPixelLength
            ) else {
                return .failed(nil, reason: .assetRemoved, retryable: false)
            }
            let phase = try await mediaFetcher.posterPhase(
                for: request,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
            return posterPhase(from: phase, cacheKey: cacheKey)
        case .pending(let record):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID) {
                return .ready(MediaPoster(cacheKey: cacheKey, jpegData: data))
            }
            guard item.isVideo,
                  let videoURL = try? await TAPPendingCaptureStore.shared.bestAvailableVideoURL(
                    captureID: record.captureID
                  ),
                  let data = await DepthAlbumThumbnailLoader.shared.videoData(
                    for: videoURL,
                    cacheKey: cacheKey,
                    pixelLength: thumbnailPixelLength
                  ) else {
                return .failed(nil, reason: .decode, retryable: false)
            }
            return .ready(MediaPoster(cacheKey: cacheKey, jpegData: data))
        }
    }

    private func posterPhase(
        from phase: MediaFetchPhase<Data, Data>,
        cacheKey: String
    ) -> MediaFetchPhase<MediaPoster, MediaPoster> {
        switch phase {
        case .idle(let preview):
            return .idle(preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) })
        case .resolving(let preview):
            return .resolving(preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) })
        case .localPreview(let preview):
            return .localPreview(MediaPoster(cacheKey: cacheKey, jpegData: preview))
        case .cloudOnly(let preview):
            return .cloudOnly(preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) })
        case .downloadingFromICloud(let preview, let progress):
            return .downloadingFromICloud(
                preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) },
                progress: progress
            )
        case .ready(let value):
            return .ready(MediaPoster(cacheKey: cacheKey, jpegData: value))
        case .failed(let preview, let reason, let retryable):
            return .failed(
                preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) },
                reason: reason,
                retryable: retryable
            )
        }
    }

    private var displayedPoster: MediaPoster? {
        switch fetchPhase {
        case .idle(let preview),
             .resolving(let preview),
             .cloudOnly(let preview),
             .downloadingFromICloud(let preview, _),
             .failed(let preview, _, _):
            return preview
        case .localPreview(let preview), .ready(let preview):
            return preview
        }
    }

    private var isCloudOnly: Bool {
        if case .cloudOnly = fetchPhase {
            return true
        }
        return false
    }

    private var isResolving: Bool {
        if case .resolving = fetchPhase {
            return true
        }
        return false
    }

    private var hasFailure: Bool {
        if case .failed = fetchPhase {
            return true
        }
        return false
    }
}
