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
        guard !(analysisState.phase == .failed && originalResourceOwner.isReady),
              analysisState.input == nil, analysisState.inputTask == nil else {
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
            let loadedInput = try await loader.loadedOriginal(
                source: source,
                requestKey: requestKey,
                expectsPairedVideo: entry.expectsPairedVideo,
                retainedResourceLease: originalResourceOwner.acquireLease(),
                resourceReadyHandler: { [weak self] resourceLease in
                    self?.publishOriginalResource(
                        resourceLease,
                        requestKey: requestKey
                    )
                },
                progressHandler: { [weak self] progress in
                    self?.applyOriginalICloudProgress(
                        progress,
                        requestKey: requestKey
                    )
                }
            )
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
        pendingSignedOriginalRefreshID = nil
        originalResourceOwner.failWaitingConsumers(CancellationError())
    }

    func publishOriginalResource(
        _ resourceLease: TAPPhotoOriginalResourceLease,
        requestKey: MediaFetchRequestKey
    ) {
        guard analysisState.activeOriginalRequestKey == requestKey else {
            return
        }
        originalResourceOwner.install(resourceLease)
        if retainsViewerData, isCurrentResource, let loader = displayFetchState.lastLoader {
            ensureDisplayPhotoLoading(
                loader: loader,
                pixelLength: displayFetchState.lastPixelLength,
                priority: displayFetchState.lastPriority,
                originalResource: resourceLease
            )
        }
        if case .pendingCapture(_, let selectedSignedPhoto) = resourceLease.origin,
           selectedSignedPhoto {
            pendingSignedOriginalRefreshID = nil
        }
        // Original-file readiness is independent from depth/3D decoding. The
        // latter continues in the same task but must not keep Share disabled.
        setOriginalMediaFetchPhase(.ready(true))
    }

    private func finishInputLoad(
        _ loadedOriginal: DepthAnalysisProgressivePhotoLoader.LoadedOriginal,
        requestKey: MediaFetchRequestKey
    ) {
        guard analysisState.activeOriginalRequestKey == requestKey else {
            return
        }
        analysisState.inputTask = nil
        analysisState.activeOriginalRequestKey = nil
        if let resourceLease = loadedOriginal.resourceLease {
            originalResourceOwner.install(resourceLease)
        } else {
            originalResourceOwner.clear()
        }
        pendingSignedOriginalRefreshID = nil

        guard retainsViewerData else { return }
        let input: TAPDepthAnalysisInput
        do {
            input = try loadedOriginal.analysisInput()
        } catch {
            analysisState.input = nil
            analysisState.completedInputRequestKey = nil
            let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
            analysisState.errorTitle = presentation.title
            analysisState.errorSystemImage = presentation.systemImage
            analysisState.errorMessage = presentation.message
            analysisState.phase = .failed
            // The complete original is still ready even when 3D/depth decoding
            // is unavailable. Share readiness follows the file-backed lease,
            // not the analysis result.
            if loadedOriginal.resourceLease != nil {
                setOriginalMediaFetchPhase(.ready(true))
            } else {
                applyMediaFetchFailure(error)
            }
            selectionState.planeRequestCoordinator.resetForNewInput()
            selectionState.planeSelection.cancelDetection()
            return
        }

        analysisState.input = input
        analysisState.completedInputRequestKey = requestKey
        analysisState.phase = .ready
        setOriginalMediaFetchPhase(.ready(true))
        clearLoadError()
        selectionState.planeSelection.cancelDetection()
        selectionState.planeRequestCoordinator.resetForNewInput()
        selectionState.hasRequestedPlaneGeometryPrewarm = false
        ensurePlaneGeometryPrewarmIfNeeded(for: input.depthMap)
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
        originalResourceOwner.clear()
        originalResourceOwner.failWaitingConsumers(error)
        pendingSignedOriginalRefreshID = nil
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
        // PhotoKit may deliver a final progress callback through a queued
        // MainActor task after the complete original lease has already been
        // published. Once exact bytes are ready, progress must never demote
        // Share readiness while depth/3D decoding continues.
        guard originalResourceOwner.acquireLease() == nil else {
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
        pendingSignedOriginalRefreshID = nil
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
        if analysisState.input == nil && !originalResourceOwner.isReady {
            analysisState.phase = .idle
        }
        if displayFetchState.displayPhoto != nil {
            setDisplayMediaFetchPhase(.ready(true))
        } else if displayFetchState.thumbnailImage != nil {
            setDisplayMediaFetchPhase(.localPreview(true))
        } else {
            setDisplayMediaFetchPhase(.idle(false))
        }

        if originalResourceOwner.isReady {
            setOriginalMediaFetchPhase(.ready(true))
        } else if preserveCloudState, wasCloudFetch {
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
