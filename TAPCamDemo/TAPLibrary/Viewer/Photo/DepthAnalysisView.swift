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

/// One detail visit owns one pager, toolbar and user-selected presentation.
/// The photo slot and video session only own the selected resource's work.
struct TAPLibraryViewer: View {
    let destination: TAPLibraryRouteAdapter.Destination
    let entries: [TAPLibraryViewerPagingEntry]
    let mediaFetcher: any LibraryMediaFetching
    let onCurrentEntryChanged: (TAPLibraryViewerPagingEntry) -> Void
    let onDeletionCompleted: (String, TAPLibraryViewerPagingEntry?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @StateObject private var store: TAPLibraryViewerStore
    @State private var deleteAlert: ViewerDeleteAlert?
    @State private var pagingInteractionState = AnalysisPagingInteractionState()
    @AppStorage(DepthAnalyzerPreferences.depthOverlayOpacityKey)
    private var heatmapOpacity = DepthAnalyzerPreferences.defaultDepthOverlayOpacity
    @AppStorage(CameraViewfinderHighlightPreference.storageKey)
    private var viewfinderHighlightRawValue = CameraViewfinderHighlightPreference.defaultValue.rawValue

    init(
        destination: TAPLibraryRouteAdapter.Destination,
        entries: [TAPLibraryViewerPagingEntry]? = nil,
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        photoLoader: DepthAnalysisProgressivePhotoLoader? = nil,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting = TAPVideoManifestDepthRegistrationAdapter(),
        onCurrentEntryChanged: @escaping (TAPLibraryViewerPagingEntry) -> Void = { _ in },
        onDeletionCompleted: @escaping (String, TAPLibraryViewerPagingEntry?) -> Void = { _, _ in }
    ) {
        self.destination = destination
        let entries = entries ?? [TAPLibraryViewerPagingEntry(id: destination.itemID, destination: destination)]
        self.entries = entries
        self.mediaFetcher = mediaFetcher
        self.onCurrentEntryChanged = onCurrentEntryChanged
        self.onDeletionCompleted = onDeletionCompleted
        _store = StateObject(wrappedValue: TAPLibraryViewerStore(
            entries: entries, currentItemID: destination.itemID, loader: photoLoader,
            mediaFetcher: mediaFetcher, registrationAdapter: registrationAdapter
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            let pixelLength = min(max(Int(ceil(max(geometry.size.width, geometry.size.height) * max(displayScale, 1))), 960), 4096)
            ZStack {
                TAPLibraryNativePagingView(
                    entries: store.windowPagingEntries,
                    currentItemID: store.currentItemID,
                    pageContentRevision: pageContentRevision,
                    pageBuilder: { entry, isCurrent, size in
                        page(entry, isCurrent, size, safeAreaInsets: geometry.safeAreaInsets)
                    },
                    onCurrentEntryChanged: { entry in
                        store.select(entry, pixelLength: pixelLength, prewarmCurrentPlaneGeometry: store.selectedTool == .threeD)
                        onCurrentEntryChanged(entry)
                    },
                    onPagingInteractionChanged: { isInteracting in
                        pagingInteractionState.isInteracting = isInteracting
                        if isInteracting { store.currentVideoSession?.beginInteractivePaging() }
                        else { store.currentVideoSession?.endInteractivePaging() }
                    },
                    shouldBeginPaging: shouldBeginPaging
                )
                .background(Color.black)

                if isDepthUnavailable {
                    DepthViewerUnavailableNotice(topSafeArea: geometry.safeAreaInsets.top)
                        .zIndex(4)
                }

                DepthViewerChromeView(
                    selectedModeID: store.selectedTool.rawValue,
                    modeItems: modeItems,
                    shareSubject: shareSubject,
                    shareResourceAccess: shareResourceAccess,
                    shareAccessibilityLabel: isVideo ? "Share video" : "Share photo",
                    deleteAccessibilityLabel: isVideo ? "Delete video" : "Delete photo",
                    bottomSafeArea: geometry.safeAreaInsets.bottom,
                    bottomAccessory: TAPVideoPlaybackTransportAccessory(model: store.currentVideoSession?.transportModel, isVideo: isVideo),
                    onModeTapped: { if let tool = AnalysisViewerTool(rawValue: $0) { store.selectedTool = tool } },
                    onDeleteTapped: { requestDelete(pixelLength: pixelLength) }
                )
                .zIndex(5)
            }
            .task(id: "\(pixelLength)-\(store.selectedTool.rawValue)") {
                store.ensureVisibleWindowLoaded(pixelLength: pixelLength, prewarmCurrentPlaneGeometry: store.selectedTool == .threeD)
            }
            .onChange(of: entries) { _, entries in
                store.reconcile(entries: entries, selectedItemID: destination.itemID, pixelLength: pixelLength)
            }
            .onChange(of: destination) { _, destination in
                store.reconcile(entries: entries, selectedItemID: destination.itemID, pixelLength: pixelLength)
            }
        }
        .background(Color.black)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarRole(.editor)
        .navigationTitle(Text(verbatim: ""))
        .ignoresSafeArea(.container, edges: .all)
        .alert(item: $deleteAlert) { alert in
            switch alert {
            case .pending(let entry, let pixelLength):
                let video = entry.isVideo
                return Alert(
                    title: Text(video ? "Delete unsaved video?" : "Delete unsaved photo?"),
                    message: Text(video
                        ? "This video has not finished exporting to Photos. Deleting it removes the local TAP copy and cannot be undone."
                        : "This capture has not finished exporting to Photos. Deleting it removes the local TAP copy and cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) { delete(entry, pixelLength: pixelLength) },
                    secondaryButton: .cancel()
                )
            case .failed(let video):
                return Alert(title: Text(video ? "Unable to delete video" : "Unable to delete photo"),
                             message: Text("Try again from TAP Library."), dismissButton: .default(Text("OK")))
            }
        }
        .onDisappear { store.cancelViewerRequests() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in store.handleMemoryWarning() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            store.currentSlot?.cancelCurrentMediaFetch()
            store.currentVideoSession?.handleDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            store.currentSlot?.retryLastMediaFetch()
            store.currentVideoSession?.resumeCanceledFetchAfterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapLibraryDidChange)) { notification in
            let change = notification.object as? TAPLibraryPendingCaptureChange
            Task { @MainActor in
                await store.currentSlot?.reloadPendingOriginalAfterLibraryChange(change)
                await store.currentVideoSession?.reloadPendingOriginalAfterLibraryChange(change)
            }
        }
    }

    private var isVideo: Bool { store.currentPagingEntry?.isVideo == true }
    private var isDepthUnavailable: Bool {
        guard store.selectedTool != .raw else { return false }
        if let session = store.currentVideoSession {
            return TAPVideoViewerModePolicy.effectiveTool(store.selectedTool,
                availability: session.registeredDepthAvailability,
                isThreeDDepthAvailable: session.isThreeDDepthAvailable) == .raw
        }
        return store.currentSlot?.analysisPhase == .failed && store.currentSlot?.originalResourceOwner.isReady == true
    }
    private var highlightPalette: AnalysisHighlightPalette {
        .resolved(viewfinderRawValue: viewfinderHighlightRawValue)
    }
    private var pageContentRevision: UInt64 {
        var hasher = Hasher()
        hasher.combine(store.contentGeneration)
        hasher.combine(store.selectedTool)
        hasher.combine(heatmapOpacity)
        hasher.combine(highlightPalette.uiColor.hash)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
    private var shareSubject: DepthAnalysisShareSubject? {
        guard let entry = store.currentPagingEntry else { return nil }
        switch entry.destination {
        case .analysis: return store.currentEntry.map(DepthAnalysisShareSubject.init(entry:))
        case .video(let route): return DepthAnalysisShareSubject(videoSource: route.source, itemID: entry.id)
        }
    }
    private var shareResourceAccess: DepthAnalysisShareResourceAccess? {
        if let slot = store.currentSlot {
            return DepthAnalysisShareResourceAccess(isReady: slot.originalResourceOwner.isReady, acquire: {
                slot.originalResourceOwner.acquireLease().map(DepthAnalysisShareOriginalResource.photo)
            }, acquirePrepared: { requiresSignedOriginal in
                .photo(try await slot.acquireOriginalResourceLease(requiresSignedOriginal: requiresSignedOriginal))
            })
        }
        if let session = store.currentVideoSession {
            return DepthAnalysisShareResourceAccess(isReady: session.isOriginalResourceReady, acquire: {
                (try? session.acquireOriginalResourceLease()).map(DepthAnalysisShareOriginalResource.video)
            }, acquirePrepared: { requiresSignedOriginal in
                .video(try await session.awaitOriginalResourceLease(requiresSignedOriginal: requiresSignedOriginal))
            })
        }
        return nil
    }
    private var modeItems: [DepthViewerModeItem] {
        if let session = store.currentVideoSession {
            return TAPVideoViewerModePolicy.items(availability: session.registeredDepthAvailability,
                selectedTool: store.selectedTool, isTwoDPlaybackReady: session.isTwoDPlaybackReady,
                isThreeDDepthAvailable: session.isThreeDDepthAvailable, isThreeDPlaybackReady: session.isThreeDPlaybackReady)
        }
        return AnalysisViewerTool.allCases.map(\.modeItem)
    }

    private func page(_ entry: TAPLibraryViewerPagingEntry, _ isCurrent: Bool, _ size: CGSize, safeAreaInsets: EdgeInsets) -> AnyView {
        if let photo = store.photoEntry(entry) {
            let slot = store.slot(for: photo)
            return AnyView(AnalysisNativePageView(
                slot: slot, tool: store.selectedTool, viewportSize: size,
                isCurrent: isCurrent, pagingInteractionState: pagingInteractionState,
                heatmapOpacity: $heatmapOpacity,
                topSafeArea: safeAreaInsets.top, highlightPalette: highlightPalette, mediaFetcher: mediaFetcher
            ).id(ObjectIdentifier(slot)))
        }
        if isCurrent, let session = store.videoSession(for: entry) {
            return AnyView(TAPVideoCurrentPlayback(session: session, selectedTool: store.selectedTool, overlayOpacity: heatmapOpacity)
                .frame(width: size.width, height: size.height))
        }
        return AnyView(TAPLibraryAdjacentMediaPreview(entry: entry, viewportSize: size,
            mediaFetcher: mediaFetcher))
    }

    private func shouldBeginPaging(at location: CGPoint, viewportSize: CGSize) -> Bool {
        // Photo projections arbitrate with the ancestor pan recognizer directly.
        guard store.selectedTool == .threeD,
              let session = store.currentVideoSession,
              session.isThreeDPlaybackReady,
              TAPVideoViewerModePolicy.effectiveTool(.threeD,
                  availability: session.registeredDepthAvailability,
                  isThreeDDepthAvailable: session.isThreeDDepthAvailable) == .threeD else { return true }
        return !DepthAnalysisViewerInteractionPolicy.pointCloudGestureRect(
            in: CGRect(origin: .zero, size: viewportSize)
        ).contains(location)
    }

    private func requestDelete(pixelLength: Int) {
        guard let entry = store.currentPagingEntry else { return }
        switch entry.destination {
        case .analysis(let route):
            if case .pendingCapture = route.source { deleteAlert = .pending(entry, pixelLength); return }
        case .video(let route):
            if route.source.requiresUnsavedDeleteConfirmation { deleteAlert = .pending(entry, pixelLength); return }
        }
        delete(entry, pixelLength: pixelLength)
    }

    private func delete(_ entry: TAPLibraryViewerPagingEntry, pixelLength: Int) {
        Task { @MainActor in
            do {
                switch entry.destination {
                case .analysis(let route): try await DepthAnalysisDeletionService.delete(source: route.source)
                case .video(let route): try await TAPVideoDeletionService.delete(source: route.source)
                }
                guard store.currentItemID == entry.id else { return }
                let next = store.removeCurrent(pixelLength: pixelLength)
                onDeletionCompleted(entry.id, next)
                if let next { onCurrentEntryChanged(next) } else { dismiss() }
            } catch is CancellationError {} catch { deleteAlert = .failed(entry.isVideo) }
        }
    }
}

private enum ViewerDeleteAlert: Hashable, Identifiable {
    case pending(TAPLibraryViewerPagingEntry, Int)
    case failed(Bool)
    var id: Self { self }
}

private struct TAPVideoCurrentPlayback: View {
    let session: TAPVideoPlaybackSession
    let selectedTool: AnalysisViewerTool
    let overlayOpacity: Double

    var body: some View {
        TAPVideoPlaybackContentSurface(session: session, selectedTool: .constant(effectiveTool),
            overlayOpacity: .constant(overlayOpacity), onRetry: session.retryCurrentFetch)
            .task(id: PlaybackTaskIdentity(session: ObjectIdentifier(session), request: session.requestKey)) {
                await session.startPlaybackSession()
            }
            .onChange(of: session.state) { _, state in
                if state == .ready { prepareTool() }
            }
            .onChange(of: selectedTool) { _, _ in prepareTool() }
    }

    private var effectiveTool: AnalysisViewerTool {
        TAPVideoViewerModePolicy.effectiveTool(selectedTool,
            availability: session.registeredDepthAvailability,
            isThreeDDepthAvailable: session.isThreeDDepthAvailable)
    }
    private func prepareTool() {
        switch selectedTool {
        case .raw: session.cancelTwoDPlaybackGate(); session.cancelThreeDPlaybackGate()
        case .twoD: session.prepareTwoDPlaybackGate()
        case .threeD: session.prepareThreeDPlaybackGate(smoothingEnabled: DepthAnalyzerPreferences.playbackSmoothingEnabled())
        }
    }
}

private struct PlaybackTaskIdentity: Hashable {
    let session: ObjectIdentifier
    let request: MediaFetchRequestKey?
}

private enum DepthAnalysisDeletionService {
    static func delete(source: DepthAnalysisSource) async throws {
        switch source {
        case .photosAsset(let assetID):
            try await PhotoLibraryWriter.deleteAsset(localIdentifier: assetID)
            try await TAPPendingCaptureStore.shared.removeExportedRecords(assetLocalIdentifier: assetID)
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        case .pendingCapture(let captureID):
            try await TAPPendingCaptureStore.shared.removeRecord(captureID: captureID)
        }
    }
}

private struct AnalysisNativePageView: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let tool: AnalysisViewerTool
    let viewportSize: CGSize
    let isCurrent: Bool
    let pagingInteractionState: AnalysisPagingInteractionState
    @Binding var heatmapOpacity: Double
    let topSafeArea: CGFloat
    let highlightPalette: AnalysisHighlightPalette
    let mediaFetcher: any LibraryMediaFetching
    @State private var projectionResult: (requestKey: MediaFetchRequestKey, state: DepthProjectionDisplayState)?

    var body: some View {
        ZStack {
            Color.black
            rawContent
                .clipShape(Path(effectiveTool == .raw
                    ? CGRect(origin: .zero, size: viewportSize)
                    : DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                        imageSize: displayedImageSize, orientation: displayedImageOrientation,
                        viewportSize: viewportSize)))
                .allowsHitTesting(!isCurrent || effectiveTool == .raw)
                .accessibilityHidden(isCurrent && effectiveTool != .raw)
                .transaction { $0.animation = nil }

            if let inputRequest = slot.analysisState.completedInputRequestKey {
                AnalysisToolPhotoStage(
                    slot: slot,
                    tool: isCurrent ? effectiveTool : .raw,
                    viewportSize: viewportSize,
                    isCurrent: isCurrent,
                    heatmapOpacity: $heatmapOpacity,
                    highlightPalette: highlightPalette,
                    isProjectionReady: projectionState == .ready,
                    onProjectionStateChanged: { state in
                        guard slot.analysisState.completedInputRequestKey == inputRequest else { return }
                        projectionResult = (inputRequest, state)
                    }
                )
                .id(inputRequest)
                .allowsHitTesting(isCurrent && effectiveTool != .raw)
                .accessibilityHidden(!isCurrent || effectiveTool == .raw)
                .transaction { $0.animation = nil }
            }

            if isCurrent && tool == .threeD && projectionState == .unavailable {
                DepthViewerUnavailableNotice(topSafeArea: topSafeArea)
            }

            AnalysisLivePhotoBadgeOverlay(
                source: slot.source,
                knownIsLivePhoto: slot.entry.albumEntry?.expectsPairedVideo,
                isCurrent: isCurrent,
                viewportSize: viewportSize,
                displayedImageSize: displayedImageSize,
                displayedImageOrientation: displayedImageOrientation,
                mediaFetcher: mediaFetcher
            )

            LibraryMediaViewerFetchOverlay(
                kind: .photo,
                state: isCurrent ? fetchOverlayState : .hidden,
                onRetry: slot.retryLastMediaFetch,
                imageSize: displayedImageSize,
                imageOrientation: displayedImageOrientation
            )
            .zIndex(4)
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
    }

    private var fetchOverlayState: LibraryMediaFetchOverlayState {
        let resourceState = LibraryMediaFetchOverlayState(
            slot.resolvedMediaFetchPhase(includeLivePhoto: effectiveTool == .raw)
        )
        guard resourceState == .hidden, effectiveTool != .raw else { return resourceState }
        if slot.input == nil { return .loading }
        if effectiveTool == .threeD && projectionState != .ready {
            return .loading
        }
        return .hidden
    }

    private var projectionState: DepthProjectionDisplayState {
        guard let projectionResult,
              projectionResult.requestKey == slot.analysisState.completedInputRequestKey else { return .preparing }
        return projectionResult.state
    }

    private var effectiveTool: AnalysisViewerTool {
        if tool == .threeD && projectionState == .unavailable { return .raw }
        // A complete original with a terminal depth decoding result cannot
        // supply this tool. Preserve the user's choice for the next resource.
        return slot.analysisPhase == .failed && slot.originalResourceOwner.isReady ? .raw : tool
    }

    private var rawContent: some View {
        ZStack {
            AnalysisRawZoomScrollView(
                slot: slot,
                source: slot.source,
                image: rawImage,
                isCurrent: isCurrent,
                isPagingInteracting: pagingInteractionState.isInteracting,
                mediaFetcher: mediaFetcher,
                isInteractionEnabled: effectiveTool == .raw
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

private struct DepthViewerUnavailableNotice: View {
    let topSafeArea: CGFloat

    var body: some View {
        VStack {
            Text("Depth unavailable; showing RAW")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.58), in: Capsule())
                .accessibilityIdentifier("tap.viewer.depthUnavailable")
            Spacer()
        }
        .padding(.top, topSafeArea + 52)
        .allowsHitTesting(false)
    }
}

@MainActor
@Observable
private final class AnalysisPagingInteractionState {
    var isInteracting = false
}

private struct AnalysisLivePhotoBadgeOverlay: View {
    let source: DepthAnalysisSource
    let knownIsLivePhoto: Bool?
    let isCurrent: Bool
    let viewportSize: CGSize
    let displayedImageSize: CGSize?
    let displayedImageOrientation: CGImagePropertyOrientation
    let mediaFetcher: any LibraryMediaFetching
    @State private var resolvedIsLivePhoto = false

    private var isLivePhoto: Bool {
        isCurrent && (knownIsLivePhoto ?? resolvedIsLivePhoto)
    }

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
        .task(id: isCurrent && knownIsLivePhoto == nil ? source.loadID : nil) {
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
        guard isCurrent, knownIsLivePhoto == nil else { return }

        let resolvedIsLivePhoto = await DepthAnalysisLivePhotoSourceResolver.isLivePhoto(
            source: source,
            mediaFetcher: mediaFetcher
        )
        guard !Task.isCancelled else {
            return
        }
        self.resolvedIsLivePhoto = resolvedIsLivePhoto
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

struct AnalysisRawZoomScrollView: UIViewRepresentable {
    let slot: AnalysisPhotoSlot
    let source: DepthAnalysisSource
    let image: UIImage?
    let isCurrent: Bool
    let isPagingInteracting: Bool
    let mediaFetcher: any LibraryMediaFetching
    var isInteractionEnabled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(slot: slot, mediaFetcher: mediaFetcher)
    }

    func makeUIView(context: Context) -> UIScrollView {
        context.coordinator.makeScrollView()
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(
            scrollView: scrollView,
            slot: slot,
            source: source,
            image: image,
            isCurrent: isCurrent,
            isPagingInteracting: isPagingInteracting,
            isInteractionEnabled: isInteractionEnabled
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
    final class Coordinator: NSObject, UIScrollViewDelegate, PHLivePhotoViewDelegate {
        private let mediaFetcher: any LibraryMediaFetching
        private weak var slot: AnalysisPhotoSlot?
        private let contentView = UIView()
        private let imageView = UIImageView()
        private let livePhotoView = PHLivePhotoView()
        private weak var scrollView: UIScrollView?
        private var currentSourceID: String?
        private var lastBoundsSize: CGSize = .zero
        private var isUpdatingLayout = false
        private var livePhotoRequestCancellation: LivePhotoRequestCancellation?
        private var livePhotoPreparationTask: Task<Void, Never>?
        private var scheduledLivePhotoRequestKey: String?
        private var livePhotoRequestKey: String?
        private var livePhotoMediaRequestKey: MediaFetchRequestKey?
        private var livePhotoCoordinatorGeneration: UInt64 = 0
        private var livePhotoReadyKey: String?
        private var livePhotoUnavailableKey: String?
        private var lastLivePhotoRequest: LivePhotoRequestContext?
        private var allowsLivePhotoPlayback = false

        init(
            slot: AnalysisPhotoSlot,
            mediaFetcher: any LibraryMediaFetching
        ) {
            self.slot = slot
            self.mediaFetcher = mediaFetcher
            super.init()
        }

        func makeScrollView() -> UIScrollView {
            let scrollView = AnalysisRawZoomUIScrollView()
            self.scrollView = scrollView
            scrollView.onLayout = { [weak self] scrollView in
                self?.handleLayout(in: scrollView)
            }
            scrollView.backgroundColor = .black
            scrollView.delegate = self
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = DepthAnalysisViewerInteractionPolicy.maximumPhotoScale
            scrollView.bounces = true
            scrollView.bouncesZoom = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.decelerationRate = .fast
            installImageView(in: scrollView)
            installDoubleTap(in: scrollView)
            // Photos owns press timing, visual feedback, and gesture arbitration.
            scrollView.addGestureRecognizer(livePhotoView.playbackGestureRecognizer)
            livePhotoView.playbackGestureRecognizer.isEnabled = false
            return scrollView
        }

        func installImageView(in scrollView: UIScrollView) {
            imageView.accessibilityIdentifier = "tap.viewer.photo"
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
            livePhotoView.isMuted = true
            livePhotoView.delegate = self

            contentView.addSubview(imageView)
            contentView.addSubview(livePhotoView)
            scrollView.addSubview(contentView)
        }

        func installDoubleTap(in scrollView: UIScrollView) {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            gesture.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(gesture)
        }

        func update(
            scrollView: UIScrollView,
            slot: AnalysisPhotoSlot,
            source: DepthAnalysisSource,
            image: UIImage?,
            isCurrent: Bool,
            isPagingInteracting: Bool,
            isInteractionEnabled: Bool = true
        ) {
            let sourceChanged = currentSourceID != source.loadID
            if self.slot !== slot || sourceChanged {
                clearLivePhoto()
                self.slot = slot
            }
            currentSourceID = source.loadID
            scrollView.isUserInteractionEnabled = isCurrent && isInteractionEnabled
            allowsLivePhotoPlayback = isCurrent && isInteractionEnabled && !isPagingInteracting
            livePhotoView.playbackGestureRecognizer.isEnabled = allowsLivePhotoPlayback
            if !allowsLivePhotoPlayback {
                livePhotoView.stopPlayback()
            }
            if imageView.image !== image {
                imageView.image = image
            }
            syncLayoutIfNeeded(in: scrollView, resetZoom: sourceChanged)
            // A mode change pauses playback while retaining this page's prepared
            // or in-flight Live Photo. A page that has never shown RAW does not
            // start a hidden request; leaving the page still releases it.
            if !isCurrent || isInteractionEnabled {
                syncLivePhoto(
                    in: scrollView,
                    source: source,
                    isCurrent: isCurrent
                )
            }
        }

        func dismantle() {
            allowsLivePhotoPlayback = false
            livePhotoView.playbackGestureRecognizer.isEnabled = false
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

        func livePhotoView(
            _ livePhotoView: PHLivePhotoView,
            canBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle
        ) -> Bool {
            allowsLivePhotoPlayback
                && scrollView?.isDragging != true
                && scrollView?.isDecelerating != true
                && scrollView?.isZooming != true
        }

        private func syncLayoutIfNeeded(in scrollView: UIScrollView, resetZoom: Bool = false) {
            let boundsSize = scrollView.bounds.size
            guard !isUpdatingLayout, boundsSize.width > 0, boundsSize.height > 0 else {
                return
            }
            let photo = imageView.image.map { AnalysisDisplayPhoto(image: $0) }
            let mediaSize = DepthAnalysisViewerInteractionPolicy.aspectFitRect(
                imageSize: photo?.pixelSize,
                orientation: photo?.orientation ?? .up,
                containerSize: boundsSize
            ).size
            guard resetZoom || boundsSize != lastBoundsSize || mediaSize != contentView.bounds.size else {
                syncPanAvailability(in: scrollView)
                return
            }

            isUpdatingLayout = true
            defer { isUpdatingLayout = false }
            let oldViewport = lastBoundsSize == .zero ? boundsSize : lastBoundsSize
            let oldCenter = contentView.convert(
                CGPoint(
                    x: scrollView.contentOffset.x + oldViewport.width * 0.5,
                    y: scrollView.contentOffset.y + oldViewport.height * 0.5
                ),
                from: scrollView
            )
            let normalizedCenter = resetZoom || contentView.bounds.isEmpty
                ? CGPoint(x: 0.5, y: 0.5)
                : CGPoint(
                    x: min(max(oldCenter.x / contentView.bounds.width, 0), 1),
                    y: min(max(oldCenter.y / contentView.bounds.height, 0), 1)
                )
            let scale = resetZoom ? 1 : scrollView.zoomScale
            lastBoundsSize = boundsSize
            scrollView.setZoomScale(1, animated: false)
            contentView.frame = CGRect(origin: .zero, size: mediaSize)
            syncMediaFrames()
            scrollView.contentSize = mediaSize
            scrollView.setZoomScale(scale, animated: false)
            centerContent(in: scrollView)
            let center = contentView.convert(
                CGPoint(x: normalizedCenter.x * mediaSize.width, y: normalizedCenter.y * mediaSize.height),
                to: scrollView
            )
            let inset = scrollView.contentInset
            scrollView.contentOffset = CGPoint(
                x: min(max(center.x - boundsSize.width * 0.5, -inset.left),
                       max(-inset.left, scrollView.contentSize.width - boundsSize.width + inset.right)),
                y: min(max(center.y - boundsSize.height * 0.5, -inset.top),
                       max(-inset.top, scrollView.contentSize.height - boundsSize.height + inset.bottom))
            )
            syncPanAvailability(in: scrollView)
        }

        private func centerContent(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }
            let horizontal = max((bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let vertical = max((bounds.height - scrollView.contentSize.height) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: vertical, left: horizontal, bottom: vertical, right: horizontal
            )
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
            livePhotoView.isHidden = false
            livePhotoReadyKey = key
            livePhotoUnavailableKey = nil
            syncMediaFrames()

            // An iCloud result may arrive while the native press is still held.
            let playbackGesture = livePhotoView.playbackGestureRecognizer
            if allowsLivePhotoPlayback,
               playbackGesture.state == .began || playbackGesture.state == .changed {
                livePhotoView.startPlayback(with: .full)
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        if let back = enclosingNavigationController?.interactivePopGestureRecognizer {
            panGestureRecognizer.require(toFail: back)
        }
        var ancestor = superview
        while let view = ancestor {
            if let pager = view as? UIScrollView {
                // At 1x the inner pan is disabled; once zoomed, the image owns
                // its drag before the surrounding asset pager can begin.
                pager.panGestureRecognizer.require(toFail: panGestureRecognizer)
                break
            }
            ancestor = view.superview
        }
    }

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
    let highlightPalette: AnalysisHighlightPalette
    let isProjectionReady: Bool
    let onProjectionStateChanged: (DepthProjectionDisplayState) -> Void
    @State private var hasOpenedProjection = false

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
            .clipped()
            .overlay(alignment: .top) {
                analysisEdgeToast
                    .padding(.top, 10)
            }
            .position(x: containerRect.midX, y: containerRect.midY)
            .accessibilityLabel(tool.accessibilityLabel)
    }

    private func toolContent(size: CGSize) -> some View {
        ZStack {
            if tool == .twoD {
                twoDContent(size: size)
            }
            if hasOpenedProjection || tool == .threeD {
                threeDContent(size: size)
                    .opacity(tool == .threeD && isProjectionReady ? 1 : 0)
                    .allowsHitTesting(tool == .threeD && isProjectionReady)
                    .accessibilityHidden(tool != .threeD || !isProjectionReady)
            }
        }
        .onChange(of: tool, initial: true) { _, tool in
            if tool == .threeD { hasOpenedProjection = true }
        }
    }

    @ViewBuilder
    private func twoDContent(size: CGSize) -> some View {
        if let input = slot.input {
            DepthAnalysisStageView(
                image: input.image,
                imageOrientation: input.imageOrientation,
                depthMap: input.depthMap,
                heatmapImage: input.heatmap.image,
                heatmapOpacity: heatmapOpacity,
                planeRegion: slot.planeSelection.selectedRegion,
                partialPlaneGridCells: slot.planeSelection.partialGridCells,
                planeGridProgress: slot.planeSelection.gridProgress,
                planeSeedPoint: slot.planeSelection.seedPoint,
                highlightPalette: highlightPalette,

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
                enablesMotionParallax: isCurrent && tool == .threeD,
                onDisplayStateChanged: onProjectionStateChanged
            )
            .frame(width: size.width, height: size.height)
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
