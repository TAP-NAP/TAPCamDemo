//
//  DepthAnalysisView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/26.
//

import Combine
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

    var body: some View {
        VStack(spacing: 0) {
            modePicker

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

            bottomPanel
        }
        .navigationTitle("Depth Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(assetID: assetID)
        }
    }

    private var modePicker: some View {
        Picker("Analysis mode", selection: $viewModel.mode) {
            ForEach(DepthAnalysisMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(12)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private func analysisContent(_ input: TAPDepthAnalysisInput) -> some View {
        switch viewModel.mode {
        case .pointCloud:
            PointCloudPreview(depthMap: input.depthMap)
                .padding()
        default:
            InteractiveDepthImage(
                image: viewModel.displayImage,
                orientation: input.imageOrientation,
                depthSize: CGSize(width: input.depthMap.width, height: input.depthMap.height),
                selection: $viewModel.selectionRect
            ) { depthRect in
                viewModel.updateSelection(depthRect)
            }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats = viewModel.regionStats {
                DepthMetricRow(title: "Median", value: stats.medianDepthMeters.map { String(format: "%.2f m", $0) } ?? "No valid depth")
                DepthMetricRow(title: "Range", value: rangeText(stats))
                DepthMetricRow(title: "Valid samples", value: "\(stats.validSampleCount)/\(stats.totalSampleCount) · \(Int((stats.validRatio * 100).rounded()))%")
            }

            if let plane = viewModel.planeEstimate {
                Divider()
                DepthMetricRow(title: "Plane residual", value: String(format: "%.3f m", plane.averageResidualMeters))
                DepthMetricRow(title: "Plane inliers", value: "\(Int((plane.inlierRatio * 100).rounded()))%")
                DepthMetricRow(title: "Plane normal", value: String(format: "[%.2f, %.2f, %.2f]", plane.normal.x, plane.normal.y, plane.normal.z))
            } else if viewModel.input != nil {
                Divider()
                Text("Select a textured planar region to estimate whether its valid depth samples are approximately coplanar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func rangeText(_ stats: TAPDepthRegionStats) -> String {
        guard let minimum = stats.minimumDepthMeters, let maximum = stats.maximumDepthMeters else {
            return "No valid depth"
        }

        return String(format: "%.2f...%.2f m", minimum, maximum)
    }
}

@MainActor
final class DepthAnalysisViewModel: ObservableObject {
    @Published var input: TAPDepthAnalysisInput?
    @Published var mode: DepthAnalysisMode = .rgb
    @Published var selectionRect: CGRect?
    @Published var regionStats: TAPDepthRegionStats?
    @Published var planeEstimate: TAPPlaneEstimate?
    @Published var errorMessage: String?

    var displayImage: CGImage {
        guard let input else {
            preconditionFailure("DepthAnalysisView requests a display image only after input loads.")
        }

        // UI mode contract:
        // - RGB shows the HEIC primary image from ImageIO.
        // - Depth shows `TAPDepthHeatmapRenderer.heatmap`, a false-color
        //   view of metric depth samples. It is visual only; measurements use
        //   `TAPMetricDepthMap.samples`.
        // - Mask shows `TAPDepthMaskRenderer.validMask`, where white
        //   means a finite positive depth sample exists.
        // - Planes reuses the heatmap as the backdrop while the bottom panel
        //   reports `TAPPlaneEstimator` results for the selected depth region.
        // - Cloud is handled by `PointCloudPreview`, so this fallback is never
        //   measured from directly.
        switch mode {
        case .rgb:
            return input.image
        case .heatmap:
            return input.heatmap
        case .mask:
            return input.validMask
        case .planes:
            return input.heatmap
        case .pointCloud:
            return input.heatmap
        }
    }

    func load(assetID: String) async {
        do {
            let data = try await PhotoLibraryWriter.originalPhotoData(localIdentifier: assetID)
            let loadedInput = try TAPDepthMapReader.analysisInput(from: data)
            input = loadedInput
            errorMessage = nil
            updateSelection(CGRect(x: 0, y: 0, width: loadedInput.depthMap.width, height: loadedInput.depthMap.height))
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func updateSelection(_ depthRect: CGRect) {
        guard let input else {
            return
        }

        regionStats = TAPDepthGeometryProjector.stats(for: input.depthMap, in: depthRect)
        planeEstimate = TAPPlaneEstimator.estimatePlane(depthMap: input.depthMap, region: depthRect)
    }
}

enum DepthAnalysisMode: String, CaseIterable, Identifiable {
    /// Normal color image. Source: ImageIO primary HEIC image item.
    case rgb

    /// False-color depth image. Source: Apple auxiliary depth/disparity rebuilt
    /// as `AVDepthData`, converted to Float32 metric depth, then colorized.
    case heatmap

    /// Valid-depth coverage image. Source: the same metric depth map; finite
    /// positive samples are white, missing/invalid samples are black.
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
}

private struct InteractiveDepthImage: View {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
    let depthSize: CGSize
    @Binding var selection: CGRect?
    let onSelectionChanged: (CGRect) -> Void

    @State private var dragStart: CGPoint?

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
                    .scaledToFit()

                if let selection {
                    let rect = viewRect(for: selection, imageFrame: imageFrame)
                    Rectangle()
                        .stroke(.white, lineWidth: 2)
                        .background(Rectangle().fill(.white.opacity(0.12)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
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
                        onSelectionChanged(depthRect)
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
        }
    }

    private func fittedRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
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
}

private struct DepthMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontDesign(.monospaced)
        }
    }
}
