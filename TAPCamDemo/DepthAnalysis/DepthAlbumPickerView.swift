//
//  DepthAlbumPickerView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Combine
import SwiftUI

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
    @State private var selectedDestination: DepthAlbumRouteAdapter.Destination?
    @State private var isViewerPresented = false
    @State private var locallyRemovedItemIDs: Set<String> = []
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

    private var visibleItems: [TAPLibraryItem] {
        libraryStore.items.filter { !locallyRemovedItemIDs.contains($0.id) }
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
        .navigationDestination(isPresented: $isViewerPresented) {
            viewerDestination()
        }
        .onChange(of: isViewerPresented) { _, isPresented in
            handleViewerPresentationChange(isPresented: isPresented)
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
                ProgressView()
                    .accessibilityLabel(
                        Text(LocalizedStringKey(viewModel.loadingPresentation.rawValue))
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Unable to load album",
                    systemImage: "photo.on.rectangle.angled",
                    description: albumErrorDescription(errorMessage)
                )
                    .frame(minHeight: 320)
            } else if visibleItems.isEmpty {
                ContentUnavailableView("No depth photos yet", systemImage: "photo.stack", description: Text("Capture a TAP depth photo first, then return here to analyze it."))
                    .frame(minHeight: 320)
            } else {
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(visibleItems) { item in
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
        .onChange(of: visibleItems.map(\.id)) { _, _ in
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

    private func albumErrorDescription(_ message: String) -> Text {
        switch message {
        case "Unable to load TAP Library. Check Photos access and try again.":
            Text("Unable to load TAP Library. Check Photos access and try again.")
        case "Unable to read the TAPCamDepth album. Check Photos access and try again.":
            Text("Unable to read the TAPCamDepth album. Check Photos access and try again.")
        default:
            // Unknown future loader diagnostics are values, not localization keys.
            Text(verbatim: message)
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
    private func viewerDestination() -> some View {
        switch selectedDestination {
        case .analysis(let route):
            DepthAnalysisView(
                source: route.source,
                albumContext: DepthAnalysisAlbumContext(
                    currentItemID: route.itemID,
                    items: visibleItems
                ),
                onCurrentAlbumEntryChanged: { entry in
                    updatePresentedAnalysisRoute(entry)
                },
                mediaFetcher: mediaFetcher
            )
        case .video(let route):
            TAPVideoDepthPlaybackView(
                source: route.source,
                albumContext: TAPVideoAlbumContext(
                    currentItemID: route.itemID,
                    items: visibleItems
                ),
                onCurrentAlbumEntryChanged: { entry in
                    updatePresentedVideoRoute(entry)
                },
                deletionContext: DepthAlbumDeletionContext(
                    currentItemID: route.itemID,
                    items: visibleItems
                ),
                onDeletionCompleted: { deletedItemID, nextEntry in
                    handleVideoDeletionCompleted(
                        deletedItemID: deletedItemID,
                        nextEntry: nextEntry
                    )
                },
                mediaFetcher: mediaFetcher
            )
            .id(route.itemID)
        case nil:
            EmptyView()
        }
    }

    private func updatePresentedAnalysisRoute(_ entry: DepthAnalysisAlbumContext.Entry) {
        selectedDestination = .analysis(DepthAlbumRouteAdapter.analysisRoute(for: entry))
        routeStore.openDepthAlbumItem(entry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: entry.id,
            routeAnchor: entry.routeAnchor,
            itemViewportY: itemViewportYByID[entry.id] ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func updatePresentedVideoRoute(_ entry: TAPVideoAlbumContext.Entry) {
        selectedDestination = .video(DepthAlbumRouteAdapter.videoRoute(for: entry))
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
        selectedDestination = DepthAlbumRouteAdapter.destination(for: item)
        isViewerPresented = true
    }

    private func handleVideoDeletionCompleted(
        deletedItemID: String,
        nextEntry: DepthAlbumDeletionContext.Entry?
    ) {
        locallyRemovedItemIDs.insert(deletedItemID)
        guard let nextEntry else {
            return
        }
        selectedDestination = nextEntry.destination
        routeStore.openDepthAlbumItem(nextEntry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: nextEntry.id,
            routeAnchor: nextEntry.routeAnchor,
            itemViewportY: itemViewportYByID[nextEntry.id] ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func handleViewerPresentationChange(isPresented: Bool) {
        guard !isPresented else {
            return
        }

        selectedDestination = nil
        scheduleReturnScrollRestore(clearAfterDelay: true)
    }

    private func restorePendingReturnScrollPosition(rowStride: CGFloat, clearAfterDelay: Bool) {
        guard pendingReturnScrollBookmark != nil,
              !isViewerPresented else {
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
                  !isViewerPresented,
                  let offsetY = Self.returnScrollOffsetY(
                    bookmark: bookmark,
                    items: visibleItems,
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
                  !isViewerPresented else {
                return
            }
            pendingReturnScrollBookmark = nil
        }
    }

    private func pruneTrackedItemViewportPositions() {
        let currentItemIDs = Set(visibleItems.map(\.id))
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
