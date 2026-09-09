//
//  TAPVideoPlaybackSession.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Observation
import OSLog
import UIKit

nonisolated enum TAPVideoPlaybackLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
enum TAPVideoPlaybackBackgroundPolicy {
    static func enforceForegroundOnly(on player: AVPlayer) {
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        player.allowsExternalPlayback = false
    }
}

@MainActor
@Observable
final class TAPVideoPlaybackSession {
    static let preferredTwoDBufferDurationSeconds: TimeInterval = 3

    private(set) var state: TAPVideoPlaybackLoadState = .idle
    private(set) var loadingPreviewImage: UIImage?
    private(set) var player: AVPlayer?
    private(set) var registeredDepthAvailability: TAPVideoRegisteredDepthAvailability = .checking
    private(set) var isTwoDPlaybackReady = false
    private(set) var depthGapNotice: String?
    private(set) var requestKey: MediaFetchRequestKey?
    private(set) var isOriginalResourceReady = false
    private(set) var pendingSignedOriginalRefreshID: UUID?
    var isPendingSignedOriginalRefreshInFlight: Bool {
        pendingSignedOriginalRefreshID != nil
    }
    private var fetchState = TAPVideoPlaybackFetchState()
    @ObservationIgnored let playbackIntentState = TAPVideoPlaybackIntentState()

    @ObservationIgnored private let source: TAPVideoPlaybackSource
    @ObservationIgnored private let registrationAdapter: any TAPVideoDepthRegistrationAdapting
    @ObservationIgnored private let mediaFetcher: any LibraryMediaFetching
    @ObservationIgnored private let depthPipeline: TAPVideoDepthPipeline
    @ObservationIgnored private var activeRequestKey: MediaFetchRequestKey?
    @ObservationIgnored private var resource: TAPVideoPlaybackResolvedResource?
    @ObservationIgnored private var playerLifecycle: TAPVideoPlaybackPlayerLifecycle?
    @ObservationIgnored private var requestGeneration: UInt64 = 1
    @ObservationIgnored private var shouldResumeFetchAfterBackground = false
    @ObservationIgnored private var shouldResumeAfterInteractivePaging = false

    init(
        source: TAPVideoPlaybackSource,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting,
        mediaFetcher: any LibraryMediaFetching,
        initialLoadingPreviewImage: UIImage? = nil
    ) {
        self.source = source
        self.registrationAdapter = registrationAdapter
        self.mediaFetcher = mediaFetcher
        loadingPreviewImage = initialLoadingPreviewImage
        depthPipeline = TAPVideoDepthPipeline(sourceLabel: source.diagnosticsLabel)
        requestKey = MediaFetchRequestKey(
            itemID: source.libraryMediaID,
            generation: requestGeneration,
            purpose: .videoOriginal
        )
        depthPipeline.onPresentationStateChange = { [weak self] state in
            self?.isTwoDPlaybackReady = state.isReady
            self?.depthGapNotice = state.gapNotice
        }
    }

    var mediaFetchPhase: MediaFetchPhase<Bool, Bool> {
        fetchState.phase
    }

    var isRegisteredDepthAvailable: Bool {
        registeredDepthAvailability.isAvailable
    }

    var hasActiveMediaFetch: Bool {
        state == .loading
    }

    var overlayStore: TAPVideoDepthOverlayStore {
        depthPipeline.overlayStore
    }

    func startPlaybackSession() async {
        guard let requestKey else {
            return
        }
        activeRequestKey = requestKey
        async let previewLoad: Void = loadPreviewIfAvailable(requestKey: requestKey)
        await loadIfNeeded(requestKey: requestKey)
        guard !Task.isCancelled,
              activeRequestKey == requestKey,
              state == .ready,
              let player else {
            _ = await previewLoad
            return
        }
        let lifecycle = TAPVideoPlaybackPlayerLifecycle(
            player: player,
            source: source,
            depthPipeline: depthPipeline
        ) { [weak self] in
            self?.state == .ready && self?.isRegisteredDepthAvailable == true
        }
        playerLifecycle = lifecycle
        lifecycle.start()
        _ = await previewLoad
    }

    func stopPlayback() {
        shouldResumeFetchAfterBackground = false
        shouldResumeAfterInteractivePaging = false
        playbackIntentState.reset()
        requestKey = nil
        activeRequestKey = nil
        pendingSignedOriginalRefreshID = nil
        releasePlaybackResources()
        registeredDepthAvailability = .checking
        state = .idle
        fetchState.reset(
            hasPreview: hasLoadingPreview,
            preservingCloudOnly: true
        )
    }

    /// Freezes the committed video's frame while the Library pager is under
    /// the user's finger. A cancelled page turn can resume the prior playback
    /// intent; a committed turn calls `stopPlayback()` first and therefore
    /// cannot resurrect the outgoing player.
    func beginInteractivePaging() {
        guard let player else {
            shouldResumeAfterInteractivePaging = false
            playbackIntentState.reset()
            return
        }
        shouldResumeAfterInteractivePaging = playbackIntentState
            .beginPagingSuspension(currentStatus: player.timeControlStatus)
        player.currentItem?.cancelPendingSeeks()
        player.cancelPendingPrerolls()
        player.pause()
    }

    func endInteractivePaging() {
        let shouldResume = shouldResumeAfterInteractivePaging
        shouldResumeAfterInteractivePaging = false
        playbackIntentState.endPagingSuspension()
        guard shouldResume,
              state == .ready,
              requestKey != nil,
              let player else {
            return
        }
        player.play()
    }

    func handleDidEnterBackground() {
        shouldResumeAfterInteractivePaging = false
        playbackIntentState.reset()
        player?.pause()
        guard hasActiveMediaFetch else {
            return
        }
        shouldResumeFetchAfterBackground = true
        cancelCurrentFetch()
    }

    func resumeCanceledFetchAfterBackground() {
        guard shouldResumeFetchAfterBackground, requestKey == nil else {
            return
        }
        shouldResumeFetchAfterBackground = false
        retryCurrentFetch()
    }

    func retryCurrentFetch() {
        shouldResumeFetchAfterBackground = false
        pendingSignedOriginalRefreshID = nil
        activeRequestKey = nil
        if isOriginalResourceReady {
            releasePlayerResources()
        } else {
            releasePlaybackResources()
        }
        state = .idle
        if isOriginalResourceReady {
            fetchState.finish()
        } else {
            fetchState.reset(hasPreview: hasLoadingPreview)
        }
        requestGeneration &+= 1
        requestKey = MediaFetchRequestKey(
            itemID: source.libraryMediaID,
            generation: requestGeneration,
            purpose: .videoOriginal
        )
    }

    /// Claims at most one unsigned-to-signed pending-resource upgrade. Queue
    /// status/export notifications may repeat while the streamed snapshot is
    /// being classified; they must not race through the record lookup and
    /// repeatedly restart the same copy.
    func claimPendingSignedOriginalRefresh() -> UUID? {
        guard pendingSignedOriginalRefreshID == nil,
              currentOriginalSelectedSignedVideo != true else {
            return nil
        }
        let refreshID = UUID()
        pendingSignedOriginalRefreshID = refreshID
        return refreshID
    }

    /// Completes a transition claim that did not reach resource loading (for
    /// example, because the queue record lookup failed). A later precise
    /// notification may then retry the upgrade.
    func cancelPendingSignedOriginalRefreshClaim(_ refreshID: UUID) {
        guard pendingSignedOriginalRefreshID == refreshID else {
            return
        }
        pendingSignedOriginalRefreshID = nil
    }

    /// Starts the one claimed resource replacement only after the queue actor
    /// confirms that signed bytes actually exist.
    @discardableResult
    func startClaimedPendingSignedOriginalRefresh(_ refreshID: UUID) -> Bool {
        guard pendingSignedOriginalRefreshID == refreshID else {
            return false
        }
        shouldResumeFetchAfterBackground = false
        activeRequestKey = nil
        releasePlaybackResources()
        state = .idle
        fetchState.reset(hasPreview: hasLoadingPreview)
        requestGeneration &+= 1
        requestKey = MediaFetchRequestKey(
            itemID: source.libraryMediaID,
            generation: requestGeneration,
            purpose: .videoOriginal
        )
        return true
    }

    func handleMemoryWarning() {
        depthPipeline.handleMemoryWarning(
            playbackTimeSeconds: playerLifecycle?.currentTimeSeconds ?? 0,
            canRestartPresentation: state == .ready && isRegisteredDepthAvailable
        )
    }

    /// Acquires a short-lived capability for the already-loaded original.
    /// Playback first-frame readiness is intentionally unrelated: Share may
    /// use the complete bytes as soon as the resource load commits, even while
    /// AVPlayerLayer is still warming its first visible frame.
    func acquireOriginalResourceLease() throws -> TAPVideoOriginalResourceLease {
        guard let resource else {
            throw MediaFetchFailure.download
        }
        return resource.acquireLease()
    }

    var currentOriginalSelectedSignedVideo: Bool? {
        resource?.acquireLease().selectedSignedVideo
    }

    func prepareTwoDPlaybackGate() {
        guard state == .ready,
              isRegisteredDepthAvailable,
              let item = player?.currentItem else {
            depthPipeline.rejectPresentationRequest()
            return
        }
        guard depthPipeline.beginPresentation(on: item) else {
            return
        }
        player?.currentItem?.preferredForwardBufferDuration =
            Self.preferredTwoDBufferDurationSeconds
        playerLifecycle?.prerollIfReady()
        depthPipeline.resolvePresentation(
            at: playerLifecycle?.currentTimeSeconds ?? 0
        )
    }

    func cancelTwoDPlaybackGate() {
        depthPipeline.cancelPresentation()
    }

    private func cancelCurrentFetch() {
        requestKey = nil
        activeRequestKey = nil
        if isOriginalResourceReady {
            releasePlayerResources()
        } else {
            releasePlaybackResources()
        }
        state = .idle
        if isOriginalResourceReady {
            fetchState.finish()
        } else {
            fetchState.cancel(hasPreview: hasLoadingPreview)
        }
    }

    private func loadPreviewIfAvailable(requestKey: MediaFetchRequestKey) async {
        guard loadingPreviewImage == nil else {
            fetchState.publishPreviewAvailability(true)
            return
        }
        let image = await TAPVideoPlaybackResourceLoader.loadingPreviewImage(
            source: source,
            originalRequestKey: requestKey,
            mediaFetcher: mediaFetcher
        )
        guard !Task.isCancelled,
              activeRequestKey == requestKey,
              let image else {
            return
        }
        loadingPreviewImage = image
        fetchState.publishPreviewAvailability(true)
    }

    private func loadIfNeeded(requestKey: MediaFetchRequestKey) async {
        guard state == .idle else {
            return
        }
        let trace = TAPVideoPerformanceTrace.beginPlayerOpen(
            source: source.diagnosticsLabel
        )
        var didOpenPlayer = false
        defer {
            TAPVideoPerformanceTrace.endPlayerOpen(trace, succeeded: didOpenPlayer)
        }
        state = .loading
        fetchState.begin(hasPreview: hasLoadingPreview)

        let loadedResource: TAPVideoPlaybackResolvedResource
        do {
            if let resource, isOriginalResourceReady {
                loadedResource = resource
            } else {
                loadedResource = try await resolveResource(requestKey: requestKey)
                publishResolvedOriginal(loadedResource, requestKey: requestKey)
            }
        } catch is CancellationError {
            handleCancelledResourceLoad(requestKey: requestKey)
            return
        } catch {
            handleFailedResourceLoad(error, requestKey: requestKey)
            return
        }

        do {
            let loadedPlayer = try await preparePlayer(
                for: loadedResource,
                requestKey: requestKey
            )
            commitLoadedResource(loadedResource, player: loadedPlayer)
            didOpenPlayer = true
        } catch is CancellationError {
            handleCancelledPlayerPreparation(requestKey: requestKey)
        } catch {
            handleFailedPlayerPreparation(error, requestKey: requestKey)
        }
    }

    private func resolveResource(
        requestKey: MediaFetchRequestKey
    ) async throws -> TAPVideoPlaybackResolvedResource {
        let progressCoalescer = TAPVideoPlaybackProgressCoalescer { [weak self] progress in
            self?.publishOriginalLoadProgress(
                progress,
                requestKey: requestKey
            )
        }
        do {
            let resource = try await TAPVideoPlaybackResourceLoader.resolve(
                source: source,
                requestKey: requestKey,
                mediaFetcher: mediaFetcher,
                progress: progressCoalescer.submit
            )
            await progressCoalescer.finish()
            try ensureCurrent(requestKey)
            return resource
        } catch {
            progressCoalescer.cancel()
            throw error
        }
    }

    private func publishOriginalLoadProgress(
        _ progress: Double?,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeRequestKey == requestKey,
              !isOriginalResourceReady else {
            return
        }
        fetchState.publishProgress(
            progress,
            hasPreview: hasLoadingPreview
        )
    }

    private func preparePlayer(
        for resource: TAPVideoPlaybackResolvedResource,
        requestKey: MediaFetchRequestKey
    ) async throws -> AVPlayer {
        try ensureCurrent(requestKey)
        let presentation = await TAPVideoDepthMetadataReader.presentation(
            for: resource.fileURL,
            registrationAdapter: registrationAdapter
        )
        try ensureCurrent(requestKey)
        configureDepthPipeline(
            presentation: presentation,
            fileURL: resource.fileURL
        )
        let player = AVPlayer(playerItem: AVPlayerItem(url: resource.fileURL))
        TAPVideoPlaybackBackgroundPolicy.enforceForegroundOnly(on: player)
        return player
    }

    private func commitLoadedResource(
        _ loadedResource: TAPVideoPlaybackResolvedResource,
        player loadedPlayer: AVPlayer
    ) {
        resource = loadedResource
        isOriginalResourceReady = true
        player = loadedPlayer
        state = .ready
        fetchState.finish()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.depthAnalysis.info("tap_video_playback_loaded source=\(self.source.diagnosticsLabel, privacy: .public) autoPlay=false")
        #endif
    }

    /// Publishes complete-original readiness as soon as the streamed resource
    /// commits. Depth metadata parsing, AVPlayer construction, and first-frame
    /// display continue independently and must not gate Share.
    private func publishResolvedOriginal(
        _ loadedResource: TAPVideoPlaybackResolvedResource,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeRequestKey == requestKey else {
            return
        }
        resource = loadedResource
        isOriginalResourceReady = true
        if loadedResource.acquireLease().selectedSignedVideo == true {
            pendingSignedOriginalRefreshID = nil
        }
        fetchState.finish()
    }

    private func handleCancelledResourceLoad(requestKey: MediaFetchRequestKey) {
        guard activeRequestKey == requestKey else {
            return
        }
        releasePlaybackResources()
        pendingSignedOriginalRefreshID = nil
        state = .idle
        fetchState.cancelLoadAfterTaskCancellation(hasPreview: hasLoadingPreview)
    }

    private func handleFailedResourceLoad(
        _ error: any Error,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeRequestKey == requestKey else {
            return
        }
        releasePlaybackResources()
        pendingSignedOriginalRefreshID = nil
        state = .failed(
            DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
        )
        fetchState.fail(
            (error as? MediaFetchFailure) ?? .decode,
            hasPreview: hasLoadingPreview
        )
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.depthAnalysis.error("tap_video_playback_load_failed source=\(self.source.diagnosticsLabel, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
        #endif
    }

    private func handleCancelledPlayerPreparation(
        requestKey: MediaFetchRequestKey
    ) {
        guard activeRequestKey == requestKey else {
            return
        }
        releasePlayerResources()
        state = .failed(
            DepthAnalysisErrorPresentation.albumLoadErrorMessage(
                for: CancellationError()
            )
        )
        fetchState.finish()
    }

    private func handleFailedPlayerPreparation(
        _ error: any Error,
        requestKey: MediaFetchRequestKey
    ) {
        guard activeRequestKey == requestKey else {
            return
        }
        releasePlayerResources()
        state = .failed(
            DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error)
        )
        fetchState.finish()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.depthAnalysis.error("tap_video_playback_prepare_failed source=\(self.source.diagnosticsLabel, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public) originalReady=true")
        #endif
    }

    private func ensureCurrent(_ requestKey: MediaFetchRequestKey) throws {
        try Task.checkCancellation()
        guard activeRequestKey == requestKey else {
            throw CancellationError()
        }
    }

    private func configureDepthPipeline(
        presentation: TAPVideoPlaybackPresentation,
        fileURL: URL
    ) {
        guard let descriptor = presentation.registrationDescriptor,
              descriptor.supportsRegisteredOverlay,
              let depthFormat = presentation.depthFormat else {
            registeredDepthAvailability = .unavailable
            depthPipeline.releaseConfiguration()
            return
        }
        registeredDepthAvailability = .available(descriptor)
        depthPipeline.configure(
            fileURL: fileURL,
            displayOrientation: presentation.depthFrameOrientation,
            depthFormat: depthFormat,
            depthTrackID: presentation.depthTrackID,
            registrationDescriptor: descriptor,
            staleToleranceSeconds: TAPVideoDepthGapPolicy.staleToleranceSeconds(
                nominalDepthFrameIntervalSeconds:
                    descriptor.nominalDepthFrameIntervalSeconds
            )
        )
    }

    private func releasePlaybackResources() {
        releasePlayerResources()
        resource = nil
        isOriginalResourceReady = false
    }

    private func releasePlayerResources() {
        playerLifecycle?.invalidate()
        playerLifecycle = nil
        depthPipeline.cancelPresentation()
        depthPipeline.releaseConfiguration()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private var hasLoadingPreview: Bool {
        loadingPreviewImage != nil
    }
}
