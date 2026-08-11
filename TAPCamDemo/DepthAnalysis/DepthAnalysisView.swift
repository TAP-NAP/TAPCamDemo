//
//  DepthAnalysisView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import ImageIO
import Observation
import OSLog
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Independent browser/analysis surface for saved TAP Depth HEIC files.
///
/// The camera view links here through a thumbnail only. The default state is a
/// Photos-like browser where the bottom capsule switches the centered primary
/// surface between RAW, 2D, and 3D.
struct DepthAnalysisView: View {
    private let onCurrentAlbumEntryChanged: ((DepthAnalysisAlbumContext.Entry) -> Void)?
    private let mixedMediaContext: DepthAlbumDeletionContext?
    private let onMixedMediaEntryChanged: ((DepthAlbumDeletionContext.Entry) -> Void)?
    private let onDeletionCompleted: ((String, DepthAlbumDeletionContext.Entry?) -> Void)?
    private let mediaFetcher: any LibraryMediaFetching

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @StateObject private var carouselStore: DepthAnalysisCarouselStore
    @State private var heatmapOpacity = 0.58
    @State private var twoDComparisonPosition = 0.5
    @State private var selectedTool = AnalysisViewerTool.raw
    @State private var sharePresentation: DepthAnalysisShareSubject?
    @State private var pendingDeleteRequest: DepthAnalysisPendingDeleteRequest?
    @State private var deleteAlert: DepthAnalysisDeleteAlert?
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue
    @AppStorage(DepthAnalyzerPreferences.planeGridAnimationEnabledKey)
    private var isPlaneGridAnimationEnabled = DepthAnalyzerPreferences.defaultPlaneGridAnimationEnabled

    init(
        source: DepthAnalysisSource,
        albumContext: DepthAnalysisAlbumContext? = nil,
        onCurrentAlbumEntryChanged: ((DepthAnalysisAlbumContext.Entry) -> Void)? = nil,
        mixedMediaContext: DepthAlbumDeletionContext? = nil,
        onMixedMediaEntryChanged: ((DepthAlbumDeletionContext.Entry) -> Void)? = nil,
        onDeletionCompleted: ((String, DepthAlbumDeletionContext.Entry?) -> Void)? = nil,
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()
    ) {
        _carouselStore = StateObject(
            wrappedValue: DepthAnalysisCarouselStore(
                source: source,
                albumContext: albumContext,
                mediaFetcher: mediaFetcher
            )
        )
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
        self.mixedMediaContext = mixedMediaContext
        self.onMixedMediaEntryChanged = onMixedMediaEntryChanged
        self.onDeletionCompleted = onDeletionCompleted
        self.mediaFetcher = mediaFetcher
    }

    init(assetID: String) {
        self.init(
            source: .photosAsset(assetID)
        )
    }

    init(pendingCaptureID: String) {
        self.init(
            source: .pendingCapture(pendingCaptureID)
        )
    }

    var body: some View {
        analysisSurface()
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(.container, edges: .all)
        .sheet(item: $sharePresentation) { subject in
            DepthAnalysisShareSheet(subject: subject)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $pendingDeleteRequest) { request in
            Alert(
                title: Text("Delete unsaved photo?"),
                message: Text("This capture has not finished exporting to Photos. Deleting it removes the local TAP copy and cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    performDelete(
                        source: request.source,
                        displayPixelLength: request.displayPixelLength,
                        prewarmCurrentPlaneGeometry: request.prewarmCurrentPlaneGeometry
                    )
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $deleteAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onDisappear {
            carouselStore.cancelViewerRequests()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            carouselStore.cancelViewerRequests()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            carouselStore.currentSlot?.retryLastMediaFetch()
        }
    }

    private func analysisSurface() -> some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            let safeAreaInsets = geometry.safeAreaInsets
            let displayPixelLength = Self.displayPixelLength(
                viewportSize: viewportSize,
                displayScale: displayScale
            )

            ZStack(alignment: .bottom) {
                AnalysisPhotoCarouselView(
                    store: carouselStore,
                    mixedMediaContext: mixedMediaContext,
                    selectedTool: selectedTool,
                    displayPixelLength: displayPixelLength,
                    heatmapOpacity: $heatmapOpacity,
                    comparisonPosition: $twoDComparisonPosition,
                    highlightPalette: highlightPalette,
                    isPlaneGridAnimationEnabled: isPlaneGridAnimationEnabled,
                    mediaFetcher: mediaFetcher,
                    onCurrentEntryChanged: handleCurrentEntryChanged,
                    onBoundaryMove: handleMixedMediaBoundaryMove,
                    onEdgeBack: {
                        dismiss()
                    }
                )
                .frame(width: viewportSize.width, height: viewportSize.height)
                .background(Color.black)

                DepthAnalysisViewerChromeView(
                    selectedTool: selectedTool,
                    heatmapOpacity: $heatmapOpacity,
                    isSharePreparing: false,
                    topSafeArea: safeAreaInsets.top,
                    bottomSafeArea: safeAreaInsets.bottom,
                    onBackTapped: {
                        dismiss()
                    },
                    onShareTapped: presentShareSheet,
                    onToolTapped: handleToolTapped,
                    onDeleteTapped: {
                        deleteCurrentItem(displayPixelLength: displayPixelLength)
                    }
                )
                .zIndex(2)
            }
            .animation(.snappy(duration: 0.2), value: selectedTool)
        }
        .background(Color.black)
    }

    private func handleToolTapped(_ tool: AnalysisViewerTool) {
        selectedTool = tool
    }

    private var highlightPalette: AnalysisHighlightPalette {
        AnalysisHighlightPalette.resolved(viewfinderRawValue: viewfinderHighlightRawValue)
    }

    private func presentShareSheet() {
        guard let currentEntry = carouselStore.currentEntry else {
            return
        }
        sharePresentation = DepthAnalysisShareSubject(entry: currentEntry)
    }

    private func deleteCurrentItem(displayPixelLength: Int) {
        guard let source = carouselStore.currentEntry?.source else {
            return
        }

        let prewarmCurrentPlaneGeometry = selectedTool == .threeD
        if case .pendingCapture = source {
            pendingDeleteRequest = DepthAnalysisPendingDeleteRequest(
                source: source,
                displayPixelLength: displayPixelLength,
                prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry
            )
            return
        }

        performDelete(
            source: source,
            displayPixelLength: displayPixelLength,
            prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry
        )
    }

    private func performDelete(
        source: DepthAnalysisSource,
        displayPixelLength: Int,
        prewarmCurrentPlaneGeometry: Bool
    ) {
        let deletedItemID = carouselStore.currentEntry?.id
            ?? source.loadID
        Task { @MainActor in
            do {
                try await DepthAnalysisDeletionService.delete(source: source)

                let removedIDs = Set([deletedItemID])
                let mixedNextEntry = mixedMediaContext?.entryAfterDeleting(
                    deletedItemID,
                    excluding: removedIDs
                )
                if case .video? = mixedNextEntry?.destination,
                   let onDeletionCompleted {
                    carouselStore.cancelViewerRequests()
                    onDeletionCompleted(deletedItemID, mixedNextEntry)
                    return
                }

                onDeletionCompleted?(deletedItemID, nil)
                if let nextEntry = carouselStore.advanceAfterDeletingCurrent(
                    pixelLength: displayPixelLength,
                    prewarmCurrentPlaneGeometry: prewarmCurrentPlaneGeometry
                ) {
                    handleCurrentEntryChanged(nextEntry)
                } else {
                    dismiss()
                }
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.photoLibrary.error("analysis delete failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                deleteAlert = DepthAnalysisDeleteAlert(
                    title: "Unable to delete photo",
                    message: "Try again from TAP Library."
                )
            }
        }
    }

    private func handleCurrentEntryChanged(_ entry: DepthAnalysisCarouselEntry) {
        if let albumEntry = entry.albumEntry {
            onCurrentAlbumEntryChanged?(albumEntry)
        }
    }

    private func handleMixedMediaBoundaryMove(offset: Int) {
        guard let currentItemID = carouselStore.currentEntry?.id,
              let entry = mixedMediaContext?.adjacentEntry(
                from: currentItemID,
                offset: offset
              ) else {
            return
        }
        carouselStore.cancelViewerRequests()
        onMixedMediaEntryChanged?(entry)
    }

    private static func displayPixelLength(viewportSize: CGSize, displayScale: CGFloat) -> Int {
        let viewportMaxLength = max(viewportSize.width, viewportSize.height)
        let scaledLength = Int(ceil(viewportMaxLength * max(displayScale, 1)))
        return min(max(scaledLength, 960), 4096)
    }
}

private struct DepthAnalysisPendingDeleteRequest: Identifiable {
    let id = UUID()
    let source: DepthAnalysisSource
    let displayPixelLength: Int
    let prewarmCurrentPlaneGeometry: Bool
}

private struct DepthAnalysisDeleteAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum DepthAnalysisDeletionService {
    static func delete(source: DepthAnalysisSource) async throws {
        switch source {
        case .photosAsset(let assetID):
            try await PhotoLibraryWriter.deleteAsset(localIdentifier: assetID)
            try await TAPPendingCaptureStore.shared.removeExportedRecords(
                assetLocalIdentifier: assetID
            )
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        case .pendingCapture(let captureID):
            try await TAPPendingCaptureStore.shared.removeRecord(captureID: captureID)
        }
    }
}

private struct AnalysisPhotoCarouselView: View {
    @ObservedObject var store: DepthAnalysisCarouselStore
    let mixedMediaContext: DepthAlbumDeletionContext?
    let selectedTool: AnalysisViewerTool
    let displayPixelLength: Int
    @Binding var heatmapOpacity: Double
    @Binding var comparisonPosition: Double
    let highlightPalette: AnalysisHighlightPalette
    let isPlaneGridAnimationEnabled: Bool
    let mediaFetcher: any LibraryMediaFetching
    let onCurrentEntryChanged: (DepthAnalysisCarouselEntry) -> Void
    let onBoundaryMove: (Int) -> Void
    let onEdgeBack: () -> Void

    var body: some View {
        AnalysisNativePagingView(
            store: store,
            mixedMediaContext: mixedMediaContext,
            selectedTool: selectedTool,
            displayPixelLength: displayPixelLength,
            heatmapOpacity: $heatmapOpacity,
            comparisonPosition: $comparisonPosition,
            highlightPalette: highlightPalette,
            isPlaneGridAnimationEnabled: isPlaneGridAnimationEnabled,
            mediaFetcher: mediaFetcher,
            onCurrentEntryChanged: onCurrentEntryChanged,
            onBoundaryMove: onBoundaryMove,
            onEdgeBack: onEdgeBack
        )
        .background(Color.black)
        .accessibilityLabel("Photo carousel")
        .task(id: "\(selectedTool.rawValue)-\(displayPixelLength)") {
            store.ensureVisibleWindowLoaded(
                pixelLength: displayPixelLength,
                prewarmCurrentPlaneGeometry: selectedTool == .threeD
            )
        }
    }
}

private struct AnalysisNativePagingView: View {
    @ObservedObject var store: DepthAnalysisCarouselStore
    let mixedMediaContext: DepthAlbumDeletionContext?
    let selectedTool: AnalysisViewerTool
    let displayPixelLength: Int
    @Binding var heatmapOpacity: Double
    @Binding var comparisonPosition: Double
    let highlightPalette: AnalysisHighlightPalette
    let isPlaneGridAnimationEnabled: Bool
    let mediaFetcher: any LibraryMediaFetching
    let onCurrentEntryChanged: (DepthAnalysisCarouselEntry) -> Void
    let onBoundaryMove: (Int) -> Void
    let onEdgeBack: () -> Void
    @State private var pagingInteractionState = AnalysisPagingInteractionState()

    var body: some View {
        TAPLibraryNativePagingView(
            entries: pagingEntries,
            currentItemID: currentItemID,
            pageContentRevision: pageContentRevision,
            pageBuilder: { entry, isCurrent, pageSize in
                page(
                    for: entry,
                    isCurrent: isCurrent,
                    pageSize: pageSize
                )
            },
            onCurrentEntryChanged: handleSettledEntry,
            onPagingInteractionChanged: { isInteracting in
                pagingInteractionState.isInteracting = isInteracting
            },
            shouldBeginPaging: shouldBeginPaging,
            onEdgeBack: onEdgeBack
        )
    }

    private var currentItemID: String {
        store.currentEntry?.id
            ?? mixedMediaContext?.currentItemID
            ?? ""
    }

    private var pagingEntries: [TAPLibraryViewerPagingEntry] {
        if let mixedMediaContext {
            return mixedMediaContext.pagingEntries(from: currentItemID)
                .map(TAPLibraryViewerPagingEntry.init)
        }

        return store.windowEntries().map { item in
            TAPLibraryViewerPagingEntry(
                id: item.entry.id,
                destination: .analysis(
                    DepthAlbumAnalysisRoute(
                        itemID: item.entry.id,
                        source: item.entry.source
                    )
                ),
                expectsPairedVideo: item.entry.albumEntry?.expectsPairedVideo
                    ?? false
            )
        }
    }

    private func page(
        for pagingEntry: TAPLibraryViewerPagingEntry,
        isCurrent: Bool,
        pageSize: CGSize
    ) -> AnyView {
        if let carouselEntry = localCarouselEntry(matching: pagingEntry) {
            return AnyView(
                AnalysisNativePageView(
                    slot: store.slot(for: carouselEntry),
                    tool: selectedTool,
                    viewportSize: pageSize,
                    isCurrent: isCurrent,
                    pagingInteractionState: pagingInteractionState,
                    heatmapOpacity: $heatmapOpacity,
                    comparisonPosition: $comparisonPosition,
                    highlightPalette: highlightPalette,
                    isPlaneGridAnimationEnabled: isPlaneGridAnimationEnabled,
                    mediaFetcher: mediaFetcher
                )
            )
        }

        return AnyView(
            TAPLibraryAdjacentMediaPreview(
                entry: pagingEntry,
                viewportSize: pageSize,
                mediaFetcher: mediaFetcher
            )
        )
    }

    private func handleSettledEntry(_ target: TAPLibraryViewerPagingEntry) {
        let currentID = currentItemID
        if localCarouselEntry(matching: target) != nil,
           let localWindowItem = store.windowEntries().first(where: {
               $0.entry.id == target.id
           }),
           localWindowItem.offset != 0,
           let entry = store.move(
               offset: localWindowItem.offset,
               pixelLength: displayPixelLength,
               prewarmCurrentPlaneGeometry: selectedTool == .threeD
           ) {
            onCurrentEntryChanged(entry)
            return
        }

        guard let mixedEntries = mixedMediaContext?.pagingEntries(from: currentID),
              let currentIndex = mixedEntries.firstIndex(where: { $0.id == currentID }),
              let targetIndex = mixedEntries.firstIndex(where: { $0.id == target.id }),
              abs(targetIndex - currentIndex) == 1 else {
            return
        }
        onBoundaryMove(targetIndex - currentIndex)
    }

    private func localCarouselEntry(
        matching pagingEntry: TAPLibraryViewerPagingEntry
    ) -> DepthAnalysisCarouselEntry? {
        guard case .analysis(let route) = pagingEntry.destination,
              let localEntry = store.windowEntries().first(where: {
                  $0.entry.id == pagingEntry.id
              })?.entry,
              localEntry.source == route.source,
              (localEntry.albumEntry?.expectsPairedVideo ?? false)
                == pagingEntry.expectsPairedVideo else {
            return nil
        }
        return localEntry
    }

    private func shouldBeginPaging(
        at location: CGPoint,
        viewportSize: CGSize
    ) -> Bool {
        guard selectedTool != .raw,
              let toolContainerRect = currentToolContainerRect(
                  viewportSize: viewportSize
              ) else {
            return true
        }
        return !toolContainerRect.contains(location)
    }

    private var pageContentRevision: UInt64 {
        var hasher = Hasher()
        hasher.combine(selectedTool.rawValue)
        hasher.combine(highlightPalette.uiColor.hash)
        hasher.combine(isPlaneGridAnimationEnabled)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private func currentToolContainerRect(viewportSize: CGSize) -> CGRect? {
        guard let slot = store.currentSlot else {
            return nil
        }
        if let input = slot.input {
            return DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                imageSize: CGSize(width: input.image.width, height: input.image.height),
                orientation: input.imageOrientation,
                viewportSize: viewportSize
            )
        }
        if let displayPhoto = slot.displayPhoto {
            return DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                imageSize: displayPhoto.pixelSize,
                orientation: displayPhoto.orientation,
                viewportSize: viewportSize
            )
        }
        if let thumbnailImage = slot.thumbnailImage {
            return DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                imageSize: thumbnailImage.size,
                orientation: .up,
                viewportSize: viewportSize
            )
        }
        return nil
    }
}

private struct AnalysisNativePageView: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let tool: AnalysisViewerTool
    let viewportSize: CGSize
    let isCurrent: Bool
    let pagingInteractionState: AnalysisPagingInteractionState
    @Binding var heatmapOpacity: Double
    @Binding var comparisonPosition: Double
    let highlightPalette: AnalysisHighlightPalette
    let isPlaneGridAnimationEnabled: Bool
    let mediaFetcher: any LibraryMediaFetching
    @State private var isLivePhotoMuted = true

    var body: some View {
        ZStack {
            Color.black

            switch tool {
            case .raw:
                rawContent
            case .twoD, .threeD:
                AnalysisToolPhotoStage(
                    slot: slot,
                    tool: tool,
                    viewportSize: viewportSize,
                    isCurrent: isCurrent,
                    heatmapOpacity: $heatmapOpacity,
                    comparisonPosition: $comparisonPosition,
                    highlightPalette: highlightPalette,
                    isPlaneGridAnimationEnabled: isPlaneGridAnimationEnabled
                )
            }

            AnalysisLivePhotoBadgeOverlay(
                source: slot.source,
                isCurrent: isCurrent,
                viewportSize: viewportSize,
                displayedImageSize: displayedImageSize,
                displayedImageOrientation: displayedImageOrientation,
                mediaFetcher: mediaFetcher
            )

            if isCurrent {
                LibraryMediaViewerFetchOverlay(
                    kind: .photo,
                    state: LibraryMediaFetchOverlayState(slot.mediaFetchPhase),
                    onRetry: slot.retryLastMediaFetch
                )
                .zIndex(4)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .onChange(of: slot.source.loadID) { _, _ in
            isLivePhotoMuted = true
        }
        .onChange(of: isCurrent) { _, isCurrent in
            if isCurrent {
                isLivePhotoMuted = true
            }
        }
    }

    private var rawContent: some View {
        ZStack {
            AnalysisRawZoomScrollView(
                slot: slot,
                source: slot.source,
                image: rawImage,
                imageIdentifier: rawImageIdentifier,
                isCurrent: isCurrent,
                isPagingInteracting: pagingInteractionState.isInteracting,
                mediaFetcher: mediaFetcher,
                isLivePhotoMuted: $isLivePhotoMuted
            )
            .frame(width: viewportSize.width, height: viewportSize.height)

            if let errorMessage = slot.errorMessage, !slot.hasDisplayImage {
                ContentUnavailableView(
                    slot.errorTitle,
                    systemImage: slot.errorSystemImage,
                    description: Text(errorMessage)
                )
                .foregroundStyle(.white)
                .padding(24)
            }
        }
    }

    private var rawImage: UIImage? {
        if let displayPhoto = slot.displayPhoto {
            return displayPhoto.image
        }
        if let input = slot.input {
            return UIImage(
                cgImage: input.image,
                scale: 1,
                orientation: input.imageOrientation.uiImageOrientation
            )
        }
        return slot.thumbnailImage
    }

    private var rawImageIdentifier: String {
        if let displayPhoto = slot.displayPhoto {
            return "\(slot.id)-display-\(displayPhoto.requestedPixelLength)-\(Int(displayPhoto.pixelSize.width))x\(Int(displayPhoto.pixelSize.height))"
        }
        if let input = slot.input {
            return "\(slot.id)-analysisInput-\(input.image.width)x\(input.image.height)-\(input.imageOrientation.rawValue)"
        }
        if slot.thumbnailImage != nil {
            return "\(slot.id)-thumbnail"
        }
        return "\(slot.id)-empty"
    }

    private var displayedImageSize: CGSize? {
        if let input = slot.input {
            return CGSize(width: input.image.width, height: input.image.height)
        }
        if let displayPhoto = slot.displayPhoto {
            return displayPhoto.pixelSize
        }
        return slot.thumbnailImage?.size
    }

    private var displayedImageOrientation: CGImagePropertyOrientation {
        slot.input?.imageOrientation ?? slot.displayPhoto?.orientation ?? .up
    }
}

@MainActor
@Observable
private final class AnalysisPagingInteractionState {
    var isInteracting = false
}

private struct AnalysisLivePhotoBadgeOverlay: View {
    let source: DepthAnalysisSource
    let isCurrent: Bool
    let viewportSize: CGSize
    let displayedImageSize: CGSize?
    let displayedImageOrientation: CGImagePropertyOrientation
    let mediaFetcher: any LibraryMediaFetching
    @State private var isLivePhoto = false

    var body: some View {
        ZStack {
            if isLivePhoto, let badgePosition {
                DepthAnalysisLivePhotoBadge(size: .viewer)
                    .position(badgePosition)
                    .transition(.opacity)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(!isLivePhoto)
        .task(id: "\(source.loadID)|\(isCurrent)") {
            await refresh()
        }
    }

    private var badgePosition: CGPoint? {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              displayedImageSize != nil else {
            return nil
        }

        let imageRect = DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
            imageSize: displayedImageSize,
            orientation: displayedImageOrientation,
            viewportSize: viewportSize
        )
        let edgeInset = DepthAnalysisLivePhotoBadge.Size.viewer.edgeInset
        return CGPoint(
            x: imageRect.maxX - edgeInset,
            y: imageRect.minY + edgeInset
        )
    }

    private func refresh() async {
        guard isCurrent else {
            isLivePhoto = false
            return
        }

        let resolvedIsLivePhoto = await DepthAnalysisLivePhotoSourceResolver.isLivePhoto(
            source: source,
            mediaFetcher: mediaFetcher
        )
        guard !Task.isCancelled else {
            return
        }
        isLivePhoto = resolvedIsLivePhoto
    }
}

private enum DepthAnalysisLivePhotoSourceResolver {
    static func isLivePhoto(
        source: DepthAnalysisSource,
        mediaFetcher: any LibraryMediaFetching
    ) async -> Bool {
        switch source {
        case .photosAsset(let assetID):
            let request = LibraryMediaAssetRequest(
                key: MediaFetchRequestKey(
                    itemID: .photosAsset(assetID),
                    generation: 0,
                    purpose: .livePhotoPlayback
                ),
                assetLocalIdentifier: assetID
            )
            return (try? await mediaFetcher.mediaKind(for: request)) == .livePhoto
        case .pendingCapture(let captureID):
            guard let record = try? await TAPPendingCaptureStore.shared.readRecord(captureID: captureID) else {
                return false
            }
            return record.pairedVideoFilename != nil
        }
    }
}

private struct AnalysisRawZoomScrollView: UIViewRepresentable {
    let slot: AnalysisPhotoSlot
    let source: DepthAnalysisSource
    let image: UIImage?
    let imageIdentifier: String
    let isCurrent: Bool
    let isPagingInteracting: Bool
    let mediaFetcher: any LibraryMediaFetching
    @Binding var isLivePhotoMuted: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(slot: slot, mediaFetcher: mediaFetcher)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = AnalysisRawZoomUIScrollView()
        let coordinator = context.coordinator
        scrollView.onLayout = { [weak coordinator] scrollView in
            coordinator?.handleLayout(in: scrollView)
        }
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = DepthAnalysisViewerInteractionPolicy.maximumPhotoScale
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        context.coordinator.installImageView(in: scrollView)
        context.coordinator.installDoubleTap(in: scrollView)
        context.coordinator.installLivePhotoLongPress(in: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(
            scrollView: scrollView,
            slot: slot,
            source: source,
            image: image,
            imageIdentifier: imageIdentifier,
            isCurrent: isCurrent,
            isPagingInteracting: isPagingInteracting,
            isLivePhotoMuted: isLivePhotoMuted
        )
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        if let rawScrollView = uiView as? AnalysisRawZoomUIScrollView {
            rawScrollView.onLayout = nil
        }
        uiView.delegate = nil
        coordinator.dismantle()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private let mediaFetcher: any LibraryMediaFetching
        private weak var slot: AnalysisPhotoSlot?
        private let contentView = UIView()
        private let imageView = UIImageView()
        private let livePhotoView = PHLivePhotoView()
        private var currentImageIdentifier: String?
        private var lastBoundsSize: CGSize = .zero
        private var livePhotoRequestCancellation: LivePhotoRequestCancellation?
        private var livePhotoPreparationTask: Task<Void, Never>?
        private var scheduledLivePhotoRequestKey: String?
        private var livePhotoRequestKey: String?
        private var livePhotoMediaRequestKey: MediaFetchRequestKey?
        private var livePhotoCoordinatorGeneration: UInt64 = 0
        private var livePhotoReadyKey: String?
        private var livePhotoUnavailableKey: String?
        private var lastLivePhotoRequest: LivePhotoRequestContext?
        private var isPressingForLivePhoto = false
        private var isPagingInteracting = false
        private var isLivePhotoMuted = true

        init(
            slot: AnalysisPhotoSlot,
            mediaFetcher: any LibraryMediaFetching
        ) {
            self.slot = slot
            self.mediaFetcher = mediaFetcher
            super.init()
        }

        func installImageView(in scrollView: UIScrollView) {
            contentView.backgroundColor = .black
            contentView.clipsToBounds = true

            imageView.backgroundColor = .black
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true

            livePhotoView.backgroundColor = .black
            livePhotoView.contentMode = .scaleAspectFit
            livePhotoView.clipsToBounds = true
            livePhotoView.isHidden = true
            livePhotoView.isUserInteractionEnabled = false

            contentView.addSubview(imageView)
            contentView.addSubview(livePhotoView)
            scrollView.addSubview(contentView)
        }

        func installDoubleTap(in scrollView: UIScrollView) {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            gesture.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(gesture)
        }

        func installLivePhotoLongPress(in scrollView: UIScrollView) {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLivePhotoLongPress(_:)))
            gesture.minimumPressDuration = 0.42
            gesture.allowableMovement = 28
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            scrollView.addGestureRecognizer(gesture)
        }

        func update(
            scrollView: UIScrollView,
            slot: AnalysisPhotoSlot,
            source: DepthAnalysisSource,
            image: UIImage?,
            imageIdentifier: String,
            isCurrent: Bool,
            isPagingInteracting: Bool,
            isLivePhotoMuted: Bool
        ) {
            if self.slot !== slot {
                clearLivePhoto()
                self.slot = slot
            }
            scrollView.isUserInteractionEnabled = isCurrent
            self.isPagingInteracting = isPagingInteracting
            if isPagingInteracting {
                isPressingForLivePhoto = false
                livePhotoView.stopPlayback()
            }
            self.isLivePhotoMuted = isLivePhotoMuted
            livePhotoView.isMuted = isLivePhotoMuted
            let boundsSize = scrollView.bounds.size
            let imageObjectChanged = imageView.image !== image
            if currentImageIdentifier != imageIdentifier || imageObjectChanged {
                currentImageIdentifier = imageIdentifier
                imageView.image = image
                if boundsSize.width > 0, boundsSize.height > 0 {
                    resetZoom(in: scrollView)
                }
            }
            syncLayoutIfNeeded(in: scrollView)
            syncLivePhoto(
                in: scrollView,
                source: source,
                isCurrent: isCurrent
            )
        }

        func dismantle() {
            clearLivePhoto()
            slot = nil
        }

        func handleLayout(in scrollView: UIScrollView) {
            syncLayoutIfNeeded(in: scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
            syncPanAvailability(in: scrollView)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UILongPressGestureRecognizer
        }

        private func resetZoom(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }
            contentView.frame = bounds
            syncMediaFrames()
            scrollView.contentSize = bounds.size
            scrollView.setZoomScale(1, animated: false)
            centerContent(in: scrollView)
            syncPanAvailability(in: scrollView)
        }

        private func syncLayoutIfNeeded(in scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else {
                syncPanAvailability(in: scrollView)
                return
            }

            let needsFrameRepair = imageView.frame.width <= 0
                || imageView.frame.height <= 0
                || scrollView.contentSize.width <= 0
                || scrollView.contentSize.height <= 0
            guard boundsSize != lastBoundsSize || needsFrameRepair else {
                syncPanAvailability(in: scrollView)
                return
            }

            lastBoundsSize = boundsSize
            if scrollView.zoomScale <= DepthAnalysisViewerInteractionPolicy.zoomedScaleThreshold || needsFrameRepair {
                resetZoom(in: scrollView)
            } else {
                syncMediaFrames()
                centerContent(in: scrollView)
                syncPanAvailability(in: scrollView)
            }
        }

        private func centerContent(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }
            var frame = contentView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) * 0.5 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) * 0.5 : 0
            contentView.frame = frame
            syncMediaFrames()
        }

        private func syncMediaFrames() {
            let bounds = contentView.bounds
            imageView.frame = bounds
            livePhotoView.frame = bounds
        }

        private func syncPanAvailability(in scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > DepthAnalysisViewerInteractionPolicy.zoomedScaleThreshold
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else {
                return
            }
            if scrollView.zoomScale > DepthAnalysisViewerInteractionPolicy.zoomedScaleThreshold {
                scrollView.setZoomScale(1, animated: true)
                return
            }
            let location = gesture.location(in: contentView)
            let targetScale = min(
                DepthAnalysisViewerInteractionPolicy.doubleTapScale,
                scrollView.maximumZoomScale
            )
            let zoomSize = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            let zoomRect = CGRect(
                x: location.x - zoomSize.width * 0.5,
                y: location.y - zoomSize.height * 0.5,
                width: zoomSize.width,
                height: zoomSize.height
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }

        @objc private func handleLivePhotoLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard !isPagingInteracting else {
                    return
                }
                isPressingForLivePhoto = true
                startLivePhotoPlaybackIfAvailable()
            case .ended, .cancelled, .failed:
                isPressingForLivePhoto = false
                livePhotoView.stopPlayback()
            default:
                break
            }
        }

        private func syncLivePhoto(
            in scrollView: UIScrollView,
            source: DepthAnalysisSource,
            isCurrent: Bool
        ) {
            guard isCurrent,
                  scrollView.bounds.width > 0,
                  scrollView.bounds.height > 0 else {
                clearLivePhoto()
                return
            }

            let targetSize = livePhotoTargetSize(in: scrollView)
            let key = "\(source.loadID)|\(Int(targetSize.width))x\(Int(targetSize.height))"
            if livePhotoReadyKey == key
                || scheduledLivePhotoRequestKey == key
                || livePhotoRequestKey == key
                || livePhotoUnavailableKey == key {
                return
            }

            scheduleLivePhotoRequest(source: source, targetSize: targetSize, key: key)
        }

        /// Defers slot publication until after `updateUIView` returns. Writing
        /// an observed slot synchronously from a representable update would
        /// mutate SwiftUI state during view reconciliation.
        private func scheduleLivePhotoRequest(
            source: DepthAnalysisSource,
            targetSize: CGSize,
            key: String
        ) {
            scheduledLivePhotoRequestKey = key
            Task { @MainActor [weak self] in
                guard let self,
                      self.scheduledLivePhotoRequestKey == key else {
                    return
                }
                self.scheduledLivePhotoRequestKey = nil
                self.requestLivePhoto(source: source, targetSize: targetSize, key: key)
            }
        }

        private func requestLivePhoto(source: DepthAnalysisSource, targetSize: CGSize, key: String) {
            cancelLivePhotoRequest(notifySlot: true, preserveCloudState: false)
            guard let slot else {
                return
            }
            livePhotoCoordinatorGeneration &+= 1
            let coordinatorGeneration = livePhotoCoordinatorGeneration
            let mediaRequestKey = slot.beginLivePhotoFetch(
                onCancel: { [weak self] in
                    self?.cancelLivePhotoRequest(
                        notifySlot: false,
                        preserveCloudState: true,
                        suppressAutomaticRetry: true,
                        expectedCoordinatorGeneration: coordinatorGeneration
                    )
                },
                onRetry: { [weak self] in
                    self?.retryLivePhotoRequest()
                }
            )
            guard livePhotoCoordinatorGeneration == coordinatorGeneration else {
                slot.cancelLivePhotoFetch(
                    requestKey: mediaRequestKey,
                    preserveCloudState: false
                )
                return
            }
            lastLivePhotoRequest = LivePhotoRequestContext(
                source: source,
                targetSize: targetSize,
                presentationKey: key
            )
            livePhotoRequestKey = key
            livePhotoMediaRequestKey = mediaRequestKey
            livePhotoReadyKey = nil
            livePhotoUnavailableKey = nil
            livePhotoView.livePhoto = nil
            livePhotoView.isHidden = true

            livePhotoPreparationTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                switch source {
                case .photosAsset(let assetID):
                    await self.requestPhotosAssetLivePhoto(
                        assetID: assetID,
                        targetSize: targetSize,
                        key: key,
                        requestKey: mediaRequestKey
                    )
                case .pendingCapture(let captureID):
                    await self.requestPendingCaptureLivePhoto(
                        captureID: captureID,
                        targetSize: targetSize,
                        key: key,
                        requestKey: mediaRequestKey
                    )
                }
            }
        }

        private func requestPhotosAssetLivePhoto(
            assetID: String,
            targetSize: CGSize,
            key: String,
            requestKey: MediaFetchRequestKey
        ) async {
            let request = LibraryMediaAssetRequest(
                key: requestKey,
                assetLocalIdentifier: assetID
            )
            do {
                let kind = try await mediaFetcher.mediaKind(for: request)
                guard isCurrentLivePhotoRequest(key: key, requestKey: requestKey) else {
                    return
                }
                guard kind == .livePhoto else {
                    markLivePhotoUnavailable(
                        key: key,
                        requestKey: requestKey,
                        failure: nil
                    )
                    return
                }
                let progressSlot = slot
                progressSlot?.markLivePhotoFetchResolving(requestKey: requestKey)
                let livePhoto = try await mediaFetcher.livePhoto(
                    for: request,
                    targetSize: targetSize,
                    progress: { progress in
                        Task { @MainActor in
                            progressSlot?.applyLivePhotoICloudProgress(
                                progress,
                                requestKey: requestKey
                            )
                        }
                    }
                )
                guard !Task.isCancelled,
                      isCurrentLivePhotoRequest(key: key, requestKey: requestKey) else {
                    return
                }
                handleLivePhotoResult(
                    livePhoto.value,
                    isCancelled: false,
                    error: nil,
                    isDegraded: false,
                    key: key,
                    requestKey: requestKey
                )
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentLivePhotoRequest(key: key, requestKey: requestKey) else {
                    return
                }
                markLivePhotoUnavailable(
                    key: key,
                    requestKey: requestKey,
                    failure: error
                )
            }
        }

        private func requestPendingCaptureLivePhoto(
            captureID: String,
            targetSize: CGSize,
            key: String,
            requestKey: MediaFetchRequestKey
        ) async {
            let resources: PendingLivePhotoResources
            do {
                let photoURL = try await TAPPendingCaptureStore.shared.bestAvailablePhotoURL(captureID: captureID)
                guard let pairedVideoURL = try await TAPPendingCaptureStore.shared.pairedVideoURL(captureID: captureID) else {
                    markLivePhotoUnavailable(
                        key: key,
                        requestKey: requestKey,
                        failure: nil
                    )
                    return
                }
                resources = PendingLivePhotoResources(photoURL: photoURL, pairedVideoURL: pairedVideoURL)
            } catch {
                markLivePhotoUnavailable(
                    key: key,
                    requestKey: requestKey,
                    failure: nil
                )
                return
            }

            guard isCurrentLivePhotoRequest(key: key, requestKey: requestKey) else {
                return
            }
            slot?.markLivePhotoFetchResolving(requestKey: requestKey)

            let requestID = PHLivePhoto.request(
                withResourceFileURLs: [resources.photoURL, resources.pairedVideoURL],
                placeholderImage: imageView.image,
                targetSize: targetSize,
                contentMode: .aspectFit
            ) { [weak self] livePhoto, info in
                Task { @MainActor in
                    self?.handleLocalResourceLivePhotoResult(
                        livePhoto,
                        info: info,
                        key: key,
                        requestKey: requestKey
                    )
                }
            }
            livePhotoRequestCancellation = .pendingResources(requestID)
        }

        private func handleLocalResourceLivePhotoResult(
            _ livePhoto: PHLivePhoto?,
            info: [AnyHashable: Any],
            key: String,
            requestKey: MediaFetchRequestKey
        ) {
            handleLivePhotoResult(
                livePhoto,
                isCancelled: info[PHLivePhotoInfoCancelledKey] as? Bool == true,
                error: info[PHLivePhotoInfoErrorKey],
                isDegraded: info[PHLivePhotoInfoIsDegradedKey] as? Bool == true,
                key: key,
                requestKey: requestKey
            )
        }

        private struct LivePhotoRequestContext {
            let source: DepthAnalysisSource
            let targetSize: CGSize
            let presentationKey: String
        }

        private struct PendingLivePhotoResources {
            let photoURL: URL
            let pairedVideoURL: URL
        }

        private enum LivePhotoRequestCancellation {
            case pendingResources(PHLivePhotoRequestID)

            func cancel() {
                switch self {
                case .pendingResources(let requestID):
                    PHLivePhoto.cancelRequest(withRequestID: requestID)
                }
            }
        }

        private func handleLivePhotoResult(
            _ livePhoto: PHLivePhoto?,
            isCancelled: Bool,
            error: Any?,
            isDegraded: Bool,
            key: String,
            requestKey: MediaFetchRequestKey
        ) {
            guard isCurrentLivePhotoRequest(key: key, requestKey: requestKey) else {
                return
            }
            if isCancelled {
                cancelLivePhotoRequest(notifySlot: true, preserveCloudState: false)
                return
            }
            if let error = error as? Error {
                markLivePhotoUnavailable(
                    key: key,
                    requestKey: requestKey,
                    failure: error
                )
                return
            }
            guard let livePhoto else {
                if !isDegraded {
                    markLivePhotoUnavailable(
                        key: key,
                        requestKey: requestKey,
                        failure: MediaFetchFailure.decode
                    )
                }
                return
            }

            livePhotoView.livePhoto = livePhoto
            livePhotoView.isMuted = isLivePhotoMuted
            livePhotoView.isHidden = false
            livePhotoReadyKey = key
            livePhotoUnavailableKey = nil
            syncMediaFrames()

            if isPressingForLivePhoto {
                startLivePhotoPlaybackIfAvailable()
            }

            guard !isDegraded else {
                return
            }
            livePhotoRequestCancellation = nil
            livePhotoPreparationTask = nil
            livePhotoRequestKey = nil
            livePhotoMediaRequestKey = nil
            slot?.completeLivePhotoFetch(requestKey: requestKey)
        }

        private func livePhotoTargetSize(in scrollView: UIScrollView) -> CGSize {
            let scale = max(UIScreen.main.scale, 1)
            return CGSize(
                width: max(scrollView.bounds.width * scale, 1),
                height: max(scrollView.bounds.height * scale, 1)
            )
        }

        private func startLivePhotoPlaybackIfAvailable() {
            guard livePhotoView.livePhoto != nil,
                  !livePhotoView.isHidden else {
                return
            }
            livePhotoView.isMuted = isLivePhotoMuted
            livePhotoView.startPlayback(with: .full)
        }

        private func markLivePhotoUnavailable(
            key: String,
            requestKey: MediaFetchRequestKey,
            failure: Error?
        ) {
            guard isCurrentLivePhotoRequest(key: key, requestKey: requestKey) else {
                return
            }
            livePhotoRequestCancellation = nil
            livePhotoPreparationTask = nil
            livePhotoRequestKey = nil
            livePhotoMediaRequestKey = nil
            livePhotoReadyKey = nil
            livePhotoUnavailableKey = key
            livePhotoView.livePhoto = nil
            livePhotoView.isHidden = true
            if let failure {
                slot?.failLivePhotoFetch(failure, requestKey: requestKey)
            } else {
                slot?.completeLivePhotoFetch(requestKey: requestKey)
            }
        }

        private func clearLivePhoto() {
            isPressingForLivePhoto = false
            livePhotoView.stopPlayback()
            scheduledLivePhotoRequestKey = nil
            cancelLivePhotoRequest(notifySlot: true, preserveCloudState: false)
            lastLivePhotoRequest = nil
            livePhotoReadyKey = nil
            livePhotoUnavailableKey = nil
            livePhotoView.livePhoto = nil
            livePhotoView.isMuted = true
            livePhotoView.isHidden = true
        }

        private func retryLivePhotoRequest() {
            guard let lastLivePhotoRequest else {
                return
            }
            livePhotoUnavailableKey = nil
            requestLivePhoto(
                source: lastLivePhotoRequest.source,
                targetSize: lastLivePhotoRequest.targetSize,
                key: lastLivePhotoRequest.presentationKey
            )
        }

        private func isCurrentLivePhotoRequest(
            key: String,
            requestKey: MediaFetchRequestKey
        ) -> Bool {
            livePhotoRequestKey == key && livePhotoMediaRequestKey == requestKey
        }

        private func cancelLivePhotoRequest(
            notifySlot: Bool,
            preserveCloudState: Bool,
            suppressAutomaticRetry: Bool = false,
            expectedCoordinatorGeneration: UInt64? = nil
        ) {
            if let expectedCoordinatorGeneration,
               expectedCoordinatorGeneration != livePhotoCoordinatorGeneration {
                return
            }
            livePhotoCoordinatorGeneration &+= 1
            let presentationKey = livePhotoRequestKey
            let mediaRequestKey = livePhotoMediaRequestKey
            livePhotoPreparationTask?.cancel()
            livePhotoPreparationTask = nil
            livePhotoRequestCancellation?.cancel()
            livePhotoRequestCancellation = nil
            livePhotoRequestKey = nil
            livePhotoMediaRequestKey = nil
            if suppressAutomaticRetry, let presentationKey {
                livePhotoUnavailableKey = presentationKey
            }
            if notifySlot, let mediaRequestKey {
                let requestSlot = slot
                Task { @MainActor in
                    requestSlot?.cancelLivePhotoFetch(
                        requestKey: mediaRequestKey,
                        preserveCloudState: preserveCloudState
                    )
                }
            }
        }
    }
}

private final class AnalysisRawZoomUIScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

extension DepthAnalyzerPreferences {
    /// Release uses the reviewed plane-growth threshold regardless of an older
    /// stored setting. Debug builds can still tune the clamped detector input.
    nonisolated static func resolvedPlaneGrowthStrictness(
        storedValue: Double,
        allowsDebugOverride: Bool = _isDebugAssertConfiguration()
    ) -> Double {
        guard allowsDebugOverride, storedValue.isFinite else {
            return DepthAnalysisPlaneSelectionState.defaultStrictness
        }
        return min(
            max(storedValue, DepthAnalysisPlaneSelectionState.minimumStrictness),
            DepthAnalysisPlaneSelectionState.maximumStrictness
        )
    }
}

private struct AnalysisToolPhotoStage: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let tool: AnalysisViewerTool
    let viewportSize: CGSize
    let isCurrent: Bool
    @Binding var heatmapOpacity: Double
    @Binding var comparisonPosition: Double
    let highlightPalette: AnalysisHighlightPalette
    let isPlaneGridAnimationEnabled: Bool
    @AppStorage(DepthAnalyzerPreferences.planeGrowthStrictnessKey)
    private var planeGrowthStrictness = DepthAnalyzerPreferences.defaultPlaneGrowthStrictness
    @State private var gridToastMessage: String?
    @State private var displayedGridToastID: UUID?

    var body: some View {
        let containerRect = DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
            imageSize: displayedImageSize,
            orientation: displayedImageOrientation,
            viewportSize: viewportSize
        )

        toolContent(size: containerRect.size)
            .frame(width: containerRect.width, height: containerRect.height)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .top) {
                analysisEdgeToast
                    .padding(.top, 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .position(x: containerRect.midX, y: containerRect.midY)
            .accessibilityLabel(tool.accessibilityLabel)
    }

    @ViewBuilder
    private func toolContent(size: CGSize) -> some View {
        switch tool {
        case .raw:
            EmptyView()
        case .twoD:
            twoDContent(size: size)
        case .threeD:
            threeDContent(size: size)
        }
    }

    @ViewBuilder
    private func twoDContent(size: CGSize) -> some View {
        if let input = slot.input {
            DepthAnalysisStageView(
                viewMode: .planes,
                image: input.image,
                imageOrientation: input.imageOrientation,
                depthMap: input.depthMap,
                heatmapImage: input.heatmap.image,
                validMaskImage: input.validMask.image,
                heatmapOpacity: heatmapOpacity,
                comparisonPosition: comparisonPosition,
                onComparisonPositionChanged: { newValue in
                    comparisonPosition = newValue
                },
                planeRegion: slot.planeSelection.selectedRegion,
                partialPlaneGridCells: slot.planeSelection.partialGridCells,
                planeGridProgress: slot.planeSelection.gridProgress,
                planeSeedPoint: slot.planeSelection.seedPoint,
                highlightPalette: highlightPalette,
                isPlaneGridAnimationEnabled: isPlaneGridAnimationEnabled,
                metadataSummary: nil,
                scoreSummary: nil,
                onSelectionCleared: {
                    slot.clearSelection()
                },
                onPlaneSeedSelected: { depthPoint in
                    slot.selectPlaneSeed(
                        depthPoint,
                        strictness: runtimePlaneGrowthStrictness
                    )
                }
            )
            .frame(width: size.width, height: size.height)
            .onAppear {
                syncPlaneGrowthStrictnessSettingIfCurrent()
            }
            .onChange(of: isCurrent) { _, _ in
                syncPlaneGrowthStrictnessSettingIfCurrent()
            }
            .onChange(of: planeGrowthStrictness) { _, _ in
                syncPlaneGrowthStrictnessSettingIfCurrent()
            }
            .onChange(of: slot.planeSelection.completedGridToastID) { _, toastID in
                showGridReadyToastIfNeeded(toastID)
            }
            .onChange(of: slot.planeSelection.generationID) { _, _ in
                hideGridToast()
            }
        } else {
            AnalysisToolLoadingView(
                slot: slot,
                title: "Preparing 2D analysis",
                size: size
            )
        }
    }

    private func syncPlaneGrowthStrictnessSettingIfCurrent() {
        guard isCurrent else {
            return
        }
        slot.updatePlaneGrowthStrictness(runtimePlaneGrowthStrictness)
    }

    private var runtimePlaneGrowthStrictness: Double {
        DepthAnalyzerPreferences.resolvedPlaneGrowthStrictness(
            storedValue: planeGrowthStrictness
        )
    }

    @ViewBuilder
    private func threeDContent(size: CGSize) -> some View {
        if let input = slot.input {
            PointCloudPreview(
                image: input.image,
                depthMap: input.depthMap,
                orientation: input.imageOrientation,
                selectedPlaneRegion: slot.planeSelection.selectedRegion,
                highlightColor: highlightPalette.uiColor,
                selection: .constant(nil),
                interactionState: .idle,
                allowsSelection: false,
                enablesMotionParallax: true,
                onSelectionBegan: { _ in },
                onSelectionChanged: { _ in },
                onSelectionEnded: { _ in },
                onSelectionCleared: { }
            )
            .frame(width: size.width, height: size.height)
        } else {
            AnalysisToolLoadingView(
                slot: slot,
                title: "Preparing 3D projection",
                size: size
            )
        }
    }

    private var displayedImageSize: CGSize? {
        if let input = slot.input {
            return CGSize(width: input.image.width, height: input.image.height)
        }
        if let displayPhoto = slot.displayPhoto {
            return displayPhoto.pixelSize
        }
        return slot.thumbnailImage?.size
    }

    private var displayedImageOrientation: CGImagePropertyOrientation {
        slot.input?.imageOrientation ?? slot.displayPhoto?.orientation ?? .up
    }

    @ViewBuilder
    private var analysisEdgeToast: some View {
        if tool == .twoD, let gridToastMessage {
            Text(gridToastMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.58), in: Capsule())
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("analysis.edgeToast")
        }
    }

    private func showGridReadyToastIfNeeded(_ toastID: UUID?) {
        guard tool == .twoD,
              isCurrent,
              let toastID,
              displayedGridToastID != toastID else {
            return
        }
        displayedGridToastID = toastID
        withAnimation(.easeInOut(duration: 0.18)) {
            gridToastMessage = "Grid ready"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard displayedGridToastID == toastID else {
                return
            }
            hideGridToast()
            slot.dismissCompletedGridToast(toastID)
        }
    }

    private func hideGridToast() {
        displayedGridToastID = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            gridToastMessage = nil
        }
    }
}

private struct AnalysisToolLoadingView: View {
    let slot: AnalysisPhotoSlot?
    let title: String
    let size: CGSize

    var body: some View {
        if let slot {
            AnalysisToolSlotLoadingView(slot: slot, title: title, size: size)
        } else {
            ProgressView(title)
                .tint(.white)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity)
                .background(Color.black)
        }
    }
}

private struct AnalysisToolSlotLoadingView: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let title: String
    let size: CGSize

    var body: some View {
        ZStack {
            Color.black

            if let input = slot.input {
                Image(decorative: input.image, scale: 1, orientation: input.imageOrientation.swiftUIImageOrientation)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.54)
            } else if let displayPhoto = slot.displayPhoto {
                Image(uiImage: displayPhoto.image)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.54)
            } else if let thumbnailImage = slot.thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.54)
            }

            if !slot.isOriginalLoading || slot.errorMessage != nil {
                VStack(spacing: 10) {
                    if let errorMessage = slot.errorMessage {
                        Image(systemName: slot.errorSystemImage)
                            .font(.title2.weight(.semibold))
                        Text(errorMessage)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.78))
                    } else {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(18)
                .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct CredentialPendingPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Generating credential", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))

            Text("This photo is still being processed in the TAPCam queue. Its credential will appear when processing finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension CGImagePropertyOrientation {
    var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        }
    }
}
