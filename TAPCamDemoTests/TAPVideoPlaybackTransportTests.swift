@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

@MainActor
struct TAPVideoPlaybackTransportTests {
    @Test func intentChangesNotifyPauseWithoutTreatingPagingAsAUserPause() {
        let intent = TAPVideoPlaybackIntentState()
        var changes: [Bool] = []
        intent.onChange = { changes.append($0) }
        intent.setUserIntent(true)
        intent.setUserIntent(true)
        #expect(intent.beginPagingSuspension(currentStatus: .playing))
        intent.updateFromPlayerStatus(.paused)
        #expect(changes == [true])
        intent.endPagingSuspension()
        intent.setUserIntent(false)
        intent.updateFromPlayerStatus(.paused)
        intent.updateFromPlayerStatus(.waitingToPlayAtSpecifiedRate)
        intent.reset()
        #expect(changes == [true, false, true, false])
    }

    @Test func clockNotificationPreservesThePausedSpatialHistoryAndPendingFrame() {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
        let cloud = TAPVideoPointCloudPlayback()
        let lifecycle = TAPVideoPlaybackPlayerLifecycle(
            player: player, source: .photosAsset("clock-notification"),
            depthPipeline: TAPVideoDepthPipeline(sourceLabel: "clock-notification"),
            pointCloudPlayback: cloud, canRestartDepthPresentation: { false }
        )
        defer { lifecycle.invalidate(); cloud.cancel() }
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480)
        var history = TAPVideoPointCloudHistory()
        let payload = history.accept(.init(presentationTimeSeconds: 0, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [SIMD4<Float>(1, 0, 0, 1)], cameraModel: model))
        cloud.acceptProjection(payload, spatialHistory: history)
        cloud.setPlaybackPaused(true)
        cloud.receiveProjection(.init(presentationTimeSeconds: 1, vertices: payload.vertices,
            colors: payload.colors, cameraModel: model))
        lifecycle.handleTimeJump(at: 1)
        #expect(lifecycle.currentTimeSeconds == 1)
        #expect(cloud.spatialHistory.frames.map(\.presentationTimeSeconds) == [0])
        #expect(cloud.spatialHistory.frames.first?.vertices == payload.vertices)
        #expect(cloud.store.presentationTimeSeconds == 0)
        cloud.setPlaybackPaused(false)
        #expect(cloud.store.presentationTimeSeconds == 1, "Clock notifications must not discard a paused pending result")
    }

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
        var completedSeeks: [Double] = []
        let resetAfterSeek = session.playbackIntentState.onSeek
        session.playbackIntentState.onSeek = { seconds in
            completedSeeks.append(seconds)
            resetAfterSeek?(seconds)
        }
        try await waitUntil { player.status == .readyToPlay && model.durationSeconds > 1 }
        session.prepareThreeDPlaybackGate()
        try await waitUntil { session.pointCloudStore.presentationTimeSeconds != nil }

        model.togglePlayback()
        try await waitUntil { CMTimeGetSeconds(player.currentTime()) > 0.15 }
        model.togglePlayback()
        try await waitUntil { player.timeControlStatus == .paused }
        #expect(!model.hasActivePlaybackIntent)
        let pausedTime = CMTimeGetSeconds(player.currentTime())
        let pausedSceneTime = session.pointCloudStore.presentationTimeSeconds
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.pointCloudStore.presentationTimeSeconds == pausedSceneTime,
                "Completing an in-flight projection must not replace the paused scene")
        model.togglePlayback()
        try await waitUntil { CMTimeGetSeconds(player.currentTime()) > pausedTime + 0.15 }
        try await waitUntil {
            (session.pointCloudStore.presentationTimeSeconds ?? -.infinity) > (pausedSceneTime ?? -.infinity)
        }
        #expect(model.hasActivePlaybackIntent)
        #expect(completedSeeks.isEmpty, "Pause and resume must not signal a spatial reset")
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
        #expect(completedSeeks.count == 1 && abs((completedSeeks.last ?? 0) - target) < 0.05)
        model.togglePlayback()
        try await waitUntil { CMTimeGetSeconds(player.currentTime()) > target + 0.15 }
        model.togglePlayback()

        model.setScrubbing(true)
        model.previewSeek(to: model.durationSeconds)
        model.setScrubbing(false)
        try await waitUntil { model.confirmedElapsedSeconds >= model.durationSeconds - 0.05 }
        #expect(!model.hasActivePlaybackIntent)
        #expect(completedSeeks.count == 2)
        model.togglePlayback()
        try await waitUntil {
            let seconds = CMTimeGetSeconds(player.currentTime())
            return seconds > 0.15 && seconds < model.durationSeconds / 2 && model.hasActivePlaybackIntent
        }
        #expect(completedSeeks.count == 3, "Replay from the end performs one explicit seek")

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
        var completedSeeks: [Double] = []
        intent.onSeek = { completedSeeks.append($0) }
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
        #expect(completedSeeks.isEmpty, "An unsuccessful seek must not reset the accepted spatial scene")
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
