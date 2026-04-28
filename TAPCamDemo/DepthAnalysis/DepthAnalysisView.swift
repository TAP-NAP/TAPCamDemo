//
//  DepthAnalysisView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

import Combine
import Foundation
import ImageIO
import Photos
import SwiftUI

/// Independent browser/analysis surface for saved TAP Depth HEIC files.
///
/// The camera view links here through a thumbnail only. All depth heatmaps,
/// point-cloud previews, pixel reads, and plane fitting live on this side of
/// the module boundary so the capture UI remains a camera.
struct DepthAnalysisView: View {
    let assetID: String
    @StateObject private var viewModel = DepthAnalysisViewModel()
    @State private var heatmapOpacity = 0.74
    @State private var panelDestination: AnalysisPanelDestination?
    @State private var buttonHint: AnalysisButtonHint?
    @State private var buttonHintToken = UUID()
    @State private var helpSubject: AnalysisHelpSubject = .view(.rgb)
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if let input = viewModel.input {
                analysisContent(input)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView("Unable to analyze image", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("Loading depth image...")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if panelDestination != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        clearSelectionAndPanel()
                    }
                    .onTapGesture {
                        panelDestination = nil
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let input = viewModel.input {
                analysisControls(for: input)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("Depth Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Analyzer settings")
                .help("View permissions, authorization, and authentication status.")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            DepthAnalyzerSettingsView()
        }
        .onChange(of: viewModel.viewMode) { _, viewMode in
            if case .inspector(let inspector) = panelDestination, !inspectors(for: viewMode).contains(inspector) {
                panelDestination = nil
            }
        }
        .task {
            await viewModel.load(assetID: assetID)
        }
    }

    @ViewBuilder
    private func analysisContent(_ input: TAPDepthAnalysisInput) -> some View {
        switch viewModel.viewMode {
        case .rgb:
            depthImageStage(
                input,
                overlayImage: nil,
                overlayOpacity: 0
            )
        case .heatmap:
            depthImageStage(
                input,
                overlayImage: input.heatmap.image,
                overlayOpacity: heatmapOpacity
            )
        case .mask:
            depthImageStage(
                input,
                overlayImage: input.validMask.image,
                overlayOpacity: 1
            )
        case .planes:
            depthImageStage(
                input,
                overlayImage: input.heatmap.image,
                overlayOpacity: heatmapOpacity,
                planeRegion: viewModel.selectedPlaneRegion,
                planeSeedPoint: viewModel.planeSeedPoint,
                isSelectionEnabled: false,
                isPointSelectionEnabled: true,
                onPointSelected: { depthPoint in
                    viewModel.selectPlaneSeed(depthPoint)
                    panelDestination = .inspector(.planeFilter)
                }
            )
        case .pointCloud:
            PointCloudPreview(
                depthMap: input.depthMap,
                orientation: input.imageOrientation,
                selection: $viewModel.selectionRect,
                interactionState: viewModel.interactionState,
                onSelectionBegan: { depthRect in
                    viewModel.beginSelection(depthRect)
                },
                onSelectionChanged: { depthRect in
                    viewModel.previewSelection(depthRect)
                },
                onSelectionEnded: { depthRect in
                    viewModel.finishSelection(depthRect)
                },
                onSelectionCleared: {
                    clearSelectionAndPanel()
                }
            )
            .background(Color.black)
        }
    }

    private func depthImageStage(
        _ input: TAPDepthAnalysisInput,
        overlayImage: CGImage?,
        overlayOpacity: Double,
        planeOverlays: [TAPDetectedPlane] = [],
        planeRegion: TAPPlaneRegion? = nil,
        planeSeedPoint: CGPoint? = nil,
        isSelectionEnabled: Bool = true,
        isPointSelectionEnabled: Bool = false,
        onPointSelected: ((CGPoint) -> Void)? = nil
    ) -> some View {
        InteractiveDepthImage(
            image: input.image,
            overlayImage: overlayImage,
            overlayOpacity: overlayOpacity,
            orientation: input.imageOrientation,
            depthSize: CGSize(width: input.depthMap.width, height: input.depthMap.height),
            selection: $viewModel.selectionRect,
            interactionState: viewModel.interactionState,
            planeOverlays: planeOverlays,
            planeRegion: planeRegion,
            planeSeedPoint: planeSeedPoint,
            isSelectionEnabled: isSelectionEnabled,
            isPointSelectionEnabled: isPointSelectionEnabled,
            onSelectionBegan: { depthRect in
                viewModel.beginSelection(depthRect)
            },
            onSelectionChanged: { depthRect in
                viewModel.previewSelection(depthRect)
            },
            onSelectionEnded: { depthRect in
                viewModel.finishSelection(depthRect)
            },
            onSelectionCleared: {
                clearSelectionAndPanel()
            },
            onPointSelected: { depthPoint in
                onPointSelected?(depthPoint)
            }
        )
    }

    private func analysisControls(for input: TAPDepthAnalysisInput) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let destination = panelDestination {
                AnalysisPanelLayer(destination: $panelDestination, maxHeight: UIScreen.main.bounds.height * 0.32) {
                    panelContent(for: destination, input: input)
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }

            AnalysisInspectorStrip(
                panelDestination: $panelDestination,
                viewMode: $viewModel.viewMode,
                inspectors: inspectors(for: viewModel.viewMode),
                buttonHint: buttonHint,
                onViewTapped: { viewMode in
                    helpSubject = .view(viewMode)
                    showButtonHint(.view(viewMode))
                },
                onInspectorTapped: { inspector in
                    helpSubject = .inspector(inspector)
                },
                onHelpTapped: {
                    if case .inspector(let inspector) = panelDestination {
                        helpSubject = .inspector(inspector)
                    } else {
                        helpSubject = .view(viewModel.viewMode)
                    }
                }
            )
        }
        .frame(maxWidth: 560, alignment: .leading)
        .animation(.snappy(duration: 0.18), value: panelDestination)
        .animation(.snappy(duration: 0.18), value: viewModel.viewMode)
    }

    private func clearSelectionAndPanel() {
        viewModel.clearSelection()
        panelDestination = nil
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

    @ViewBuilder
    private func panelContent(for destination: AnalysisPanelDestination, input: TAPDepthAnalysisInput) -> some View {
        switch destination {
        case .inspector(let inspector):
            inspectorContent(for: inspector, input: input)
        case .help:
            AnalysisHelpView(subject: helpSubject)
        }
    }

    @ViewBuilder
    private func inspectorContent(for inspector: AnalysisInspector, input: TAPDepthAnalysisInput) -> some View {
        switch inspector {
        case .measurements:
            measurementsContent
        case .legend:
            legendContent(for: input)
        case .overlay:
            OverlayInspectorContent(opacity: $heatmapOpacity)
        case .region:
            RegionInspectorContent(
                image: input.image,
                orientation: input.imageOrientation,
                depthSize: CGSize(width: input.depthMap.width, height: input.depthMap.height),
                selection: viewModel.selectionRect,
                interactionState: viewModel.interactionState,
                stats: viewModel.regionStats,
                planeEstimate: viewModel.planeEstimate,
                regionHeatmap: viewModel.regionHeatmap,
                heatmapErrorMessage: viewModel.regionHeatmapErrorMessage
            )
        case .planeFilter:
            PlaneFilterInspectorContent(
                depthMap: input.depthMap,
                depthAccuracy: input.depthAccuracy,
                depthQuality: input.depthQuality,
                selectedPlaneRegion: viewModel.selectedPlaneRegion,
                planeSeedPoint: viewModel.planeSeedPoint,
                errorMessage: viewModel.planeRegionErrorMessage,
                strictness: Binding(
                    get: { viewModel.planeGrowthStrictness },
                    set: { viewModel.updatePlaneGrowthStrictness($0) }
                )
            )
        case .cloudInfo:
            CloudInfoInspectorContent(
                depthMap: input.depthMap,
                orientation: input.imageOrientation,
                selection: viewModel.selectionRect,
                interactionState: viewModel.interactionState
            )
        }
    }

    private var measurementsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats = viewModel.regionStats {
                DepthMetricRow(
                    title: "Median depth",
                    value: stats.medianDepthMeters.map { String(format: "%.2f m", $0) } ?? "No valid depth",
                    explanation: "Sort the selected valid depth samples from near to far; this is the value in the middle. It is less sensitive to isolated noisy pixels than an average."
                )
                DepthMetricRow(
                    title: "Range",
                    value: rangeText(stats),
                    explanation: "The nearest and farthest valid metric depth samples found inside the selection."
                )
                DepthMetricRow(
                    title: "Valid samples",
                    value: "\(stats.validSampleCount)/\(stats.totalSampleCount) · \(Int((stats.validRatio * 100).rounded()))%",
                    explanation: "How many pixels in the selected region contain finite positive depth. Plane fitting and point projection ignore invalid samples."
                )
            } else {
                Text(viewModel.interactionState == .drawingSelection ? "Selecting region..." : "No region selected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let plane = viewModel.planeEstimate {
                Divider()
                DepthMetricRow(
                    title: "Plane residual",
                    value: String(format: "%.3f m", plane.averageResidualMeters),
                    explanation: "Average distance from inlier points to the fitted plane. Smaller values usually mean the selected surface is flatter."
                )
                DepthMetricRow(
                    title: "Plane inliers",
                    value: "\(Int((plane.inlierRatio * 100).rounded()))%",
                    explanation: "The share of sampled points close enough to the fitted plane to count as inliers."
                )
                DepthMetricRow(
                    title: "Plane normal",
                    value: String(format: "[%.2f, %.2f, %.2f]", plane.normal.x, plane.normal.y, plane.normal.z),
                    explanation: "The fitted plane direction in local camera coordinates. It is useful for comparing orientation, not for world tracking."
                )
            } else {
                Divider()
                Text("No local plane estimate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func legendContent(for input: TAPDepthAnalysisInput) -> some View {
        switch viewModel.viewMode {
        case .rgb:
            Text("No generated legend.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .heatmap, .planes:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Global depth legend")
                        .font(.caption.weight(.semibold))
                        .help(viewModel.viewMode.legendDescription)
                    Spacer(minLength: 8)
                    Text(globalHeatmapRangeText(input.heatmap))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DepthLegendView(stops: input.heatmap.legendStops)
            }
        case .mask:
            VStack(alignment: .leading, spacing: 8) {
                Text("Mask legend")
                    .font(.caption.weight(.semibold))
                    .help(viewModel.viewMode.legendDescription)
                SwatchLegendView(stops: input.validMask.legendStops)
                Text("\(Int((input.validMask.validRatio * 100).rounded()))% valid depth coverage")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .pointCloud:
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud legend")
                    .font(.caption.weight(.semibold))
                    .help(viewModel.viewMode.legendDescription)
                DepthLegendView(stops: cloudLegendStops)
            }
        }
    }

    private func inspectors(for viewMode: DepthAnalysisViewMode) -> [AnalysisInspector] {
        switch viewMode {
        case .rgb:
            [.measurements, .region]
        case .heatmap:
            [.measurements, .legend, .overlay, .region]
        case .mask:
            [.measurements, .legend, .region]
        case .planes:
            [.planeFilter, .legend, .overlay]
        case .pointCloud:
            [.cloudInfo, .measurements, .region]
        }
    }

    private func rangeText(_ stats: TAPDepthRegionStats) -> String {
        guard let minimum = stats.minimumDepthMeters, let maximum = stats.maximumDepthMeters else {
            return "No valid depth"
        }

        return String(format: "%.2f...%.2f m", minimum, maximum)
    }

    private func globalHeatmapRangeText(_ heatmap: TAPDepthHeatmapVisualization) -> String {
        String(format: "%.2f...%.2f m", heatmap.rangeMeters.lowerBound, heatmap.rangeMeters.upperBound)
    }

    private var cloudLegendStops: [TAPDepthLegendStop] {
        [
            TAPDepthLegendStop(position: 0, label: "Near points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 0)),
            TAPDepthLegendStop(position: 1, label: "Far points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 1))
        ]
    }
}

@MainActor
final class DepthAnalysisViewModel: ObservableObject {
    @Published var input: TAPDepthAnalysisInput?
    @Published var viewMode: DepthAnalysisViewMode = .rgb
    @Published var selectionRect: CGRect?
    @Published var interactionState: AnalysisInteractionState = .idle
    @Published var regionStats: TAPDepthRegionStats?
    @Published var regionHeatmap: TAPDepthHeatmapVisualization?
    @Published var regionHeatmapErrorMessage: String?
    @Published var planeEstimate: TAPPlaneEstimate?
    @Published var planeGrowthStrictness = 0.68
    @Published var planeSeedPoint: CGPoint?
    @Published var selectedPlaneRegion: TAPPlaneRegion?
    @Published var planeRegionErrorMessage: String?
    @Published var errorMessage: String?

    var displayImage: CGImage {
        guard let input else {
            preconditionFailure("DepthAnalysisView requests a display image only after input loads.")
        }

        // UI view mode contract:
        // - RGB shows the HEIC primary image from ImageIO.
        // - Depth overlays `TAPDepthHeatmapRenderer.heatmap`, a false-color
        //   view of metric depth samples. It is visual only; measurements use
        //   `TAPMetricDepthMap.samples`.
        // - Mask overlays `TAPDepthMaskRenderer.validMask`, where transparent
        //   areas are invalid and colored regions have finite positive depth.
        // - Planes reuses the heatmap as the backdrop while the bottom panel
        //   reports `TAPPlaneEstimator` results for the selected depth region.
        // - Cloud is handled by `PointCloudPreview`, so this fallback is never
        //   measured from directly.
        switch viewMode {
        case .rgb:
            return input.image
        case .heatmap:
            return input.heatmap.image
        case .mask:
            return input.validMask.image
        case .planes:
            return input.heatmap.image
        case .pointCloud:
            return input.heatmap.image
        }
    }

    func load(assetID: String) async {
        do {
            let data = try await PhotoLibraryWriter.originalPhotoData(localIdentifier: assetID)
            let loadedInput = try TAPDepthMapReader.analysisInput(from: data)
            input = loadedInput
            planeSeedPoint = nil
            selectedPlaneRegion = nil
            planeRegionErrorMessage = nil
            errorMessage = nil
            setInitialSelection(CGRect(x: 0, y: 0, width: loadedInput.depthMap.width, height: loadedInput.depthMap.height))
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func beginSelection(_ depthRect: CGRect) {
        selectionRect = clampedSelection(depthRect)
        interactionState = .drawingSelection
        regionStats = nil
        planeEstimate = nil
        regionHeatmap = nil
        regionHeatmapErrorMessage = nil
    }

    func previewSelection(_ depthRect: CGRect) {
        selectionRect = clampedSelection(depthRect)
        interactionState = .drawingSelection
    }

    func finishSelection(_ depthRect: CGRect) {
        let rect = clampedSelection(depthRect)
        selectionRect = rect
        interactionState = .regionSelected
        updateRegionProducts(rect)
    }

    func clearSelection() {
        selectionRect = nil
        interactionState = .idle
        regionStats = nil
        planeEstimate = nil
        regionHeatmap = nil
        regionHeatmapErrorMessage = nil
        planeSeedPoint = nil
        selectedPlaneRegion = nil
        planeRegionErrorMessage = nil
    }

    func selectPlaneSeed(_ depthPoint: CGPoint) {
        guard let input else {
            return
        }

        let clamped = CGPoint(
            x: min(max(depthPoint.x, 0), CGFloat(max(input.depthMap.width - 1, 0))),
            y: min(max(depthPoint.y, 0), CGFloat(max(input.depthMap.height - 1, 0)))
        )
        planeSeedPoint = clamped
        updateSeedPlaneRegion()
    }

    func updatePlaneGrowthStrictness(_ strictness: Double) {
        planeGrowthStrictness = min(max(strictness, 0.35), 0.95)
        if planeSeedPoint != nil {
            updateSeedPlaneRegion()
        }
    }

    private func setInitialSelection(_ depthRect: CGRect) {
        let rect = clampedSelection(depthRect)
        selectionRect = rect
        interactionState = .idle
        updateMetricsAndPlane(rect)
        regionHeatmap = nil
        regionHeatmapErrorMessage = nil
    }

    private func updateRegionProducts(_ depthRect: CGRect) {
        updateMetricsAndPlane(depthRect)
        updateRegionHeatmap(depthRect)
    }

    private func updateMetricsAndPlane(_ depthRect: CGRect) {
        guard let input else {
            return
        }

        regionStats = TAPDepthGeometryProjector.stats(for: input.depthMap, in: depthRect)
        planeEstimate = TAPPlaneEstimator.estimatePlane(depthMap: input.depthMap, region: depthRect)
    }

    private func updateRegionHeatmap(_ depthRect: CGRect) {
        guard let input else {
            return
        }

        do {
            regionHeatmap = try TAPDepthHeatmapRenderer.heatmap(for: input.depthMap, region: depthRect)
            regionHeatmapErrorMessage = nil
        } catch {
            regionHeatmap = nil
            regionHeatmapErrorMessage = "Not enough valid depth samples in this region."
        }
    }

    private func updateSeedPlaneRegion() {
        guard let input, let planeSeedPoint else {
            selectedPlaneRegion = nil
            planeRegionErrorMessage = nil
            return
        }

        do {
            selectedPlaneRegion = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: input.depthMap,
                seed: planeSeedPoint,
                strictness: planeGrowthStrictness
            )
            planeRegionErrorMessage = nil
        } catch let error as TAPPlaneGrowthError {
            selectedPlaneRegion = nil
            planeRegionErrorMessage = error.localizedDescription
        } catch {
            selectedPlaneRegion = nil
            planeRegionErrorMessage = "No stable plane region found from this point."
        }
    }

    private func clampedSelection(_ rect: CGRect) -> CGRect {
        guard let input else {
            return rect
        }

        let fullRect = CGRect(x: 0, y: 0, width: input.depthMap.width, height: input.depthMap.height)
        let clamped = rect.intersection(fullRect)
        if clamped.isNull || clamped.width <= 0 || clamped.height <= 0 {
            return CGRect(x: 0, y: 0, width: min(1, input.depthMap.width), height: min(1, input.depthMap.height))
        }
        return clamped
    }
}

enum DepthAnalysisViewMode: String, CaseIterable, Identifiable {
    /// Normal color image. Source: ImageIO primary HEIC image item.
    case rgb

    /// False-color depth image. Source: Apple auxiliary depth/disparity rebuilt
    /// as `AVDepthData`, converted to Float32 metric depth, then colorized.
    case heatmap

    /// Valid-depth coverage image. Source: the same metric depth map; finite
    /// positive samples are colored, missing/invalid samples are transparent.
    case mask

    /// Region plane analysis. Source: selected metric depth samples plus
    /// `AVCameraCalibrationData` intrinsics from the TAP manifest.
    case planes

    /// Lightweight camera-coordinate point preview. Source: metric depth samples
    /// projected with camera intrinsics; this is not a world-space AR mesh.
    case pointCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rgb:
            "RGB"
        case .heatmap:
            "Depth"
        case .mask:
            "Mask"
        case .planes:
            "Planes"
        case .pointCloud:
            "Cloud"
        }
    }

    var systemImage: String {
        switch self {
        case .rgb:
            "photo"
        case .heatmap:
            "thermometer.medium"
        case .mask:
            "square.dashed"
        case .planes:
            "square.3.layers.3d"
        case .pointCloud:
            "point.3.connected.trianglepath.dotted"
        }
    }

    var shortExplanation: String {
        switch self {
        case .rgb:
            "The original color photo stored in the TAP depth HEIC."
        case .heatmap:
            "A false-color overlay where color represents metric depth in meters."
        case .mask:
            "A coverage overlay showing which pixels have usable depth samples."
        case .planes:
            "Tap a surface point to grow and grid the connected camera-coordinate plane."
        case .pointCloud:
            "A local camera-coordinate point cloud preview made from valid depth pixels."
        }
    }

    var detailedExplanation: String {
        switch self {
        case .rgb:
            "RGB view shows the primary HEIC image. It is the visual reference used to choose regions, but the depth measurements still come from the auxiliary depth map embedded beside it."
        case .heatmap:
            "Depth view overlays metric depth as a false-color heatmap. Near pixels use the low end of the legend and far pixels use the high end. Transparent pixels do not contain valid depth."
        case .mask:
            "Mask view highlights the pixels that contain finite positive depth samples. Green areas can contribute to statistics, plane fitting, and point projection; transparent areas are ignored."
        case .planes:
            "Planes view grows a connected plane from the surface point you tap, then divides that region into fit-confidence grid cells. Rectangular Region selection is disabled here so the view stays focused on plane analysis."
        case .pointCloud:
            "Cloud view projects valid depth pixels through camera intrinsics into a lightweight camera-coordinate point preview. It is a point cloud, not cloud storage, cloud compute, or a semantic word cloud."
        }
    }

    var legendDescription: String {
        switch self {
        case .rgb:
            "RGB has no color legend because it shows the original photo."
        case .heatmap:
            "The legend maps the current depth range from near to far. Adjust opacity to compare the heatmap against the RGB image."
        case .mask:
            "Green indicates valid depth coverage. Yellow outlines mark transitions between valid and invalid depth."
        case .planes:
            "Plane cells use stronger green for better local plane fit and warmer color for weaker fit; the bright edge marks the grown boundary."
        case .pointCloud:
            "Point colors map near-to-far depth in the same direction as the depth legend."
        }
    }
}

private struct InteractiveDepthImage: View {
    let image: CGImage
    let overlayImage: CGImage?
    let overlayOpacity: Double
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    @Binding var selection: CGRect?
    let interactionState: AnalysisInteractionState
    let planeOverlays: [TAPDetectedPlane]
    let planeRegion: TAPPlaneRegion?
    let planeSeedPoint: CGPoint?
    let isSelectionEnabled: Bool
    let isPointSelectionEnabled: Bool
    let onSelectionBegan: (CGRect) -> Void
    let onSelectionChanged: (CGRect) -> Void
    let onSelectionEnded: (CGRect) -> Void
    let onSelectionCleared: () -> Void
    let onPointSelected: (CGPoint) -> Void

    @State private var dragStart: CGPoint?
    @State private var lastClearDate = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
            // ImageIO returns raw pixels and a separate EXIF/CGImage orientation.
            // SwiftUI renders the pixels with that orientation applied, so the
            // fitted display rect must use the orientation-adjusted dimensions.
            let imageSize = TAPImageOrientationMapper.displayedSize(
                nativeSize: CGSize(width: image.width, height: image.height),
                orientation: orientation
            )
            let imageFrame = fittedRect(imageSize: imageSize, containerSize: proxy.size)

            ZStack {
                Color.black

                Image(decorative: image, scale: 1, orientation: orientation.swiftUIImageOrientation)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                if let overlayImage {
                    Image(decorative: overlayImage, scale: 1, orientation: orientation.swiftUIImageOrientation)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                        .opacity(overlayOpacity)
                }

                ForEach(planeOverlays) { plane in
                    let rect = viewRect(for: plane.imageBounds, imageFrame: imageFrame)
                    if rect.width > 8, rect.height > 8 {
                        PlaneOverlayMarker(plane: plane)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        }
                }

                if let planeRegion {
                    PlaneRegionOverlay(
                        region: planeRegion,
                        depthSize: depthSize,
                        orientation: orientation,
                        imageFrame: imageFrame
                    )

                    let rect = viewRect(for: planeRegion.imageBounds, imageFrame: imageFrame)
                    if rect.width > 8, rect.height > 8 {
                        PlaneRegionBadge(region: planeRegion)
                            .position(x: rect.minX + 44, y: max(rect.minY + 16, imageFrame.minY + 16))
                    }
                }

                if let planeSeedPoint {
                    let seedRect = viewRect(
                        for: CGRect(x: planeSeedPoint.x - 2, y: planeSeedPoint.y - 2, width: 4, height: 4),
                        imageFrame: imageFrame
                    )
                    PlaneSeedMarker()
                        .position(x: seedRect.midX, y: seedRect.midY)
                }

                if isSelectionEnabled, let selection {
                    let rect = viewRect(for: selection, imageFrame: imageFrame)
                    Rectangle()
                        .stroke(.white, lineWidth: 2)
                        .background(Rectangle().fill(selectionFill))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard isSelectionEnabled else {
                            return
                        }
                        let isBeginning = dragStart == nil
                        if isBeginning {
                            dragStart = value.startLocation
                        }
                        let viewRect = CGRect(
                            x: min(dragStart?.x ?? value.location.x, value.location.x),
                            y: min(dragStart?.y ?? value.location.y, value.location.y),
                            width: abs(value.location.x - (dragStart?.x ?? value.location.x)),
                            height: abs(value.location.y - (dragStart?.y ?? value.location.y))
                        ).insetBy(dx: -14, dy: -14)

                        let depthRect = depthRect(for: viewRect, imageFrame: imageFrame)
                        selection = depthRect
                        if isBeginning {
                            onSelectionBegan(depthRect)
                        } else {
                            onSelectionChanged(depthRect)
                        }
                    }
                    .onEnded { value in
                        guard isSelectionEnabled else {
                            dragStart = nil
                            return
                        }
                        let viewRect = CGRect(
                            x: min(dragStart?.x ?? value.location.x, value.location.x),
                            y: min(dragStart?.y ?? value.location.y, value.location.y),
                            width: abs(value.location.x - (dragStart?.x ?? value.location.x)),
                            height: abs(value.location.y - (dragStart?.y ?? value.location.y))
                        ).insetBy(dx: -14, dy: -14)
                        let depthRect = depthRect(for: viewRect, imageFrame: imageFrame)
                        selection = depthRect
                        onSelectionEnded(depthRect)
                        dragStart = nil
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        dragStart = nil
                        lastClearDate = Date()
                        onSelectionCleared()
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1)
                    .onEnded { value in
                        guard isPointSelectionEnabled,
                              Date().timeIntervalSince(lastClearDate) > 0.25,
                              let depthPoint = depthPoint(for: value.location, imageFrame: imageFrame) else {
                            return
                        }
                        onPointSelected(depthPoint)
                    }
            )
        }
    }

    private var selectionFill: Color {
        switch interactionState {
        case .drawingSelection:
            .white.opacity(0.08)
        case .idle, .regionSelected:
            .white.opacity(0.14)
        }
    }

    private func fittedRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let verticalBias: CGFloat = 0.38
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) * verticalBias,
            width: size.width,
            height: size.height
        )
    }

    private func depthRect(for viewRect: CGRect, imageFrame: CGRect) -> CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return .zero
        }

        let clamped = viewRect.intersection(imageFrame)
        guard !clamped.isNull else {
            return .zero
        }

        // The user drags in oriented display coordinates. Plane fitting and
        // depth statistics operate on the native depth-map pixel grid, so we
        // first scale into the displayed depth plane and then invert the
        // orientation transform.
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedX = (clamped.minX - imageFrame.minX) / imageFrame.width * displayedDepthSize.width
        let displayedY = (clamped.minY - imageFrame.minY) / imageFrame.height * displayedDepthSize.height
        let displayedWidth = clamped.width / imageFrame.width * displayedDepthSize.width
        let displayedHeight = clamped.height / imageFrame.height * displayedDepthSize.height
        let displayedRect = CGRect(
            x: displayedX,
            y: displayedY,
            width: max(displayedWidth, 1),
            height: max(displayedHeight, 1)
        )
        return TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedRect,
            nativeSize: depthSize,
            orientation: orientation
        )
    }

    private func viewRect(for depthRect: CGRect, imageFrame: CGRect) -> CGRect {
        guard depthSize.width > 0, depthSize.height > 0 else {
            return .zero
        }

        // Selection state is stored as a native depth-map rect because that is
        // what `TAPDepthGeometryProjector` and `TAPPlaneEstimator` consume. This
        // converts it back into oriented display coordinates for the overlay.
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: depthRect,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGRect(
            x: imageFrame.minX + displayedRect.minX / displayedDepthSize.width * imageFrame.width,
            y: imageFrame.minY + displayedRect.minY / displayedDepthSize.height * imageFrame.height,
            width: displayedRect.width / displayedDepthSize.width * imageFrame.width,
            height: displayedRect.height / displayedDepthSize.height * imageFrame.height
        )
    }

    private func depthPoint(for location: CGPoint, imageFrame: CGRect) -> CGPoint? {
        guard imageFrame.contains(location), imageFrame.width > 0, imageFrame.height > 0 else {
            return nil
        }

        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedPointRect = CGRect(
            x: (location.x - imageFrame.minX) / imageFrame.width * displayedDepthSize.width,
            y: (location.y - imageFrame.minY) / imageFrame.height * displayedDepthSize.height,
            width: 1,
            height: 1
        )
        let nativeRect = TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedPointRect,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGPoint(
            x: min(max(nativeRect.midX, 0), max(depthSize.width - 1, 0)),
            y: min(max(nativeRect.midY, 0), max(depthSize.height - 1, 0))
        )
    }
}

private struct PlaneRegionOverlay: View {
    let region: TAPPlaneRegion
    let depthSize: CGSize
    let orientation: CGImagePropertyOrientation
    let imageFrame: CGRect

    var body: some View {
        Canvas { context, _ in
            for cell in region.gridCells {
                let rect = viewRect(for: cell.imageBounds).insetBy(dx: 0.8, dy: 0.8)
                context.fill(Path(rect), with: .color(cellFillColor(cell)))
                context.stroke(Path(rect), with: .color(cellEdgeColor(cell)), lineWidth: 1.15)
            }

            let stride = max(region.contourPoints.count / 2_500, 1)
            for (index, point) in region.contourPoints.enumerated() where index.isMultiple(of: stride) {
                let rect = viewRect(for: CGRect(x: point.x, y: point.y, width: 1, height: 1))
                    .insetBy(dx: -1.2, dy: -1.2)
                context.fill(Path(ellipseIn: rect), with: .color(edgeColor))
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Selected plane region")
    }

    private func cellFillColor(_ cell: TAPPlaneGridCell) -> Color {
        let confidence = min(max(cell.confidence, 0), 1)
        return Color(
            red: 1.0 - 0.26 * confidence,
            green: 0.58 + 0.38 * confidence,
            blue: 0.22 + 0.14 * confidence
        )
        .opacity(0.16 + 0.18 * confidence)
    }

    private func cellEdgeColor(_ cell: TAPPlaneGridCell) -> Color {
        let confidence = min(max(cell.confidence, 0), 1)
        return Color(
            red: 1.0 - 0.30 * confidence,
            green: 0.72 + 0.28 * confidence,
            blue: 0.24 + 0.16 * confidence
        )
        .opacity(0.42 + 0.42 * confidence)
    }

    private var edgeColor: Color {
        Color(red: 0.78, green: 1.0, blue: 0.42).opacity(0.92)
    }

    private func viewRect(for depthRect: CGRect) -> CGRect {
        guard depthSize.width > 0, depthSize.height > 0 else {
            return .zero
        }

        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: depthRect,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGRect(
            x: imageFrame.minX + displayedRect.minX / displayedDepthSize.width * imageFrame.width,
            y: imageFrame.minY + displayedRect.minY / displayedDepthSize.height * imageFrame.height,
            width: max(displayedRect.width / displayedDepthSize.width * imageFrame.width, 1),
            height: max(displayedRect.height / displayedDepthSize.height * imageFrame.height, 1)
        )
    }
}

private struct PlaneRegionBadge: View {
    let region: TAPPlaneRegion

    var body: some View {
        Text("\(Int((region.confidence * 100).rounded()))%")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(red: 0.78, green: 1.0, blue: 0.42), in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel("Selected plane region \(Int((region.confidence * 100).rounded())) percent confidence")
    }
}

private struct PlaneSeedMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.78), lineWidth: 5)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(Color(red: 0.78, green: 1.0, blue: 0.42), lineWidth: 3)
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color(red: 0.78, green: 1.0, blue: 0.42))
                .frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.32), radius: 4, y: 2)
        .accessibilityLabel("Plane seed point")
    }
}

private struct PlaneOverlayMarker: View {
    let plane: TAPDetectedPlane

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(markerColor, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(markerColor.opacity(0.13))
                )

            Text("\(Int((plane.confidence * 100).rounded()))%")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(markerColor, in: Capsule())
                .padding(5)
        }
        .accessibilityLabel("Detected plane \(Int((plane.confidence * 100).rounded())) percent confidence")
    }

    private var markerColor: Color {
        if plane.confidence >= 0.82 {
            return Color(red: 0.70, green: 0.95, blue: 0.30)
        }
        if plane.confidence >= 0.68 {
            return Color(red: 0.98, green: 0.78, blue: 0.22)
        }
        return Color(red: 1.0, green: 0.48, blue: 0.28)
    }
}

private struct AnalysisLoupe: View {
    let image: CGImage
    let overlayImage: CGImage?
    let overlayOpacity: Double
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    let selection: CGRect
    var title = "Loupe"
    var previewSize = CGSize(width: 136, height: 136)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))

            ZStack {
                Color.black
                magnifiedImage(image, opacity: 1)

                if let overlayImage {
                    magnifiedImage(overlayImage, opacity: overlayOpacity)
                }
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
        }
        .padding(8)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Selected area loupe")
    }

    private func magnifiedImage(_ image: CGImage, opacity: Double) -> some View {
        GeometryReader { proxy in
            let normalizedCenter = normalizedSelectionCenter()
            let zoom = zoomScale()

            Image(decorative: image, scale: 1, orientation: orientation.swiftUIImageOrientation)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(
                    x: (0.5 - normalizedCenter.x) * proxy.size.width * zoom,
                    y: (0.5 - normalizedCenter.y) * proxy.size.height * zoom
                )
                .opacity(opacity)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }

    private func normalizedSelectionCenter() -> CGPoint {
        let displayedDepthSize = TAPImageOrientationMapper.displayedSize(nativeSize: depthSize, orientation: orientation)
        guard displayedDepthSize.width > 0, displayedDepthSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: selection,
            nativeSize: depthSize,
            orientation: orientation
        )
        return CGPoint(
            x: min(max(displayedRect.midX / displayedDepthSize.width, 0), 1),
            y: min(max(displayedRect.midY / displayedDepthSize.height, 0), 1)
        )
    }

    private func zoomScale() -> CGFloat {
        guard selection.width > 0, selection.height > 0 else {
            return 2.4
        }

        let widthRatio = depthSize.width / selection.width
        let heightRatio = depthSize.height / selection.height
        return min(max(min(widthRatio, heightRatio), 2.2), 5.2)
    }
}

private enum AnalysisButtonHint: Equatable {
    case view(DepthAnalysisViewMode)
    case inspector(AnalysisInspector)
    case help

    var title: String {
        switch self {
        case .view(let viewMode):
            viewMode.title
        case .inspector(let inspector):
            inspector.title
        case .help:
            "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .view(let viewMode):
            viewMode.systemImage
        case .inspector(let inspector):
            inspector.systemImage
        case .help:
            "questionmark.circle"
        }
    }
}

private enum AnalysisHelpSubject: Equatable {
    case view(DepthAnalysisViewMode)
    case inspector(AnalysisInspector)

    var title: String {
        switch self {
        case .view(let viewMode):
            viewMode.title
        case .inspector(let inspector):
            inspector.title
        }
    }

    var subtitle: String {
        switch self {
        case .view:
            "View"
        case .inspector:
            "Inspector"
        }
    }

    var systemImage: String {
        switch self {
        case .view(let viewMode):
            viewMode.systemImage
        case .inspector(let inspector):
            inspector.systemImage
        }
    }

    var detail: String {
        switch self {
        case .view(let viewMode):
            viewMode.detailedExplanation
        case .inspector(let inspector):
            inspector.detailedExplanation
        }
    }
}

private extension AnalysisInspector {
    var detailedExplanation: String {
        switch self {
        case .measurements:
            "Shows numeric depth measurements for the selected region, including median depth, range, valid samples, and any local plane estimate."
        case .legend:
            "Explains the current view's color mapping, such as near-to-far depth colors, valid-depth coverage, or point-cloud distance colors."
        case .overlay:
            "Controls the opacity of generated overlays on the main image, so you can compare the analysis layer against the RGB photo."
        case .region:
            "Shows measurements and previews for a completed rectangular selection. In Depth view, the selected crop is recolored using only local valid depth samples."
        case .planeFilter:
            "Controls seed-grown plane strictness and reports the selected plane region's cells, area, confidence, flatness, residual, and calibration diagnostics."
        case .cloudInfo:
            "Explains the local camera-coordinate point cloud preview and reports point counts and near-to-far color meaning."
        }
    }
}

private struct AnalysisInspectorStrip: View {
    @Binding var panelDestination: AnalysisPanelDestination?
    @Binding var viewMode: DepthAnalysisViewMode
    let inspectors: [AnalysisInspector]
    let buttonHint: AnalysisButtonHint?
    let onViewTapped: (DepthAnalysisViewMode) -> Void
    let onInspectorTapped: (AnalysisInspector) -> Void
    let onHelpTapped: () -> Void
    @State private var viewScrollPosition: String? = DepthAnalysisViewMode.rgb.id
    @State private var inspectorScrollPosition: String?

    private static let helpScrollID = "analysis-help"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PinnedStripRow(
                systemImage: "eye",
                accessibilityLabel: "Views",
                helpText: "Views",
                scrollPosition: $viewScrollPosition
            ) {
                viewModeTabs
            }

            PinnedStripRow(
                systemImage: "scope",
                accessibilityLabel: "Inspectors",
                helpText: "Inspectors",
                scrollPosition: $inspectorScrollPosition
            ) {
                inspectorTabs
                helpButton
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            if let buttonHint {
                AnalysisButtonBubble(hint: buttonHint)
                    .offset(y: -38)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear {
            viewScrollPosition = viewMode.id
            syncInspectorScrollPosition()
        }
        .onChange(of: viewMode) { _, newValue in
            viewScrollPosition = newValue.id
            syncInspectorScrollPosition()
        }
        .onChange(of: inspectors) { _, _ in
            syncInspectorScrollPosition()
        }
        .onChange(of: panelDestination) { _, _ in
            syncInspectorScrollPosition()
        }
        .animation(.snappy(duration: 0.18), value: buttonHint)
    }

    private var viewModeTabs: some View {
        ForEach(DepthAnalysisViewMode.allCases) { item in
            Button {
                onViewTapped(item)
                viewScrollPosition = item.id
                viewMode = item
            } label: {
                iconButton(
                    systemImage: item.systemImage,
                    isSelected: item == viewMode
                )
            }
            .id(item.id)
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .help(item.detailedExplanation)
        }
    }

    private var inspectorTabs: some View {
        ForEach(inspectors) { inspector in
            Button {
                onInspectorTapped(inspector)
                inspectorScrollPosition = inspector.id
                toggle(.inspector(inspector))
            } label: {
                iconButton(
                    systemImage: inspector.systemImage,
                    isSelected: panelDestination?.selectedInspector == inspector
                )
            }
            .id(inspector.id)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(inspector.title)
            .help(inspector.title)
        }
    }

    private var helpButton: some View {
        Button {
            onHelpTapped()
            inspectorScrollPosition = Self.helpScrollID
            toggle(.help)
        } label: {
            iconButton(
                systemImage: "questionmark.circle",
                isSelected: panelDestination == .help
            )
        }
        .id(Self.helpScrollID)
        .buttonStyle(.plain)
        .accessibilityLabel("Analysis Help")
        .help("Open Analysis Help.")
    }

    private func iconButton(systemImage: String, isSelected: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 34, height: 32)
            .foregroundStyle(.primary)
            .background(iconBackground(isSelected: isSelected), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func toggle(_ destination: AnalysisPanelDestination) {
        if panelDestination == destination {
            panelDestination = nil
        } else {
            panelDestination = destination
        }
    }

    private func iconBackground(isSelected: Bool) -> Color {
        if isSelected {
            return Color.primary.opacity(0.16)
        }
        return Color.primary.opacity(0.06)
    }

    private func syncInspectorScrollPosition() {
        if case .inspector(let inspector) = panelDestination, inspectors.contains(inspector) {
            inspectorScrollPosition = inspector.id
        } else if panelDestination == .help {
            inspectorScrollPosition = Self.helpScrollID
        } else if inspectorScrollPosition == nil || !isValidInspectorScrollID(inspectorScrollPosition) {
            inspectorScrollPosition = inspectors.first?.id ?? Self.helpScrollID
        }
    }

    private func isValidInspectorScrollID(_ id: String?) -> Bool {
        guard let id else {
            return false
        }
        return id == Self.helpScrollID || inspectors.contains { $0.id == id }
    }
}

private struct PinnedStripRow<Content: View>: View {
    let systemImage: String
    let accessibilityLabel: String
    let helpText: String
    @Binding var scrollPosition: String?
    let content: Content

    init(
        systemImage: String,
        accessibilityLabel: String,
        helpText: String,
        scrollPosition: Binding<String?>,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.helpText = helpText
        _scrollPosition = scrollPosition
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 32)
                .accessibilityLabel(accessibilityLabel)
                .help(helpText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition, anchor: .center)
        }
    }
}

private struct AnalysisButtonBubble: View {
    let hint: AnalysisButtonHint

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hint.systemImage)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(hint.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.2), lineWidth: 1)
            }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}

private struct AnalysisPanelLayer<Content: View>: View {
    @Binding var destination: AnalysisPanelDestination?
    let maxHeight: CGFloat
    let content: Content
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredPanelHeight: CGFloat = 0

    init(destination: Binding<AnalysisPanelDestination?>, maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        _destination = destination
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: titleIcon)
                    .font(.headline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    destination = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close analysis panel")
                .help("Close this analysis panel.")
            }

            Divider()

            adaptivePanelContent
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: AnalysisPanelHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(AnalysisPanelContentHeightKey.self) { height in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                measuredContentHeight = height
            }
            logPanelLayout(contentHeight: height, panelHeight: measuredPanelHeight)
        }
        .onPreferenceChange(AnalysisPanelHeightKey.self) { height in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                measuredPanelHeight = height
            }
            logPanelLayout(contentHeight: measuredContentHeight, panelHeight: height)
        }
        .onChange(of: destination) { _, _ in
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                measuredContentHeight = 0
                measuredPanelHeight = 0
            }
        }
    }

    private var adaptivePanelContent: some View {
        ScrollView(.vertical, showsIndicators: measuredContentHeight > contentMaxHeight + 1) {
            measuredPanelContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentViewportHeight, alignment: .top)
        .clipped()
    }

    private var measuredPanelContent: some View {
        panelContent
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: AnalysisPanelContentHeightKey.self, value: proxy.size.height)
                }
            }
    }

    private var panelContent: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentMaxHeight: CGFloat {
        max(72, maxHeight - 78)
    }

    private var contentViewportHeight: CGFloat {
        guard measuredContentHeight > 0 else {
            return 1
        }
        return min(measuredContentHeight, contentMaxHeight)
    }

    private func logPanelLayout(contentHeight: CGFloat, panelHeight: CGFloat) {
        #if DEBUG
        guard contentHeight > 0 || panelHeight > 0 else {
            return
        }
        let isScrolling = contentHeight > contentMaxHeight + 1
        print(
            "[DepthAnalysisPanel] title=\(title) content=\(String(format: "%.1f", contentHeight)) " +
            "panel=\(String(format: "%.1f", panelHeight)) contentMax=\(String(format: "%.1f", contentMaxHeight)) " +
            "scroll=\(isScrolling)"
        )
        #endif
    }

    private var title: String {
        guard let destination else {
            return "Analysis"
        }

        switch destination {
        case .inspector(let inspector):
            return inspector.title
        case .help:
            return "Analysis Help"
        }
    }

    private var titleIcon: String {
        guard let destination else {
            return "scope"
        }

        switch destination {
        case .inspector(let inspector):
            return inspector.systemImage
        case .help:
            return "questionmark.circle"
        }
    }
}

private struct AnalysisPanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AnalysisPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AnalysisHelpView: View {
    let subject: AnalysisHelpSubject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: subject.systemImage)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(subject.title)
                        .font(.headline)
                    Text(subject.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(subject.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RegionInspectorContent: View {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    let selection: CGRect?
    let interactionState: AnalysisInteractionState
    let stats: TAPDepthRegionStats?
    let planeEstimate: TAPPlaneEstimate?
    let regionHeatmap: TAPDepthHeatmapVisualization?
    let heatmapErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Region")
                    .font(.caption.weight(.semibold))
                    .help("Drag on the image to choose a region. The region heatmap uses only the selected valid depth samples to recalculate its color range.")
                Spacer(minLength: 8)
                Text(stateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if interactionState == .drawingSelection {
                Label("Selecting region...", systemImage: "hand.draw")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let selection, interactionState.showsRegionInspector {
                if let regionHeatmap {
                    HStack(alignment: .top, spacing: 12) {
                        AnalysisLoupe(
                            image: image,
                            overlayImage: regionHeatmap.image,
                            overlayOpacity: 0.92,
                            orientation: orientation,
                            depthSize: depthSize,
                            selection: selection,
                            title: "Local heatmap",
                            previewSize: CGSize(width: 154, height: 154)
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(localRangeText(regionHeatmap))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            DepthLegendView(stops: regionHeatmap.legendStops)
                        }
                    }
                } else {
                    Label(heatmapErrorMessage ?? "Not enough valid depth samples in this region.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                regionSummary
            } else {
                Label("No region selected.", systemImage: "viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var regionSummary: some View {
        if let stats {
            VStack(alignment: .leading, spacing: 7) {
                DepthMetricRow(
                    title: "Median depth",
                    value: stats.medianDepthMeters.map { String(format: "%.2f m", $0) } ?? "No valid depth",
                    explanation: "Sort the selected valid depth samples from near to far; this is the value in the middle."
                )
                DepthMetricRow(
                    title: "Range",
                    value: rangeText(stats),
                    explanation: "The selected region's nearest and farthest valid depth samples."
                )
                DepthMetricRow(
                    title: "Valid samples",
                    value: "\(stats.validSampleCount)/\(stats.totalSampleCount) · \(Int((stats.validRatio * 100).rounded()))%",
                    explanation: "How many selected pixels contain finite positive depth."
                )

                if let planeEstimate {
                    DepthMetricRow(
                        title: "Plane inliers",
                        value: "\(Int((planeEstimate.inlierRatio * 100).rounded()))%",
                        explanation: "The share of selected depth points that match the fitted local plane."
                    )
                }
            }
        }
    }

    private var stateText: String {
        switch interactionState {
        case .idle:
            "No local region"
        case .drawingSelection:
            "Selecting"
        case .regionSelected:
            "Selected"
        }
    }

    private func rangeText(_ stats: TAPDepthRegionStats) -> String {
        guard let minimum = stats.minimumDepthMeters, let maximum = stats.maximumDepthMeters else {
            return "No valid depth"
        }
        return String(format: "%.2f...%.2f m", minimum, maximum)
    }

    private func localRangeText(_ heatmap: TAPDepthHeatmapVisualization) -> String {
        String(format: "Local range %.2f...%.2f m", heatmap.rangeMeters.lowerBound, heatmap.rangeMeters.upperBound)
    }
}

private struct PlaneFilterInspectorContent: View {
    let depthMap: TAPMetricDepthMap
    let depthAccuracy: String
    let depthQuality: String
    let selectedPlaneRegion: TAPPlaneRegion?
    let planeSeedPoint: CGPoint?
    let errorMessage: String?
    @Binding var strictness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Plane region")
                    .font(.caption.weight(.semibold))
                    .help("Tap a surface point in Planes view. The analyzer grows a connected camera-coordinate plane region from that seed.")
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Strictness")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Higher strictness keeps only pixels that fit the seed plane more tightly.")
                Slider(value: $strictness, in: 0.35...0.95)
                    .tint(.primary)
                Text("\(Int((strictness * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            if let selectedPlaneRegion {
                DepthMetricRow(
                    title: "Confidence",
                    value: "\(Int((selectedPlaneRegion.confidence * 100).rounded()))%",
                    explanation: "Combined score from flatness, inlier ratio, and selected plane size."
                )
                DepthMetricRow(
                    title: "Plane cells",
                    value: "\(selectedPlaneRegion.gridCells.count)",
                    explanation: "Grid cells inside the grown region that contain enough pixels fitting the selected plane."
                )
                DepthMetricRow(
                    title: "Area",
                    value: areaText(selectedPlaneRegion.areaSquareMeters),
                    explanation: "Approximate visible surface area in camera coordinates."
                )
                DepthMetricRow(
                    title: "Flatness",
                    value: "\(Int((selectedPlaneRegion.flatnessScore * 100).rounded()))%",
                    explanation: "How tightly the grown region fits a single local plane. Higher is flatter."
                )
                DepthMetricRow(
                    title: "Residual",
                    value: String(format: "%.3f m", selectedPlaneRegion.estimate.averageResidualMeters),
                    explanation: "Average distance from inlier points to the selected plane."
                )
                DepthMetricRow(
                    title: "Inliers",
                    value: "\(Int((selectedPlaneRegion.estimate.inlierRatio * 100).rounded()))% · \(selectedPlaneRegion.sampleCount)",
                    explanation: "Share and count of grown points that match the fitted plane."
                )
                DepthMetricRow(
                    title: "Normal",
                    value: String(format: "[%.2f, %.2f, %.2f]", selectedPlaneRegion.estimate.normal.x, selectedPlaneRegion.estimate.normal.y, selectedPlaneRegion.estimate.normal.z),
                    explanation: "Selected plane direction in local camera coordinates."
                )
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if depthMap.calibration == nil {
                Label("Camera calibration missing.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if planeSeedPoint == nil {
                Label("Tap a surface point to grow a plane region.", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("No stable plane region found from this point.", systemImage: "square.dashed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                PlaneLegendSwatch(color: Color(red: 0.74, green: 0.96, blue: 0.36), text: "High-fit cell")
                PlaneLegendSwatch(color: Color(red: 1.0, green: 0.62, blue: 0.24), text: "Lower-fit cell")
            }

            Divider()

            DepthMetricRow(
                title: "Depth size",
                value: "\(depthMap.width)x\(depthMap.height)",
                explanation: "Native auxiliary depth-map resolution used for camera-coordinate plane fitting."
            )
            DepthMetricRow(
                title: "Calibration",
                value: depthMap.calibration == nil ? "Missing" : "Available",
                explanation: "Camera intrinsics used to project depth pixels into local camera coordinates."
            )
            DepthMetricRow(
                title: "Depth quality",
                value: "\(depthAccuracy) / \(depthQuality)",
                explanation: "Apple depth accuracy and quality metadata for this captured photo."
            )
        }
    }

    private var statusText: String {
        if let selectedPlaneRegion {
            return "\(selectedPlaneRegion.gridCells.count) cells"
        }
        return "No seed"
    }

    private func areaText(_ area: Double) -> String {
        if area < 0.01 {
            return String(format: "%.1f sq cm", area * 10_000)
        }
        return String(format: "%.3f sq m", area)
    }
}

private struct PlaneLegendSwatch: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 12)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OverlayInspectorContent: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("Overlay opacity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .help("Opacity controls the global overlay on the main image. It does not change local region heatmap colors.")
            Slider(value: $opacity, in: 0.2...1.0)
                .tint(.primary)
            Text("\(Int((opacity * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private struct CloudInfoInspectorContent: View {
    let depthMap: TAPMetricDepthMap
    let orientation: CGImagePropertyOrientation
    let selection: CGRect?
    let interactionState: AnalysisInteractionState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloud")
                .font(.caption.weight(.semibold))
                .help("This is a local camera-coordinate point cloud preview. It is not cloud storage, cloud compute, or a semantic word cloud.")
            DepthLegendView(stops: [
                TAPDepthLegendStop(position: 0, label: "Near points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 0)),
                TAPDepthLegendStop(position: 1, label: "Far points", color: TAPDepthHeatmapRenderer.viridisColor(normalized: 1))
            ])
            Text("\(sampleCount(in: fullRegion)) sampled points")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if let selection, interactionState.showsRegionInspector {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    PointCloudRegionPreview(
                        depthMap: depthMap,
                        orientation: orientation,
                        selection: selection,
                        previewSize: CGSize(width: 154, height: 154)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(sampleCount(in: selection)) selected points")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var fullRegion: CGRect {
        CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
    }

    private func sampleCount(in region: CGRect) -> Int {
        TAPDepthGeometryProjector.sampledPoints(from: depthMap, in: region, maxCount: 900).count
    }
}

struct DepthLegendView: View {
    let stops: [TAPDepthLegendStop]

    var body: some View {
        VStack(spacing: 5) {
            LinearGradient(
                stops: stops.map { Gradient.Stop(color: $0.color.swiftUIColor, location: $0.position) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 9)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.primary.opacity(0.14), lineWidth: 1)
            }

            HStack {
                Text(stops.first?.label ?? "Near")
                Spacer(minLength: 8)
                Text(stops.last?.label ?? "Far")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SwatchLegendView: View {
    let stops: [TAPDepthLegendStop]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(stops) { stop in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stop.color.swiftUIColor)
                        .frame(width: 18, height: 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(.primary.opacity(0.16), lineWidth: 1)
                        }

                    Text(stop.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DepthMetricRow: View {
    let title: String
    let value: String
    let explanation: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .help(explanation)
            Spacer()
            Text(value)
                .fontDesign(.monospaced)
        }
    }
}

private extension TAPRGBAColor {
    var swiftUIColor: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }
}
