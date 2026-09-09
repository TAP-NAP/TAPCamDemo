//
//  AnalysisPhotoSlot+Selection.swift
//  TAPCamDemo
//

import CoreGraphics
import Foundation

@MainActor
extension AnalysisPhotoSlot {
    func clearSelection() {
        selectionState.planeRequestCoordinator.cancelRegionRequest()
        selectionState.planeSelection.clear()
    }

    func dismissCompletedGridToast(_ toastID: UUID) {
        selectionState.planeSelection.dismissCompletedGridToast(toastID)
    }

    func selectPlaneSeed(_ depthPoint: CGPoint, strictness: Double? = nil) {
        guard let input = analysisState.input else {
            return
        }

        if let strictness {
            selectionState.planeSelection.updateStrictness(strictness)
        }
        let generationID = selectionState.planeSelection.selectSeed(
            depthPoint,
            depthMap: input.depthMap
        )
        updateSeedPlaneRegion(generationID: generationID)
    }

    func updatePlaneGrowthStrictness(_ strictness: Double) {
        selectionState.planeSelection.updateStrictness(strictness)
        if selectionState.planeSelection.hasSeed {
            updateSeedPlaneRegion(
                generationID: selectionState.planeSelection.generationID,
                debounceNanoseconds: 120_000_000
            )
        }
    }

    func ensurePlaneGeometryPrewarmIfNeeded(for depthMap: TAPMetricDepthMap) {
        guard selectionState.wantsPlaneGeometryPrewarm,
              !selectionState.hasRequestedPlaneGeometryPrewarm else {
            return
        }
        selectionState.hasRequestedPlaneGeometryPrewarm = true
        selectionState.planeRequestCoordinator.prewarmGeometry(for: depthMap)
    }

    func updateSeedPlaneRegion(
        generationID: Int,
        debounceNanoseconds: UInt64 = 0
    ) {
        guard let input = analysisState.input,
              let planeSeedPoint = selectionState.planeSelection.seedPoint else {
            selectionState.planeRequestCoordinator.cancelRegionRequest()
            selectionState.planeSelection.clearDetection()
            return
        }

        selectionState.planeRequestCoordinator.requestRegion(
            depthMap: input.depthMap,
            seed: planeSeedPoint,
            strictness: selectionState.planeSelection.strictness,
            generationID: generationID,
            debounceNanoseconds: debounceNanoseconds,
            eventHandler: { [weak self] event in
                self?.applyPlaneRequestEvent(event)
            }
        )
    }

    func applyPlaneRequestEvent(_ event: DepthAnalysisPlaneRegionRequestEvent) {
        switch event {
        case .started(let generationID):
            selectionState.planeSelection.startDetection(generationID: generationID)
        case .partial(let progress, let generationID):
            selectionState.planeSelection.applyPartialGrid(
                progress,
                generationID: generationID
            )
        case .succeeded(let detection, let generationID):
            selectionState.planeSelection.finishDetection(
                detection,
                generationID: generationID
            )
        case .failed(let error, let generationID):
            selectionState.planeSelection.finishFailure(error, generationID: generationID)
        case .cancelled(let generationID):
            selectionState.planeSelection.cancelDetection(generationID: generationID)
        }
    }
}
