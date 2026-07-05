//
//  DepthAnalysisView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

nonisolated enum AnalysisToolViewportLayout {
    static let horizontalPadding: CGFloat = 24
    static let maximumHeightRatio: CGFloat = 0.64
    static let fallbackAspectRatio: CGFloat = 4.0 / 3.0

    static func size(
        imageSize: CGSize?,
        orientation: CGImagePropertyOrientation,
        viewportSize: CGSize
    ) -> CGSize {
        let availableWidth = max(viewportSize.width - horizontalPadding, 1)
        let maxHeight = max(viewportSize.height * maximumHeightRatio, 240)
        let aspectRatio = displayAspectRatio(imageSize: imageSize, orientation: orientation)
        let naturalHeight = availableWidth / aspectRatio

        guard naturalHeight > maxHeight else {
            return CGSize(width: availableWidth, height: max(naturalHeight, 1))
        }

        return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
    }

    private static func displayAspectRatio(
        imageSize: CGSize?,
        orientation: CGImagePropertyOrientation
    ) -> CGFloat {
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return fallbackAspectRatio
        }

        let displayedSize = TAPImageOrientationMapper.displayedSize(
            nativeSize: imageSize,
            orientation: orientation
        )
        guard displayedSize.width > 0, displayedSize.height > 0 else {
            return fallbackAspectRatio
        }
        return displayedSize.width / displayedSize.height
    }
}

/// Independent browser/analysis surface for saved TAP Depth HEIC files.
///
/// The camera view links here through a thumbnail only. The default state is a
/// Photos-like browser for the original image; analysis tools live in the
/// scroll-revealed black detail page below the photo.
struct DepthAnalysisView: View {
    private let onCurrentAlbumEntryChanged: ((DepthAnalysisAlbumContext.Entry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var carouselStore: DepthAnalysisCarouselStore
    @StateObject private var appAttestController: AppAttestRuntimeController
    @State private var analysisScrollPosition = ScrollPosition(idType: String.self)
    @State private var heatmapOpacity = 0.58
    @State private var selectedTool: AnalysisDrawerTool?
    @State private var buttonHint: AnalysisButtonHint?
    @State private var buttonHintToken = UUID()
    @State private var signatureVerificationRunID = UUID()
    @State private var photoScale: CGFloat = 1
    @State private var photoOffset: CGSize = .zero
    @AppStorage(DepthAnalyzerPreferences.showsAnalysisHelpKey)
    private var isShowingInlineHelp = DepthAnalyzerPreferences.defaultShowsAnalysisHelp

    init(
        source: DepthAnalysisSource,
        albumContext: DepthAnalysisAlbumContext? = nil,
        appAttestController: AppAttestRuntimeController? = nil,
        onCurrentAlbumEntryChanged: ((DepthAnalysisAlbumContext.Entry) -> Void)? = nil
    ) {
        _carouselStore = StateObject(
            wrappedValue: DepthAnalysisCarouselStore(
                source: source,
                albumContext: albumContext
            )
        )
        _appAttestController = StateObject(wrappedValue: appAttestController ?? AppAttestRuntimeController())
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
    }

    init(
        assetID: String,
        appAttestController: AppAttestRuntimeController? = nil
    ) {
        self.init(
            source: .photosAsset(assetID),
            appAttestController: appAttestController
        )
    }

    init(
        pendingCaptureID: String,
        appAttestController: AppAttestRuntimeController? = nil
    ) {
        self.init(
            source: .pendingCapture(pendingCaptureID),
            appAttestController: appAttestController
        )
    }

    var body: some View {
        analysisSurface()
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            carouselStore.ensureVisibleWindowLoaded()
        }
        .onChange(of: carouselStore.currentItemID) { _, _ in
            resetPhotoTransform()
            carouselStore.ensureVisibleWindowLoaded()
            if selectedTool == .credential {
                signatureVerificationRunID = UUID()
            }
        }
    }

    private func analysisSurface() -> some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            let drawerY = halfDrawerScrollY(for: viewportSize)

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        AnalysisPhotoCarouselView(
                            store: carouselStore,
                            scale: $photoScale,
                            offset: $photoOffset,
                            onCurrentEntryChanged: { entry in
                                if let albumEntry = entry.albumEntry {
                                    onCurrentAlbumEntryChanged?(albumEntry)
                                }
                            },
                            onDismiss: {
                                dismiss()
                            }
                        )
                        .frame(width: viewportSize.width, height: viewportSize.height)
                        .id("photo")

                        analysisDetailPage(
                            slot: carouselStore.currentSlot,
                            viewportSize: viewportSize
                        )
                            .frame(width: viewportSize.width)
                            .frame(minHeight: viewportSize.height)
                            .id("tools")
                    }
                }
                .scrollPosition($analysisScrollPosition)
                .background(Color.black)

                analysisControls(drawerY: drawerY)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.black)
    }

    private func analysisControls(drawerY: CGFloat) -> some View {
        DepthAnalysisControlsView(
            selectedTool: selectedTool,
            buttonHint: buttonHint,
            onToolTapped: { tool in
                selectedTool = tool
                if tool == .credential {
                    signatureVerificationRunID = UUID()
                }
                showButtonHint(.tool(tool))
                withAnimation(.snappy(duration: 0.28)) {
                    analysisScrollPosition.scrollTo(y: drawerY)
                }
            },
            onShareTapped: {
                showButtonHint(.share)
            },
            onDeleteTapped: {
                showButtonHint(.delete)
            }
        )
        .animation(.snappy(duration: 0.18), value: isShowingInlineHelp)
    }

    private func analysisDetailPage(
        slot: AnalysisPhotoSlot?,
        viewportSize: CGSize
    ) -> some View {
        let activeTool = selectedTool ?? .credential

        return VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.36))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            toolHeader(activeTool)

            toolContent(for: activeTool, slot: slot, viewportSize: viewportSize)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 92)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .foregroundStyle(.white)
        .background(Color.black)
    }

    private func toolHeader(_ tool: AnalysisDrawerTool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tool.systemImage)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(tool.title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.86))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func toolContent(
        for tool: AnalysisDrawerTool,
        slot: AnalysisPhotoSlot?,
        viewportSize: CGSize
    ) -> some View {
        switch tool {
        case .twoD:
            twoDToolContent(slot: slot, viewportSize: viewportSize)
        case .threeD:
            threeDToolContent(slot: slot, viewportSize: viewportSize)
        case .credential:
            credentialToolContent(slot: slot)
        }
    }

    @ViewBuilder
    private func twoDToolContent(
        slot: AnalysisPhotoSlot?,
        viewportSize: CGSize
    ) -> some View {
        if let slot, let input = slot.input {
            let toolSize = toolViewportSize(input: input, slot: slot, viewportSize: viewportSize)
            VStack(alignment: .leading, spacing: 12) {
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
                .frame(width: toolSize.width, height: toolSize.height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }

                OverlayInspectorContent(opacity: $heatmapOpacity, showsInlineHelp: isShowingInlineHelp)
                PlaneFilterInspectorContent(
                    depthMap: input.depthMap,
                    depthAccuracy: input.depthAccuracy,
                    depthQuality: input.depthQuality,
                    selectedPlaneRegion: slot.planeSelection.selectedRegion,
                    planeSeedPoint: slot.planeSelection.seedPoint,
                    isDetecting: slot.planeSelection.isDetecting,
                    errorMessage: DepthAnalysisInspectorErrorMessage.planeSelection(
                        slot.planeSelection.errorMessage
                    ),
                    strictness: Binding(
                        get: { slot.planeSelection.strictness },
                        set: { slot.updatePlaneGrowthStrictness($0) }
                    ),
                    showsInlineHelp: isShowingInlineHelp
                )
            }
            .tint(.white)
        } else {
            AnalysisToolLoadingView(
                slot: slot,
                title: "Preparing 2D analysis",
                size: toolViewportSize(input: nil, slot: slot, viewportSize: viewportSize)
            )
        }
    }

    @ViewBuilder
    private func threeDToolContent(
        slot: AnalysisPhotoSlot?,
        viewportSize: CGSize
    ) -> some View {
        if let slot, let input = slot.input {
            let toolSize = toolViewportSize(input: input, slot: slot, viewportSize: viewportSize)
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
            .frame(width: toolSize.width, height: toolSize.height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
        } else {
            AnalysisToolLoadingView(
                slot: slot,
                title: "Preparing 3D projection",
                size: toolViewportSize(input: nil, slot: slot, viewportSize: viewportSize)
            )
        }
    }

    @ViewBuilder
    private func credentialToolContent(slot: AnalysisPhotoSlot?) -> some View {
        if let slot {
            switch slot.source {
            case .photosAsset(let assetID):
                AppAttestSignatureVerificationPanel(
                    assetID: assetID,
                    appAttestController: appAttestController,
                    runID: signatureVerificationRunID
                )
            case .pendingCapture:
                CredentialPendingPanel()
            }
        } else {
            CredentialPendingPanel()
        }
    }

    private func resetPhotoTransform() {
        photoScale = 1
        photoOffset = .zero
    }

    private func halfDrawerScrollY(for viewportSize: CGSize) -> CGFloat {
        max(viewportSize.height - halfDrawerHeight(for: viewportSize), 0)
    }

    private func halfDrawerHeight(for viewportSize: CGSize) -> CGFloat {
        min(max(viewportSize.height * 0.48, 300), viewportSize.height * 0.62)
    }

    private func toolViewportSize(
        input: TAPDepthAnalysisInput?,
        slot: AnalysisPhotoSlot?,
        viewportSize: CGSize
    ) -> CGSize {
        if let input {
            return AnalysisToolViewportLayout.size(
                imageSize: CGSize(width: input.image.width, height: input.image.height),
                orientation: input.imageOrientation,
                viewportSize: viewportSize
            )
        }

        return AnalysisToolViewportLayout.size(
            imageSize: slot?.thumbnailImage?.size,
            orientation: .up,
            viewportSize: viewportSize
        )
    }

    private func showButtonHint(_ hint: AnalysisButtonHint) {
        let token = UUID()
        buttonHintToken = token
        withAnimation(.snappy(duration: 0.16)) {
            buttonHint = hint
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard buttonHintToken == token else {
                return
            }
            withAnimation(.snappy(duration: 0.16)) {
                buttonHint = nil
            }
        }
    }
}

private struct AnalysisPhotoCarouselView: View {
    @ObservedObject var store: DepthAnalysisCarouselStore
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    let onCurrentEntryChanged: (DepthAnalysisCarouselEntry) -> Void
    let onDismiss: () -> Void

    @GestureState private var carouselDragX: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let width = max(viewportSize.width, 1)
            let window = store.windowEntries()
            let currentPosition = window.firstIndex { $0.offset == 0 } ?? 0

            HStack(spacing: 0) {
                ForEach(window, id: \.entry.id) { item in
                    ZoomableAnalysisPhotoStage(
                        slot: store.slot(for: item.entry),
                        isCurrent: item.offset == 0,
                        scale: $scale,
                        offset: $offset
                    )
                    .frame(width: viewportSize.width, height: viewportSize.height)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height, alignment: .leading)
            .offset(x: -CGFloat(currentPosition) * width + carouselDragX)
            .animation(.snappy(duration: 0.24), value: store.currentItemID)
            .animation(.snappy(duration: 0.18), value: carouselDragX == 0)
            .contentShape(Rectangle())
            .gesture(carouselGesture(width: width))
            .background(Color.black)
        }
        .background(Color.black)
        .accessibilityLabel("Photo carousel")
    }

    private var isZoomed: Bool {
        scale > 1.05
    }

    private func carouselGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($carouselDragX) { value, state, _ in
                guard !isZoomed else {
                    return
                }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 0.82 else {
                    return
                }
                let direction = horizontal < 0 ? 1 : -1
                state = store.canMove(offset: direction) ? horizontal : horizontal * 0.22
            }
            .onEnded { value in
                guard !isZoomed else {
                    return
                }

                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predictedHorizontal = value.predictedEndTranslation.width
                if vertical > 110, vertical > abs(horizontal) * 1.3 {
                    onDismiss()
                    return
                }

                let direction = horizontal < 0 ? 1 : -1
                let threshold = min(max(width * 0.18, 72), 132)
                guard abs(horizontal) > threshold || abs(predictedHorizontal) > threshold * 1.24 else {
                    return
                }
                guard let entry = store.move(offset: direction) else {
                    return
                }
                onCurrentEntryChanged(entry)
            }
    }
}

private struct ZoomableAnalysisPhotoStage: View {
    @ObservedObject var slot: AnalysisPhotoSlot
    let isCurrent: Bool
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    @GestureState private var pinchScale: CGFloat = 1
    @State private var dragStartOffset: CGSize?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                displayImage
                    .scaleEffect(isCurrent ? effectiveScale : 1)
                    .offset(isCurrent ? offset : .zero)
                    .animation(.snappy(duration: 0.22), value: scale)
                    .animation(.snappy(duration: 0.22), value: offset)

                if slot.isOriginalLoading {
                    AnalysisPhotoProgressBadge(progress: slot.loadProgress)
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
            .contentShape(Rectangle())
            .simultaneousGesture(pinchGesture(containerSize: proxy.size))
            .simultaneousGesture(dragGesture(containerSize: proxy.size))
            .simultaneousGesture(doubleTapGesture(containerSize: proxy.size))
        }
        .background(Color.black)
        .accessibilityLabel("Photo")
    }

    @ViewBuilder
    private var displayImage: some View {
        if let input = slot.input {
            Image(decorative: input.image, scale: 1, orientation: input.imageOrientation.swiftUIImageOrientation)
                .resizable()
                .scaledToFit()
                .transition(.opacity)
                .id("original-\(slot.id)")
        } else if let thumbnailImage = slot.thumbnailImage {
            Image(uiImage: thumbnailImage)
                .resizable()
                .scaledToFit()
                .transition(.opacity)
                .id("thumbnail-\(slot.id)")
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var effectiveScale: CGFloat {
        clampedScale(scale * pinchScale)
    }

    private var isZoomed: Bool {
        scale > 1.05
    }

    private func pinchGesture(containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                guard isCurrent else {
                    return
                }
                state = value
            }
            .onEnded { value in
                guard isCurrent else {
                    return
                }
                scale = clampedScale(scale * value)
                offset = clampedOffset(offset, scale: scale, containerSize: containerSize)
                if scale <= 1.05 {
                    reset()
                }
            }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard isCurrent, isZoomed else {
                    return
                }
                if dragStartOffset == nil {
                    dragStartOffset = offset
                }
                let start = dragStartOffset ?? .zero
                offset = clampedOffset(
                    CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                    scale: scale,
                    containerSize: containerSize
                )
            }
            .onEnded { value in
                defer {
                    dragStartOffset = nil
                }

                guard isCurrent else {
                    return
                }
                guard !isZoomed else {
                    offset = clampedOffset(offset, scale: scale, containerSize: containerSize)
                    return
                }
            }
    }

    private func doubleTapGesture(containerSize: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard isCurrent else {
                    return
                }
                if isZoomed {
                    reset()
                } else {
                    scale = 2.5
                    offset = clampedOffset(.zero, scale: scale, containerSize: containerSize)
                }
            }
    }

    private func reset() {
        scale = 1
        offset = .zero
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 5)
    }

    private func clampedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        containerSize: CGSize
    ) -> CGSize {
        guard scale > 1.05 else {
            return .zero
        }
        let maxX = max(containerSize.width * (scale - 1) * 0.5, 0)
        let maxY = max(containerSize.height * (scale - 1) * 0.5, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
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
