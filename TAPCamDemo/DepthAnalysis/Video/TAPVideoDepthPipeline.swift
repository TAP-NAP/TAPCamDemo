//
//  TAPVideoDepthPipeline.swift
//  TAPCamDemo
//

import AVFoundation
import OSLog

nonisolated enum TAPVideoDepthPipelineDecodeFailureReason: String, Sendable {
    case metadataRead
    case decode
    case backpressure
}

nonisolated struct TAPVideoDepthPipelineEvent {
    nonisolated enum Payload {
        case frame(TAPDecodedDepthVideoFrame)
        case noSample(playbackTimeSeconds: Double)
        case decodeFailed(
            reason: TAPVideoDepthPipelineDecodeFailureReason,
            presentationTimeSeconds: Double
        )
    }

    let generation: UInt64
    let payload: Payload
}

@MainActor
final class TAPVideoDepthPipeline {
    struct PresentationState: Equatable {
        let isReady: Bool
    }

    let overlayStore = TAPVideoDepthOverlayStore()
    var onPresentationStateChange: ((PresentationState) -> Void)?

    private let frameCache = TAPVideoDepthFrameCache()
    private var metadataOutput: TAPVideoDepthMetadataOutput?
    private var resolvedFileURL: URL?
    private var registrationDescriptor: TAPVideoDepthRegistrationDescriptor?
    private var currentPlaybackTimeSeconds: Double = 0
    private var currentFrameTimeSeconds: Double?
    private var staleToleranceSeconds = TAPVideoDepthPlaybackBudget
        .failSafeFrameStaleToleranceSeconds
    private var isHoldingLastFrameAcrossGap = false
    private var generation: UInt64 = 0
    private var readinessTrace: OSSignpostIntervalState?
    private(set) var isPresentationRequested = false
    private(set) var isPreparing = false

    var isConfigured: Bool {
        metadataOutput != nil && resolvedFileURL != nil
    }

    var isReady: Bool {
        isPresentationRequested && !isPreparing && currentFrameTimeSeconds != nil
    }

    func configure(
        fileURL: URL,
        displayOrientation: CGImagePropertyOrientation,
        depthFormat: TAPVideoManifest.DepthFormat,
        depthTrackID: CMPersistentTrackID?,
        registrationDescriptor: TAPVideoDepthRegistrationDescriptor,
        staleToleranceSeconds: TimeInterval
    ) {
        releaseConfiguration()
        self.resolvedFileURL = fileURL
        self.registrationDescriptor = registrationDescriptor
        self.staleToleranceSeconds = staleToleranceSeconds
        metadataOutput = TAPVideoDepthMetadataOutput(
            displayOrientation: displayOrientation,
            depthFormat: depthFormat,
            depthTrackID: depthTrackID
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    func beginNewGeneration() {
        if let metadataOutput {
            generation = metadataOutput.beginNewGeneration()
        } else {
            generation &+= 1
        }
    }

    @discardableResult
    func beginPresentation(on item: AVPlayerItem) -> Bool {
        guard let metadataOutput,
              resolvedFileURL != nil else {
            setPresentationRequested(false)
            setPreparing(false)
            return false
        }
        setPresentationRequested(true)
        beginReadiness(outcomeForPreviousAttempt: "restarted")
        metadataOutput.attach(to: item)
        generation = metadataOutput.beginNewGeneration()
        return true
    }

    func rejectPresentationRequest() {
        isPresentationRequested = false
        setPreparing(false)
    }

    func resolvePresentation(at playbackTimeSeconds: Double) {
        currentPlaybackTimeSeconds = playbackTimeSeconds
        updateFrame(for: playbackTimeSeconds)
        if isPreparing {
            requestProbe(playbackTimeSeconds: playbackTimeSeconds)
        }
    }

    func cancelPresentation() {
        finishReadiness(outcome: "cancelled")
        isPresentationRequested = false
        isPreparing = false
        if let metadataOutput {
            generation = metadataOutput.beginNewGeneration()
            metadataOutput.detach()
        } else {
            generation &+= 1
        }
        frameCache.clear()
        currentFrameTimeSeconds = nil
        isHoldingLastFrameAcrossGap = false
        overlayStore.clear()
        publishPresentationState()
    }

    func handleMemoryWarning(
        playbackTimeSeconds: Double,
        canRestartPresentation: Bool
    ) {
        currentPlaybackTimeSeconds = playbackTimeSeconds
        finishReadiness(outcome: "memory-warning")
        resetFrameSelection(beginNewGeneration: true)
        guard isPresentationRequested,
              canRestartPresentation,
              isConfigured else {
            setPreparing(false)
            return
        }
        beginReadiness(outcomeForPreviousAttempt: "memory-warning")
        requestProbe(playbackTimeSeconds: playbackTimeSeconds)
    }

    func handleDiscontinuity(
        playbackTimeSeconds: Double,
        canRestartPresentation: Bool
    ) {
        currentPlaybackTimeSeconds = playbackTimeSeconds
        resetFrameSelection(beginNewGeneration: true)
        guard isPresentationRequested,
              canRestartPresentation else {
            return
        }
        beginReadiness(outcomeForPreviousAttempt: "discontinuity")
        requestProbe(playbackTimeSeconds: playbackTimeSeconds)
    }

    func updatePlaybackTime(_ playbackTimeSeconds: Double) {
        currentPlaybackTimeSeconds = playbackTimeSeconds
        updateFrame(for: playbackTimeSeconds)
    }

    func releaseConfiguration() {
        if let metadataOutput {
            generation = metadataOutput.beginNewGeneration()
        } else {
            generation &+= 1
        }
        metadataOutput?.detach()
        metadataOutput = nil
        resolvedFileURL = nil
        registrationDescriptor = nil
        frameCache.clear()
        overlayStore.clear()
        currentPlaybackTimeSeconds = 0
        currentFrameTimeSeconds = nil
        isHoldingLastFrameAcrossGap = false
        staleToleranceSeconds = TAPVideoDepthPlaybackBudget
            .failSafeFrameStaleToleranceSeconds
        publishPresentationState()
    }

    private func requestProbe(playbackTimeSeconds: Double) {
        guard isPresentationRequested,
              isPreparing,
              let metadataOutput,
              let resolvedFileURL else {
            return
        }
        metadataOutput.probe(
            fileURL: resolvedFileURL,
            playbackTimeSeconds: max(0, playbackTimeSeconds),
            staleToleranceSeconds: staleToleranceSeconds,
            leadToleranceSeconds: TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds
        )
    }

    private func handle(_ event: TAPVideoDepthPipelineEvent) {
        guard isPresentationRequested,
              TAPVideoDepthPipelineGenerationPolicy.accepts(
                eventGeneration: event.generation,
                currentGeneration: generation
              ) else {
            return
        }
        switch event.payload {
        case .frame(let frame):
            store(frame)
        case .noSample:
            finishUnavailable(outcome: "no-sample")
        case .decodeFailed(let reason, _):
            finishUnavailable(outcome: "decode-failed-\(reason.rawValue)")
        }
    }

    private func finishUnavailable(outcome: String) {
        holdOrClearDisplayedFrameAcrossGap()
        guard isPresentationRequested else {
            return
        }
        isPreparing = false
        publishPresentationState()
        finishReadiness(outcome: outcome)
    }

    private func store(_ frame: TAPDecodedDepthVideoFrame) {
        guard isPresentationRequested,
              frameCache.insert(frame, around: currentPlaybackTimeSeconds) else {
            return
        }
        updateFrame(for: currentPlaybackTimeSeconds)
    }

    private func updateFrame(for playbackTimeSeconds: Double) {
        guard isPresentationRequested,
              playbackTimeSeconds.isFinite else {
            return
        }
        frameCache.prune(around: playbackTimeSeconds)
        guard let frame = frameCache.nearestFrame(
            to: playbackTimeSeconds,
            staleToleranceSeconds: staleToleranceSeconds
        ) else {
            handleMissingFrame()
            return
        }
        isHoldingLastFrameAcrossGap = false
        isPreparing = false
        guard currentFrameTimeSeconds != frame.presentationTimeSeconds else {
            publishPresentationState()
            finishReadiness(outcome: "frame")
            return
        }
        currentFrameTimeSeconds = frame.presentationTimeSeconds
        guard let registrationDescriptor else {
            overlayStore.clear()
            publishPresentationState()
            return
        }
        overlayStore.present(
            frame.image,
            registrationDescriptor: registrationDescriptor
        )
        publishPresentationState()
        finishReadiness(outcome: "frame")
    }

    private func handleMissingFrame() {
        holdOrClearDisplayedFrameAcrossGap()
        publishPresentationState()
    }

    private func beginReadiness(outcomeForPreviousAttempt: String) {
        finishReadiness(outcome: outcomeForPreviousAttempt)
        readinessTrace = TAPVideoPerformanceTrace.beginTwoDReadiness()
        setPreparing(true)
    }

    private func finishReadiness(outcome: String) {
        guard let readinessTrace else {
            return
        }
        self.readinessTrace = nil
        TAPVideoPerformanceTrace.endTwoDReadiness(
            readinessTrace,
            outcome: outcome
        )
    }

    private func resetFrameSelection(beginNewGeneration: Bool) {
        currentFrameTimeSeconds = nil
        isHoldingLastFrameAcrossGap = false
        frameCache.clear()
        overlayStore.clear()
        if beginNewGeneration {
            self.beginNewGeneration()
        }
    }

    private func holdOrClearDisplayedFrameAcrossGap() {
        let shouldHold = TAPVideoDepthFrameHoldPolicy.shouldHoldLastFrame(
            hasDisplayedFrame: currentFrameTimeSeconds != nil,
            context: .continuousPlaybackGap
        )
        guard shouldHold else {
            currentFrameTimeSeconds = nil
            isHoldingLastFrameAcrossGap = false
            overlayStore.clear()
            return
        }
        guard !isHoldingLastFrameAcrossGap else {
            return
        }
        isHoldingLastFrameAcrossGap = true
    }

    private func setPresentationRequested(_ value: Bool) {
        isPresentationRequested = value
        publishPresentationState()
    }

    private func setPreparing(_ value: Bool) {
        isPreparing = value
        publishPresentationState()
    }

    private func publishPresentationState() {
        onPresentationStateChange?(PresentationState(
            isReady: isReady
        ))
    }
}
