//
//  AnalysisPhotoSlot+Analysis.swift
//  TAPCamDemo
//

import Foundation

@MainActor
extension AnalysisPhotoSlot {
    func ensureInputLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        priority: TaskPriority,
        prewarmPlaneGeometry: Bool
    ) {
        if prewarmPlaneGeometry {
            selectionState.wantsPlaneGeometryPrewarm = true
        }
        if let input = analysisState.input {
            ensurePlaneGeometryPrewarmIfNeeded(for: input.depthMap)
        }
        guard analysisState.input == nil, analysisState.inputTask == nil else {
            return
        }

        let source = entry.source
        let requestKey = newOriginalRequestKey()
        analysisState.phase = .loading(progress: nil)
        setOriginalMediaFetchPhase(.resolving(hasDisplayImage))
        analysisState.errorMessage = nil
        analysisState.inputTask = Task(priority: priority) { [weak self] in
            await self?.loadInput(
                with: loader,
                source: source,
                requestKey: requestKey
            )
        }
    }

    private func loadInput(
        with loader: DepthAnalysisProgressivePhotoLoader,
        source: DepthAnalysisSource,
        requestKey: MediaFetchRequestKey
    ) async {
        do {
            let loadedInput = try await loader.input(
                source: source,
                requestKey: requestKey
            ) { [weak self] progress in
                self?.applyOriginalICloudProgress(progress, requestKey: requestKey)
            }
            guard !Task.isCancelled else {
                finishCancelledInputLoad(requestKey: requestKey)
                return
            }
            finishInputLoad(loadedInput, requestKey: requestKey)
        } catch {
            guard !Task.isCancelled else {
                finishCancelledInputLoad(requestKey: requestKey)
                return
            }
            finishFailedInputLoad(error, requestKey: requestKey)
        }
    }

    private func finishCancelledInputLoad(requestKey: MediaFetchRequestKey) {
        guard analysisState.activeOriginalRequestKey == requestKey else {
            return
        }
        analysisState.inputTask = nil
        analysisState.activeOriginalRequestKey = nil
    }

    private func finishInputLoad(
        _ loadedInput: TAPDepthAnalysisInput,
        requestKey: MediaFetchRequestKey
    ) {
        guard analysisState.activeOriginalRequestKey == requestKey else {
            return
        }
        analysisState.inputTask = nil
        analysisState.activeOriginalRequestKey = nil
        analysisState.input = loadedInput
        analysisState.phase = .ready
        setOriginalMediaFetchPhase(.ready(true))
        clearLoadError()
        selectionState.regionSelection.clear()
        selectionState.planeSelection.cancelDetection()
        selectionState.planeRequestCoordinator.resetForNewInput()
        selectionState.hasRequestedPlaneGeometryPrewarm = false
        ensurePlaneGeometryPrewarmIfNeeded(for: loadedInput.depthMap)
    }

    private func finishFailedInputLoad(
        _ error: Error,
        requestKey: MediaFetchRequestKey
    ) {
        guard analysisState.activeOriginalRequestKey == requestKey else {
            return
        }
        analysisState.inputTask = nil
        analysisState.activeOriginalRequestKey = nil
        applyLoadError(error)
    }

    func clearLoadError() {
        analysisState.errorMessage = nil
        analysisState.errorTitle = "Unable to analyze image"
        analysisState.errorSystemImage = "exclamationmark.triangle"
    }

    func clearLoadErrorIfAnalysisIsHealthy() {
        guard analysisState.phase != .failed else {
            return
        }
        clearLoadError()
    }

    func applyLoadError(_ error: Error) {
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        analysisState.errorTitle = presentation.title
        analysisState.errorSystemImage = presentation.systemImage
        analysisState.errorMessage = presentation.message
        analysisState.phase = .failed
        applyMediaFetchFailure(error)
        selectionState.planeRequestCoordinator.resetForNewInput()
        selectionState.planeSelection.cancelDetection()
    }

    func newOriginalRequestKey() -> MediaFetchRequestKey {
        analysisState.activeOriginalRequestKey = nil
        analysisState.originalFetchGeneration &+= 1
        analysisState.lastOriginalProgress = nil
        let requestKey = MediaFetchRequestKey(
            itemID: entry.mediaID,
            generation: analysisState.originalFetchGeneration,
            purpose: .photoOriginal
        )
        analysisState.activeOriginalRequestKey = requestKey
        return requestKey
    }

    func applyOriginalICloudProgress(
        _ progress: Double?,
        requestKey: MediaFetchRequestKey
    ) {
        guard analysisState.activeOriginalRequestKey == requestKey else {
            return
        }
        let normalizedProgress = progress.map { min(max($0, 0), 1) }
        if let normalizedProgress {
            analysisState.lastOriginalProgress = max(
                analysisState.lastOriginalProgress ?? 0,
                normalizedProgress
            )
        }
        analysisState.phase = .loading(progress: analysisState.lastOriginalProgress)
        setOriginalMediaFetchPhase(.downloadingFromICloud(
            hasDisplayImage,
            progress: analysisState.lastOriginalProgress
        ))
    }

    func applyMediaFetchFailure(_ error: Error) {
        if error is CancellationError {
            return
        }
        let failure = mediaFetchFailure(for: error)
        setOriginalMediaFetchPhase(.failed(
            hasDisplayImage,
            reason: failure,
            retryable: failure.isRetryable
        ))
    }

    func cancelOriginalTasks(preserveCloudState: Bool) {
        let wasCloudFetch: Bool
        switch analysisState.mediaFetchPhase {
        case .cloudOnly, .downloadingFromICloud:
            wasCloudFetch = true
        default:
            wasCloudFetch = false
        }

        displayFetchState.activeDisplayRequestKey = nil
        displayFetchState.displayFetchGeneration &+= 1
        analysisState.activeOriginalRequestKey = nil
        analysisState.originalFetchGeneration &+= 1
        analysisState.lastOriginalProgress = nil
        displayFetchState.displayTask?.cancel()
        displayFetchState.displayTask = nil
        displayFetchState.displayTaskPixelLength = nil
        analysisState.inputTask?.cancel()
        analysisState.inputTask = nil

        if displayFetchState.displayPhoto == nil {
            displayFetchState.phase = displayFetchState.thumbnailImage == nil
                ? .idle
                : .thumbnailReady
        }
        if analysisState.input == nil {
            analysisState.phase = .idle
        }
        if displayFetchState.displayPhoto != nil {
            setDisplayMediaFetchPhase(.ready(true))
        } else if displayFetchState.thumbnailImage != nil {
            setDisplayMediaFetchPhase(.localPreview(true))
        } else {
            setDisplayMediaFetchPhase(.idle(false))
        }

        if preserveCloudState, wasCloudFetch {
            setOriginalMediaFetchPhase(.cloudOnly(hasDisplayImage))
        } else if hasDisplayImage {
            setOriginalMediaFetchPhase(.localPreview(true))
        } else {
            setOriginalMediaFetchPhase(.idle(false))
        }
    }

    func setOriginalMediaFetchPhase(_ phase: MediaFetchPhase<Bool, Bool>) {
        analysisState.mediaFetchPhase = phase
    }
}
