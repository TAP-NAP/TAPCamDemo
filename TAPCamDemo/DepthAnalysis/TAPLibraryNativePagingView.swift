//
//  TAPLibraryNativePagingView.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

/// Small in-memory handoff between an adjacent poster and the renderer that
/// becomes current after the page settles. It avoids a black frame and a
/// duplicate PhotoKit/decode request without retaining original media.
@MainActor
final class TAPLibraryPagingPreviewCache {
    static let shared = TAPLibraryPagingPreviewCache()

    private let storage = NSCache<NSString, UIImage>()

    private init() {
        storage.countLimit = 12
    }

    func image(for itemID: String) -> UIImage? {
        storage.object(forKey: itemID as NSString)
    }

    func insert(_ image: UIImage, for itemID: String) {
        storage.setObject(image, forKey: itemID as NSString)
    }
}

/// Lightweight visual identity used by the shared photo/video pager.
/// Heavy media ownership remains with the committed current renderer.
nonisolated struct TAPLibraryViewerPagingEntry: Identifiable, Equatable {
    let id: String
    let destination: DepthAlbumRouteAdapter.Destination
    let expectsPairedVideo: Bool

    init(
        id: String,
        destination: DepthAlbumRouteAdapter.Destination,
        expectsPairedVideo: Bool = false
    ) {
        self.id = id
        self.destination = destination
        self.expectsPairedVideo = expectsPairedVideo
    }

    init(_ entry: DepthAlbumDeletionContext.Entry) {
        id = entry.id
        destination = entry.destination
        expectsPairedVideo = entry.expectsPairedVideo
    }
}

/// The single native horizontal paging implementation used by TAP Library
/// photo, Live Photo, and video viewers.
///
/// Only the committed page is interactive. Adjacent pages are deliberately
/// lightweight previews, so dragging across a video never creates an
/// off-screen AVPlayer or claims audio.
struct TAPLibraryNativePagingView: UIViewRepresentable {
    let entries: [TAPLibraryViewerPagingEntry]
    let currentItemID: String
    let pageSpacing: CGFloat
    let pageContentRevision: UInt64
    let pageBuilder: (TAPLibraryViewerPagingEntry, Bool, CGSize) -> AnyView
    let onCurrentEntryChanged: (TAPLibraryViewerPagingEntry) -> Void
    let onPagingInteractionChanged: (Bool) -> Void
    let shouldBeginPaging: (CGPoint, CGSize) -> Bool

    init(
        entries: [TAPLibraryViewerPagingEntry],
        currentItemID: String,
        pageSpacing: CGFloat = DepthAnalysisViewerInteractionPolicy.nativePageSpacing,
        pageContentRevision: UInt64 = 0,
        pageBuilder: @escaping (TAPLibraryViewerPagingEntry, Bool, CGSize) -> AnyView,
        onCurrentEntryChanged: @escaping (TAPLibraryViewerPagingEntry) -> Void,
        onPagingInteractionChanged: @escaping (Bool) -> Void = { _ in },
        shouldBeginPaging: @escaping (CGPoint, CGSize) -> Bool = { _, _ in true }
    ) {
        self.entries = entries
        self.currentItemID = currentItemID
        self.pageSpacing = pageSpacing
        self.pageContentRevision = pageContentRevision
        self.pageBuilder = pageBuilder
        self.onCurrentEntryChanged = onCurrentEntryChanged
        self.onPagingInteractionChanged = onPagingInteractionChanged
        self.shouldBeginPaging = shouldBeginPaging
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        context.coordinator.makeScrollView()
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(parent: self, scrollView: scrollView)
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.cancelInteractionForTeardown()
        (scrollView as? TAPLibraryPagingScrollView)?.shouldBeginPaging = nil
        (scrollView as? TAPLibraryPagingScrollView)?.onViewportSizeChanged = nil
        scrollView.delegate = nil
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private var parent: TAPLibraryNativePagingView?
        private var hosts: [UIHostingController<AnyView>] = []
        private var hostConfigurations: [HostConfiguration?] = []
        private var isProgrammaticScroll = false
        private var isPagingInteractionActive = false
        private var isAwaitingAnimatedReset = false
        private var committedTargetID: String?
        private var observedCurrentItemID: String?
        private var interactionEntries: [TAPLibraryViewerPagingEntry]?
        private var interactionCurrentItemID: String?
        private var interactionContentRevision: UInt64?

        func installHosts(in scrollView: UIScrollView) {
            guard hosts.isEmpty else {
                return
            }
            hosts = (0..<3).map { _ in
                let host = UIHostingController(rootView: AnyView(Color.black))
                // Media fills the viewport; the outer viewer lays out its chrome.
                host.safeAreaRegions = []
                host.view.backgroundColor = .black
                host.view.isOpaque = true
                scrollView.addSubview(host.view)
                return host
            }
            hostConfigurations = Array(repeating: nil, count: hosts.count)
        }

        func makeScrollView() -> UIScrollView {
            let scrollView = TAPLibraryPagingScrollView()
            scrollView.backgroundColor = .black
            scrollView.isPagingEnabled = true
            scrollView.alwaysBounceHorizontal = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.decelerationRate = .fast
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
            scrollView.onViewportSizeChanged = { [weak self] scrollView in
                guard let self, let parent = self.parent else { return }
                self.update(parent: parent, scrollView: scrollView)
            }
            installHosts(in: scrollView)
            return scrollView
        }

        func update(parent: TAPLibraryNativePagingView, scrollView: UIScrollView) {
            self.parent = parent
            (scrollView as? TAPLibraryPagingScrollView)?.shouldBeginPaging = {
                location, viewportSize in
                let pageSize = TAPLibraryViewerPagingPolicy.pageContentSize(
                    viewportSize: viewportSize,
                    pageSpacing: parent.pageSpacing
                )
                let pageLocation = TAPLibraryViewerPagingPolicy.pageLocation(
                    viewportLocation: location,
                    viewportSize: viewportSize,
                    pageSpacing: parent.pageSpacing
                )
                return parent.shouldBeginPaging(pageLocation, pageSize)
            }
            if observedCurrentItemID != parent.currentItemID {
                observedCurrentItemID = parent.currentItemID
                committedTargetID = nil
            }
            let isWaitingForCommittedRoute = committedTargetID != nil
                && committedTargetID != parent.currentItemID
            configure(
                scrollView: scrollView,
                parent: parent,
                forceResetOffset: !scrollView.isDragging
                    && !scrollView.isDecelerating
                    && !isAwaitingAnimatedReset
                    && !isWaitingForCommittedRoute
            )
        }

        private func configure(
            scrollView: UIScrollView,
            parent: TAPLibraryNativePagingView,
            forceResetOffset: Bool,
            animatedResetOffset: Bool = false
        ) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }

            let entries = interactionEntries ?? parent.entries
            let currentItemID = interactionCurrentItemID ?? parent.currentItemID
            let contentRevision = interactionContentRevision
                ?? parent.pageContentRevision
            let currentIndex = entries.firstIndex(where: {
                $0.id == currentItemID
            }) ?? 0
            let pageWidth = bounds.width
            let spacing = min(parent.pageSpacing, max(pageWidth - 1, 0))
            let pageSize = CGSize(
                width: max(pageWidth - spacing, 1),
                height: bounds.height
            )
            scrollView.contentSize = CGSize(
                width: pageWidth * CGFloat(max(entries.count, 1)),
                height: bounds.height
            )

            for index in hosts.indices {
                let host = hosts[index]
                host.view.frame = CGRect(
                    x: CGFloat(index) * pageWidth + spacing * 0.5,
                    y: 0,
                    width: pageSize.width,
                    height: pageSize.height
                )

                guard entries.indices.contains(index) else {
                    if hostConfigurations[index] != nil {
                        host.rootView = AnyView(Color.black)
                        hostConfigurations[index] = nil
                    }
                    host.view.isHidden = true
                    host.view.isUserInteractionEnabled = false
                    host.view.accessibilityElementsHidden = true
                    continue
                }

                let entry = entries[index]
                let isCurrent = entry.id == currentItemID
                host.view.isHidden = false
                host.view.isUserInteractionEnabled = isCurrent
                host.view.accessibilityElementsHidden = !isCurrent
                let configuration = HostConfiguration(
                    entry: entry,
                    isCurrent: isCurrent,
                    pageSize: pageSize,
                    contentRevision: contentRevision
                )
                if hostConfigurations[index] != configuration {
                    host.rootView = parent.pageBuilder(entry, isCurrent, pageSize)
                    hostConfigurations[index] = configuration
                }
            }

            guard forceResetOffset else {
                return
            }
            let targetOffset = CGPoint(x: CGFloat(currentIndex) * pageWidth, y: 0)
            if abs(scrollView.contentOffset.x - targetOffset.x) > 0.5
                || scrollView.contentOffset.y != 0 {
                if animatedResetOffset {
                    isAwaitingAnimatedReset = true
                    scrollView.setContentOffset(targetOffset, animated: true)
                    return
                }
                isProgrammaticScroll = true
                scrollView.setContentOffset(targetOffset, animated: false)
                isProgrammaticScroll = false
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isAwaitingAnimatedReset = false
            interactionEntries = parent?.entries
            interactionCurrentItemID = parent?.currentItemID
            interactionContentRevision = parent?.pageContentRevision
            committedTargetID = nil
            beginInteractionIfNeeded()
        }

        func scrollViewDidEndDragging(
            _ scrollView: UIScrollView,
            willDecelerate decelerate: Bool
        ) {
            guard !decelerate else {
                return
            }
            finishPaging(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishPaging(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            isAwaitingAnimatedReset = false
            finishPaging(scrollView)
        }

        private func finishPaging(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll, let parent else {
                finishInteractionIfNeeded(scrollView: scrollView)
                return
            }
            defer {
                if !isAwaitingAnimatedReset {
                    finishInteractionIfNeeded(scrollView: scrollView)
                }
            }

            let settledEntries = interactionEntries ?? parent.entries
            let settledCurrentItemID = interactionCurrentItemID
                ?? parent.currentItemID
            guard let currentIndex = settledEntries.firstIndex(where: {
                $0.id == settledCurrentItemID
            }) else {
                configure(scrollView: scrollView, parent: parent, forceResetOffset: true)
                return
            }

            switch TAPLibraryViewerPagingPolicy.settlement(
                currentIndex: currentIndex,
                pageCount: settledEntries.count,
                contentOffsetX: scrollView.contentOffset.x,
                pageWidth: scrollView.bounds.width
            ) {
            case .stay:
                configure(
                    scrollView: scrollView,
                    parent: parent,
                    forceResetOffset: true,
                    animatedResetOffset: true
                )
            case .move(let offset):
                let targetIndex = currentIndex + offset
                guard settledEntries.indices.contains(targetIndex) else {
                    configure(scrollView: scrollView, parent: parent, forceResetOffset: true)
                    return
                }
                let target = settledEntries[targetIndex]
                guard let freshTarget = parent.entries.first(where: {
                    $0.id == target.id
                }) else {
                    configure(
                        scrollView: scrollView,
                        parent: parent,
                        forceResetOffset: true,
                        animatedResetOffset: true
                    )
                    return
                }
                guard committedTargetID != target.id else {
                    return
                }
                committedTargetID = target.id
                // Identity is frozen for gesture semantics, while source and
                // Live-Photo classification come from the latest catalog.
                parent.onCurrentEntryChanged(freshTarget)
            }
        }

        private func beginInteractionIfNeeded() {
            guard !isPagingInteractionActive else {
                return
            }
            isPagingInteractionActive = true
            parent?.onPagingInteractionChanged(true)
        }

        func finishInteractionIfNeeded(scrollView: UIScrollView? = nil) {
            guard isPagingInteractionActive else {
                return
            }
            isPagingInteractionActive = false
            interactionEntries = nil
            interactionCurrentItemID = nil
            interactionContentRevision = nil
            if committedTargetID == nil,
               let scrollView,
               let parent {
                configure(
                    scrollView: scrollView,
                    parent: parent,
                    forceResetOffset: true
                )
            }
            parent?.onPagingInteractionChanged(false)
        }

        func cancelInteractionForTeardown() {
            isPagingInteractionActive = false
            isAwaitingAnimatedReset = false
            interactionEntries = nil
            interactionCurrentItemID = nil
            interactionContentRevision = nil
            parent = nil
        }

        private struct HostConfiguration: Equatable {
            let entry: TAPLibraryViewerPagingEntry
            let isCurrent: Bool
            let pageSize: CGSize
            let contentRevision: UInt64
        }

    }
}

private final class TAPLibraryPagingScrollView: UIScrollView {
    var shouldBeginPaging: ((CGPoint, CGSize) -> Bool)?
    var onViewportSizeChanged: ((UIScrollView) -> Void)?
    private var laidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        onViewportSizeChanged?(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let back = enclosingNavigationController?.interactivePopGestureRecognizer {
            panGestureRecognizer.require(toFail: back)
        }
    }

    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panGestureRecognizer,
              let shouldBeginPaging else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        let location = gestureRecognizer.location(in: self)
        let visibleLocation = CGPoint(
            x: location.x - contentOffset.x,
            y: location.y - contentOffset.y
        )
        return shouldBeginPaging(visibleLocation, bounds.size)
            && super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

/// Adjacent mixed-media pages intentionally load only a bounded poster. The
/// committed renderer replaces this preview after the native page settles.
struct TAPLibraryAdjacentMediaPreview: View {
    let entry: TAPLibraryViewerPagingEntry
    let viewportSize: CGSize
    let mediaFetcher: any LibraryMediaFetching

    @State private var image: UIImage?
    @State private var didFinishLoading = false

    init(
        entry: TAPLibraryViewerPagingEntry,
        viewportSize: CGSize,
        mediaFetcher: any LibraryMediaFetching
    ) {
        self.entry = entry
        self.viewportSize = viewportSize
        self.mediaFetcher = mediaFetcher
        _image = State(
            initialValue: TAPLibraryPagingPreviewCache.shared.image(for: entry.id)
        )
    }

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if !didFinishLoading {
                ProgressView()
                    .tint(.white.opacity(0.72))
            } else {
                Image(systemName: previewPlaceholderSystemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: entry.id) {
            let itemID = entry.id
            image = TAPLibraryPagingPreviewCache.shared.image(for: itemID)
            didFinishLoading = image != nil
            if image != nil {
                return
            }
            let loadedImage = await loadPreview()
            guard !Task.isCancelled else {
                return
            }
            if let loadedImage {
                TAPLibraryPagingPreviewCache.shared.insert(loadedImage, for: itemID)
            }
            image = loadedImage
            didFinishLoading = true
        }
    }

    private var previewPlaceholderSystemImage: String {
        switch entry.destination {
        case .analysis:
            "photo"
        case .video:
            "video"
        }
    }

    private func loadPreview() async -> UIImage? {
        let pixelLength = min(
            max(Int(ceil(max(viewportSize.width, viewportSize.height) * 2)), 640),
            1_600
        )
        switch entry.destination {
        case .analysis(let route):
            return await DepthAnalysisProgressivePhotoLoader(
                mediaFetcher: mediaFetcher
            ).thumbnail(source: route.source, pixelLength: pixelLength)
        case .video(let route):
            let requestKey = MediaFetchRequestKey(
                itemID: route.source.libraryMediaID,
                generation: 0,
                purpose: .videoOriginal
            )
            return await TAPVideoPlaybackResourceLoader.adjacentPreviewImage(
                source: route.source,
                originalRequestKey: requestKey,
                mediaFetcher: mediaFetcher
            )
        }
    }
}

@MainActor
extension UIView {
    var enclosingNavigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController,
               let navigation = controller.navigationController {
                return navigation
            }
            responder = current.next
        }
        return nil
    }
}
