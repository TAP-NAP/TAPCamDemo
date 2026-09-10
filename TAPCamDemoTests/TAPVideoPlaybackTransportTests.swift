@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

@MainActor
struct TAPVideoPlaybackTransportTests {
    #if DEBUG
    @Test func oneTransportSurvivesViewReconstructionAndResumesTheActualPlayer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        let session = TAPVideoPlaybackSession(
            source: .fixtureFile(artifact.fileURL, automaticSeekScheduleSeconds: [], autoPlay: false),
            registrationAdapter: TAPVideoManifestDepthRegistrationAdapter(), mediaFetcher: PhotoKitLibraryMediaFetcher()
        )
        await session.startPlaybackSession()
        defer { session.stopPlayback() }
        let player = try #require(session.player)
        let model = try #require(session.transportModel)
        try await waitUntil { player.status == .readyToPlay && model.durationSeconds > 1 }

        model.togglePlayback()
        try await waitUntil { CMTimeGetSeconds(player.currentTime()) > 0.15 }
        model.togglePlayback()
        try await waitUntil { player.timeControlStatus == .paused }
        #expect(!model.hasActivePlaybackIntent)
        let pausedTime = CMTimeGetSeconds(player.currentTime())
        model.togglePlayback()
        try await waitUntil { CMTimeGetSeconds(player.currentTime()) > pausedTime + 0.15 }
        #expect(model.hasActivePlaybackIntent)
        model.togglePlayback()

        let target = model.durationSeconds / 2
        model.setScrubbing(true)
        model.previewSeek(to: target)
        model.setScrubbing(false)
        for _ in 0..<12 {
            _ = TAPVideoPlaybackTransportView(model: model)
            #expect(session.transportModel === model)
            await Task.yield()
        }
        try await waitUntil {
            abs(CMTimeGetSeconds(player.currentTime()) - target) < 0.05
                && abs(model.confirmedElapsedSeconds - target) < 0.05
        }
        #expect(!model.hasActivePlaybackIntent)
        model.togglePlayback()
        try await waitUntil { CMTimeGetSeconds(player.currentTime()) > target + 0.15 }
        model.togglePlayback()

        model.setScrubbing(true)
        model.previewSeek(to: model.durationSeconds)
        model.setScrubbing(false)
        try await waitUntil { model.confirmedElapsedSeconds >= model.durationSeconds - 0.05 }
        #expect(!model.hasActivePlaybackIntent)
        model.togglePlayback()
        try await waitUntil {
            let seconds = CMTimeGetSeconds(player.currentTime())
            return seconds > 0.15 && seconds < model.durationSeconds / 2 && model.hasActivePlaybackIntent
        }

        // Queue the old item's end callback, then dispose its model before the
        // callback's MainActor task runs. A replacement owner keeps its intent.
        let oldItem = try #require(player.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        session.stopPlayback()
        session.playbackIntentState.setUserIntent(true)
        model.togglePlayback()
        try await Task.sleep(for: .milliseconds(40))
        #expect(session.transportModel == nil)
        #expect(session.playbackIntentState.intendsPlayback)
    }
    #endif

    @Test func failedResumeSeekRestoresPausedIntent() async throws {
        let player = TransportFailedSeekPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        let intent = TAPVideoPlaybackIntentState()
        let model = TAPVideoPlaybackTransportModel(player: player, intentState: intent)
        defer { model.invalidate() }
        intent.setUserIntent(true)
        model.setScrubbing(true)
        model.setScrubbing(false)
        #expect(model.hasActivePlaybackIntent)
        try await waitUntil { !model.hasActivePlaybackIntent }
        #expect(!intent.intendsPlayback)
        #expect(player.timeControlStatus == .paused)
        #expect(model.elapsedSeconds == model.confirmedElapsedSeconds)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Transport did not reach the expected AVPlayer state or confirmed time")
    }
}

nonisolated private final class TransportFailedSeekPlayer: AVPlayer, @unchecked Sendable {
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                       completionHandler: @escaping @Sendable (Bool) -> Void) {
        completionHandler(false)
    }
}
