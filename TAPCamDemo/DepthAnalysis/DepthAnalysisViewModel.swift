//
//  DepthAnalysisViewModel.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Combine
import CoreGraphics
import Foundation

/// Owns depth-analysis loading and bridges local selection state.
///
/// `DepthAnalysisView` keeps panel and presentation state. This object owns the
/// data that changes because the user selected a loaded image region or plane
/// seed, while small models own the synchronous local analysis products.
@MainActor
final class DepthAnalysisViewModel: ObservableObject {
    @Published var input: TAPDepthAnalysisInput?
    @Published var viewMode: DepthAnalysisViewMode = .rgb
    @Published var regionSelection = DepthAnalysisRegionSelectionState()
    @Published var planeSelection = DepthAnalysisPlaneSelectionState()
    @Published var errorMessage: String?
    @Published var errorTitle = "Unable to analyze image"
    @Published var errorSystemImage = "exclamationmark.triangle"

    private let inputLoader: DepthAnalysisInputLoader
    private let planeRequestCoordinator: DepthAnalysisPlaneRegionRequestCoordinator

    init(
        inputLoader: DepthAnalysisInputLoader? = nil,
        planeRegionDetector: DepthAnalysisPlaneRegionDetector? = nil
    ) {
        self.inputLoader = inputLoader ?? DepthAnalysisInputLoader()
        self.planeRequestCoordinator = DepthAnalysisPlaneRegionRequestCoordinator(
            detector: planeRegionDetector ?? DepthAnalysisPlaneRegionDetector()
        )
    }

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
        // - Planes reuses the heatmap as the backdrop while a background Plane
        //   Filter task grows a seed-selected region using the prewarmed
        //   geometry cache when available.
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

    func load(source: DepthAnalysisSource) async {
        planeRequestCoordinator.resetForNewInput()
        planeSelection.cancelDetection()

        do {
            let loadedInput = try await inputLoader.loadInput(source: source)
            input = loadedInput
            clearSelection()
            planeRequestCoordinator.prewarmGeometry(for: loadedInput.depthMap)
            clearLoadError()
        } catch {
            applyLoadError(error)
        }
    }

    private func clearLoadError() {
        errorMessage = nil
        errorTitle = "Unable to analyze image"
        errorSystemImage = "exclamationmark.triangle"
    }

    private func applyLoadError(_ error: Error) {
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        errorTitle = presentation.title
        errorSystemImage = presentation.systemImage
        errorMessage = presentation.message
    }

    func beginSelection(_ depthRect: CGRect) {
        regionSelection.beginSelection(depthRect, depthMap: input?.depthMap)
    }

    func previewSelection(_ depthRect: CGRect) {
        regionSelection.previewSelection(depthRect, depthMap: input?.depthMap)
    }

    func finishSelection(_ depthRect: CGRect) {
        regionSelection.finishSelection(depthRect, depthMap: input?.depthMap)
    }

    func clearSelection() {
        planeRequestCoordinator.cancelRegionRequest()
        regionSelection.clear()
        planeSelection.clear()
    }

    func selectPlaneSeed(_ depthPoint: CGPoint) {
        guard let input else {
            return
        }

        planeSelection.selectSeed(depthPoint, depthMap: input.depthMap)
        updateSeedPlaneRegion()
    }

    func updatePlaneGrowthStrictness(_ strictness: Double) {
        planeSelection.updateStrictness(strictness)
        if planeSelection.hasSeed {
            updateSeedPlaneRegion(debounceNanoseconds: 120_000_000)
        }
    }

    private func updateSeedPlaneRegion(debounceNanoseconds: UInt64 = 0) {
        guard let input, let planeSeedPoint = planeSelection.seedPoint else {
            planeRequestCoordinator.cancelRegionRequest()
            planeSelection.clearDetection()
            return
        }

        planeRequestCoordinator.requestRegion(
            depthMap: input.depthMap,
            seed: planeSeedPoint,
            strictness: planeSelection.strictness,
            debounceNanoseconds: debounceNanoseconds,
            eventHandler: { [weak self] event in
                self?.applyPlaneRequestEvent(event)
            }
        )
    }

    private func applyPlaneRequestEvent(_ event: DepthAnalysisPlaneRegionRequestEvent) {
        switch event {
        case .started:
            planeSelection.startDetection()
        case .succeeded(let detection):
            planeSelection.finishDetection(detection)
        case .failed(let error):
            planeSelection.finishFailure(error)
        case .cancelled:
            planeSelection.cancelDetection()
        }
    }
}
