//
//  TAPVideoDepthPlaybackPolicyTests.swift
//  TAPCamDemoTests
//

import Foundation
import ImageIO
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPVideoDepthPlaybackPolicyTests {
    @Test @MainActor
    func videoOriginalProgressCoalescerPreservesEndpointsAndDropsCallbackFlood() async {
        let recorder = TAPVideoPlaybackProgressRecorder()
        let coalescer = TAPVideoPlaybackProgressCoalescer(
            minimumInterval: .milliseconds(1)
        ) { progress in
            recorder.append(progress)
        }

        coalescer.submit(0)
        for index in 1...500 {
            coalescer.submit(Double(index) / 501)
        }
        coalescer.submit(1)
        await coalescer.finish()

        #expect(recorder.values.compactMap(\.self) == [0, 1])
    }

    @Test @MainActor
    func videoOriginalProgressCoalescerFlushesNewestIntermediateValue() async {
        let recorder = TAPVideoPlaybackProgressRecorder()
        let coalescer = TAPVideoPlaybackProgressCoalescer(
            minimumInterval: .milliseconds(1)
        ) { progress in
            recorder.append(progress)
        }

        coalescer.submit(0)
        coalescer.submit(0.2)
        coalescer.submit(0.4)
        await coalescer.finish()

        #expect(recorder.values.compactMap(\.self) == [0, 0.4])
    }

    @Test @MainActor
    func cancelledVideoOriginalProgressCoalescerDropsBufferedValue() async throws {
        let recorder = TAPVideoPlaybackProgressRecorder()
        let coalescer = TAPVideoPlaybackProgressCoalescer(
            minimumInterval: .milliseconds(100)
        ) { progress in
            recorder.append(progress)
        }

        coalescer.submit(0)
        for _ in 0..<50 where recorder.values.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(recorder.values.compactMap(\.self) == [0])

        coalescer.submit(0.5)
        coalescer.cancel()
        try await Task.sleep(for: .milliseconds(125))

        #expect(recorder.values.compactMap(\.self) == [0])
    }

    @Test func originalResourceLeaseRetainsTemporaryFileAfterViewerRelease() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("original.mp4")
        try Data("stable-video-original".utf8).write(to: fileURL)

        var owner: TAPVideoOriginalResourceOwner? = try TAPVideoOriginalResourceOwner(
            mediaID: .photosAsset("stable-video-original"),
            origin: .photosAsset(assetID: "stable-video-original"),
            fileURL: fileURL,
            managedTemporaryFile: LibraryManagedTemporaryFile(
                fileURL: fileURL,
                directoryURL: directoryURL
            )
        )
        var lease: TAPVideoOriginalResourceLease? = owner?.acquireLease()
        owner = nil

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: try #require(lease).fileURL) == Data("stable-video-original".utf8))

        lease = nil
        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test func originalResourceOwnerRejectsUnavailableFiles() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let missingURL = directoryURL.appendingPathComponent("missing.mp4")
        let emptyURL = directoryURL.appendingPathComponent("empty.mp4")
        try Data().write(to: emptyURL)

        #expect(throws: TAPVideoOriginalResourceError.unavailableVideo) {
            _ = try TAPVideoOriginalResourceOwner(
                mediaID: .photosAsset("missing-video"),
                origin: .photosAsset(assetID: "missing-video"),
                fileURL: missingURL
            )
        }
        #expect(throws: TAPVideoOriginalResourceError.unavailableVideo) {
            _ = try TAPVideoOriginalResourceOwner(
                mediaID: .photosAsset("directory-video"),
                origin: .photosAsset(assetID: "directory-video"),
                fileURL: directoryURL
            )
        }
        #expect(throws: TAPVideoOriginalResourceError.unavailableVideo) {
            _ = try TAPVideoOriginalResourceOwner(
                mediaID: .photosAsset("empty-video"),
                origin: .photosAsset(assetID: "empty-video"),
                fileURL: emptyURL
            )
        }
    }

    @Test @MainActor func pendingSignedOriginalRefreshClaimIsSingleFlight() {
        let session = Self.makePendingRefreshSession()

        let refreshID = session.claimPendingSignedOriginalRefresh()
        #expect(refreshID != nil)
        #expect(session.isPendingSignedOriginalRefreshInFlight)
        #expect(session.claimPendingSignedOriginalRefresh() == nil)
        #expect(session.isPendingSignedOriginalRefreshInFlight)
    }

    @Test @MainActor func cancelledPendingSignedOriginalRefreshClaimCanBeRetried() throws {
        let session = Self.makePendingRefreshSession()

        let refreshID = try #require(session.claimPendingSignedOriginalRefresh())
        session.cancelPendingSignedOriginalRefreshClaim(refreshID)
        #expect(!session.isPendingSignedOriginalRefreshInFlight)
        #expect(session.claimPendingSignedOriginalRefresh() != nil)
    }

    @Test @MainActor
    func stalePendingSignedOriginalRefreshTokenCannotCancelOrStartANewerClaim() throws {
        let session = Self.makePendingRefreshSession()
        let staleID = try #require(session.claimPendingSignedOriginalRefresh())

        // A retry invalidates the suspended actor lookup associated with the
        // old token. A later notification may then claim the same session.
        session.retryCurrentFetch()
        let currentID = try #require(session.claimPendingSignedOriginalRefresh())
        let requestBeforeStaleCallbacks = try #require(session.requestKey)

        session.cancelPendingSignedOriginalRefreshClaim(staleID)
        #expect(session.pendingSignedOriginalRefreshID == currentID)
        #expect(!session.startClaimedPendingSignedOriginalRefresh(staleID))
        #expect(session.requestKey == requestBeforeStaleCallbacks)

        #expect(session.startClaimedPendingSignedOriginalRefresh(currentID))
        #expect(session.requestKey?.generation == requestBeforeStaleCallbacks.generation + 1)
    }

    @Test @MainActor
    func startedPendingSignedOriginalRefreshRejectsDuplicateNotificationWithoutAnotherRequest() throws {
        let session = Self.makePendingRefreshSession()
        let initialRequest = try #require(session.requestKey)

        let refreshID = try #require(session.claimPendingSignedOriginalRefresh())
        #expect(session.startClaimedPendingSignedOriginalRefresh(refreshID))
        let replacementRequest = try #require(session.requestKey)
        #expect(replacementRequest.generation == initialRequest.generation + 1)

        // A repeated status-only queue notification must fail the claim before
        // it can start another replacement and tear down playback a second time.
        #expect(session.claimPendingSignedOriginalRefresh() == nil)
        #expect(session.requestKey == replacementRequest)
        #expect(session.isPendingSignedOriginalRefreshInFlight)
    }

    @Test func pausedAtZeroProbeUsesABoundedForwardWindow() throws {
        let window = try #require(TAPVideoDepthMetadataProbePolicy.window(
            playbackTimeSeconds: 0,
            staleToleranceSeconds: 0.1,
            leadToleranceSeconds: 0.08,
            assetDurationSeconds: 12
        ))

        #expect(window.startSeconds == 0)
        #expect(abs(window.endSeconds - 0.08) < 0.000_001)
    }

    @Test func seekProbeBoundsLookBehindAndChoosesNearestSample() throws {
        let window = try #require(TAPVideoDepthMetadataProbePolicy.window(
            playbackTimeSeconds: 10,
            staleToleranceSeconds: 0.1,
            leadToleranceSeconds: 0.08,
            assetDurationSeconds: 12
        ))
        let timestamps = [9.7, 9.92, 10.03, 10.2]
        let index = try #require(TAPVideoDepthMetadataProbePolicy.nearestCandidateIndex(
            timestamps: timestamps,
            playbackTimeSeconds: 10,
            window: window
        ))

        #expect(abs(window.startSeconds - 9.9) < 0.000_001)
        #expect(abs(window.endSeconds - 10.08) < 0.000_001)
        #expect(index == 2)
    }

    @Test func probePolicyRejectsOutOfWindowSamplesAndStaleEvents() throws {
        let window = try #require(TAPVideoDepthMetadataProbePolicy.window(
            playbackTimeSeconds: 5,
            staleToleranceSeconds: 0.1,
            leadToleranceSeconds: 0.08,
            assetDurationSeconds: 5
        ))

        #expect(window.startSeconds == 4.9)
        #expect(window.endSeconds == 5)
        #expect(TAPVideoDepthMetadataProbePolicy.nearestCandidateIndex(
            timestamps: [4.7, 5.2],
            playbackTimeSeconds: 5,
            window: window
        ) == nil)
        #expect(TAPVideoDepthPipelineGenerationPolicy.accepts(
            eventGeneration: 7,
            currentGeneration: 7
        ))
        #expect(!TAPVideoDepthPipelineGenerationPolicy.accepts(
            eventGeneration: 6,
            currentGeneration: 7
        ))
    }

    @Test func typedPipelineEventsPreserveGenerationAndFailureReason() {
        let event = TAPVideoDepthPipelineEvent(
            generation: 11,
            payload: .decodeFailed(
                reason: .decode,
                presentationTimeSeconds: 3.5
            )
        )

        #expect(event.generation == 11)
        switch event.payload {
        case .decodeFailed(let reason, let presentationTimeSeconds):
            #expect(reason == .decode)
            #expect(presentationTimeSeconds == 3.5)
        case .frame, .noSample:
            Issue.record("expected a typed decode-failure event")
        }
    }

    @Test @MainActor func frameCacheNeverExceedsItsByteBudget() throws {
        let cache = TAPVideoDepthFrameCache(
            maximumRetainedBytes: 12,
            lookBehindSeconds: 10,
            lookAheadSeconds: 10
        )

        #expect(cache.insert(Self.frame(index: 0, time: 0, retainedBytes: 6), around: 0.2))
        #expect(cache.insert(Self.frame(index: 1, time: 0.1, retainedBytes: 6), around: 0.2))
        #expect(cache.insert(Self.frame(index: 2, time: 0.2, retainedBytes: 6), around: 0.2))

        #expect(cache.retainedByteCount == 12)
        #expect(cache.frames.map(\.frameIndex) == [1, 2])
        #expect(!cache.insert(Self.frame(index: 3, time: 0.3, retainedBytes: 13), around: 0.3))
        #expect(cache.retainedByteCount == 12)
    }

    @Test @MainActor func frameCacheClampsInjectedBudgetToThe24MiBReleaseMaximum() {
        let cache = TAPVideoDepthFrameCache(
            maximumRetainedBytes: Int.max,
            lookBehindSeconds: 10,
            lookAheadSeconds: 10
        )

        #expect(
            cache.maximumRetainedBytes
                == TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes
        )
        #expect(!cache.insert(
            Self.frame(
                index: 0,
                time: 0,
                retainedBytes: TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes + 1
            ),
            around: 0
        ))
    }

    @Test @MainActor func frameSelectionClearsAcrossARealTimestampGap() throws {
        let cache = TAPVideoDepthFrameCache(
            maximumRetainedBytes: 64,
            lookBehindSeconds: 10,
            lookAheadSeconds: 10
        )
        #expect(cache.insert(Self.frame(index: 7, time: 1, retainedBytes: 4), around: 1))

        #expect(cache.nearestFrame(to: 1.099)?.frameIndex == 7)
        #expect(cache.nearestFrame(to: 1.101) == nil)
        #expect(cache.nearestFrame(to: 0.91) == nil)
        #expect(cache.nearestFrame(to: 0.925)?.frameIndex == 7)
    }

    @Test func gapPolicyUsesTwoNominalIntervalsWithA100MillisecondFloor() {
        #expect(TAPVideoDepthGapPolicy.staleToleranceSeconds(
            nominalDepthFrameIntervalSeconds: nil
        ) == 0.1)
        #expect(TAPVideoDepthGapPolicy.staleToleranceSeconds(
            nominalDepthFrameIntervalSeconds: 1.0 / 30.0
        ) == 0.1)
        #expect(abs(TAPVideoDepthGapPolicy.staleToleranceSeconds(
            nominalDepthFrameIntervalSeconds: 1.0 / 15.0
        ) - (2.0 / 15.0)) < 0.000_001)
    }

    @Test func decodeAdmissionCapsGlobalPhysicalWork() throws {
        let admission = TAPVideoDepthDecodeAdmission(maximumConcurrentDecodes: 2)
        let owner = admission.makeOwner()
        let first = try #require(admission.admit(for: owner))
        let second = try #require(admission.admit(for: owner))

        #expect(admission.admit(for: owner) == nil)
        #expect(admission.activeDecodeCount == 2)
        admission.beginNewGeneration(for: owner)
        #expect(!admission.isCurrent(first))
        #expect(!admission.isCurrent(second))
        #expect(admission.admit(for: owner) == nil)

        admission.finish(first)
        let current = try #require(admission.admit(for: owner))
        #expect(admission.isCurrent(current))
        #expect(admission.activeDecodeCount == 2)
        admission.finish(second)
        admission.finish(current)
        #expect(admission.activeDecodeCount == 0)
    }

    @Test func decodeAdmissionClampsInjectedConcurrencyToTheReleaseMaximum() throws {
        let admission = TAPVideoDepthDecodeAdmission(maximumConcurrentDecodes: Int.max)
        let owner = admission.makeOwner()
        let first = try #require(admission.admit(for: owner))
        let second = try #require(admission.admit(for: owner))

        #expect(admission.admit(for: owner) == nil)
        #expect(admission.activeDecodeCount == TAPVideoDepthPlaybackBudget.maximumConcurrentDecodes)
        admission.finish(first)
        admission.finish(second)
        #expect(admission.activeDecodeCount == 0)
    }

    @Test func probeAdmissionWaitsForOldGenerationWorkToReleaseCapacity() async throws {
        let admission = TAPVideoDepthDecodeAdmission(maximumConcurrentDecodes: 2)
        let owner = admission.makeOwner()
        let oldGeneration = admission.beginNewGeneration(for: owner)
        let first = try #require(admission.admit(for: owner))
        let second = try #require(admission.admit(for: owner))
        let currentGeneration = admission.beginNewGeneration(for: owner)
        #expect(currentGeneration != oldGeneration)

        let waitingProbe = Task {
            await admission.admitWhenAvailable(
                for: owner,
                expectedGeneration: currentGeneration
            )
        }
        let didQueue = await Self.waitUntil {
            admission.waitingAdmissionCount == 1
        }
        #expect(didQueue)
        #expect(admission.activeDecodeCount == 2)

        admission.finish(first)
        let admittedValue = await waitingProbe.value
        let admitted = try #require(admittedValue)
        #expect(admission.isCurrent(admitted))
        #expect(admission.activeDecodeCount == 2)

        admission.finish(second)
        admission.finish(admitted)
        #expect(admission.activeDecodeCount == 0)
    }

    @Test func staleAndCancelledProbeWaitersExitWithoutLeakingTokens() async throws {
        let admission = TAPVideoDepthDecodeAdmission(maximumConcurrentDecodes: 1)
        let owner = admission.makeOwner()
        let generation = admission.beginNewGeneration(for: owner)
        let active = try #require(admission.admit(for: owner))

        let staleWaiter = Task {
            await admission.admitWhenAvailable(
                for: owner,
                expectedGeneration: generation
            )
        }
        let didQueueStaleWaiter = await Self.waitUntil {
            admission.waitingAdmissionCount == 1
        }
        #expect(didQueueStaleWaiter)
        let nextGeneration = admission.beginNewGeneration(for: owner)
        #expect(await staleWaiter.value == nil)
        #expect(admission.waitingAdmissionCount == 0)

        let cancelledWaiter = Task {
            await admission.admitWhenAvailable(
                for: owner,
                expectedGeneration: nextGeneration
            )
        }
        let didQueueCancelledWaiter = await Self.waitUntil {
            admission.waitingAdmissionCount == 1
        }
        #expect(didQueueCancelledWaiter)
        cancelledWaiter.cancel()
        #expect(await cancelledWaiter.value == nil)
        #expect(admission.waitingAdmissionCount == 0)

        admission.finish(active)
        #expect(admission.activeDecodeCount == 0)
        let replacement = try #require(admission.admit(for: owner))
        admission.finish(replacement)
        #expect(admission.activeDecodeCount == 0)
    }

    @Test func ownerGenerationsDoNotInvalidateOtherPlaybackOutputs() throws {
        let admission = TAPVideoDepthDecodeAdmission(maximumConcurrentDecodes: 2)
        let firstOwner = admission.makeOwner()
        let secondOwner = admission.makeOwner()
        admission.beginNewGeneration(for: firstOwner)
        let secondGeneration = admission.beginNewGeneration(for: secondOwner)
        let firstToken = try #require(admission.admit(for: firstOwner))
        let secondToken = try #require(admission.admit(for: secondOwner))

        admission.beginNewGeneration(for: firstOwner)

        #expect(!admission.isCurrent(firstToken))
        #expect(admission.isCurrent(secondToken))
        #expect(admission.currentGeneration(for: secondOwner) == secondGeneration)
        admission.finish(firstToken)
        admission.finish(secondToken)
        #expect(admission.activeDecodeCount == 0)
    }

    @Test func rawKLVFixtureDecodesToARegisteredOverlayImage() throws {
        let packedDepth = Self.float32Data([1, 2, 3, 4])
        let encoded = TAPDepthKLVFrame(
            frameIndex: 42,
            timestampValue: 600,
            timestampTimescale: 600,
            compressionCodec: .raw,
            uncompressedByteCount: packedDepth.count,
            calibrationIndex: 0,
            payload: packedDepth
        )
        let format = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 2,
            height: 2,
            packedRowStride: 8,
            sourceRowStride: 16,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 16
        )

        let frame = try TAPDepthVideoFrameDecoder.decode(
            encoded.encodedData(),
            presentationTimeSeconds: 1,
            depthFormat: format,
            displayOrientation: .right
        )

        #expect(frame.frameIndex == 42)
        #expect(frame.presentationTimeSeconds == 1)
        #expect(frame.width == 2)
        #expect(frame.height == 2)
        #expect(frame.image.imageOrientation == .right)
        #expect(frame.image.cgImage != nil)
        #expect(frame.retainedByteCount > 0)
    }

    @Test func decoderRejectsManifestStrideThatIsNotPacked() throws {
        let packedDepth = Self.float32Data([1, 2, 3, 4, 5, 6])
        let encoded = TAPDepthKLVFrame(
            frameIndex: 1,
            timestampValue: 0,
            timestampTimescale: 600,
            compressionCodec: .raw,
            uncompressedByteCount: packedDepth.count,
            calibrationIndex: nil,
            payload: packedDepth
        )
        let paddedFormat = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 2,
            height: 2,
            packedRowStride: 12,
            sourceRowStride: 12,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 24
        )

        #expect(throws: TAPDepthCaptureError.self) {
            try TAPDepthVideoFrameDecoder.decode(
                encoded.encodedData(),
                presentationTimeSeconds: 0,
                depthFormat: paddedFormat,
                displayOrientation: .up
            )
        }
    }

    @Test func decoderHonorsGenerationCancellationBeforePublishingWork() throws {
        let format = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 1,
            height: 1,
            packedRowStride: 4,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 4
        )
        let encoded = TAPDepthKLVFrame(
            frameIndex: 1,
            timestampValue: 0,
            timestampTimescale: 600,
            compressionCodec: .raw,
            uncompressedByteCount: 4,
            calibrationIndex: nil,
            payload: Self.float32Data([1])
        )

        #expect(throws: CancellationError.self) {
            try TAPDepthVideoFrameDecoder.decode(
                encoded.encodedData(),
                presentationTimeSeconds: 0,
                depthFormat: format,
                displayOrientation: .up,
                shouldContinue: { false }
            )
        }
    }

    @Test func calibrationMetadataAloneDoesNotEnableRegisteredOverlay() {
        let adapter = TAPVideoManifestDepthRegistrationAdapter()
        let manifest = Self.calibrationOnlyManifest()

        #expect(adapter.registrationDescriptor(for: manifest) == nil)
    }

    @Test func productionDescriptorProjectsSyntheticLandmarksIntoRGBPresentation() throws {
        let descriptor = try #require(
            TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
                for: Self.productionRegisteredManifest()
            )
        )
        let projection = try #require(descriptor.projection)

        #expect(descriptor.supportsRegisteredOverlay)
        #expect(descriptor.mapping == .avDepthDataWarpedToSynchronizedRGB)
        #expect(descriptor.rgbPresentationWidth == 4)
        #expect(descriptor.rgbPresentationHeight == 8)
        let topLeft = try #require(projection.projectDepthPixelCenter(x: 0, y: 0))
        let bottomRight = try #require(projection.projectDepthPixelCenter(x: 3, y: 1))
        #expect(abs(topLeft.x - 2.5) < 0.000_001)
        #expect(abs(topLeft.y - 0.5) < 0.000_001)
        #expect(abs(bottomRight.x - 0.5) < 0.000_001)
        #expect(abs(bottomRight.y - 6.5) < 0.000_001)
    }

    @Test func production2DDescriptorDoesNotRequireMetricCalibrationCoverage() throws {
        let manifest = Self.productionRegisteredManifest(calibrationTable: [])
        let descriptor = try #require(
            TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
                for: manifest
            )
        )

        #expect(descriptor.supportsRegisteredOverlay)
        #expect(manifest.payload.spatialRegistration.calibrationTable.isEmpty)
    }

    @Test func productionProjectionMatchesAllConnectionQuadrantsAndCleanAperture() throws {
        let expectedTopLeftByRotation: [Int: CGPoint] = [
            0: CGPoint(x: 0.5, y: 0.5),
            90: CGPoint(x: 2.5, y: 0.5),
            180: CGPoint(x: 6.5, y: 2.5),
            270: CGPoint(x: 0.5, y: 6.5)
        ]
        for rotation in [0, 90, 180, 270] {
            let descriptor = try #require(
                TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
                    for: Self.productionRegisteredManifest(rotationDegrees: rotation)
                )
            )
            let point = try #require(
                descriptor.projection?.projectDepthPixelCenter(x: 0, y: 0)
            )
            let expected = try #require(expectedTopLeftByRotation[rotation])
            #expect(abs(point.x - expected.x) < 0.000_001)
            #expect(abs(point.y - expected.y) < 0.000_001)
        }

        let crop = TAPVideoManifest.Rect(x: 0, y: 2, width: 4, height: 4)
        let croppedDescriptor = try #require(
            TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
                for: Self.productionRegisteredManifest(cleanAperture: crop)
            )
        )
        let croppedPoint = try #require(
            croppedDescriptor.projection?.projectDepthPixelCenter(x: 1, y: 0)
        )
        #expect(abs(croppedPoint.x - 2.5) < 0.000_001)
        #expect(abs(croppedPoint.y - 0.5) < 0.000_001)
    }

    @Test func productionProjectionMirrorsEncodedSpaceAfterEveryRotation() throws {
        let expectedTopLeftByRotation: [Int: CGPoint] = [
            0: CGPoint(x: 6.5, y: 0.5),
            90: CGPoint(x: 0.5, y: 0.5),
            180: CGPoint(x: 0.5, y: 2.5),
            270: CGPoint(x: 2.5, y: 6.5)
        ]
        for rotation in [0, 90, 180, 270] {
            let descriptor = try #require(
                TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
                    for: Self.productionRegisteredManifest(
                        rotationDegrees: rotation,
                        isMirrored: true
                    )
                )
            )
            let projection = try #require(descriptor.projection)
            let point = try #require(projection.projectDepthPixelCenter(x: 0, y: 0))
            let expected = try #require(expectedTopLeftByRotation[rotation])
            #expect(projection.isEncodedHorizontallyMirrored)
            #expect(abs(point.x - expected.x) < 0.000_001)
            #expect(abs(point.y - expected.y) < 0.000_001)
        }
    }

    @Test func productionAdapterRejectsNonCanonicalOrMalformedRegistration() {
        #expect(TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
            for: Self.productionRegisteredManifest(
                affine: [2, 0.01, 0.5, 0, 2, 0.5]
            )
        ) == nil)
        #expect(TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
            for: Self.productionRegisteredManifest(
                connectionTransform: "rotation:90;diagonal"
            )
        ) == nil)
        #expect(TAPVideoManifestDepthRegistrationAdapter().registrationDescriptor(
            for: Self.productionRegisteredManifest(
                connectionTransform: "rotation:90;mirrored"
            )
        ) == nil)
    }

    #if DEBUG
    @Test func explicitIdentityFixtureCanOptIntoRegisteredOverlay() throws {
        let descriptor = try #require(
            TAPVideoFixtureIdentityRegistrationAdapter().registrationDescriptor(
                for: Self.identityFixtureManifest()
            )
        )

        #expect(descriptor.supportsRegisteredOverlay)
        #expect(descriptor.rgbPresentationWidth == 2)
        #expect(descriptor.rgbPresentationHeight == 2)
        #expect(descriptor.nominalDepthFrameIntervalSeconds == 1.0 / 30.0)
    }
    #endif

    @MainActor
    private static func frame(
        index: Int,
        time: Double,
        retainedBytes: Int
    ) -> TAPDecodedDepthVideoFrame {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return TAPDecodedDepthVideoFrame(
            frameIndex: index,
            presentationTimeSeconds: time,
            width: 1,
            height: 1,
            pixelFormat: "fdep",
            image: image,
            retainedByteCount: retainedBytes
        )
    }

    @MainActor
    private static func makePendingRefreshSession() -> TAPVideoPlaybackSession {
        TAPVideoPlaybackSession(
            source: .pendingCapture("refresh-claim-\(UUID().uuidString)"),
            registrationAdapter: TAPVideoManifestDepthRegistrationAdapter(),
            mediaFetcher: PhotoKitLibraryMediaFetcher()
        )
    }

    private static func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if predicate() {
                return true
            }
            await Task.yield()
        }
        return predicate()
    }

    private static func float32Data(_ values: [Float]) -> Data {
        var data = Data()
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    private static func calibrationOnlyManifest() -> TAPVideoManifest {
        let calibration = TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [1, 0, 0, 0, 1, 0, 1, 1, 1],
            intrinsicMatrixReferenceDimensions: .init(width: 2, height: 2),
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
            pixelSizeMillimeters: 0.001,
            lensDistortionCenter: .init(x: 1, y: 1),
            lensDistortionLookupTable: nil,
            inverseLensDistortionLookupTable: nil
        )
        return manifest(
            spatialRegistration: TAPVideoManifest.SpatialRegistration(
                status: .registered,
                mapping: "AVDepthData.cameraCalibrationData",
                rgbReferenceDimensions: .init(width: 2, height: 2),
                depthReferenceDimensions: .init(width: 2, height: 2),
                rgbCleanAperture: .init(x: 0, y: 0, width: 2, height: 2),
                recordedTransform: "rotation:0;not-mirrored",
                calibration: calibration
            )
        )
    }

    private static func identityFixtureManifest() -> TAPVideoManifest {
        manifest(
            spatialRegistration: TAPVideoManifest.SpatialRegistration(
                status: .registered,
                mapping: TAPVideoFixtureIdentityRegistrationAdapter.mappingIdentifier,
                rgbReferenceDimensions: .init(width: 2, height: 2),
                depthReferenceDimensions: .init(width: 2, height: 2),
                rgbCleanAperture: .init(x: 0, y: 0, width: 2, height: 2),
                recordedTransform: "rotation:0;not-mirrored",
                calibration: nil
            )
        )
    }

    private static func productionRegisteredManifest(
        affine: [Double] = [2, 0, 0.5, 0, 2, 0.5],
        rotationDegrees: Int = 90,
        isMirrored: Bool = false,
        connectionTransform: String? = nil,
        cleanAperture requestedCleanAperture: TAPVideoManifest.Rect? = nil,
        calibrationTable requestedCalibrationTable: [TAPVideoManifest.CameraCalibration]? = nil
    ) -> TAPVideoManifest {
        let alignedDimensions = TAPVideoManifest.Dimensions(width: 8, height: 4)
        let isSideways = rotationDegrees == 90 || rotationDegrees == 270
        let encodedDimensions = TAPVideoManifest.Dimensions(
            width: isSideways ? 4 : 8,
            height: isSideways ? 8 : 4
        )
        let depthDimensions = TAPVideoManifest.Dimensions(width: 4, height: 2)
        let cleanAperture = requestedCleanAperture ?? TAPVideoManifest.Rect(
            x: 0,
            y: 0,
            width: encodedDimensions.width,
            height: encodedDimensions.height
        )
        let actualConnectionTransform = connectionTransform
            ?? (isMirrored
                ? "rotation:\(rotationDegrees);mirrored"
                : "rotation:\(rotationDegrees);not-mirrored")
        let calibration = TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [1, 0, 0, 0, 1, 0, 2, 1, 1],
            intrinsicMatrixReferenceDimensions: depthDimensions,
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
            pixelSizeMillimeters: 0.001,
            lensDistortionCenter: .init(x: 2, y: 1),
            lensDistortionLookupTable: nil,
            inverseLensDistortionLookupTable: nil
        )
        let signedDescriptor = TAPVideoManifest.RegistrationDescriptor(
            alignedRGBCodedDimensions: alignedDimensions,
            encodedRGBCodedDimensions: encodedDimensions,
            depthDimensions: depthDimensions,
            depthToAlignedRGBPixelCenterAffine: affine,
            connectionTransform: actualConnectionTransform,
            isEncodedHorizontallyMirrored: isMirrored,
            rgbCleanAperture: cleanAperture
        )
        let calibrationTable = requestedCalibrationTable ?? [calibration]
        return manifest(
            spatialRegistration: TAPVideoManifest.SpatialRegistration(
                status: .registered,
                mapping: TAPVideoManifest.RegistrationDescriptor.schemaID,
                rgbReferenceDimensions: alignedDimensions,
                depthReferenceDimensions: depthDimensions,
                rgbCleanAperture: cleanAperture,
                recordedTransform: actualConnectionTransform,
                calibration: calibration,
                calibrationTable: calibrationTable,
                calibrationCoverage: calibrationTable.isEmpty
                    ? .init(
                        indexedSampleCount: 0,
                        missingCalibrationSampleCount: 1,
                        overflowUnindexedSampleCount: 0,
                        tableOverflowed: false
                    )
                    : .init(
                        indexedSampleCount: 1,
                        missingCalibrationSampleCount: 0,
                        overflowUnindexedSampleCount: 0,
                        tableOverflowed: false
                    ),
                descriptor: signedDescriptor
            ),
            rgbWidth: Int32(encodedDimensions.width),
            rgbHeight: Int32(encodedDimensions.height),
            rgbTransform: isMirrored
                ? "rotation:\(rotationDegrees);mirrored"
                : "rotation:\(rotationDegrees)",
            depthWidth: 4,
            depthHeight: 2
        )
    }

    private static func manifest(
        spatialRegistration: TAPVideoManifest.SpatialRegistration,
        rgbWidth: Int32 = 2,
        rgbHeight: Int32 = 2,
        rgbTransform: String = "identity",
        depthWidth: Int32 = 2,
        depthHeight: Int32 = 2
    ) -> TAPVideoManifest {
        let format = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: depthWidth,
            height: depthHeight,
            packedRowStride: Int(depthWidth) * 4,
            bytesPerSample: 4,
            uncompressedFrameByteCount: Int(depthWidth * depthHeight) * 4
        )
        return TAPVideoManifest(
            payload: TAPVideoManifest.Payload(
                id: "playback-fixture",
                capturedAt: "2026-07-11T00:00:00Z",
                selectedCameraPlan: TAPVideoManifest.SelectedCameraPlan(
                    deviceUniqueID: nil,
                    deviceType: nil,
                    localizedName: nil,
                    position: "back",
                    requestedFocalLengthLabel: nil,
                    resolvedFocalLengthLabel: nil,
                    resolvedZoomFactor: nil,
                    depthCapable: true
                ),
                container: TAPVideoManifest.Container(
                    fileType: "mp4",
                    mediaType: "video/mp4",
                    durationSeconds: 1,
                    timeScale: 600,
                    trackCount: 2
                ),
                rgbTrack: TAPVideoManifest.RGBTrack(
                    trackID: 1,
                    codec: "avc1",
                    width: rgbWidth,
                    height: rgbHeight,
                    durationSeconds: 1,
                    timeScale: 600,
                    nominalFrameRate: 30,
                    frameCount: 30,
                    transform: rgbTransform
                ),
                audioTrack: TAPVideoManifest.AudioTrack(
                    status: .notCaptured,
                    trackID: nil,
                    codec: nil,
                    durationSeconds: nil,
                    timeScale: nil,
                    sampleRate: nil,
                    channelCount: nil
                ),
                depthCoverage: TAPVideoManifest.DepthCoverage(
                    trackID: 3,
                    trackCodec: "mebx",
                    trackDurationSeconds: 1,
                    trackTimeScale: 600,
                    sampleCount: 1,
                    format: format
                ),
                spatialRegistration: spatialRegistration,
                synchronization: TAPVideoManifest.Synchronization(
                    timing: "sample-timestamps",
                    rgbToDepthMapping: "nearest-rgb-frame",
                    maxObservedDeltaSeconds: 0,
                    maxObservedDepthIntervalSeconds: 0.8,
                    nominalDepthIntervalSeconds: 1.0 / 30.0
                ),
                stop: TAPVideoManifest.Stop(
                    reason: .userStop,
                    recordedDurationSeconds: 1
                ),
                software: TAPVideoManifest.Software(
                    appIdentifier: "net.tapcam.demo",
                    appVersion: "test",
                    buildNumber: "1",
                    schemaWriter: "test"
                )
            )
        )
    }
}

@MainActor
private final class TAPVideoPlaybackProgressRecorder {
    private(set) var values: [Double?] = []

    func append(_ progress: Double?) {
        values.append(progress)
    }
}
