//
//  AnalysisPhotoSlot+DisplayFetch.swift
//  TAPCamDemo
//

import Foundation
import UIKit

@MainActor
extension AnalysisPhotoSlot {
    /// Registers the Live Photo request as a slot-owned fetch. The returned
    /// key is the only identity accepted by later progress/result callbacks.
    func beginLivePhotoFetch(
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) -> MediaFetchRequestKey {
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        displayFetchState.livePhotoFetchGeneration &+= 1
        let requestKey = MediaFetchRequestKey(
            itemID: entry.mediaID,
            generation: displayFetchState.livePhotoFetchGeneration,
            purpose: .livePhotoPlayback
        )
        displayFetchState.activeLivePhotoRequestKey = requestKey
        displayFetchState.cancelLivePhotoFetchAction = onCancel
        displayFetchState.retryLivePhotoFetchAction = onRetry
        displayFetchState.livePhotoMediaFetchPhase = hasDisplayImage
            ? .localPreview(true)
            : .idle(false)
        return requestKey
    }

    func markLivePhotoFetchResolving(requestKey: MediaFetchRequestKey) {
        guard displayFetchState.activeLivePhotoRequestKey == requestKey else {
            return
        }
        displayFetchState.livePhotoMediaFetchPhase = .resolving(hasDisplayImage)
    }

    func applyLivePhotoICloudProgress(
        _ progress: Double?,
        requestKey: MediaFetchRequestKey
    ) {
        guard displayFetchState.activeLivePhotoRequestKey == requestKey else {
            return
        }
        displayFetchState.livePhotoMediaFetchPhase = .downloadingFromICloud(
            hasDisplayImage,
            progress: progress.map { min(max($0, 0), 1) }
        )
    }

    func completeLivePhotoFetch(requestKey: MediaFetchRequestKey) {
        guard displayFetchState.activeLivePhotoRequestKey == requestKey else {
            return
        }
        displayFetchState.activeLivePhotoRequestKey = nil
        displayFetchState.cancelLivePhotoFetchAction = nil
        displayFetchState.retryLivePhotoFetchAction = nil
        displayFetchState.livePhotoMediaFetchPhase = .ready(true)
    }

    func failLivePhotoFetch(
        _ error: Error,
        requestKey: MediaFetchRequestKey
    ) {
        guard displayFetchState.activeLivePhotoRequestKey == requestKey else {
            return
        }
        guard !(error is CancellationError) else {
            cancelLivePhotoFetch(
                requestKey: requestKey,
                preserveCloudState: false
            )
            return
        }
        let failure = mediaFetchFailure(for: error)
        displayFetchState.activeLivePhotoRequestKey = nil
        displayFetchState.cancelLivePhotoFetchAction = nil
        displayFetchState.livePhotoMediaFetchPhase = .failed(
            hasDisplayImage,
            reason: failure,
            retryable: failure.isRetryable
        )
    }

    /// Called by the UIKit coordinator after it has cancelled its concrete
    /// PhotoKit/PHLivePhoto request. Stale coordinators cannot clear a newer
    /// request because the full request key must still match.
    func cancelLivePhotoFetch(
        requestKey: MediaFetchRequestKey,
        preserveCloudState: Bool
    ) {
        guard displayFetchState.activeLivePhotoRequestKey == requestKey else {
            return
        }
        cancelLivePhotoFetch(
            preserveCloudState: preserveCloudState,
            invokesCancellationAction: false
        )
    }

    func ensureThumbnailLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int
    ) {
        guard displayFetchState.thumbnailImage == nil,
              displayFetchState.thumbnailTask == nil else {
            return
        }

        let source = entry.source
        displayFetchState.thumbnailTask = Task(priority: .utility) { [weak self] in
            let image = await loader.thumbnail(source: source, pixelLength: pixelLength)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                self.displayFetchState.thumbnailTask = nil
                guard let image else {
                    return
                }
                self.displayFetchState.thumbnailImage = image
                if self.displayFetchState.displayPhoto == nil,
                   case .idle = self.displayFetchState.phase {
                    self.displayFetchState.phase = .thumbnailReady
                }
            }
        }
    }

    func ensureDisplayPhotoLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority
    ) {
        if displayFetchState.displayPhoto != nil || displayFetchState.displayTask != nil {
            if let displayPhoto = displayFetchState.displayPhoto,
               displayPhoto.requestedPixelLength >= Int(Double(pixelLength) * 0.9) {
                return
            }
            if let taskPixelLength = displayFetchState.displayTaskPixelLength,
               taskPixelLength >= Int(Double(pixelLength) * 0.9) {
                return
            }
            displayFetchState.displayTask?.cancel()
            displayFetchState.displayTask = nil
            displayFetchState.displayTaskPixelLength = nil
        }

        let source = entry.source
        let requestKey = newDisplayRequestKey()
        displayFetchState.phase = .displayLoading
        setDisplayMediaFetchPhase(.resolving(hasDisplayImage))
        analysisState.errorMessage = nil
        displayFetchState.displayTaskPixelLength = pixelLength
        displayFetchState.displayTask = Task(priority: priority) { [weak self] in
            do {
                let loadedDisplayPhoto = try await loader.displayPhoto(
                    source: source,
                    pixelLength: pixelLength,
                    requestKey: requestKey
                ) { [weak self] progress in
                    self?.applyDisplayICloudProgress(progress, requestKey: requestKey)
                }
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.displayFetchState.activeDisplayRequestKey == requestKey else {
                        return
                    }
                    self.displayFetchState.displayTask = nil
                    self.displayFetchState.displayTaskPixelLength = nil
                    self.displayFetchState.activeDisplayRequestKey = nil
                    self.displayFetchState.displayPhoto = loadedDisplayPhoto
                    self.displayFetchState.phase = .displayReady
                    self.setDisplayMediaFetchPhase(.ready(true))
                    self.markDisplayPreviewAvailableDuringOriginalFetch()
                    self.clearLoadErrorIfAnalysisIsHealthy()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard let self,
                              self.displayFetchState.activeDisplayRequestKey == requestKey else {
                            return
                        }
                        self.displayFetchState.displayTask = nil
                        self.displayFetchState.displayTaskPixelLength = nil
                        self.displayFetchState.activeDisplayRequestKey = nil
                    }
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.displayFetchState.activeDisplayRequestKey == requestKey else {
                        return
                    }
                    self.displayFetchState.displayTask = nil
                    self.displayFetchState.displayTaskPixelLength = nil
                    self.displayFetchState.activeDisplayRequestKey = nil
                    self.applyDisplayLoadError(error)
                }
            }
        }
    }

    func newDisplayRequestKey() -> MediaFetchRequestKey {
        displayFetchState.activeDisplayRequestKey = nil
        displayFetchState.displayFetchGeneration &+= 1
        let requestKey = MediaFetchRequestKey(
            itemID: entry.mediaID,
            generation: displayFetchState.displayFetchGeneration,
            purpose: .photoDisplay
        )
        displayFetchState.activeDisplayRequestKey = requestKey
        return requestKey
    }

    func applyDisplayICloudProgress(
        _ progress: Double?,
        requestKey: MediaFetchRequestKey
    ) {
        guard displayFetchState.activeDisplayRequestKey == requestKey else {
            return
        }
        setDisplayMediaFetchPhase(.downloadingFromICloud(
            hasDisplayImage,
            progress: progress.map { min(max($0, 0), 1) }
        ))
    }

    func markDisplayPreviewAvailableDuringOriginalFetch() {
        displayFetchState.mediaFetchPhase = phaseWithCurrentPreview(
            displayFetchState.mediaFetchPhase
        )
        analysisState.mediaFetchPhase = phaseWithCurrentPreview(
            analysisState.mediaFetchPhase
        )
    }

    func applyDisplayLoadError(_ error: Error) {
        displayFetchState.phase = .failed
        applyDisplayMediaFetchFailure(error)
        guard analysisState.inputTask == nil, analysisState.input == nil else {
            return
        }
        let presentation = DepthAnalysisErrorPresentation.analysisLoadError(for: error)
        analysisState.errorTitle = presentation.title
        analysisState.errorSystemImage = presentation.systemImage
        analysisState.errorMessage = presentation.message
    }

    func applyDisplayMediaFetchFailure(_ error: Error) {
        if error is CancellationError {
            return
        }
        let failure = mediaFetchFailure(for: error)
        setDisplayMediaFetchPhase(.failed(
            hasDisplayImage,
            reason: failure,
            retryable: failure.isRetryable
        ))
    }

    func cancelLivePhotoFetch(
        preserveCloudState: Bool,
        invokesCancellationAction: Bool
    ) {
        let wasCloudFetch: Bool
        switch displayFetchState.livePhotoMediaFetchPhase {
        case .cloudOnly, .downloadingFromICloud:
            wasCloudFetch = true
        default:
            wasCloudFetch = false
        }
        let cancellationAction = displayFetchState.cancelLivePhotoFetchAction
        displayFetchState.activeLivePhotoRequestKey = nil
        displayFetchState.livePhotoFetchGeneration &+= 1
        displayFetchState.cancelLivePhotoFetchAction = nil
        if !preserveCloudState {
            displayFetchState.retryLivePhotoFetchAction = nil
        }
        if preserveCloudState, wasCloudFetch {
            displayFetchState.livePhotoMediaFetchPhase = .cloudOnly(hasDisplayImage)
        } else if hasDisplayImage {
            displayFetchState.livePhotoMediaFetchPhase = .localPreview(true)
        } else {
            displayFetchState.livePhotoMediaFetchPhase = .idle(false)
        }
        if invokesCancellationAction {
            cancellationAction?()
        }
    }

    func setDisplayMediaFetchPhase(_ phase: MediaFetchPhase<Bool, Bool>) {
        displayFetchState.mediaFetchPhase = phase
    }

    func resolvedMediaFetchPhase() -> MediaFetchPhase<Bool, Bool> {
        let originalPhase = phaseWithCurrentPreview(analysisState.mediaFetchPhase)
        let displayPhase = phaseWithCurrentPreview(displayFetchState.mediaFetchPhase)
        let livePhotoPhase = phaseWithCurrentPreview(
            displayFetchState.livePhotoMediaFetchPhase
        )

        switch originalPhase {
        case .failed, .downloadingFromICloud, .cloudOnly:
            return originalPhase
        case .resolving:
            if case .downloadingFromICloud = livePhotoPhase {
                return livePhotoPhase
            }
            return originalPhase
        case .ready:
            switch livePhotoPhase {
            case .failed, .downloadingFromICloud, .cloudOnly, .resolving:
                return livePhotoPhase
            case .idle, .localPreview, .ready:
                return originalPhase
            }
        case .idle, .localPreview:
            switch livePhotoPhase {
            case .failed, .downloadingFromICloud, .cloudOnly, .resolving:
                return livePhotoPhase
            case .idle, .localPreview, .ready:
                return displayPhase
            }
        }
    }

    func phaseWithCurrentPreview(
        _ phase: MediaFetchPhase<Bool, Bool>
    ) -> MediaFetchPhase<Bool, Bool> {
        switch phase {
        case .idle:
            return .idle(hasDisplayImage)
        case .resolving:
            return .resolving(hasDisplayImage)
        case .localPreview:
            return hasDisplayImage ? .localPreview(true) : .idle(false)
        case .cloudOnly:
            return .cloudOnly(hasDisplayImage)
        case .downloadingFromICloud(_, let progress):
            return .downloadingFromICloud(hasDisplayImage, progress: progress)
        case .ready(let value):
            return .ready(value)
        case .failed(_, let reason, let retryable):
            return .failed(
                hasDisplayImage,
                reason: reason,
                retryable: retryable
            )
        }
    }

    func mediaFetchFailure(for error: Error) -> MediaFetchFailure {
        (error as? MediaFetchFailure) ?? .decode
    }
}
