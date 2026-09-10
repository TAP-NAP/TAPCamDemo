@preconcurrency import AVFoundation
import Foundation
import Testing
import UIKit
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

    #if DEBUG
    @Test func adjacentVideoRetainsOriginalButReleasesItsPlayerAndRestoresItsOwnPosition() async throws {
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        let id = UUID().uuidString
        let destination = DepthAlbumRouteAdapter.Destination.video(TAPVideoPlaybackRoute(
            itemID: id, source: .fixtureFile(artifact.fileURL, automaticSeekScheduleSeconds: [], autoPlay: false)))
        let entry = TAPLibraryViewerPagingEntry(id: id, destination: destination,
            mediaVersion: LibraryMediaVersion(contentRevision: "1", posterRevision: "1"))
        let store = TAPLibraryViewerStore(entries: [entry], currentItemID: id)
        let session = try #require(store.videoSession(for: entry))
        await session.startPlaybackSession()
        let original = try session.acquireOriginalResourceLease()
        let player = try #require(session.player)
        let model = try #require(session.transportModel)
        try await waitUntil { player.status == .readyToPlay && model.durationSeconds > 1 }
        model.setScrubbing(true)
        model.previewSeek(to: 0.5)
        model.setScrubbing(false)
        try await waitUntil { abs(model.confirmedElapsedSeconds - 0.5) < 0.05 }
        session.suspendForAdjacent()
        #expect(session.player == nil)
        #expect(session.transportModel == nil)
        #expect(session.isOriginalResourceReady)
        #expect(try session.acquireOriginalResourceLease().fileURL == original.fileURL)
        let newPoster = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let refreshedEntry = TAPLibraryViewerPagingEntry(id: id, destination: destination,
            mediaVersion: LibraryMediaVersion(contentRevision: "1", posterRevision: "2"))
        TAPLibraryPagingPreviewCache.shared.insert(newPoster, for: id, version: refreshedEntry.mediaVersion)
        store.reconcile(entries: [refreshedEntry], selectedItemID: id, pixelLength: 80)
        #expect(store.currentVideoSession === session)
        #expect(session.loadingPreviewImage === newPoster)
        await session.startPlaybackSession()
        #expect(session.player !== player)
        #expect(try session.acquireOriginalResourceLease().fileURL == original.fileURL)
        #expect(session.isReusingOriginal)
        #expect(LibraryMediaFetchOverlayState(session.mediaFetchPhase) == .hidden)
        try await waitUntil { abs((session.transportModel?.confirmedElapsedSeconds ?? 0) - 0.5) < 0.05 }
        session.stopPlayback()
        #expect(!session.isOriginalResourceReady)
        #expect(FileManager.default.fileExists(atPath: original.fileURL.path))
    }
    #endif

    @Test func evictedVideoCancelsOriginalWhenItsLastShareWaiterCancels() async throws {
        let probe = ViewerOriginalFetchProbe()
        let session = TAPVideoPlaybackSession(source: .photosAsset("waiting-share"),
            registrationAdapter: TAPVideoManifestDepthRegistrationAdapter(), mediaFetcher: WaitingViewerOriginalFetcher(probe: probe))
        let share = Task { try await session.awaitOriginalResourceLease() }
        try await waitUntil { probe.started }
        session.stopPlayback()
        #expect(session.hasActiveMediaFetch)
        share.cancel()
        await #expect(throws: CancellationError.self) { try await share.value }
        try await waitUntil { probe.cancelled }
        #expect(!session.hasActiveMediaFetch)
        #expect(session.player == nil)
        #expect(!session.isOriginalResourceReady)
    }

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

@MainActor
private final class ViewerOriginalFetchProbe {
    var started = false
    var cancelled = false
}

nonisolated private struct WaitingViewerOriginalFetcher: LibraryMediaFetching {
    let probe: ViewerOriginalFetchProbe
    func mediaKind(for request: LibraryMediaAssetRequest) async throws -> LibraryMediaKind { .tapVideo }
    func posterPhase(for request: LibraryMediaPosterRequest, allowsNetworkAccess: Bool,
                     progress: @escaping @Sendable (Double?) -> Void) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> { .idle(nil) }
    func previewPhase(for request: LibraryMediaAssetRequest, pixelLength: Int, allowsNetworkAccess: Bool,
                      progress: @escaping @Sendable (Double?) -> Void) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> { .idle(nil) }
    func photoDisplayImage(for request: LibraryMediaAssetRequest, pixelLength: Int,
                           progress: @escaping @Sendable (Double?) -> Void) async throws -> UIImage { throw MediaFetchFailure.decode }
    func livePhoto(for request: LibraryMediaAssetRequest, targetSize: CGSize,
                   progress: @escaping @Sendable (Double?) -> Void) async throws -> LibraryLivePhoto { throw MediaFetchFailure.decode }
    func videoOriginalFile(for request: LibraryMediaAssetRequest,
                           progress: @escaping @Sendable (Double?) -> Void) async throws -> LibraryManagedTemporaryFile {
        await MainActor.run { probe.started = true }
        progress(0.25)
        do { try await Task.sleep(for: .seconds(30)) }
        catch { await MainActor.run { probe.cancelled = true }; throw error }
        throw MediaFetchFailure.download
    }
}
