//
//  TAPVideoPlaybackPlayerLifecycle.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

@MainActor
final class TAPVideoPlaybackPlayerLifecycle {
    private let player: AVPlayer
    private let source: TAPVideoPlaybackSource
    private let depthPipeline: TAPVideoDepthPipeline
    private let pointCloudPlayback: TAPVideoPointCloudPlayback?
    private let canRestartDepthPresentation: () -> Bool

    private var timeJumpObserver: NSObjectProtocol?
    private var periodicTimeObserver: Any?
    private var playerStatusObservation: NSKeyValueObservation?
    private var isInvalidated = false
    #if DEBUG
    private var fixtureSeekTask: Task<Void, Never>?
    #endif

    private(set) var currentTimeSeconds: Double = 0

    init(
        player: AVPlayer,
        source: TAPVideoPlaybackSource,
        depthPipeline: TAPVideoDepthPipeline,
        pointCloudPlayback: TAPVideoPointCloudPlayback? = nil,
        canRestartDepthPresentation: @escaping () -> Bool
    ) {
        self.player = player
        self.source = source
        self.depthPipeline = depthPipeline
        self.pointCloudPlayback = pointCloudPlayback
        self.canRestartDepthPresentation = canRestartDepthPresentation
    }

    func start() {
        guard !isInvalidated, let item = player.currentItem else {
            return
        }
        installObservers(item: item)
        depthPipeline.beginNewGeneration()
        warmPlayback()
        #if DEBUG
        if case .fixtureFile(_, _, let autoPlay) = source, autoPlay {
            player.play()
        }
        scheduleFixtureSeekIfNeeded()
        #endif
    }

    func prerollIfReady() {
        guard !isInvalidated, player.status == .readyToPlay, player.rate == 0 else {
            return
        }
        player.preroll(atRate: 1) { _ in }
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        #if DEBUG
        fixtureSeekTask?.cancel()
        fixtureSeekTask = nil
        #endif
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
        player.cancelPendingPrerolls()
    }

    private func warmPlayback() {
        player.currentItem?.preferredForwardBufferDuration =
            TAPVideoPlaybackSession.preferredTwoDBufferDurationSeconds
        guard player.status != .readyToPlay else {
            prerollIfReady()
            return
        }
        playerStatusObservation = player.observe(\.status, options: [.new]) {
            [weak self] observedPlayer, _ in
            guard observedPlayer.status == .readyToPlay else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self, !isInvalidated else {
                    return
                }
                playerStatusObservation?.invalidate()
                playerStatusObservation = nil
                prerollIfReady()
            }
        }
        if player.status == .readyToPlay {
            playerStatusObservation?.invalidate()
            playerStatusObservation = nil
            prerollIfReady()
        }
    }

    private func installObservers(item: AVPlayerItem) {
        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self, weak player] in
                guard let self, !isInvalidated else {
                    return
                }
                let seconds = player.map { CMTimeGetSeconds($0.currentTime()) }
                    .flatMap { $0.isFinite ? max(0, $0) : nil }
                    ?? currentTimeSeconds
                handleTimeJump(at: seconds)
            }
        }
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !isInvalidated else {
                    return
                }
                let rawSeconds = CMTimeGetSeconds(time)
                guard rawSeconds.isFinite else {
                    return
                }
                let seconds = max(0, rawSeconds)
                if abs(seconds - currentTimeSeconds) > 1 {
                    depthPipeline.handleDiscontinuity(
                        playbackTimeSeconds: seconds,
                        canRestartPresentation: canRestartDepthPresentation()
                    )
                }
                currentTimeSeconds = seconds
                depthPipeline.updatePlaybackTime(seconds)
                pointCloudPlayback?.update(at: seconds)
            }
        }
    }

    func handleTimeJump(at seconds: Double) {
        currentTimeSeconds = seconds
        // AVPlayer clock discontinuities are not explicit user seeks. Preserve
        // the accumulated scene and any validated result waiting behind pause.
        pointCloudPlayback?.update(at: seconds)
        depthPipeline.handleDiscontinuity(
            playbackTimeSeconds: seconds,
            canRestartPresentation: canRestartDepthPresentation()
        )
    }

    #if DEBUG
    private func scheduleFixtureSeekIfNeeded() {
        guard case .fixtureFile(_, let schedule, let autoPlay) = source,
              !schedule.isEmpty else {
            return
        }
        fixtureSeekTask?.cancel()
        fixtureSeekTask = Task { @MainActor [weak self, weak player] in
            for (index, seconds) in schedule.enumerated() {
                do {
                    try await Task.sleep(
                        nanoseconds: index == 0 ? 900_000_000 : 500_000_000
                    )
                } catch {
                    return
                }
                guard let self, let player, !isInvalidated else {
                    return
                }
                let finished = await player.seek(
                    to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                guard finished, !isInvalidated, !Task.isCancelled else { return }
                let actualTime = CMTimeGetSeconds(player.currentTime())
                if actualTime.isFinite { pointCloudPlayback?.reset(at: max(0, actualTime)) }
                if autoPlay {
                    player.play()
                }
            }
            self?.fixtureSeekTask = nil
        }
    }
    #endif
}
