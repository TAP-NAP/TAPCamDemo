//
//  TAPLibraryView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import SwiftUI

/// The TAP Library grid for photos, Live Photos, and videos; opens the selected Viewer.
struct TAPLibraryView: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var routeStore: CameraRouteStore
    @StateObject private var viewModel: TAPLibraryViewModel
    private let libraryStore: LibraryMediaStore
    private let mediaFetcher: any LibraryMediaFetching
    private let photoLoader: DepthAnalysisProgressivePhotoLoader?
    private let itemAccessibilityIdentifier: ((TAPLibraryItem) -> String)?
    @State private var albumScrollPosition = ScrollPosition(idType: String.self)
    @State private var openedItemID: String?
    @State private var selectedDestination: TAPLibraryRouteAdapter.Destination?
    @State private var isViewerPresented = false
    @State private var locallyRemovedItemIDs: Set<String> = []
    @State private var visibleSnapshot: LibraryVisibleSnapshot
    @State private var presentedItemRevision: LibraryViewerItemRevision?

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

    private var visibleItems: [TAPLibraryItem] {
        visibleSnapshot.items
    }

    init(
        routeStore: CameraRouteStore,
        libraryStore: LibraryMediaStore? = nil,
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        photoLoader: DepthAnalysisProgressivePhotoLoader? = nil,
        itemAccessibilityIdentifier: ((TAPLibraryItem) -> String)? = nil
    ) {
        self.routeStore = routeStore
        self.mediaFetcher = mediaFetcher
        self.photoLoader = photoLoader
        self.itemAccessibilityIdentifier = itemAccessibilityIdentifier
        let resolvedLibraryStore = libraryStore ?? LibraryMediaStore(observesChanges: false)
        self.libraryStore = resolvedLibraryStore
        _visibleSnapshot = State(
            initialValue: LibraryVisibleSnapshot(
                items: resolvedLibraryStore.items,
                excluding: []
            )
        )
        _viewModel = StateObject(
            wrappedValue: TAPLibraryViewModel(libraryStore: resolvedLibraryStore)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            albumContent(
                thumbnailPixelLength: Self.thumbnailPixelLength(
                    containerWidth: containerWidth,
                    displayScale: displayScale
                )
            )
        }
        .navigationTitle("TAP Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: routeStore.isLibraryPresented) {
            guard routeStore.isLibraryPresented else {
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
    }

    @ViewBuilder
    private func albumContent(thumbnailPixelLength: Int) -> some View {
        ScrollView {
            if viewModel.shouldShowLoading {
                ProgressView()
                    .accessibilityLabel(
                        Text("Loading TAP Library...")
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
                            openAlbumItem(item)
                        } label: {
                            TAPLibraryItemCell(
                                item: item,
                                thumbnailPixelLength: thumbnailPixelLength,
                                mediaFetcher: mediaFetcher
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(itemAccessibilityIdentifier?(item) ?? "tap.library.item")
                        .id(item.id)
                        .onAppear {
                            routeStore.recordVisibleLibraryItem(item.routeAnchor)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(Self.gridPadding)
            }
        }
        .scrollPosition($albumScrollPosition)
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

    @ViewBuilder
    private func viewerDestination() -> some View {
        if let selectedDestination {
            TAPLibraryViewer(
                destination: selectedDestination,
                entries: LibraryDeletionContext(currentItemID: selectedDestination.itemID, items: visibleItems)
                    .entries.map(TAPLibraryViewerPagingEntry.init),
                mediaFetcher: mediaFetcher,
                photoLoader: photoLoader,
                onCurrentEntryChanged: updatePresentedMixedMediaRoute,
                onDeletionCompleted: { deletedItemID, nextEntry in
                    handleViewerDeletionCompleted(deletedItemID: deletedItemID, nextEntry: nextEntry)
                }
            )
        }
    }

    private func updatePresentedMixedMediaRoute(_ entry: TAPLibraryViewerPagingEntry) {
        selectedDestination = entry.destination
        recordPresentedRevision(itemID: entry.id)
        if let item = visibleItems.first(where: { $0.id == entry.id }) {
            routeStore.openLibraryItem(item.routeAnchor)
        }
    }

    private func reconcilePresentedDestination(
        previousRevisions: [LibraryViewerItemRevision]
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
        let updatedDestination = TAPLibraryRouteAdapter.destination(for: currentItem)
        let updatedRevision = LibraryViewerItemRevision(item: currentItem)
        guard updatedRevision != presentedItemRevision else {
            return
        }
        if updatedDestination != selectedDestination {
            self.selectedDestination = updatedDestination
        }
        presentedItemRevision = updatedRevision
    }

    private func moveAfterExternalRemoval(
        selectedDestination: TAPLibraryRouteAdapter.Destination,
        previousRevisions: [LibraryViewerItemRevision]
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
        let replacementDestination = TAPLibraryRouteAdapter.destination(for: replacement)
        self.selectedDestination = replacementDestination
        presentedItemRevision = LibraryViewerItemRevision(item: replacement)
        routeStore.openLibraryItem(replacement.routeAnchor)
    }

    private func recordPresentedRevision(itemID: String) {
        presentedItemRevision = visibleItems.first(where: { $0.id == itemID })
            .map(LibraryViewerItemRevision.init(item:))
    }

    private func openAlbumItem(_ item: TAPLibraryItem) {
        openedItemID = item.id
        routeStore.openLibraryItem(item.routeAnchor)
        selectedDestination = TAPLibraryRouteAdapter.destination(for: item)
        presentedItemRevision = LibraryViewerItemRevision(item: item)
        isViewerPresented = true
    }

    private func handleViewerDeletionCompleted(
        deletedItemID: String,
        nextEntry: TAPLibraryViewerPagingEntry?
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

        // The native scroll position survives a visit to the Viewer. When the
        // current item changed there, return with that item visible.
        if let itemID = selectedDestination?.itemID,
           itemID != openedItemID,
           visibleSnapshot.itemIDs.contains(itemID) {
            albumScrollPosition.scrollTo(id: itemID, anchor: .center)
        }
        selectedDestination = nil
        presentedItemRevision = nil
        openedItemID = nil
    }

    private func refreshVisibleSnapshot() {
        visibleSnapshot = LibraryVisibleSnapshot(
            items: libraryStore.items,
            excluding: locallyRemovedItemIDs
        )
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
/// for every read of `TAPLibraryView.body`.
@MainActor
private struct LibraryVisibleSnapshot {
    let items: [TAPLibraryItem]
    let itemIDs: [String]
    let revisions: [LibraryViewerItemRevision]

    init(items: [TAPLibraryItem], excluding removedItemIDs: Set<String>) {
        let visibleItems = removedItemIDs.isEmpty
            ? items
            : items.filter { !removedItemIDs.contains($0.id) }
        self.items = visibleItems
        self.itemIDs = visibleItems.map(\.id)
        self.revisions = visibleItems.map(LibraryViewerItemRevision.init(item:))
    }
}

/// Renderer-relevant identity for a visible Library item. `Destination`
/// catches pending/owned/source transitions; `isLivePhoto` also catches the
/// legacy case where Photos reveals the paired resource after an initial
/// fallback catalog entry was presented as a still image.
nonisolated private struct LibraryViewerItemRevision: Equatable {
    let destination: TAPLibraryRouteAdapter.Destination
    let isLivePhoto: Bool
    let contentRevision: String

    init(item: TAPLibraryItem) {
        destination = TAPLibraryRouteAdapter.destination(for: item)
        isLivePhoto = item.isLivePhoto
        contentRevision = item.summary.version.contentRevision
    }
}
