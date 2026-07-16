//
//  TAPVideoPlaybackTransportModel.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Observation

nonisolated enum TAPVideoPlaybackTransportPolicy {
    static func hasActivePlaybackIntent(
        status: AVPlayer.TimeControlStatus
    ) -> Bool {
        status != .paused
    }
}

@MainActor
enum TAPVideoPlaybackAudioSession {
    @discardableResult
    static func activate() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

@MainActor
@Observable
final class TAPVideoPlaybackTransportModel {
    private(set) var hasActivePlaybackIntent = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var confirmedElapsedSeconds: Double = 0
    private(set) var durationSeconds: Double = 0

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var periodicTimeObserver: Any?
    @ObservationIgnored private var timeControlStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var durationObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackEndObserver: NSObjectProtocol?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var seekGeneration: UInt64 = 0
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var shouldResumeAfterScrubbing = false
    @ObservationIgnored private var ownsPlaybackAudioSession = false
    @ObservationIgnored private var isInvalidated = false

    init(player: AVPlayer) {
        self.player = player
        installObservers()
    }

    deinit {
        seekTask?.cancel()
        player.currentItem?.cancelPendingSeeks()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        timeControlStatusObservation?.invalidate()
        durationObservation?.invalidate()
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        if ownsPlaybackAudioSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    func togglePlayback() {
        guard !isInvalidated else {
            return
        }
        if hasActivePlaybackIntent {
            cancelPendingSeek()
            shouldResumeAfterScrubbing = false
            player.pause()
            return
        }
        if durationSeconds > 0,
           elapsedSeconds >= durationSeconds - 0.05 {
            performSeek(to: .zero, resumeAfterSeek: true)
            return
        }
        cancelPendingSeek()
        activatePlaybackAudioSessionIfNeeded()
        player.play()
    }

    func previewSeek(to seconds: Double) {
        guard seconds.isFinite else {
            return
        }
        elapsedSeconds = min(max(seconds, 0), max(durationSeconds, 0))
    }

    func setScrubbing(_ scrubbing: Bool) {
        guard !isInvalidated, scrubbing != isScrubbing else {
            return
        }
        if scrubbing {
            shouldResumeAfterScrubbing = TAPVideoPlaybackTransportPolicy
                .hasActivePlaybackIntent(status: player.timeControlStatus)
            cancelPendingSeek()
            isScrubbing = true
            player.pause()
            return
        }
        isScrubbing = false
        let target = CMTime(seconds: elapsedSeconds, preferredTimescale: 600)
        let shouldResume = shouldResumeAfterScrubbing
        shouldResumeAfterScrubbing = false
        performSeek(to: target, resumeAfterSeek: shouldResume)
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        player.pause()
        tearDown()
    }

    private func performSeek(to target: CMTime, resumeAfterSeek: Bool) {
        cancelPendingSeek()
        guard let expectedItem = player.currentItem else {
            elapsedSeconds = confirmedElapsedSeconds
            return
        }
        seekGeneration &+= 1
        let generation = seekGeneration
        let player = player
        seekTask = Task { @MainActor [weak self] in
            let didFinish = await player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard let self,
                  !isInvalidated,
                  generation == seekGeneration else {
                return
            }
            seekTask = nil
            guard !Task.isCancelled,
                  didFinish,
                  !isScrubbing,
                  player.currentItem === expectedItem else {
                elapsedSeconds = confirmedElapsedSeconds
                return
            }
            updateConfirmedElapsedTime(player.currentTime())
            if resumeAfterSeek {
                activatePlaybackAudioSessionIfNeeded()
                player.play()
            }
        }
    }

    private func cancelPendingSeek() {
        seekGeneration &+= 1
        seekTask?.cancel()
        seekTask = nil
        player.currentItem?.cancelPendingSeeks()
    }

    private func installObservers() {
        updateDuration(player.currentItem?.duration ?? .invalid)
        updateConfirmedElapsedTime(player.currentTime())
        timeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.hasActivePlaybackIntent = TAPVideoPlaybackTransportPolicy
                    .hasActivePlaybackIntent(status: player.timeControlStatus)
            }
        }
        if let item = player.currentItem {
            durationObservation = item.observe(\.duration, options: [.initial, .new]) {
                [weak self] item, _ in
                Task { @MainActor [weak self] in
                    self?.updateDuration(item.duration)
                }
            }
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    cancelPendingSeek()
                    hasActivePlaybackIntent = false
                    elapsedSeconds = durationSeconds
                    confirmedElapsedSeconds = durationSeconds
                }
            }
        }
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !isScrubbing else {
                    return
                }
                updateConfirmedElapsedTime(time)
            }
        }
    }

    private func updateConfirmedElapsedTime(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else {
            return
        }
        let bounded = min(max(seconds, 0), max(durationSeconds, 0))
        confirmedElapsedSeconds = bounded
        elapsedSeconds = bounded
    }

    private func updateDuration(_ duration: CMTime) {
        let seconds = CMTimeGetSeconds(duration)
        durationSeconds = seconds.isFinite && seconds > 0 ? seconds : 0
        confirmedElapsedSeconds = min(confirmedElapsedSeconds, durationSeconds)
        elapsedSeconds = min(elapsedSeconds, durationSeconds)
    }

    private func activatePlaybackAudioSessionIfNeeded() {
        guard !ownsPlaybackAudioSession else {
            return
        }
        ownsPlaybackAudioSession = TAPVideoPlaybackAudioSession.activate()
    }

    private func tearDown() {
        cancelPendingSeek()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if ownsPlaybackAudioSession {
            TAPVideoPlaybackAudioSession.deactivate()
            ownsPlaybackAudioSession = false
        }
    }
}
