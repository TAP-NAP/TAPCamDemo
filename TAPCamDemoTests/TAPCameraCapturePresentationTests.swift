//
//  TAPCameraCapturePresentationTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Combine
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPCameraCapturePresentationTests {
    @Test(.timeLimit(.minutes(1))) @MainActor
    func captureModeChangeWaitsForBothGraphDirectionsAndCanRetry() async throws {
        let coordinator = CaptureLifecycleCoordinator()
        for (mode, ready) in [(CameraCaptureModeOption.photo, true), (.video, false), (.video, true)] {
            let (started, startedContinuation) = AsyncStream<Void>.makeStream()
            var release: CheckedContinuation<Void, Never>?
            var completed: [Bool] = []
            var calls: [CameraCaptureModeOption] = []
            let operation: @MainActor (CameraCaptureModeOption) async -> Void = { operationMode in
                calls.append(operationMode)
                await withCheckedContinuation { continuation in
                    release = continuation
                    startedContinuation.yield(())
                    startedContinuation.finish()
                }
            }
            let requestedTask = coordinator.prepareCaptureMode(to: mode,
                prepareVideoMode: { await operation(.video); return ready },
                restorePhotoMode: { await operation(.photo) },
                completion: { completed.append($0) })
            let task = try #require(requestedTask)
            #expect(coordinator.isChangingCaptureMode, "Gate is set before the target mode is published")
            #expect(coordinator.prepareCaptureMode(to: mode,
                prepareVideoMode: { Issue.record("Duplicate preparation"); return false },
                restorePhotoMode: { Issue.record("Duplicate restoration") }, completion: { _ in }) == nil)
            var iterator = started.makeAsyncIterator()
            #expect(await iterator.next() != nil)
            #expect(calls == [mode] && completed.isEmpty && coordinator.isChangingCaptureMode)
            try #require(release).resume()
            await task.value
            #expect(completed == [ready])
            #expect(!coordinator.isChangingCaptureMode)
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func cancelledCaptureModeChangeWaitsForTheStartedOperationAndDoesNotPublish() async throws {
        let coordinator = CaptureLifecycleCoordinator()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var completed = false
        var settled = false
        let requestedTask = coordinator.prepareCaptureMode(to: .video,
            prepareVideoMode: {
                await withCheckedContinuation { continuation in
                    release = continuation
                    startedContinuation.yield(())
                    startedContinuation.finish()
                }
                return true
            }, restorePhotoMode: {}, completion: { _ in completed = true },
            settled: {
                #expect(!coordinator.isChangingCaptureMode)
                settled = true
            })
        let task = try #require(requestedTask)
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        coordinator.cancelCaptureModeChange()
        #expect(coordinator.isChangingCaptureMode && !completed && !settled)
        try #require(release).resume()
        await task.value
        #expect(!coordinator.isChangingCaptureMode && !completed && settled)
        let requestedRetry = coordinator.prepareCaptureMode(to: .video,
            prepareVideoMode: { true }, restorePhotoMode: {}, completion: { completed = $0 })
        let retry = try #require(requestedRetry)
        await retry.value
        #expect(completed && !coordinator.isChangingCaptureMode)

        for mode in CameraCaptureModeOption.allCases {
            var restoredPhoto = false
            let requestedCancellation = coordinator.prepareCaptureMode(to: mode,
                prepareVideoMode: { Issue.record("Cancelled Video preparation started"); return true },
                restorePhotoMode: { restoredPhoto = true },
                completion: { _ in Issue.record("Cancelled mode published completion") })
            let cancelledTask = try #require(requestedCancellation)
            coordinator.cancelCaptureModeChange()
            await cancelledTask.value
            #expect(restoredPhoto == (mode == .photo))
            #expect(!coordinator.isChangingCaptureMode)
        }
    }

    @Test @MainActor func videoPreparationIsInvalidatedWithTheCameraConfiguration() {
        let viewModel = CameraViewModel(capabilityMatrix: CapabilityMatrix(rgbSources: [], depthCandidates: []),
            libraryStore: LibraryMediaStore())
        viewModel.isDepthCaptureReady = true
        #expect(viewModel.canCapture)
        for state in [CameraVideoPreparationState.idle, .preparing, .ready, .needsPreparation] {
            viewModel.videoPreparationState = state
            #expect(viewModel.isPreparingVideoMode == (state == .preparing))
            #expect(viewModel.canCapture == (state != .preparing))
            #expect(!viewModel.canUseVideoShutter, "No active camera configuration means no video readiness")
            viewModel.configurationGeneration += 1
            #expect(viewModel.videoPreparationState == state, "Operation identity alone does not destroy a retained graph")
            viewModel.invalidateVideoPreparation()
            #expect(viewModel.videoPreparationState == .idle)
        }
        viewModel.isVideoRecording = true
        #expect(viewModel.canUseVideoShutter, "The stop control must remain available")
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func stoppedVideoRequestsPreparationAndRetryWaitsForTheSessionOperation() async throws {
        let viewModel = CameraViewModel(capabilityMatrix: CapabilityMatrix(rgbSources: [], depthCandidates: []),
            libraryStore: LibraryMediaStore())
        var states: [CameraVideoPreparationState] = []
        let subscription = viewModel.$videoPreparationState.sink { states.append($0) }
        defer { subscription.cancel() }
        for reason in [TAPVideoManifest.StopReason.userStop, .durationLimit, .thermalPressure,
                       .systemPressure, .appLifecycle, .storageFailure, .captureFailure] {
            viewModel.isVideoRecording = true
            // No recorder is installed: exercise the real stop-failure cleanup
            // without camera hardware or a persisted capture workspace.
            await viewModel.stopVideoRecording(reason: reason, pendingCaptureWorkerClient: nil)
            #expect(!viewModel.isVideoRecording)
            #expect(Array(states.suffix(2)) == [.preparing, .needsPreparation])
            #expect(!viewModel.canUseVideoShutter)
        }

        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let preparation = Task { @MainActor in
            await viewModel.prepareVideoMode {
                await withCheckedContinuation { continuation in
                    release = continuation
                    startedContinuation.yield(())
                    startedContinuation.finish()
                }
            }
        }
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        #expect(viewModel.videoPreparationState == .preparing)
        #expect(!viewModel.canUseVideoShutter)
        try #require(release).resume()
        #expect(await preparation.value)
        #expect(viewModel.videoPreparationState == .ready)

        #expect(await viewModel.prepareVideoMode {
            throw TAPDepthCaptureError.videoRecordingNotActive
        } == false)
        #expect(viewModel.videoPreparationState == .idle, "A failed recovery does not request another automatic attempt")
        #expect(await viewModel.prepareVideoMode {})
        #expect(viewModel.videoPreparationState == .ready)
        #expect(await viewModel.prepareVideoMode {
            viewModel.configurationGeneration += 1
        } == false)
        #expect(viewModel.videoPreparationState == .preparing, "A retired configuration cannot publish readiness")
        viewModel.invalidateVideoPreparation()
        #expect(viewModel.videoPreparationState == .idle, "A retired configuration cannot publish readiness")
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func videoPreparationCoalescesMatchingRequestsAndRetiresStaleCompletion() async throws {
        let viewModel = CameraViewModel(capabilityMatrix: CapabilityMatrix(rgbSources: [], depthCandidates: []),
            libraryStore: LibraryMediaStore())
        var preparedRequest: Int?
        var operations: [Int] = []
        var states: [CameraVideoPreparationState] = []
        let subscription = viewModel.$videoPreparationState.sink { states.append($0) }
        let (operationStarts, operationStarted) = AsyncStream<Int>.makeStream()
        let (waiterEntries, waiterEntered) = AsyncStream<Void>.makeStream()
        var operationIterator = operationStarts.makeAsyncIterator()
        var waiterIterator = waiterEntries.makeAsyncIterator()
        var operationContinuation: CheckedContinuation<Void, Never>?
        defer {
            subscription.cancel()
            operationContinuation?.resume()
            operationStarted.finish()
            waiterEntered.finish()
        }
        let prepare: @MainActor (Int) async -> Bool = { request in
            await viewModel.prepareVideoMode(isPrepared: { preparedRequest == request }) {
                operations.append(request)
                await withCheckedContinuation { continuation in
                    operationContinuation = continuation
                    operationStarted.yield(request)
                }
                preparedRequest = request
            }
        }
        @MainActor func finishOperation() throws {
            let continuation = try #require(operationContinuation)
            operationContinuation = nil
            continuation.resume()
        }

        let first = Task { @MainActor in await prepare(1) }
        #expect(await operationIterator.next() == 1)
        let duplicate = Task { @MainActor in
            waiterEntered.yield(())
            return await prepare(1)
        }
        #expect(await waiterIterator.next() != nil)
        #expect(operations == [1])
        try finishOperation()
        #expect(await first.value)
        #expect(await duplicate.value)
        #expect(states == [.idle, .preparing, .ready])
        #expect(await prepare(1))
        #expect(operations == [1])
        #expect(states == [.idle, .preparing, .ready], "Matching retained graphs never publish preparing again")

        let changed = Task { @MainActor in await prepare(2) }
        #expect(await operationIterator.next() == 2)
        let nextChanged = Task { @MainActor in
            waiterEntered.yield(())
            return await prepare(3)
        }
        #expect(await waiterIterator.next() != nil)
        #expect(operations == [1, 2], "A different request waits for the current graph operation")
        try finishOperation()
        #expect(await operationIterator.next() == 3)
        #expect(operations == [1, 2, 3], "A waiter rechecks its own parameters after the previous operation")
        try finishOperation()
        #expect(await changed.value)
        #expect(await nextChanged.value)
        #expect(preparedRequest == 3)

        let retired = Task { @MainActor in await prepare(4) }
        #expect(await operationIterator.next() == 4)
        viewModel.configurationGeneration += 1
        viewModel.invalidateVideoPreparation()
        #expect(viewModel.videoPreparationState == .idle)
        let recovery = Task { @MainActor in
            waiterEntered.yield(())
            return await prepare(5)
        }
        #expect(await waiterIterator.next() != nil)
        #expect(operations == [1, 2, 3, 4], "Invalidation still waits for physical work to drain")
        let statesAfterInvalidation = states.count
        try finishOperation()
        #expect(await retired.value == false)
        #expect(await operationIterator.next() == 5)
        #expect(Array(states.dropFirst(statesAfterInvalidation)) == [.preparing], "Retired completion cannot publish ready")
        try finishOperation()
        #expect(await recovery.value)
        #expect(preparedRequest == 5)
        #expect(operations == [1, 2, 3, 4, 5])
        #expect(viewModel.videoPreparationState == .ready)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true]) @MainActor
    func savedVideoPublishesActualReadinessBeforeThePendingWorkerFinishes(retainsGraph: Bool) async throws {
        let expectedState: CameraVideoPreparationState = retainsGraph ? .ready : .needsPreparation
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureStore = TAPPendingCaptureStore(rootURL: directory.appendingPathComponent("fixture"))
        let captureID = UUID().uuidString
        let fixture = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: fixtureStore, captureID: captureID, hasDepth: false)
        let fixtureURL = try await fixtureStore.videoArtifactURL(captureID: captureID)
        let manifest = try TAPVideoManifestBox.decodedManifest(fromFileAt: fixtureURL)
        let store = TAPPendingCaptureStore(rootURL: directory.appendingPathComponent("pending"))
        let workspace = try await store.beginVideoCaptureWorkspace(captureID: captureID)
        try FileManager.default.copyItem(at: fixtureURL, to: workspace.artifactURL)
        let artifact = TAPVideoRecordingArtifact(captureID: captureID, packageID: fixture.packageID,
            capturedAt: fixture.capturedAt, videoURL: workspace.artifactURL, manifest: manifest, location: nil)
        var states: [CameraVideoPreparationState] = []
        let viewModel = CameraViewModel(capabilityMatrix: CapabilityMatrix(rgbSources: [], depthCandidates: []),
            pendingCaptureStore: store, libraryStore: LibraryMediaStore(),
            videoPosterGenerator: CameraStoppedVideoPosterGenerator {
                #expect(states.last == expectedState, "Local ingest releases preparation before poster work")
                return Data("poster".utf8)
            })
        let subscription = viewModel.$videoPreparationState.sink { states.append($0) }
        defer { subscription.cancel() }
        viewModel.isVideoRecording = true
        viewModel.activeVideoRecordingCaptureID = captureID
        viewModel.videoRecordingTemporaryDirectoryURL = workspace.bundleURL

        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var releaseWorker: CheckedContinuation<Void, Never>?
        defer { releaseWorker?.resume() }
        var stopReturned = false
        let stop = Task { @MainActor in
            await viewModel.stopVideoRecording(reason: .userStop, finishRecording: { artifact },
                isVideoModePrepared: { retainsGraph },
                processPendingCaptures: {
                    let record = try? await store.readRecord(captureID: captureID)
                    #expect(record?.status == .pending)
                    #expect(record?.thumbnailFilename != nil, "Poster persistence precedes worker cleanup")
                    await withCheckedContinuation { continuation in
                        releaseWorker = continuation
                        startedContinuation.yield(())
                        startedContinuation.finish()
                    }
                })
            stopReturned = true
        }
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        #expect(!stopReturned)
        #expect(!viewModel.isVideoRecording)
        #expect(viewModel.activeVideoRecordingCaptureID == nil)
        #expect(viewModel.videoRecordingTemporaryDirectoryURL == nil)
        #expect(viewModel.videoPreparationState == expectedState)
        #expect(await viewModel.prepareVideoMode {})
        #expect(viewModel.videoPreparationState == .ready)

        let continuation = try #require(releaseWorker)
        releaseWorker = nil
        continuation.resume()
        await stop.value
        #expect(stopReturned)
        #expect(viewModel.videoPreparationState == .ready, "The previous worker cannot reset new readiness")
        #expect(states.filter { $0 == .needsPreparation }.count == (retainsGraph ? 0 : 1))
    }

    @Test func shutterKeepsTargetModeAppearanceWhilePreparingAndPreservesRecordingSquare() {
        for mode in CameraCaptureModeOption.allCases {
            for preparing in [false, true] {
                for recording in [false, true] {
                    let state = CameraCaptureControlsState(isShutterEnabled: !preparing,
                        isLibraryWriteInProgress: false, selectedMode: mode,
                        isRecordingMovie: recording, isPreparingCaptureMode: preparing,
                        showsProfessionalControls: false, isInteractionLocked: false,
                        adjustmentControlState: nil,
                        basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
                        contentRotation: .zero)
                    #expect(state.shutterDiameter == (recording ? 34 : 62))
                    #expect(state.shutterColor == (mode == .video || recording ? Color.red : Color.white))
                    #expect(state.canOpenTAPLibrary == !recording)
                }
            }
        }
    }

    @Test @MainActor func cameraChromeOrientationMapsNotificationsAndRetainsStableAngle() async throws {
        let fixture = CameraChromeOrientationTestFixture()
        fixture.orientation = .landscapeLeft
        let controller = fixture.makeController()
        var publishedDegrees: [Double] = []
        let subscription = controller.$angle.sink { publishedDegrees.append($0.degrees) }
        defer {
            subscription.cancel()
            controller.stop()
        }

        #expect(controller.angle == .zero)
        controller.start()
        #expect(controller.angle == .degrees(90))

        let rotations: [(UIDeviceOrientation, Double)] = [
            (.landscapeRight, -90),
            (.portraitUpsideDown, 180),
            (.portrait, 0),
            (.landscapeLeft, 90)
        ]
        for (orientation, degrees) in rotations {
            try await fixture.postOrientation(orientation)
            #expect(controller.angle == .degrees(degrees))
        }
        #expect(publishedDegrees == [0, 90, -90, 180, 0, 90])

        for orientation in [UIDeviceOrientation.unknown, .faceUp, .faceDown, .landscapeLeft] {
            try await fixture.postOrientation(orientation)
            #expect(controller.angle == .degrees(90))
        }
        #expect(publishedDegrees == [0, 90, -90, 180, 0, 90])
    }

    @Test @MainActor func cameraChromeOrientationBalancesRepeatedStartAndStop() async throws {
        let fixture = CameraChromeOrientationTestFixture()
        let controller = fixture.makeController()
        defer { controller.stop() }

        controller.stop()
        #expect(fixture.events.isEmpty)
        try await fixture.postOrientation(.landscapeLeft)
        #expect(fixture.orientationReadCount == 0)

        controller.start()
        controller.start()
        #expect(fixture.events == ["startChromeOrientation"])
        #expect(fixture.orientationReadCount == 1)
        #expect(controller.angle == .degrees(90))

        try await fixture.postOrientation(.landscapeRight)
        #expect(fixture.orientationReadCount == 2)
        #expect(controller.angle == .degrees(-90))

        controller.stop()
        controller.stop()
        #expect(fixture.events == ["startChromeOrientation", "stopChromeOrientation"])
        try await fixture.postOrientation(.portraitUpsideDown)
        #expect(fixture.orientationReadCount == 2)
        #expect(controller.angle == .degrees(-90))

        controller.start()
        #expect(fixture.orientationReadCount == 3)
        #expect(controller.angle == .degrees(180))
        controller.stop()
        #expect(fixture.events == [
            "startChromeOrientation", "stopChromeOrientation",
            "startChromeOrientation", "stopChromeOrientation"
        ])
    }

    @Test @MainActor func cameraChromeOrientationDiscardsNotificationsQueuedBeforeStop() async throws {
        let fixture = CameraChromeOrientationTestFixture()
        fixture.orientation = .landscapeLeft
        let controller = fixture.makeController()
        controller.start()

        fixture.orientation = .landscapeRight
        fixture.notificationCenter.post(name: UIDevice.orientationDidChangeNotification, object: nil)
        controller.stop()
        try await Task.sleep(for: .milliseconds(200))

        #expect(fixture.orientationReadCount == 1)
        #expect(controller.angle == .degrees(90))
        #expect(fixture.events == ["startChromeOrientation", "stopChromeOrientation"])
    }

    @Test func settingsSessionReconfigurationPolicyCoalescesCaptureChanges() {
        var policy = CameraSettingsSessionReconfigurationPolicy()

        let firstPresentedChangeReconfigures =
            policy.capturePreferenceDidChange(isSettingsPresented: true)
        let secondPresentedChangeReconfigures =
            policy.capturePreferenceDidChange(isSettingsPresented: true)
        #expect(!firstPresentedChangeReconfigures)
        #expect(!secondPresentedChangeReconfigures)
        #expect(policy.hasPendingReconfiguration)
        let firstDismissalReconfigures = policy.settingsDidDismiss()
        #expect(firstDismissalReconfigures)
        #expect(!policy.hasPendingReconfiguration)
        let secondDismissalReconfigures = policy.settingsDidDismiss()
        let outsideSettingsChangeReconfigures =
            policy.capturePreferenceDidChange(isSettingsPresented: false)
        #expect(!secondDismissalReconfigures)
        #expect(outsideSettingsChangeReconfigures)
    }

    @Test @MainActor func captureLifecycleStartsObservationAndStopsItBeforeCamera() {
        let fixture = CameraChromeOrientationTestFixture()
        fixture.orientation = .landscapeLeft
        let controller = fixture.makeController()
        let coordinator = CaptureLifecycleCoordinator()
        defer { controller.stop() }

        coordinator.viewDidAppear(chromeOrientation: controller)
        #expect(controller.angle == .degrees(90))
        #expect(fixture.orientationReadCount == 1)
        coordinator.viewDidDisappear(chromeOrientation: controller) {
            fixture.events.append("stopCamera")
        }
        #expect(fixture.events == [
            "startChromeOrientation", "stopChromeOrientation", "stopCamera"
        ])
    }

    @Test @MainActor func foregroundLifecycleRestoresRouteBeforeRefreshingAndRetrying() async throws {
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let route = CameraRouteStore(contextStore: CameraRouteFileContextStore(directoryURL: directory))
        let coordinator = CaptureLifecycleCoordinator()
        var events: [String] = []
        for phase in [ScenePhase.inactive, .background, .active] {
            route.presentDepthAlbum()
            events.removeAll()
            await coordinator.scenePhaseDidChange(
                phase,
                shouldReturnToCameraOnForeground: true,
                routeStore: route,
                refreshLibraryPreview: {
                    #expect(!route.isDepthAlbumPresented)
                    events.append("preview")
                },
                retryPendingCaptures: { events.append("retry") }
            )
            #expect(events == (phase == .active ? ["preview", "retry"] : []))
            #expect(route.isDepthAlbumPresented == (phase != .active))
        }
        route.presentDepthAlbum()
        await coordinator.scenePhaseDidChange(
            .active, shouldReturnToCameraOnForeground: false, routeStore: route,
            refreshLibraryPreview: {}, retryPendingCaptures: {}
        )
        #expect(route.isDepthAlbumPresented)
    }

    @Test @MainActor func credentialCompletionRetriesOnlyOnTheFallingEdge() async {
        let coordinator = CaptureLifecycleCoordinator()
        for wasPreparing in [false, true] {
            for isPreparing in [false, true] {
                var calls = 0
                await coordinator.credentialPreparationDidChange(
                    wasPreparing: wasPreparing, isPreparing: isPreparing,
                    retryPendingCaptures: { calls += 1 }
                )
                #expect(calls == (wasPreparing && !isPreparing ? 1 : 0))
                #expect(CaptureLifecycleCoordinator.shouldRetryPendingCaptures(
                    isCredentialPreparationActive: wasPreparing, isCameraBusy: isPreparing
                ) == (!wasPreparing && !isPreparing))
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func libraryReturnWaitsForCameraButNotPendingRecovery() async throws {
        let coordinator = CaptureLifecycleCoordinator()
        let hiddenTask = coordinator.depthAlbumPresentationDidChange(
            isPresented: true, preparesVideoMode: false,
            canResumeCamera: { false },
            resumeAfterAnalysis: { Issue.record("Opening the library must not resume the camera") },
            prepareVideoMode: { Issue.record("Opening the library must not prepare video"); return false },
            isCameraReady: { false },
            retryPendingCaptures: { Issue.record("Opening the library must not retry pending captures") },
            completion: { _ in Issue.record("Opening the library must not publish a return") }
        )
        #expect(hiddenTask == nil)

        for video in [false, true] {
            for ready in [false, true] {
                var events: [String] = []
                var result: CaptureLifecycleCoordinator.LibraryReturnResult?
                let (started, startedContinuation) = AsyncStream<Void>.makeStream()
                let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
                let requestedTask = coordinator.depthAlbumPresentationDidChange(
                    isPresented: false, preparesVideoMode: video,
                    canResumeCamera: { true },
                    resumeAfterAnalysis: { events.append("resume") },
                    prepareVideoMode: { events.append("video"); return ready },
                    isCameraReady: { ready },
                    retryPendingCaptures: {
                        startedContinuation.yield(())
                        startedContinuation.finish()
                        for await _ in release {}
                    },
                    completion: { result = $0 }
                )
                let task = try #require(requestedTask)
                await task.value
                #expect(events == (video ? ["resume", "video"] : ["resume"]))
                #expect(result == (ready ? (video ? .videoReady : .cameraReady) : .failed))
                // Reaching this point proves recovery did not hold the return.
                var iterator = started.makeAsyncIterator()
                #expect(await iterator.next() != nil)
                releaseContinuation.finish()
                withExtendedLifetime(coordinator) {}
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func cancelledOrHiddenLibraryReturnCannotPrepareOrPublishLateFailure() async throws {
        for suspendVideo in [false, true] {
            for cancelTask in [false, true] {
                let coordinator = CaptureLifecycleCoordinator()
                let presentation = CameraLibraryReturnTestFixture()
                var events: [String] = []
                let (started, startedContinuation) = AsyncStream<Void>.makeStream()
                var release: CheckedContinuation<Void, Never>?
                let suspend: @MainActor () async -> Void = {
                    await withCheckedContinuation { continuation in
                        release = continuation
                        startedContinuation.yield(())
                        startedContinuation.finish()
                    }
                }
                let requestedTask = coordinator.depthAlbumPresentationDidChange(
                    isPresented: false, preparesVideoMode: true,
                    canResumeCamera: { presentation.canResumeCamera },
                    resumeAfterAnalysis: {
                        events.append("resume")
                        if !suspendVideo { await suspend() }
                    },
                    prepareVideoMode: {
                        events.append("video")
                        if suspendVideo { await suspend() }
                        return false
                    },
                    isCameraReady: { false },
                    retryPendingCaptures: { Issue.record("A retired return cannot retry") },
                    completion: { _ in Issue.record("A retired return cannot publish failure") }
                )
                let task = try #require(requestedTask)
                var iterator = started.makeAsyncIterator()
                #expect(await iterator.next() != nil)
                var needsForegroundResume = false
                if cancelTask {
                    coordinator.suspendForInactiveScene { needsForegroundResume = true }
                    #expect(needsForegroundResume, "Cancellation preserves an unfinished Library return")
                } else {
                    presentation.canResumeCamera = false
                }
                #expect(coordinator.isChangingCaptureMode)
                #expect(coordinator.prepareCaptureMode(to: .video,
                    prepareVideoMode: { Issue.record("Overlapping mode preparation"); return true },
                    restorePhotoMode: {}, completion: { _ in }) == nil)
                try #require(release).resume()
                await task.value
                #expect(events == (suspendVideo ? ["resume", "video"] : ["resume"]))
                #expect(!coordinator.isChangingCaptureMode)
                if cancelTask {
                    var recovered = false
                    let recovery = coordinator.depthAlbumPresentationDidChange(
                        isPresented: false, preparesVideoMode: true,
                        canResumeCamera: { presentation.canResumeCamera },
                        resumeAfterAnalysis: { needsForegroundResume = false },
                        prepareVideoMode: { true }, isCameraReady: { true }, retryPendingCaptures: {},
                        completion: { recovered = $0 == .videoReady })
                    await recovery?.value
                    #expect(recovered && !needsForegroundResume)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true]) @MainActor
    func libraryReturnWaitsForRetiredPreparationAndOwnsCompletion(startsAsModeChange: Bool) async throws {
        let coordinator = CaptureLifecycleCoordinator()
        var events: [String] = []
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let prepare: @MainActor () async -> Bool = {
            await withCheckedContinuation { continuation in
                release = continuation
                startedContinuation.yield(())
                startedContinuation.finish()
            }
            events.append("retired-video-finished")
            return false
        }
        let firstRequest: Task<Void, Never>?
        if startsAsModeChange {
            firstRequest = coordinator.prepareCaptureMode(to: .video,
                prepareVideoMode: prepare, restorePhotoMode: {},
                completion: { _ in Issue.record("The replaced mode change cannot publish failure") })
        } else {
            firstRequest = coordinator.depthAlbumPresentationDidChange(
                isPresented: false, preparesVideoMode: true,
                canResumeCamera: { true }, resumeAfterAnalysis: {},
                prepareVideoMode: prepare,
                isCameraReady: { false }, retryPendingCaptures: {},
                completion: { _ in Issue.record("The replaced return cannot publish failure") }
            )
        }
        let first = try #require(firstRequest)
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        let replacementRequest = coordinator.depthAlbumPresentationDidChange(
            isPresented: false, preparesVideoMode: true,
            canResumeCamera: { true },
            resumeAfterAnalysis: { events.append("current-resume") },
            prepareVideoMode: { events.append("current-video"); return true },
            isCameraReady: { true }, retryPendingCaptures: {},
            completion: {
                #expect($0 == .videoReady)
                #expect(coordinator.isChangingCaptureMode)
                events.append("current-completion")
            }
        )
        let replacement = try #require(replacementRequest)
        #expect(coordinator.isChangingCaptureMode)
        try #require(release).resume()
        await first.value
        await replacement.value
        #expect(events == ["retired-video-finished", "current-resume", "current-video", "current-completion"])
        #expect(!coordinator.isChangingCaptureMode)
    }

    @Test func shutterHapticsPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterHapticsEnabled)
        #expect(!CameraFeedbackPreferences.shutterHapticsEnabledKey.isEmpty)
    }

    @Test @MainActor func sharedCameraHapticsEnableAudioInputAllowanceOnlyWhenEnabled() {
        var allowsHapticsDuringAudioInput = false
        var audioInputAllowanceAttempts = 0
        let controller = CameraHapticFeedbackController(
            areHapticsAllowedDuringAudioInput: { allowsHapticsDuringAudioInput }
        ) {
            audioInputAllowanceAttempts += 1
            allowsHapticsDuringAudioInput = true
        }

        controller.setEnabled(false)
        controller.prepareForCameraInteraction()
        controller.prepareAdjustmentFeedback()
        controller.adjustmentChanged(style: .selection)
        controller.shutterAccepted()
        #expect(controller.hasPreparedCameraInteraction)
        #expect(!controller.isEnabled)
        #expect(audioInputAllowanceAttempts == 0)

        controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(audioInputAllowanceAttempts == 1)

        controller.prepareForCameraInteraction()
        controller.prepareAdjustmentFeedback()
        controller.adjustmentChanged(style: .selection)
        controller.shutterAccepted()
        #expect(audioInputAllowanceAttempts == 1)
    }

    @Test @MainActor func cameraHapticsRestoreRevokedAudioInputAllowanceBeforeFeedback() {
        var allowsHapticsDuringAudioInput = true
        var audioInputAllowanceAttempts = 0
        let controller = CameraHapticFeedbackController(
            areHapticsAllowedDuringAudioInput: { allowsHapticsDuringAudioInput }
        ) {
            audioInputAllowanceAttempts += 1
            allowsHapticsDuringAudioInput = true
        }

        controller.prepareForCameraInteraction()
        #expect(audioInputAllowanceAttempts == 0)

        for style in [CameraAdjustmentHapticStyle.selection, .integerTick, .zeroTick] {
            allowsHapticsDuringAudioInput = false
            controller.adjustmentChanged(style: style)
            #expect(allowsHapticsDuringAudioInput)
        }
        #expect(audioInputAllowanceAttempts == 3)

        allowsHapticsDuringAudioInput = false
        controller.shutterAccepted()
        #expect(allowsHapticsDuringAudioInput)
        #expect(audioInputAllowanceAttempts == 4)

        allowsHapticsDuringAudioInput = false
        controller.prepareAdjustmentFeedback()
        #expect(allowsHapticsDuringAudioInput)
        #expect(audioInputAllowanceAttempts == 5)
    }

    @Test @MainActor func cameraHapticsRetryAudioInputAllowanceAfterFailure() {
        enum AllowanceError: Error { case unavailable }
        var allowsHapticsDuringAudioInput = false
        var audioInputAllowanceAttempts = 0
        let controller = CameraHapticFeedbackController(
            areHapticsAllowedDuringAudioInput: { allowsHapticsDuringAudioInput }
        ) {
            audioInputAllowanceAttempts += 1
            if audioInputAllowanceAttempts == 1 {
                throw AllowanceError.unavailable
            }
            allowsHapticsDuringAudioInput = true
        }

        controller.prepareAdjustmentFeedback()
        #expect(!allowsHapticsDuringAudioInput)
        #expect(audioInputAllowanceAttempts == 1)

        controller.adjustmentChanged(style: .selection)
        #expect(allowsHapticsDuringAudioInput)
        #expect(audioInputAllowanceAttempts == 2)

        controller.adjustmentChanged(style: .integerTick)
        #expect(audioInputAllowanceAttempts == 2)
    }

    @Test func shutterSoundPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterSoundEnabled)
        #expect(!CameraFeedbackPreferences.shutterSoundEnabledKey.isEmpty)
    }

    @Test func releaseCapturePoliciesStayFixedWhileDebugOverridesRemainAvailable() {
        #expect(CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: CameraPhotoQualityPreference.speed.rawValue,
            allowsDebugOverride: true
        ) == .speed)
        #expect(CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: CameraPhotoQualityPreference.balanced.rawValue,
            allowsDebugOverride: true
        ) == .balanced)
        #expect(CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: CameraPhotoQualityPreference.speed.rawValue,
            allowsDebugOverride: false
        ) == .quality)

        #expect(!CameraDepthAvailabilityHintPreferences.resolvedShowsHints(
            storedValue: false,
            allowsDebugOverride: true
        ))
        #expect(CameraDepthAvailabilityHintPreferences.resolvedShowsHints(
            storedValue: false,
            allowsDebugOverride: false
        ))

        #expect(CameraFeedbackPreferences.shouldSuppressShutterSound(
            storedIsEnabled: false,
            suppressionSupported: true
        ))
        #expect(!CameraFeedbackPreferences.shouldSuppressShutterSound(
            storedIsEnabled: false,
            suppressionSupported: false
        ))
        #expect(!CameraFeedbackPreferences.shouldSuppressShutterSound(
            storedIsEnabled: true,
            suppressionSupported: true
        ))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func proVideoIsAProductionPathWithNoDebugPreference() throws {
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/Settings/DepthAnalyzerSettingsView.swift"
        )
        let preferencesSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraUXPreferences.swift"
        )
        let videoViewModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/ViewModel/CameraViewModel+VideoCapture.swift"
        )

        #expect(!settingsSource.contains("PRO Video Graph Probe"))
        #expect(!settingsSource.contains("CameraProVideoResearchPreferences"))
        #expect(!preferencesSource.contains("CameraProVideoResearchPreferences"))
        #expect(!cameraSource.contains("isProVideoResearchEnabled"))
        #expect(!cameraSource.contains("proVideoResearchPreferenceEnabled"))
        #expect(!cameraSource.contains("Video is unavailable in PRO mode"))
        #expect(!cameraSource.contains("PRO mode is available for photos"))
        #expect(cameraSource.contains("viewModel.isPhotographerModeActive"))
        #expect(cameraSource.contains("viewModel.isRearCameraActive"))
        #expect(cameraSource.contains("if selectedMode == .video"))
        #expect(cameraSource.contains("await viewModel.teardownPreparedVideoModeIfNeeded()"))
        #expect(cameraSource.contains("await viewModel.prepareVideoModeIfNeeded()"))

        #expect(videoViewModelSource.contains("handleVideoRecordingWriterFailure"))
        #expect(videoViewModelSource.contains("cancelVideoRecordingAfterWriterFailure"))
    }

    @Test func videoRecordingDelegateCleanupPreservesSharedManualFocusOutput() {
        let manualFocusStream = CameraManualFocusPreviewStream()
        let videoOutput = AVCaptureVideoDataOutput()
        let audioOutput = AVCaptureAudioDataOutput()
        let depthOutput = AVCaptureDepthDataOutput()
        let delegate = CameraVideoOutputCleanupDelegate()
        let callbackQueue = DispatchQueue(label: "tapcam.tests.recording-output-cleanup")
        videoOutput.setSampleBufferDelegate(delegate, queue: callbackQueue)
        audioOutput.setSampleBufferDelegate(delegate, queue: callbackQueue)
        depthOutput.setDelegate(delegate, callbackQueue: callbackQueue)

        #expect(videoOutput.sampleBufferDelegate === delegate)
        #expect(audioOutput.sampleBufferDelegate === delegate)
        #expect(depthOutput.delegate === delegate)
        #expect(videoOutput.sampleBufferCallbackQueue === callbackQueue)
        #expect(audioOutput.sampleBufferCallbackQueue === callbackQueue)
        #expect(depthOutput.delegateCallbackQueue === callbackQueue)

        CaptureSessionController.clearVideoRecordingOutputDelegates([
            videoOutput, audioOutput, depthOutput
        ])

        #expect(videoOutput.sampleBufferDelegate == nil)
        #expect(audioOutput.sampleBufferDelegate == nil)
        #expect(depthOutput.delegate == nil)
        #expect(videoOutput.sampleBufferCallbackQueue == nil)
        #expect(audioOutput.sampleBufferCallbackQueue == nil)
        #expect(depthOutput.delegateCallbackQueue == nil)
        #expect(manualFocusStream.videoOutput.sampleBufferDelegate === manualFocusStream)
        #expect(manualFocusStream.videoOutput.sampleBufferCallbackQueue === manualFocusStream.sharedVideoCallbackQueue)
    }

    @Test func videoRecordingOutputRemovalPreservesBaseSessionAndIsRepeatable() throws {
        let session = AVCaptureSession()
        let manualFocusStream = CameraManualFocusPreviewStream()
        let photoOutput = AVCapturePhotoOutput()
        let audioOutput = AVCaptureAudioDataOutput()
        do {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            try #require(session.canAddOutput(manualFocusStream.videoOutput))
            session.addOutputWithNoConnections(manualFocusStream.videoOutput)
            try #require(session.canAddOutput(photoOutput))
            session.addOutputWithNoConnections(photoOutput)
            try #require(session.canAddOutput(audioOutput))
            session.addOutputWithNoConnections(audioOutput)
        }
        #expect(session.outputs.count == 3)

        for _ in 0..<2 {
            session.beginConfiguration()
            CaptureSessionController.removeVideoRecordingOutputs(
                [audioOutput],
                audioInputAddedByRecording: nil,
                from: session
            )
            session.commitConfiguration()

            #expect(session.outputs.count == 2)
            #expect(session.outputs.contains(manualFocusStream.videoOutput))
            #expect(session.outputs.contains(photoOutput))
            #expect(session.inputs.isEmpty)
            #expect(session.connections.isEmpty)
            #expect(!session.isRunning)
            #expect(manualFocusStream.videoOutput.sampleBufferDelegate === manualFocusStream)
            #expect(manualFocusStream.videoOutput.sampleBufferCallbackQueue === manualFocusStream.sharedVideoCallbackQueue)
        }
    }

    @Test func resourceInitializationRequiresCameraInteractionAndUsableCatalog() {
        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .ready)

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: true,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .preparing(.cameraSession))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: false,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .preparing(.firstPreview))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: false,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .preparing(.primaryControls))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: false,
            hasUsableLibraryCatalog: true
        ) == .preparing(.haptics))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: false
        ) == .preparing(.libraryCatalog))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .denied,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: false,
            isDepthCaptureReady: false,
            hasPresentedFirstPreview: false,
            hasSafePrimaryControls: false,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: false
        ) == .preparing(.cameraAuthorization))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true,
            isSceneActive: false
        ) == .preparing(.cameraSession))
    }

    @Test func cameraRouteForegroundPreferenceDefaultsToDisabled() throws {
        let suiteName = "TAPCameraCapturePresentationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(!CameraRoutePreferences.defaultReturnToCameraOnForeground)
        #expect(!CameraRoutePreferences.returnToCameraOnForegroundKey.isEmpty)
        #expect(!CameraRoutePreferences.returnToCameraOnForeground(in: userDefaults))

        userDefaults.set(true, forKey: CameraRoutePreferences.returnToCameraOnForegroundKey)

        #expect(CameraRoutePreferences.returnToCameraOnForeground(in: userDefaults))
    }

    @Test @MainActor func foregroundCameraRouteRestoreRequiresEnabledPreferenceAndPriorInactivePhase() throws {
        let coordinator = CaptureLifecycleCoordinator()

        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: true
        ))
        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .inactive,
            returnsToCameraOnForeground: true
        ))
        #expect(coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: true
        ))

        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .background,
            returnsToCameraOnForeground: false
        ))
        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: false
        ))
    }

    @Test(arguments: [false, true])
    func cameraCaptureControlsStateLocksLibraryWhileCaptureWrites(isPreparingMovie: Bool) throws {
        let readyState = CameraCaptureControlsState(
            isShutterEnabled: !isPreparingMovie,
            isLibraryWriteInProgress: false,
            selectedMode: isPreparingMovie ? .video : .photo,
            isRecordingMovie: false,
            isPreparingCaptureMode: isPreparingMovie,
            showsProfessionalControls: false,
            isInteractionLocked: false,
            adjustmentControlState: nil,
            basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        #expect(readyState.canOpenTAPLibrary)
        #expect(readyState.recentThumbnailOpacity == 1)
        #expect(readyState.tapLibraryAccessibilityLabel == "Open TAPCamDepth album")
        #expect(readyState.tapLibraryHelpText == "Open TAPCamDepth album.")

        let writingState = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: true,
            selectedMode: isPreparingMovie ? .video : .photo,
            isRecordingMovie: false,
            isPreparingCaptureMode: isPreparingMovie,
            showsProfessionalControls: false,
            isInteractionLocked: false,
            adjustmentControlState: nil,
            basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        #expect(!writingState.canOpenTAPLibrary)
        #expect(writingState.recentThumbnailOpacity == 0.42)
        #expect(writingState.tapLibraryAccessibilityLabel == "Finishing capture write")
        #expect(writingState.tapLibraryHelpText == "TAP Library will be available after the current capture finishes writing.")
    }

    @Test(arguments: [false, true])
    func cameraCaptureControlsStateLocksLibraryWhileRecording(isPreparingMovie: Bool) {
        let state = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: false,
            selectedMode: .video,
            isRecordingMovie: true,
            isPreparingCaptureMode: isPreparingMovie,
            showsProfessionalControls: false,
            isInteractionLocked: false,
            adjustmentControlState: nil,
            basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )

        #expect(!state.canOpenTAPLibrary)
        #expect(state.tapLibraryAccessibilityLabel == "TAP Library unavailable during video capture")
        #expect(state.tapLibraryHelpText == "TAP Library will be available after video capture finishes.")
    }

    @Test func videoRecordingTimecodeFormatsElapsedAndLimit() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let state = CameraVideoRecordingTimecodeState(
            startedAt: startedAt,
            maximumDuration: 180
        )

        #expect(state.displayText(at: startedAt) == "0:00 / 3:00")
        #expect(state.displayText(at: startedAt.addingTimeInterval(1.9)) == "0:01 / 3:00")
        #expect(state.displayText(at: startedAt.addingTimeInterval(181)) == "3:00 / 3:00")
        #expect(state.displayText(at: startedAt.addingTimeInterval(-1)) == "0:00 / 3:00")
    }

    @Test func videoRecordingTimecodeFormatsHourDurations() {
        #expect(CameraVideoRecordingTimecodeState.formatted(seconds: 3_661) == "1:01:01")
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func videoRecordingTimecodeUsesLeafNativeUpdateBoundary() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/Controls/CameraVideoRecordingTimecodeView.swift"
        )

        #expect(source.contains("UIViewRepresentable"))
        #expect(source.contains("override var intrinsicContentSize"))
        #expect(source.contains("timecodeLabel.text = text"))
        #expect(!source.contains("TimelineView"))
        #expect(!source.contains("@Published"))
    }

    @Test func cameraPreviewStageStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraPreviewStageState(
            nativePreviewAspectRatio: 3.0 / 4.0,
            focalLengthOptions: [],
            shouldShowFocalLengthSelector: false,
            guideOverlayPreference: .ruleOfThirds,
            temporaryFocusEVOffset: 0.3,
            focusMode: .auto,
            focusRuntimeEvent: nil,
            focusMagnifierPreference: .brief,
            focusLoupePulseID: nil,
            viewfinderEdgeToastMessage: nil,
            contentRotation: .zero,
            transitionPresentation: .hidden,
            previewReadinessGeneration: 0
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraPreviewFocusPointClampsInvalidCoordinates() {
        let nonFinitePoint = CameraPreviewFocusPoint(x: .nan, y: .infinity)

        #expect(CameraPreviewFocusPoint(x: -1, y: 2) == CameraPreviewFocusPoint(x: 0, y: 1))
        #expect(nonFinitePoint == CameraPreviewFocusPoint(x: 0.5, y: 0.5))
    }

    @Test func cameraFocusLockRequestSeparatesDisplayAndCapturePoints() throws {
        let displayPoint = CameraPreviewFocusPoint(x: 0.25, y: 0.75)
        let capturePoint = CameraPreviewFocusPoint(x: 0.3, y: 0.65)
        let lockCurrent = CameraFocusLockRequest.lockCurrent(displayPoint: displayPoint)
        let refocusAndLock = CameraFocusLockRequest.refocusAndLock(
            displayPoint: displayPoint,
            capturePoint: capturePoint
        )

        #expect(lockCurrent.displayPoint == displayPoint)
        #expect(lockCurrent.capturePoint == nil)
        #expect(refocusAndLock.displayPoint == displayPoint)
        #expect(refocusAndLock.capturePoint == capturePoint)
    }

    @Test func cameraFocusTargetOverlayStatePersistsUntilRuntimeInvalidation() throws {
        let point = CameraPreviewFocusPoint(x: 0.25, y: 0.75)
        let focusing = CameraFocusTargetOverlay.focusing(at: point)
        let initialFocusCycle = focusing.applyingRuntimeEvent(.focusStarted)
        let focused = try #require(focusing.applyingRuntimeEvent(.focusSettled))
        let invalidatedBySubjectChange = focused.applyingRuntimeEvent(.subjectAreaChanged)
        let invalidatedByRuntimeFocusCycle = focused.applyingRuntimeEvent(.focusStarted)
        let locked = focused.lockedOverlay()
        let ignoredRuntimeCycle = locked.applyingRuntimeEvent(.focusStarted)
        let movedLockPoint = CameraPreviewFocusPoint(x: 0.8, y: 0.2)
        let movedLocked = focused.lockedOverlay(at: movedLockPoint)
        let previewSize = CGSize(width: 300, height: 400)
        let insideCurrentFrame = focused.contains(
            CameraPreviewFocusPoint(x: 0.25 + 35.0 / 300.0, y: 0.75),
            previewSize: previewSize,
            sideLength: 72
        )
        let outsideCurrentFrame = focused.contains(
            CameraPreviewFocusPoint(x: 0.25 + 37.0 / 300.0, y: 0.75),
            previewSize: previewSize,
            sideLength: 72
        )

        #expect(focusing.point == point)
        #expect(focusing.phase == .focusing)
        #expect(initialFocusCycle == focusing)
        #expect(focused.id == focusing.id)
        #expect(focused.phase == .focused)
        #expect(invalidatedBySubjectChange == nil)
        #expect(invalidatedByRuntimeFocusCycle == nil)
        #expect(locked.phase == .locked)
        #expect(ignoredRuntimeCycle == locked)
        #expect(movedLocked.point == movedLockPoint)
        #expect(movedLocked.phase == .locked)
        #expect(insideCurrentFrame)
        #expect(!outsideCurrentFrame)
    }

    @Test func cameraFocalLengthDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraFocalLengthDisplayOption(
            selectionToken: "fov-0",
            displayName: "24 mm Wide",
            numericLabel: "24",
            unitLabel: "mm",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "camera",
            "device",
            "profile",
            "source",
            "depth",
            "zoom",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraGuideOverlayPreferenceDefaultsToOffAndResolvesSafely() throws {
        #expect(CameraGuideOverlayPreference.defaultValue == .off)
        #expect(CameraGuideOverlayPreference.resolved(rawValue: "ruleOfThirds") == .ruleOfThirds)
        #expect(CameraGuideOverlayPreference.resolved(rawValue: "centerCross") == .centerCross)
        #expect(CameraGuideOverlayPreference.resolved(rawValue: "unexpected") == .off)
        #expect(CameraViewfinderHighlightPreference.defaultValue == .yellow)
        #expect(CameraViewfinderHighlightPreference.resolved(rawValue: "titian") == .titian)
        #expect(CameraViewfinderHighlightPreference.resolved(rawValue: "unexpected") == .yellow)
        #expect(CameraViewfinderHighlightPreference.titian.title == "Akane")
    }

    @Test func cameraCaptureModeOptionEnablesPhotoAndVideo() throws {
        #expect(CameraCaptureModeOption.allCases.map(\.title) == ["PHOTO", "VIDEO"])
        #expect(
            CameraCaptureModeOption.allCases.map(\.accessibilityLabel)
                == ["Photo mode", "Video mode"]
        )
    }

    @Test func cameraChromeControlModesKeepExpectedDefaultsAndCycleOrder() throws {
        #expect(CameraFocusControlMode.auto.toggled == .manual)
        #expect(CameraFocusControlMode.manual.toggled == .auto)
        #expect(CameraFlashControlMode.defaultValue == .auto)
        #expect(CameraFlashControlMode.defaultStartupPolicy == .defaultOn)
        #expect(CameraFlashControlMode.auto.next == .on)
        #expect(CameraFlashControlMode.on.next == .off)
        #expect(CameraFlashControlMode.off.next == .auto)
        #expect(CameraFlashControlMode.auto.captureFlashMode == .auto)
        #expect(CameraFlashControlMode.on.captureFlashMode == .on)
        #expect(CameraFlashControlMode.off.captureFlashMode == .off)
        #expect(CameraViewfinderControlDefaultPolicy.allCases.map(\.title) == [
            "Default Off",
            "Default On",
            "Remember Last State"
        ])
    }

    @Test func viewfinderControlDefaultPoliciesResolveStartupState() throws {
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOff.rawValue,
            lastModeRawValue: CameraFlashControlMode.on.rawValue
        ) == .off)
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOn.rawValue,
            lastModeRawValue: CameraFlashControlMode.off.rawValue
        ) == .auto)
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            lastModeRawValue: CameraFlashControlMode.on.rawValue
        ) == .on)
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: "unexpected",
            lastModeRawValue: CameraFlashControlMode.off.rawValue
        ) == .auto)

        #expect(!CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOff.rawValue,
            lastIsEnabled: true
        ))
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOn.rawValue,
            lastIsEnabled: false
        ))
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            lastIsEnabled: true
        ))
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: "unexpected",
            lastIsEnabled: true
        ))
    }

    @Test func viewfinderControlStartupPoliciesReadPersistedDefaultsAndLastState() throws {
        let suiteName = "TAPCameraViewfinderDefaultPolicyTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraFlashControlMode.resolvedStartupMode(in: userDefaults) == .auto)
        #expect(!CameraLivePhotoPreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            forKey: CameraFlashControlMode.startupPolicyKey
        )
        userDefaults.set(CameraFlashControlMode.on.rawValue, forKey: CameraFlashControlMode.lastModeKey)
        #expect(CameraFlashControlMode.resolvedStartupMode(in: userDefaults) == .on)

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            forKey: CameraLivePhotoPreferences.startupPolicyKey
        )
        userDefaults.set(true, forKey: CameraLivePhotoPreferences.lastEnabledKey)
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(in: userDefaults))

    }

    @Test func cameraCaptureDataUsePreferencesDefaultToLocationOnMicrophoneOff() throws {
        let suiteName = "TAPCameraCaptureDataUsePreferencesTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraCaptureDataUsePreferences.usesLocationData(in: userDefaults))
        #expect(!CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))

        userDefaults.set(false, forKey: CameraCaptureDataUsePreferences.usesLocationDataKey)
        userDefaults.set(true, forKey: CameraCaptureDataUsePreferences.usesMicrophoneDataKey)

        #expect(!CameraCaptureDataUsePreferences.usesLocationData(in: userDefaults))
        #expect(CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
    }

    @Test func firstMicrophoneAuthorizationEnablesDataUseOnlyWithoutAPriorChoice() throws {
        let suiteName = "TAPCameraMicrophoneFirstAuthorizationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))
        #expect(CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
        #expect(!CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))

        userDefaults.set(false, forKey: CameraCaptureDataUsePreferences.usesMicrophoneDataKey)
        #expect(!CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))
        #expect(!CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
    }

    @Test func cameraAdjustmentControlStatePublishesCapabilityGatedRanges() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            minimumFocusDistanceMillimeters: 125,
            isoRange: .init(minimum: 64, maximum: 1_250),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 8_000.0, maximum: 0.5)
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: .iso,
            exposureMode: .auto(globalBias: 0.3),
            focusMode: .manual,
            draft: .init(iso: 400.4, shutterDurationSeconds: 1.0 / 125.0, lensPosition: 0.456)
        )
        let shutterPosition = state.exposure.shutterPosition(for: 1.0 / 120.0)
        let resolvedShutter = state.exposure.shutterDuration(forPosition: shutterPosition)

        #expect(state.exposure.isAvailable)
        #expect(state.focus.isAvailable)
        #expect(state.exposure.isoRange == 64...1_250)
        #expect(state.activeControl == .iso)
        #expect(state.exposure.evTitle == "EV")
        #expect(state.exposure.evValue == "+0.3")
        #expect(state.exposure.isoBadge == "A")
        #expect(state.exposure.shutterBadge == "A")
        #expect(abs(resolvedShutter - (1.0 / 125.0)) < 0.0001)
        #expect(state.exposure.isoScale.label(for: 400.4) == "400")
        #expect(state.exposure.shutterScale.label(for: 1.0 / 120.0) == "1/125")
        #expect(state.exposure.isoAutomationState == .automatic)
        #expect(state.exposure.shutterAutomationState == .automatic)
        #expect(state.focus.lensPositionLabel(for: 0.456) == "0.46")
        #expect(state.focus.lensPositionValue == "0.46")
        #expect(state.focus.automationState == .manual)
        #expect(state.focus.badge == "M")
    }

    @Test func cameraAdjustmentControlStateShowsMeterForCustomExposure() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .custom(meterOffset: -0.7),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )

        #expect(state.exposure.isCustom)
        #expect(state.exposure.evTitle == "Meter")
        #expect(state.exposure.evValue == "-0.7")
        #expect(state.exposure.isoBadge == "M")
        #expect(state.exposure.shutterBadge == "M")
    }

    @Test func cameraAdjustmentControlStateDisablesUnsupportedRows() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsCustomExposure: false,
            supportsCustomLensPosition: false,
            minimumFocusDistanceMillimeters: nil,
            isoRange: .init(minimum: 100, maximum: 100),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 60.0, maximum: 1.0 / 60.0)
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .auto(globalBias: 0),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )

        #expect(!state.exposure.isAvailable)
        #expect(!state.focus.isAvailable)
        #expect(state.focus.lensPositionValue == "0.50")
    }

    @Test func cameraAdjustmentControlStateCanDisableManualFocusDespiteCapabilitySupport() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsLockedFocus: true,
            supportsCustomLensPosition: true
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .auto(globalBias: 0),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability),
            allowsManualFocusControl: false
        )

        #expect(capability.focus.supportsManualLensPosition)
        #expect(!state.focus.isAvailable)
    }

    @Test func cameraAdjustmentControlStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: .focus,
            exposureMode: .auto(globalBias: 0),
            focusMode: .manual,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data",
            "device"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }
    @Test func cameraFirstStagePreferencesExposeExplicitStorageKeysAndDefaults() throws {
        #expect(CameraEVPreferences.defaultResetOnAppLaunch)
        #expect(!CameraEVPreferences.resetOnAppLaunchKey.isEmpty)
        #expect(CameraEVPreferences.defaultGlobalBias == 0)
        #expect(!CameraEVPreferences.globalBiasKey.isEmpty)
        #expect(CameraEVPreferences.minimumGlobalBias < CameraEVPreferences.maximumGlobalBias)
        #expect(CameraPhotoQualityPreference.defaultValue == .quality)
        #expect(!CameraPhotoQualityPreference.storageKey.isEmpty)
        #expect(CameraFlashControlMode.defaultValue == .auto)
        #expect(CameraFlashControlMode.defaultStartupPolicy == .defaultOn)
        #expect(!CameraFlashControlMode.startupPolicyKey.isEmpty)
        #expect(CameraFlashControlMode.defaultLastMode == .auto)
        #expect(!CameraFlashControlMode.lastModeKey.isEmpty)
        #expect(CameraDepthAvailabilityHintPreferences.defaultShowsHints)
        #expect(!CameraDepthAvailabilityHintPreferences.showsHintsKey.isEmpty)
        #expect(CameraFocusMagnifierPreference.defaultValue == .brief)
        #expect(!CameraFocusMagnifierPreference.storageKey.isEmpty)
        #expect(CameraLivePhotoPreferences.defaultStartupPolicy == .rememberLastState)
        #expect(!CameraLivePhotoPreferences.startupPolicyKey.isEmpty)
        #expect(!CameraLivePhotoPreferences.defaultLastEnabled)
        #expect(!CameraLivePhotoPreferences.lastEnabledKey.isEmpty)
        #expect(CameraIdleTimerPreferences.defaultKeepScreenAwake)
        #expect(!CameraIdleTimerPreferences.keepScreenAwakeKey.isEmpty)
    }

    @Test func cameraEVPreferenceClampsAndResetsPerLaunchWhenEnabled() throws {
        let suiteName = "TAPCameraEVPreferenceTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraEVPreferences.clampedBias(-99) == CameraEVPreferences.minimumGlobalBias)
        #expect(CameraEVPreferences.clampedBias(99) == CameraEVPreferences.maximumGlobalBias)
        #expect(CameraEVPreferences.clampedBias(.nan) == CameraEVPreferences.defaultGlobalBias)

        userDefaults.set(true, forKey: CameraEVPreferences.resetOnAppLaunchKey)
        userDefaults.set(1.2, forKey: CameraEVPreferences.globalBiasKey)
        userDefaults.set(-1, forKey: CameraEVPreferences.launchResetProcessIDKey)

        #expect(CameraEVPreferences.resolvedLaunchBias(in: userDefaults) == 0)
        #expect(userDefaults.double(forKey: CameraEVPreferences.globalBiasKey) == 0)

        CameraEVPreferences.persistGlobalBias(1.4, in: userDefaults)

        #expect(CameraEVPreferences.resolvedLaunchBias(in: userDefaults) == 1.4)
    }

    @Test func cameraEVPreferenceCanPersistAcrossColdLaunchWhenResetDisabled() throws {
        let suiteName = "TAPCameraEVPersistTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(false, forKey: CameraEVPreferences.resetOnAppLaunchKey)
        userDefaults.set(-0.7, forKey: CameraEVPreferences.globalBiasKey)

        #expect(CameraEVPreferences.resolvedLaunchBias(in: userDefaults) == -0.7)
    }

    @Test func cameraBasicEVControlStateClampsAndFormatsCompactValue() throws {
        let negative = CameraBasicEVControlState(bias: -99, isStripVisible: true)
        let zero = CameraBasicEVControlState(bias: 0.01, isStripVisible: false)
        let positive = CameraBasicEVControlState(bias: 1.24, isStripVisible: false)

        #expect(negative.bias == CameraEVPreferences.minimumGlobalBias)
        #expect(negative.compactValue == "-2.0")
        #expect(negative.isStripVisible)
        #expect(zero.compactValue == "0.0")
        #expect(positive.compactValue == "+1.2")
    }

    @Test func cameraTemporaryFocusEVPreferenceClampsOffset() throws {
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(-99) == CameraTemporaryFocusEVPreferences.minimumOffset)
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(99) == CameraTemporaryFocusEVPreferences.maximumOffset)
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(.nan) == 0)
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(0.7) == 0.7)
    }

    @Test func captureScoreSummaryUsesPublicSafeCaptureFacts() throws {
        let signedDepthScore = CaptureScoreSummary.make(
            depthAvailability: .available,
            fileContainer: .heic,
            photoQualityLevel: .quality,
            signatureStatus: .signed(keyID: "secret-key-id")
        )
        let noDepthPendingScore = CaptureScoreSummary.make(
            depthAvailability: .unavailable,
            fileContainer: .jpeg,
            photoQualityLevel: .speed,
            signatureStatus: .pending(reason: "secret pending reason")
        )

        #expect(signedDepthScore.value == 100)
        #expect(signedDepthScore.detail == "Depth available · HEIC · Quality · Capture signed · Analysis ready")
        #expect(noDepthPendingScore.value < signedDepthScore.value)
        #expect(noDepthPendingScore.detail.contains("Depth unavailable"))
        for text in [
            signedDepthScore.detail,
            signedDepthScore.accessibilityText,
            noDepthPendingScore.detail,
            noDepthPendingScore.accessibilityText
        ] {
            for forbidden in ["secret", "key-id", "captureID", "asset", "file://", "/private/"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }

    @Test func captureScoreIntentServicePublishesLatestPublicSafeSnapshot() async throws {
        let olderScore = CaptureScoreSummary.make(
            depthAvailability: .unavailable,
            fileContainer: .jpeg,
            photoQualityLevel: .speed,
            signatureStatus: .pending(reason: "private reason")
        )
        let latestScore = CaptureScoreSummary.make(
            depthAvailability: .available,
            fileContainer: .heic,
            photoQualityLevel: .quality,
            signatureStatus: .signed(keyID: "private-key")
        )
        let olderRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "raw-older-capture",
            capturedAt: Date(timeIntervalSince1970: 10),
            status: .pending,
            photoQualityLevel: .speed,
            captureScoreSummary: olderScore
        )
        let latestRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "raw-latest-capture",
            capturedAt: Date(timeIntervalSince1970: 20),
            status: .exported,
            assetLocalIdentifier: "raw-asset-id",
            captureScoreSummary: latestScore
        )
        let service = CaptureScoreIntentService(
            records: {
                [olderRecord, latestRecord]
            },
            token: { rawValue in
                "token-\(rawValue.hashValue.magnitude)"
            }
        )

        let snapshot = try #require(try await service.latestScore())

        #expect(snapshot.summary == latestScore)
        #expect(snapshot.statusLabel == "Exported")
        #expect(snapshot.subtitle == "100/100 · Strong · Exported")
        #expect(!snapshot.id.contains("raw-latest-capture"))
        #expect(!snapshot.dialogText.contains("raw-latest-capture"))
        #expect(!snapshot.dialogText.contains("raw-asset-id"))
        #expect(!snapshot.dialogText.localizedCaseInsensitiveContains("private-key"))

        let matchedSnapshots = try await service.scoreSnapshots(matching: [snapshot.id])
        #expect(matchedSnapshots == [snapshot])
    }

    @Test func captureScoreQuerySuggestsRecentPublicSafeEntities() async throws {
        let score = CaptureScoreSummary.make(
            depthAvailability: .available,
            fileContainer: .heic,
            photoQualityLevel: .balanced,
            signatureStatus: .signed(keyID: "private-key")
        )
        let records = (0..<6).map { index in
            TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: "raw-capture-\(index)",
                capturedAt: Date(timeIntervalSince1970: Double(index)),
                status: .exported,
                captureScoreSummary: score
            )
        }
        let query = CaptureScoreQuery(service: CaptureScoreIntentService(
            records: {
                records
            },
            token: { rawValue in
                "token-\(rawValue.hashValue.magnitude)"
            }
        ))

        let suggestedEntities = try await query.suggestedEntities()

        #expect(suggestedEntities.count == 5)
        #expect(suggestedEntities.map(\.snapshot.capturedAt) == records.reversed().prefix(5).map(\.capturedAt))
        for entity in suggestedEntities {
            #expect(!entity.snapshot.subtitle.isEmpty)
            #expect(!entity.id.contains("raw-capture"))
            #expect(!entity.snapshot.dialogText.contains("raw-capture"))
            #expect(!entity.snapshot.dialogText.localizedCaseInsensitiveContains("private-key"))
        }
    }

    @Test func tapCamIntentHandoffStoreConsumesOnlyFreshDestinationRequests() throws {
        let suiteName = "TAPCamIntentHandoffTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = TAPCamIntentHandoffStore(userDefaults: userDefaults)
        let now = Date(timeIntervalSince1970: 1_000)

        store.saveHandoff(TAPCamIntentHandoff(destination: .tapLibrary, requestedAt: now))
        #expect(store.loadAndClearHandoff(now: now.addingTimeInterval(20))?.destination == .tapLibrary)
        #expect(store.loadAndClearHandoff(now: now.addingTimeInterval(21)) == nil)

        store.saveHandoff(TAPCamIntentHandoff(
            destination: .camera,
            requestedAt: now.addingTimeInterval(-TAPCamIntentHandoff.defaultTimeToLive - 1)
        ))
        #expect(store.loadAndClearHandoff(now: now) == nil)
    }

    @Test func cameraIdleTimerPolicyOnlyDisablesIdleTimerForActiveVisibleCamera() throws {
        #expect(CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: false,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: false,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: false,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: false,
            isSettingsPresented: false,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: true,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: false,
            isLibraryPresented: true
        ))
    }

    @Test func cameraViewfinderChromeStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraViewfinderChromeState(
            flashMode: .auto,
            isFlashAvailable: true,
            isLivePhotoAvailable: false,
            isLivePhotoEnabled: false,
            proModeState: .standard,
            basicEVState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    #if DEBUG
    @Test func cameraPreviewDebugStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraPreviewDebugState(
            isDepthReady: true,
            activeCameraDisplayName: "Debug camera",
            statusMessage: "Debug status",
            recentMetrics: [],
            queuedJobCount: 0,
            depthOptions: [],
            showsZoomControl: false,
            zoomOptions: [],
            selectedZoomFactor: 1,
            fovLabel: "24mm",
            sliderRange: 1...1,
            isSliderEnabled: false,
            manualControlLines: []
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "route",
            "data",
            "session",
            "controller",
            "capability",
            "plan",
            "profile",
            "format",
            "device"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraDebugDepthDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraDebugDepthDisplayOption(
            selectionToken: "debug-depth-0",
            displayName: "Wide",
            iconName: "camera",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "device",
            "profile",
            "source",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "plan"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraDebugZoomDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraDebugZoomDisplayOption(
            selectionToken: "debug-zoom-0",
            displayName: "1x",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "device",
            "profile",
            "source",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "plan"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }
    #endif
}

private nonisolated final class CameraVideoOutputCleanupDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureDepthDataOutputDelegate {}

private nonisolated struct CameraStoppedVideoPosterGenerator: LibraryVideoPosterGenerating {
    let generate: @MainActor @Sendable () -> Data

    func posterData(for videoURL: URL, cacheKey: String, pixelLength: Int) async throws -> Data {
        await generate()
    }
}

@MainActor
private final class CameraLibraryReturnTestFixture {
    var canResumeCamera = true
}

@MainActor
private final class CameraChromeOrientationTestFixture {
    let notificationCenter = NotificationCenter()
    var orientation: UIDeviceOrientation = .portrait
    var orientationReadCount = 0
    var events: [String] = []

    func makeController() -> CameraChromeOrientationController {
        CameraChromeOrientationController(
            notificationCenter: notificationCenter,
            readOrientation: {
                self.orientationReadCount += 1
                return self.orientation
            },
            setOrientationNotificationsEnabled: { isEnabled in
                self.events.append(isEnabled ? "startChromeOrientation" : "stopChromeOrientation")
            }
        )
    }

    func postOrientation(_ orientation: UIDeviceOrientation) async throws {
        self.orientation = orientation
        notificationCenter.post(name: UIDevice.orientationDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(200))
    }
}
