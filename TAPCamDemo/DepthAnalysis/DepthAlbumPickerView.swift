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
    @StateObject private var itemViewportTracker = DepthAlbumItemViewportTracker()
    @State private var pendingReturnScrollBookmark: DepthAlbumReturnScrollBookmark?
    @State private var latestReturnScrollRowStride: CGFloat = 0
    @State private var selectedDestination: DepthAlbumRouteAdapter.Destination?
    @State private var isViewerPresented = false
    @State private var locallyRemovedItemIDs: Set<String> = []
    @State private var visibleSnapshot: DepthAlbumVisibleSnapshot
    @State private var returnScrollRestoreToken = UUID()
    @State private var analysisViewerGeneration = UUID()
    @State private var presentedItemRevision: DepthAlbumViewerItemRevision?

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
        visibleSnapshot.items
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
        _visibleSnapshot = State(
            initialValue: DepthAlbumVisibleSnapshot(
                items: resolvedLibraryStore.items,
                excluding: []
            )
        )
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
        .toolbar(isViewerPresented ? .hidden : .visible, for: .navigationBar)
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
            await viewModel.loadForPresentation()
        }
        .navigationDestination(isPresented: $isViewerPresented) {
            viewerDestination()
        }
        .onChange(of: isViewerPresented) { _, isPresented in
            handleViewerPresentationChange(isPresented: isPresented)
        }
        .onChange(of: libraryStore.snapshot.revision) { _, _ in
            refreshVisibleSnapshot()
        }
        .onChange(of: visibleSnapshot.revisions) {
            previousRevisions, _ in
            reconcilePresentedDestination(previousRevisions: previousRevisions)
        }
        .modifier(DepthAlbumEdgeBackModifier(onReturn: returnToCameraWithoutAnimation))
    }

    @ViewBuilder
    private func albumContent(thumbnailPixelLength: Int, returnScrollRowStride: CGFloat) -> some View {
        ScrollView {
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
                            itemViewportTracker.record(newViewportY, for: item.id)
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
        .onChange(of: visibleSnapshot.itemIDs) { _, _ in
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
                mixedMediaContext: DepthAlbumDeletionContext(
                    currentItemID: route.itemID,
                    items: visibleItems
                ),
                onMixedMediaEntryChanged: { entry in
                    updatePresentedMixedMediaRoute(entry)
                },
                onDeletionCompleted: { deletedItemID, nextEntry in
                    handleViewerDeletionCompleted(
                        deletedItemID: deletedItemID,
                        nextEntry: nextEntry
                    )
                },
                mediaFetcher: mediaFetcher
            )
            // Ordinary photo-to-photo moves stay inside the retained carousel.
            // A mixed-media handoff to a photo that the old immutable carousel
            // snapshot does not own must create a fresh store for that item.
            .id(analysisViewerGeneration)
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
                onMixedMediaEntryChanged: { entry in
                    updatePresentedMixedMediaRoute(entry)
                },
                deletionContext: DepthAlbumDeletionContext(
                    currentItemID: route.itemID,
                    items: visibleItems
                ),
                onDeletionCompleted: { deletedItemID, nextEntry in
                    handleViewerDeletionCompleted(
                        deletedItemID: deletedItemID,
                        nextEntry: nextEntry
                    )
                },
                mediaFetcher: mediaFetcher
            )
            // TAPVideoDepthPlaybackView migrates only its playback session when
            // the current video or backing source changes. The viewer, pager,
            // fixed chrome, and transport keep one identity for the whole visit.
        case nil:
            EmptyView()
        }
    }

    private func updatePresentedAnalysisRoute(_ entry: DepthAnalysisAlbumContext.Entry) {
        selectedDestination = .analysis(DepthAlbumRouteAdapter.analysisRoute(for: entry))
        recordPresentedRevision(itemID: entry.id)
        routeStore.openDepthAlbumItem(entry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: entry.id,
            routeAnchor: entry.routeAnchor,
            itemViewportY: itemViewportTracker.viewportY(for: entry.id) ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func updatePresentedMixedMediaRoute(
        _ entry: DepthAlbumDeletionContext.Entry
    ) {
        if case .analysis = selectedDestination,
           case .analysis = entry.destination {
            analysisViewerGeneration = UUID()
        }
        selectedDestination = entry.destination
        recordPresentedRevision(itemID: entry.id)
        routeStore.openDepthAlbumItem(entry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: entry.id,
            routeAnchor: entry.routeAnchor,
            itemViewportY: itemViewportTracker.viewportY(for: entry.id) ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func updatePresentedVideoRoute(_ entry: TAPVideoAlbumContext.Entry) {
        selectedDestination = .video(DepthAlbumRouteAdapter.videoRoute(for: entry))
        recordPresentedRevision(itemID: entry.id)
        routeStore.openDepthAlbumItem(entry.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: entry.id,
            routeAnchor: entry.routeAnchor,
            itemViewportY: itemViewportTracker.viewportY(for: entry.id) ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func reconcilePresentedDestination(
        previousRevisions: [DepthAlbumViewerItemRevision]
    ) {
        guard isViewerPresented,
              let selectedDestination else {
            return
        }
        guard let currentItem = visibleItems.first(where: {
            $0.id == selectedDestination.itemID
        }) else {
            moveAfterExternalRemoval(
                selectedDestination: selectedDestination,
                previousRevisions: previousRevisions
            )
            return
        }
        let updatedDestination = DepthAlbumRouteAdapter.destination(for: currentItem)
        let updatedRevision = DepthAlbumViewerItemRevision(item: currentItem)
        guard updatedRevision != presentedItemRevision else {
            return
        }
        if case .analysis = updatedDestination {
            analysisViewerGeneration = UUID()
        }
        if updatedDestination != selectedDestination {
            self.selectedDestination = updatedDestination
        }
        presentedItemRevision = updatedRevision
    }

    private func moveAfterExternalRemoval(
        selectedDestination: DepthAlbumRouteAdapter.Destination,
        previousRevisions: [DepthAlbumViewerItemRevision]
    ) {
        guard !visibleItems.isEmpty else {
            self.selectedDestination = nil
            presentedItemRevision = nil
            isViewerPresented = false
            return
        }
        let removedIndex = previousRevisions.firstIndex(where: {
            $0.destination.itemID == selectedDestination.itemID
        }) ?? 0
        let replacement = visibleItems[min(removedIndex, visibleItems.count - 1)]
        let replacementDestination = DepthAlbumRouteAdapter.destination(for: replacement)
        if case .analysis = selectedDestination,
           case .analysis = replacementDestination {
            analysisViewerGeneration = UUID()
        }
        self.selectedDestination = replacementDestination
        presentedItemRevision = DepthAlbumViewerItemRevision(item: replacement)
        routeStore.openDepthAlbumItem(replacement.routeAnchor)
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: replacement.id,
            routeAnchor: replacement.routeAnchor,
            itemViewportY: itemViewportTracker.viewportY(for: replacement.id) ?? 0
        )
        returnScrollRestoreToken = UUID()
    }

    private func recordPresentedRevision(itemID: String) {
        presentedItemRevision = visibleItems.first(where: { $0.id == itemID })
            .map(DepthAlbumViewerItemRevision.init(item:))
    }

    private func openAlbumItem(_ item: TAPLibraryItem, returnScrollRowStride: CGFloat) {
        latestReturnScrollRowStride = returnScrollRowStride
        pendingReturnScrollBookmark = DepthAlbumReturnScrollBookmark(
            itemID: item.id,
            routeAnchor: item.routeAnchor,
            itemViewportY: itemViewportTracker.viewportY(for: item.id) ?? 0
        )
        returnScrollRestoreToken = UUID()
        routeStore.openDepthAlbumItem(item.routeAnchor)
        selectedDestination = DepthAlbumRouteAdapter.destination(for: item)
        presentedItemRevision = DepthAlbumViewerItemRevision(item: item)
        isViewerPresented = true
    }

    private func handleViewerDeletionCompleted(
        deletedItemID: String,
        nextEntry: DepthAlbumDeletionContext.Entry?
    ) {
        locallyRemovedItemIDs.insert(deletedItemID)
        refreshVisibleSnapshot()
        guard let nextEntry else {
            return
        }
        updatePresentedMixedMediaRoute(nextEntry)
    }

    private func handleViewerPresentationChange(isPresented: Bool) {
        guard !isPresented else {
            return
        }

        selectedDestination = nil
        presentedItemRevision = nil
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
        itemViewportTracker.retainOnly(Set(visibleSnapshot.itemIDs))
    }

    private func refreshVisibleSnapshot() {
        visibleSnapshot = DepthAlbumVisibleSnapshot(
            items: libraryStore.items,
            excluding: locallyRemovedItemIDs
        )
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

/// Derives the large-grid filter and the two change-observation projections
/// once per semantic Library revision (or local deletion), rather than once
/// for every read of `DepthAlbumPickerView.body`.
@MainActor
private struct DepthAlbumVisibleSnapshot {
    let items: [TAPLibraryItem]
    let itemIDs: [String]
    let revisions: [DepthAlbumViewerItemRevision]

    init(items: [TAPLibraryItem], excluding removedItemIDs: Set<String>) {
        let visibleItems = removedItemIDs.isEmpty
            ? items
            : items.filter { !removedItemIDs.contains($0.id) }
        self.items = visibleItems
        self.itemIDs = visibleItems.map(\.id)
        self.revisions = visibleItems.map(DepthAlbumViewerItemRevision.init(item:))
    }
}

/// Keeps exact per-item return positions without making every geometry update
/// an observed mutation of the whole grid. SwiftUI owns this object's lifetime,
/// but it deliberately emits no `objectWillChange` events while scrolling.
@MainActor
final class DepthAlbumItemViewportTracker: ObservableObject {
    private var viewportYByID: [String: CGFloat] = [:]

    func record(_ viewportY: CGFloat, for itemID: String) {
        viewportYByID[itemID] = viewportY
    }

    func viewportY(for itemID: String) -> CGFloat? {
        viewportYByID[itemID]
    }

    func retainOnly(_ itemIDs: Set<String>) {
        viewportYByID = viewportYByID.filter { itemIDs.contains($0.key) }
    }
}

/// Renderer-relevant identity for a visible Library item. `Destination`
/// catches pending/owned/source transitions; `isLivePhoto` also catches the
/// legacy case where Photos reveals the paired resource after an initial
/// fallback catalog entry was presented as a still image.
nonisolated private struct DepthAlbumViewerItemRevision: Equatable {
    let destination: DepthAlbumRouteAdapter.Destination
    let isLivePhoto: Bool

    init(item: TAPLibraryItem) {
        destination = DepthAlbumRouteAdapter.destination(for: item)
        isLivePhoto = item.isLivePhoto
    }
}
