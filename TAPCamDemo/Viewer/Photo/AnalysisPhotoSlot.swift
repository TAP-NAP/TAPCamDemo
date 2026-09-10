//
//  AnalysisPhotoSlot.swift
//  TAPCamDemo
//

import Combine
import CoreGraphics
import Foundation
import UIKit

nonisolated struct AnalysisPhotoSlotRetainedState {
    var planeSelection: DepthAnalysisPlaneSelectionState
}

@MainActor
struct AnalysisPhotoDisplayFetchState {
    var phase: AnalysisPhotoDisplayPhase = .idle
    var thumbnailImage: UIImage?
    var displayPhoto: AnalysisDisplayPhoto?

    var thumbnailTask: Task<Void, Never>?
    var displayTask: Task<Void, Never>?
    var displayTaskPixelLength: Int?

    var displayFetchGeneration: UInt64 = 0
    var activeDisplayRequestKey: MediaFetchRequestKey?
    var mediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)

    var livePhotoFetchGeneration: UInt64 = 0
    var activeLivePhotoRequestKey: MediaFetchRequestKey?
    var livePhotoMediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)
    var cancelLivePhotoFetchAction: (() -> Void)?
    var retryLivePhotoFetchAction: (() -> Void)?

    var lastLoader: DepthAnalysisProgressivePhotoLoader?
    var lastPixelLength = 960
    var lastPriority: TaskPriority = .userInitiated
    var lastRequestedAnalysis = false
    var lastRequestedPlaneGeometryPrewarm = false
}

@MainActor
struct AnalysisPhotoAnalysisState {
    var phase: AnalysisPhotoAnalysisPhase = .idle
    var input: TAPDepthAnalysisInput?
    var completedInputRequestKey: MediaFetchRequestKey?
    var inputTask: Task<Void, Never>?

    var originalFetchGeneration: UInt64 = 0
    var activeOriginalRequestKey: MediaFetchRequestKey?
    var mediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)
    var lastOriginalProgress: Double?

    var errorMessage: String?
    var errorTitle = "Unable to analyze image"
    var errorSystemImage = "exclamationmark.triangle"
}

@MainActor
struct AnalysisPhotoSelectionState {
    let planeRequestCoordinator: DepthAnalysisPlaneRegionRequestCoordinator
    var planeSelection = DepthAnalysisPlaneSelectionState()
    var wantsPlaneGeometryPrewarm = false
    var hasRequestedPlaneGeometryPrewarm = false

    init(
        planeRegionDetector: DepthAnalysisPlaneRegionDetector,
        retainedPlaneSelection: DepthAnalysisPlaneSelectionState?
    ) {
        self.planeRequestCoordinator = DepthAnalysisPlaneRegionRequestCoordinator(
            detector: planeRegionDetector
        )
        if var retainedPlaneSelection {
            retainedPlaneSelection.cancelDetection()
            self.planeSelection = retainedPlaneSelection
        }
    }
}

/// Stable carousel-item identity that coordinates three focused state surfaces.
///
/// Display/resource fetching, full-resolution analysis, and user selection keep
/// independent storage and behavior while views continue to observe one slot.
@MainActor
final class AnalysisPhotoSlot: ObservableObject, Identifiable {
    let entry: DepthAnalysisCarouselEntry

    @Published var displayFetchState = AnalysisPhotoDisplayFetchState()
    @Published var analysisState = AnalysisPhotoAnalysisState()
    @Published var selectionState: AnalysisPhotoSelectionState
    let originalResourceOwner = TAPPhotoOriginalResourceOwner()
    var pendingSignedOriginalRefreshID: UUID?

    var id: String { entry.id }
    var source: DepthAnalysisSource { entry.source }

    var displayPhase: AnalysisPhotoDisplayPhase { displayFetchState.phase }
    var analysisPhase: AnalysisPhotoAnalysisPhase { analysisState.phase }
    var thumbnailImage: UIImage? { displayFetchState.thumbnailImage }
    var displayPhoto: AnalysisDisplayPhoto? { displayFetchState.displayPhoto }
    var input: TAPDepthAnalysisInput? { analysisState.input }
    var mediaFetchPhase: MediaFetchPhase<Bool, Bool> { resolvedMediaFetchPhase() }
    var errorMessage: String? { analysisState.errorMessage }
    var errorTitle: String { analysisState.errorTitle }
    var errorSystemImage: String { analysisState.errorSystemImage }

    var planeSelection: DepthAnalysisPlaneSelectionState {
        get { selectionState.planeSelection }
        set { selectionState.planeSelection = newValue }
    }

    var phase: AnalysisSlotLoadPhase {
        if case .failed = analysisPhase {
            return .failed
        }
        if case .ready = analysisPhase {
            return .analysisReady
        }
        if case .failed = displayPhase {
            return .failed
        }
        if case .loading(let progress) = analysisPhase {
            return .originalLoading(progress: progress)
        }
        switch displayPhase {
        case .idle:
            return .idle
        case .thumbnailReady:
            return .thumbnailReady
        case .displayLoading:
            return .originalLoading(progress: nil)
        case .displayReady:
            return .thumbnailReady
        case .failed:
            return .failed
        }
    }

    var isOriginalLoading: Bool {
        analysisPhase.isLoading || displayPhase == .displayLoading
    }

    var loadProgress: Double? {
        if case .loading(let progress) = analysisPhase {
            return progress
        }
        return nil
    }

    var hasDisplayImage: Bool {
        displayPhoto != nil || input != nil || thumbnailImage != nil
    }

    init(
        entry: DepthAnalysisCarouselEntry,
        retainedState: AnalysisPhotoSlotRetainedState? = nil,
        planeRegionDetector: DepthAnalysisPlaneRegionDetector = DepthAnalysisPlaneRegionDetector()
    ) {
        self.entry = entry
        self.selectionState = AnalysisPhotoSelectionState(
            planeRegionDetector: planeRegionDetector,
            retainedPlaneSelection: retainedState?.planeSelection
        )
    }

    func ensureLoading(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority,
        prewarmPlaneGeometry: Bool = false
    ) {
        ensureDisplayPhoto(loader: loader, pixelLength: pixelLength, priority: priority)
        displayFetchState.lastRequestedAnalysis = true
        displayFetchState.lastRequestedPlaneGeometryPrewarm = prewarmPlaneGeometry
        ensureInputLoading(
            loader: loader,
            priority: priority,
            prewarmPlaneGeometry: prewarmPlaneGeometry
        )
    }

    func ensureThumbnail(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int
    ) {
        ensureThumbnailLoading(loader: loader, pixelLength: pixelLength)
    }

    func ensureDisplayPhoto(
        loader: DepthAnalysisProgressivePhotoLoader,
        pixelLength: Int,
        priority: TaskPriority
    ) {
        displayFetchState.lastLoader = loader
        displayFetchState.lastPixelLength = pixelLength
        displayFetchState.lastPriority = priority
        displayFetchState.lastRequestedAnalysis = false
        displayFetchState.lastRequestedPlaneGeometryPrewarm = false
        ensureThumbnail(loader: loader, pixelLength: pixelLength)
        ensureDisplayPhotoLoading(loader: loader, pixelLength: pixelLength, priority: priority)
    }

    func cancelCurrentMediaFetch() {
        cancelLivePhotoFetch(preserveCloudState: true, invokesCancellationAction: true)
        cancelOriginalTasks(preserveCloudState: true)
    }

    func retryLastMediaFetch() {
        let livePhotoRetryAction = displayFetchState.retryLivePhotoFetchAction
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        cancelOriginalTasks(preserveCloudState: false)
        if let lastLoader = displayFetchState.lastLoader {
            if displayFetchState.lastRequestedAnalysis {
                ensureLoading(
                    loader: lastLoader,
                    pixelLength: displayFetchState.lastPixelLength,
                    priority: displayFetchState.lastPriority,
                    prewarmPlaneGeometry: displayFetchState.lastRequestedPlaneGeometryPrewarm
                )
            } else {
                ensureDisplayPhoto(
                    loader: lastLoader,
                    pixelLength: displayFetchState.lastPixelLength,
                    priority: displayFetchState.lastPriority
                )
            }
        }
        livePhotoRetryAction?()
    }

    /// A pending capture may have completed signing while this Viewer kept an
    /// earlier unsigned snapshot alive. Refresh only that app-private source;
    /// Photos/iCloud originals are immutable for this presentation and do not
    /// need a queue-driven reload.
    func reloadPendingOriginalAfterLibraryChange(
        _ change: TAPLibraryPendingCaptureChange?
    ) async {
        guard case .pendingCapture(let captureID) = source,
              change?.captureID == captureID,
              pendingSignedOriginalRefreshID == nil,
              let lastLoader = displayFetchState.lastLoader else {
            return
        }
        // Claim the transition before the actor hop below. Burst queue
        // notifications otherwise pass the same guard and repeatedly restart
        // the original request after each suspended record read resumes.
        let refreshID = UUID()
        pendingSignedOriginalRefreshID = refreshID
        if let lease = originalResourceOwner.acquireLease(),
           case .pendingCapture(_, let selectedSignedPhoto) = lease.origin,
           selectedSignedPhoto {
            if pendingSignedOriginalRefreshID == refreshID {
                pendingSignedOriginalRefreshID = nil
            }
            return
        }
        guard let record = try? await TAPPendingCaptureStore.shared
            .readRecord(captureID: captureID),
              record.signedPhotoFilename != nil else {
            if pendingSignedOriginalRefreshID == refreshID {
                pendingSignedOriginalRefreshID = nil
            }
            return
        }
        guard case .pendingCapture(let currentCaptureID) = source,
              currentCaptureID == captureID,
              pendingSignedOriginalRefreshID == refreshID else {
            return
        }
        cancelOriginalTasks(preserveCloudState: false)
        pendingSignedOriginalRefreshID = refreshID
        originalResourceOwner.clear()
        analysisState.input = nil
        analysisState.completedInputRequestKey = nil
        analysisState.phase = .idle
        ensureInputLoading(
            loader: lastLoader,
            priority: displayFetchState.lastPriority,
            prewarmPlaneGeometry: displayFetchState.lastRequestedPlaneGeometryPrewarm
        )
    }

    func prepareForAdjacentPreview() {
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)
        cancelOriginalTasks(preserveCloudState: true)
        analysisState.input = nil
        analysisState.completedInputRequestKey = nil
        originalResourceOwner.clear()
        analysisState.phase = .idle
        selectionState.planeRequestCoordinator.cancelRegionRequest()
        selectionState.planeRequestCoordinator.resetForNewInput()
        selectionState.hasRequestedPlaneGeometryPrewarm = false
    }

    func retainedStateForEviction() -> AnalysisPhotoSlotRetainedState {
        var retainedPlaneSelection = selectionState.planeSelection
        retainedPlaneSelection.cancelDetection()
        return AnalysisPhotoSlotRetainedState(planeSelection: retainedPlaneSelection)
    }

    func prepareForEviction() {
        cancelLivePhotoFetch(preserveCloudState: false, invokesCancellationAction: true)

        displayFetchState.thumbnailTask?.cancel()
        displayFetchState.thumbnailTask = nil
        displayFetchState.displayTask?.cancel()
        displayFetchState.displayTask = nil
        displayFetchState.displayTaskPixelLength = nil
        analysisState.inputTask?.cancel()
        analysisState.inputTask = nil

        selectionState.planeRequestCoordinator.cancelRegionRequest()
        selectionState.planeRequestCoordinator.resetForNewInput()
        displayFetchState.thumbnailImage = nil
        displayFetchState.displayPhoto = nil
        analysisState.input = nil
        analysisState.completedInputRequestKey = nil
        originalResourceOwner.clear()
        displayFetchState.phase = .idle
        analysisState.phase = .idle

        displayFetchState.activeDisplayRequestKey = nil
        displayFetchState.displayFetchGeneration &+= 1
        displayFetchState.mediaFetchPhase = .idle(false)
        analysisState.activeOriginalRequestKey = nil
        analysisState.originalFetchGeneration &+= 1
        analysisState.mediaFetchPhase = .idle(false)
        analysisState.lastOriginalProgress = nil
        displayFetchState.livePhotoMediaFetchPhase = .idle(false)

        analysisState.errorMessage = nil
        selectionState.wantsPlaneGeometryPrewarm = false
        selectionState.hasRequestedPlaneGeometryPrewarm = false
        selectionState.planeSelection.cancelDetection()
    }
}
