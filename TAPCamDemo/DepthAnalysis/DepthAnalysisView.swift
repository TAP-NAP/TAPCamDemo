//
//  DepthAnalysisView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import ImageIO
import OSLog
import SwiftUI
import UIKit

/// Independent browser/analysis surface for saved TAP Depth HEIC files.
///
/// The camera view links here through a thumbnail only. The default state is a
/// Photos-like browser where the bottom capsule switches the centered primary
/// surface between RAW, 2D, and 3D.
struct DepthAnalysisView: View {
    private let onCurrentAlbumEntryChanged: ((DepthAnalysisAlbumContext.Entry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @StateObject private var carouselStore: DepthAnalysisCarouselStore
    @State private var heatmapOpacity = 0.58
    @State private var selectedTool = AnalysisViewerTool.raw
    @State private var shareRequest: DepthAnalysisShareRequest?
    @State private var deleteRequest: DepthAnalysisDeleteRequest?
    @State private var deleteAlert: DepthAnalysisDeleteAlert?

    init(
        source: DepthAnalysisSource,
        albumContext: DepthAnalysisAlbumContext? = nil,
        onCurrentAlbumEntryChanged: ((DepthAnalysisAlbumContext.Entry) -> Void)? = nil
    ) {
        _carouselStore = StateObject(
            wrappedValue: DepthAnalysisCarouselStore(
                source: source,
                albumContext: albumContext
            )
        )
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
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
        .sheet(item: $shareRequest) { request in
            DepthAnalysisShareSheet(source: request.source)
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete photo?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                deleteConfirmedItem()
            }
            Button("Cancel", role: .cancel) {
                deleteRequest = nil
            }
        } message: {
            Text("This removes the current item from TAP Library.")
        }
        .alert(item: $deleteAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
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
                    selectedTool: selectedTool,
                    displayPixelLength: displayPixelLength,
                    heatmapOpacity: $heatmapOpacity,
                    onCurrentEntryChanged: handleCurrentEntryChanged,
                    onEdgeBack: {
                        dismiss()
                    }
                )
                .frame(width: viewportSize.width, height: viewportSize.height)
                .background(Color.black)

                DepthAnalysisViewerChromeView(
                    selectedTool: selectedTool,
                    heatmapOpacity: $heatmapOpacity,
                    topSafeArea: safeAreaInsets.top,
                    bottomSafeArea: safeAreaInsets.bottom,
                    onBackTapped: {
                        dismiss()
                    },
                    onShareTapped: presentShareSheet,
                    onToolTapped: handleToolTapped,
                    onDeleteTapped: confirmDeleteCurrentItem
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

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                deleteRequest != nil
            },
            set: { isPresented in
                if !isPresented {
                    deleteRequest = nil
                }
            }
        )
    }

    private func presentShareSheet() {
        guard let source = carouselStore.currentEntry?.source else {
            return
        }
        shareRequest = DepthAnalysisShareRequest(source: source)
    }

    private func confirmDeleteCurrentItem() {
        guard let source = carouselStore.currentEntry?.source else {
            return
        }
        deleteRequest = DepthAnalysisDeleteRequest(source: source)
    }

    private func deleteConfirmedItem() {
        guard let request = deleteRequest else {
            return
        }
        deleteRequest = nil

        Task { @MainActor in
            do {
                try await DepthAnalysisDeletionService.delete(source: request.source)
                dismiss()
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

    private static func displayPixelLength(viewportSize: CGSize, displayScale: CGFloat) -> Int {
        let viewportMaxLength = max(viewportSize.width, viewportSize.height)
        let scaledLength = Int(ceil(viewportMaxLength * max(displayScale, 1)))
        return min(max(scaledLength, 960), 4096)
    }
}

private struct DepthAnalysisShareRequest: Identifiable {
    let source: DepthAnalysisSource

    var id: String {
        source.loadID
    }
}

private struct DepthAnalysisDeleteRequest: Identifiable {
    let source: DepthAnalysisSource

    var id: String {
        source.loadID
    }
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
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        case .pendingCapture(let captureID):
            try await TAPPendingCaptureStore.shared.removeRecord(captureID: captureID)
        }
    }
}

private struct AnalysisPhotoCarouselView: View {
    @ObservedObject var store: DepthAnalysisCarouselStore
    let selectedTool: AnalysisViewerTool
    let displayPixelLength: Int
    @Binding var heatmapOpacity: Double
    let onCurrentEntryChanged: (DepthAnalysisCarouselEntry) -> Void
    let onEdgeBack: () -> Void

    var body: some View {
        AnalysisNativePagingView(
            store: store,
            selectedTool: selectedTool,
            displayPixelLength: displayPixelLength,
            heatmapOpacity: $heatmapOpacity,
            onCurrentEntryChanged: onCurrentEntryChanged,
            onEdgeBack: onEdgeBack
        )
        .background(Color.black)
        .accessibilityLabel("Photo carousel")
        .task(id: "\(selectedTool.rawValue)-\(displayPixelLength)") {
            store.ensureVisibleWindowLoaded(
                pixelLength: displayPixelLength,
                loadCurrentAnalysis: selectedTool != .raw,
                prewarmCurrentPlaneGeometry: selectedTool == .threeD
            )
        }
    }
}

private struct AnalysisNativePagingView: UIViewRepresentable {
    @ObservedObject var store: DepthAnalysisCarouselStore
    let selectedTool: AnalysisViewerTool
    let displayPixelLength: Int
    @Binding var heatmapOpacity: Double
    let onCurrentEntryChanged: (DepthAnalysisCarouselEntry) -> Void
    let onEdgeBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.isPagingEnabled = true
        scrollView.bounces = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.delegate = context.coordinator
        scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.installHosts(in: scrollView)
        context.coordinator.installEdgeBackGesture(in: scrollView, onEdgeBack: onEdgeBack)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(parent: self, scrollView: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private var parent: AnalysisNativePagingView?
        private var hosts: [UIHostingController<AnyView>] = []
        private var isProgrammaticScroll = false
        private var edgeBackAction: (() -> Void)?

        func installHosts(in scrollView: UIScrollView) {
            guard hosts.isEmpty else {
                return
            }
            hosts = (0..<3).map { _ in
                let host = UIHostingController(rootView: AnyView(Color.black))
                host.view.backgroundColor = .black
                host.view.isOpaque = true
                scrollView.addSubview(host.view)
                return host
            }
        }

        func installEdgeBackGesture(in scrollView: UIScrollView, onEdgeBack: @escaping () -> Void) {
            edgeBackAction = onEdgeBack
            guard scrollView.gestureRecognizers?.contains(where: { $0 is UIScreenEdgePanGestureRecognizer }) != true else {
                return
            }
            let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeBack(_:)))
            gesture.edges = .left
            gesture.delegate = self
            scrollView.addGestureRecognizer(gesture)
        }

        func update(parent: AnalysisNativePagingView, scrollView: UIScrollView) {
            self.parent = parent
            edgeBackAction = parent.onEdgeBack
            configure(
                scrollView: scrollView,
                parent: parent,
                forceResetOffset: !scrollView.isDragging && !scrollView.isDecelerating
            )
        }

        private func configure(
            scrollView: UIScrollView,
            parent: AnalysisNativePagingView,
            forceResetOffset: Bool
        ) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }

            let window = parent.store.windowEntries()
            let currentPosition = window.firstIndex { $0.offset == 0 } ?? 0
            let pageWidth = bounds.width
            let pageSpacing = min(
                DepthAnalysisViewerInteractionPolicy.nativePageSpacing,
                max(pageWidth - 1, 0)
            )
            let pageContentSize = CGSize(
                width: max(pageWidth - pageSpacing, 1),
                height: bounds.height
            )
            scrollView.contentSize = CGSize(width: bounds.width * CGFloat(max(window.count, 1)), height: bounds.height)

            for index in hosts.indices {
                let host = hosts[index]
                host.view.frame = CGRect(
                    x: CGFloat(index) * pageWidth + pageSpacing * 0.5,
                    y: 0,
                    width: pageContentSize.width,
                    height: pageContentSize.height
                )

                guard window.indices.contains(index) else {
                    host.rootView = AnyView(Color.black)
                    host.view.isHidden = true
                    continue
                }

                let item = window[index]
                host.view.isHidden = false
                host.rootView = AnyView(
                    AnalysisNativePageView(
                        slot: parent.store.slot(for: item.entry),
                        tool: parent.selectedTool,
                        viewportSize: pageContentSize,
                        isCurrent: item.offset == 0,
                        heatmapOpacity: parent.$heatmapOpacity
                    )
                )
            }

            let targetOffset = CGPoint(x: CGFloat(currentPosition) * pageWidth, y: 0)
            guard forceResetOffset else {
                return
            }
            if abs(scrollView.contentOffset.x - targetOffset.x) > 0.5 || scrollView.contentOffset.y != 0 {
                isProgrammaticScroll = true
                scrollView.setContentOffset(targetOffset, animated: false)
                isProgrammaticScroll = false
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else {
                return
            }
            finishPaging(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishPaging(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            finishPaging(scrollView)
        }

        private func finishPaging(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll,
                  let parent,
                  scrollView.bounds.width > 0 else {
                return
            }
            let window = parent.store.windowEntries()
            guard !window.isEmpty else {
                return
            }
            let currentPosition = window.firstIndex { $0.offset == 0 } ?? 0
            let page = min(
                max(Int(round(scrollView.contentOffset.x / scrollView.bounds.width)), 0),
                window.count - 1
            )
            let offset = page - currentPosition
            guard offset != 0 else {
                configure(scrollView: scrollView, parent: parent, forceResetOffset: true)
                return
            }
            guard let entry = parent.store.move(
                offset: offset,
                pixelLength: parent.displayPixelLength,
                loadCurrentAnalysis: parent.selectedTool != .raw,
                prewarmCurrentPlaneGeometry: parent.selectedTool == .threeD
            ) else {
                configure(scrollView: scrollView, parent: parent, forceResetOffset: true)
                return
            }
            parent.onCurrentEntryChanged(entry)
            configure(scrollView: scrollView, parent: parent, forceResetOffset: true)
        }

        @objc private func handleEdgeBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else {
                return
            }
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            let predicted = CGSize(
                width: translation.x + velocity.x * 0.12,
                height: translation.y + velocity.y * 0.12
            )
            guard AnalysisEdgeBackPolicy.shouldReturn(
                startX: 0,
                translation: CGSize(width: translation.x, height: translation.y),
                predictedTranslation: predicted
            ) else {
                return
            }
            edgeBackAction?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIScreenEdgePanGestureRecognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let parent,
                  let scrollView = gestureRecognizer.view as? UIScrollView,
                  gestureRecognizer === scrollView.panGestureRecognizer,
                  parent.selectedTool != .raw,
                  let toolContainerRect = currentToolContainerRect(in: scrollView, parent: parent) else {
                return true
            }

            let location = gestureRecognizer.location(in: scrollView)
            let visibleX: CGFloat
            if location.x >= scrollView.contentOffset.x,
               location.x <= scrollView.contentOffset.x + scrollView.bounds.width {
                visibleX = location.x - scrollView.contentOffset.x
            } else {
                visibleX = location.x
            }
            let visibleLocation = CGPoint(x: visibleX, y: location.y)
            let shouldBegin = !toolContainerRect.contains(visibleLocation)
            return shouldBegin
        }

        private func currentToolContainerRect(
            in scrollView: UIScrollView,
            parent: AnalysisNativePagingView
        ) -> CGRect? {
            guard let slot = parent.store.currentSlot else {
                return nil
            }
            if let input = slot.input {
                return DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                    imageSize: CGSize(width: input.image.width, height: input.image.height),
                    orientation: input.imageOrientation,
                    viewportSize: scrollView.bounds.size
                )
            }
            if let displayPhoto = slot.displayPhoto {
                return DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                    imageSize: displayPhoto.pixelSize,
                    orientation: displayPhoto.orientation,
                    viewportSize: scrollView.bounds.size
                )
            }
            if let thumbnailImage = slot.thumbnailImage {
                return DepthAnalysisViewerInteractionPolicy.centeredToolContainerRect(
                    imageSize: thumbnailImage.size,
                    orientation: .up,
                    viewportSize: scrollView.bounds.size
                )
            }
            return nil
        }
    }
}

private struct AnalysisNativePageView: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let tool: AnalysisViewerTool
    let viewportSize: CGSize
    let isCurrent: Bool
    @Binding var heatmapOpacity: Double

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
                    heatmapOpacity: $heatmapOpacity
                )
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
    }

    private var rawContent: some View {
        ZStack {
            AnalysisRawZoomScrollView(
                image: rawImage,
                imageIdentifier: rawImageIdentifier,
                isCurrent: isCurrent
            )
            .frame(width: viewportSize.width, height: viewportSize.height)

            if slot.displayPhase == .displayLoading, rawImage == nil {
                AnalysisPhotoProgressBadge(progress: nil)
            }

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
}

private struct AnalysisRawZoomScrollView: UIViewRepresentable {
    let image: UIImage?
    let imageIdentifier: String
    let isCurrent: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(
            scrollView: scrollView,
            image: image,
            imageIdentifier: imageIdentifier,
            isCurrent: isCurrent
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private let imageView = UIImageView()
        private var currentImageIdentifier: String?
        private var lastBoundsSize: CGSize = .zero

        func installImageView(in scrollView: UIScrollView) {
            imageView.backgroundColor = .black
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            scrollView.addSubview(imageView)
        }

        func installDoubleTap(in scrollView: UIScrollView) {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            gesture.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(gesture)
        }

        func update(
            scrollView: UIScrollView,
            image: UIImage?,
            imageIdentifier: String,
            isCurrent: Bool
        ) {
            scrollView.isUserInteractionEnabled = isCurrent
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
        }

        func handleLayout(in scrollView: UIScrollView) {
            syncLayoutIfNeeded(in: scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            syncPanAvailability(in: scrollView)
        }

        private func resetZoom(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }
            imageView.frame = bounds
            scrollView.contentSize = bounds.size
            scrollView.setZoomScale(1, animated: false)
            centerImage(in: scrollView)
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
                centerImage(in: scrollView)
                syncPanAvailability(in: scrollView)
            }
        }

        private func centerImage(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else {
                return
            }
            var frame = imageView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) * 0.5 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) * 0.5 : 0
            imageView.frame = frame
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
            let location = gesture.location(in: imageView)
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
    }
}

private final class AnalysisRawZoomUIScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

private struct AnalysisToolPhotoStage: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let tool: AnalysisViewerTool
    let viewportSize: CGSize
    @Binding var heatmapOpacity: Double

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
                selection: Binding(
                    get: { slot.regionSelection.selectionRect },
                    set: { slot.regionSelection.selectionRect = $0 }
                ),
                interactionState: slot.regionSelection.interactionState,
                planeRegion: slot.planeSelection.selectedRegion,
                planeSeedPoint: slot.planeSelection.seedPoint,
                metadataSummary: nil,
                scoreSummary: nil,
                allowsRegionSelection: false,
                onSelectionBegan: { _ in },
                onSelectionChanged: { _ in },
                onSelectionEnded: { _ in },
                onSelectionCleared: {
                    slot.clearSelection()
                },
                onPlaneSeedSelected: { depthPoint in
                    slot.selectPlaneSeed(depthPoint)
                }
            )
            .frame(width: size.width, height: size.height)
        } else {
            AnalysisToolLoadingView(
                slot: slot,
                title: "Preparing 2D analysis",
                size: size
            )
        }
    }

    @ViewBuilder
    private func threeDContent(size: CGSize) -> some View {
        if let input = slot.input {
            PointCloudPreview(
                image: input.image,
                depthMap: input.depthMap,
                orientation: input.imageOrientation,
                selectedPlaneRegion: slot.planeSelection.selectedRegion,
                selection: Binding(
                    get: { slot.regionSelection.selectionRect },
                    set: { slot.regionSelection.selectionRect = $0 }
                ),
                interactionState: slot.regionSelection.interactionState,
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

}

private struct AnalysisPhotoProgressBadge: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 4)
                .frame(width: 44, height: 44)

            if let clampedProgress {
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(10)
        .background(.black.opacity(0.44), in: Circle())
        .accessibilityLabel("Downloading photo")
    }

    private var clampedProgress: Double? {
        guard let progress, progress.isFinite else {
            return nil
        }
        return min(max(progress, 0), 1)
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

            VStack(spacing: 10) {
                if slot.isOriginalLoading {
                    AnalysisPhotoProgressBadge(progress: slot.loadProgress)
                } else if let errorMessage = slot.errorMessage {
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
            Label("正在生成凭证", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))

            Text("该照片仍在 TAPCam 队列中处理。生成完成后会显示该照片的凭证已生成。")
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
