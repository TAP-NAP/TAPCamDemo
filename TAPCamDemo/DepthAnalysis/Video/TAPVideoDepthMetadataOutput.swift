//
//  TAPVideoDepthMetadataOutput.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import ImageIO
import OSLog

@MainActor
final class TAPVideoDepthMetadataOutput: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private nonisolated static let depthMetadataIdentifierRawValue =
        "mdta/com.tapnap.depth.klv"
    private nonisolated static let decodeAdmission = TAPVideoDepthDecodeAdmission()

    private nonisolated let displayOrientation: CGImagePropertyOrientation
    private nonisolated let depthFormat: TAPVideoManifest.DepthFormat
    private nonisolated let depthTrackID: CMPersistentTrackID?
    private nonisolated let decodeOwner: TAPVideoDepthDecodeAdmission.Owner
    private let metadataQueue = DispatchQueue(
        label: "com.tapnap.video-depth.metadata",
        qos: .userInitiated
    )
    private let onEvent: (TAPVideoDepthPipelineEvent) -> Void
    private weak var attachedItem: AVPlayerItem?
    private var attachedOutput: AVPlayerItemMetadataOutput?
    private var activeGeneration: UInt64 = 0
    private var probeTask: Task<Void, Never>?
    private var probeSequence: UInt64 = 0

    init(
        displayOrientation: CGImagePropertyOrientation,
        depthFormat: TAPVideoManifest.DepthFormat,
        depthTrackID: CMPersistentTrackID?,
        onEvent: @escaping (TAPVideoDepthPipelineEvent) -> Void
    ) {
        self.displayOrientation = displayOrientation
        self.depthFormat = depthFormat
        self.depthTrackID = depthTrackID
        self.decodeOwner = Self.decodeAdmission.makeOwner()
        self.onEvent = onEvent
    }

    deinit {
        Self.decodeAdmission.invalidate(decodeOwner)
    }

    func attach(to item: AVPlayerItem) {
        detach()
        let output = AVPlayerItemMetadataOutput(
            identifiers: [Self.depthMetadataIdentifierRawValue]
        )
        output.advanceIntervalForDelegateInvocation = TAPVideoDepthPlaybackBudget
            .metadataAdvanceIntervalSeconds
        output.setDelegate(self, queue: metadataQueue)
        item.add(output)
        attachedItem = item
        attachedOutput = output
    }

    func detach() {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        guard let attachedOutput else {
            attachedItem = nil
            return
        }
        attachedOutput.setDelegate(nil, queue: nil)
        attachedItem?.remove(attachedOutput)
        self.attachedOutput = nil
        attachedItem = nil
    }

    @discardableResult
    func beginNewGeneration() -> UInt64 {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        let generation = Self.decodeAdmission.beginNewGeneration(for: decodeOwner)
        activeGeneration = generation
        return generation
    }

    func probe(
        fileURL: URL,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double
    ) {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        let probeID = probeSequence
        guard let depthTrackID else {
            publish(
                .noSample(playbackTimeSeconds: playbackTimeSeconds),
                generation: activeGeneration
            )
            return
        }
        let decodeAdmission = Self.decodeAdmission
        let decodeOwner = self.decodeOwner
        let expectedGeneration = activeGeneration
        probeTask = Task.detached(priority: .userInitiated) {
            [weak output = self, decodeAdmission, depthFormat = self.depthFormat,
             displayOrientation = self.displayOrientation] in
            await Self.runProbe(
                output: output,
                fileURL: fileURL,
                trackID: depthTrackID,
                playbackTimeSeconds: playbackTimeSeconds,
                staleToleranceSeconds: staleToleranceSeconds,
                leadToleranceSeconds: leadToleranceSeconds,
                depthFormat: depthFormat,
                displayOrientation: displayOrientation,
                decodeAdmission: decodeAdmission,
                decodeOwner: decodeOwner,
                expectedGeneration: expectedGeneration,
                probeID: probeID
            )
        }
    }

    private nonisolated static func runProbe(
        output: TAPVideoDepthMetadataOutput?,
        fileURL: URL,
        trackID: CMPersistentTrackID,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        decodeAdmission: TAPVideoDepthDecodeAdmission,
        decodeOwner: TAPVideoDepthDecodeAdmission.Owner,
        expectedGeneration: UInt64,
        probeID: UInt64
    ) async {
        guard let token = await decodeAdmission.admitWhenAvailable(
            for: decodeOwner,
            expectedGeneration: expectedGeneration
        ) else {
            return
        }
        defer {
            decodeAdmission.finish(token)
        }
        guard let payload = await TAPVideoDepthMetadataDecodeWorker.probePayload(
            fileURL: fileURL,
            trackID: trackID,
            playbackTimeSeconds: playbackTimeSeconds,
            staleToleranceSeconds: staleToleranceSeconds,
            leadToleranceSeconds: leadToleranceSeconds,
            depthFormat: depthFormat,
            displayOrientation: displayOrientation,
            decodeAdmission: decodeAdmission,
            token: token
        ), decodeAdmission.isCurrent(token) else {
            return
        }
        await MainActor.run { [weak output] in
            guard decodeAdmission.isCurrent(token) else {
                return
            }
            output?.publishProbe(
                payload,
                generation: token.generation,
                probeID: probeID
            )
        }
    }

    nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            let presentationTimeSeconds = CMTimeGetSeconds(group.timeRange.start)
            guard presentationTimeSeconds.isFinite else {
                continue
            }
            for item in group.items
            where item.identifier?.rawValue == Self.depthMetadataIdentifierRawValue {
                enqueueDepthMetadataItem(
                    item,
                    presentationTimeSeconds: max(0, presentationTimeSeconds)
                )
            }
        }
    }

    private nonisolated func enqueueDepthMetadataItem(
        _ item: AVMetadataItem,
        presentationTimeSeconds: Double
    ) {
        let decodeAdmission = Self.decodeAdmission
        let decodeOwner = self.decodeOwner
        guard let token = decodeAdmission.admit(for: decodeOwner) else {
            publishBackpressureFailure(
                presentationTimeSeconds: presentationTimeSeconds,
                decodeAdmission: decodeAdmission,
                decodeOwner: decodeOwner
            )
            return
        }

        let frameOrientation = displayOrientation
        Task.detached(priority: .userInitiated) {
            [weak output = self, decodeAdmission, depthFormat = self.depthFormat] in
            await Self.runPushDecode(
                output: output,
                item: item,
                presentationTimeSeconds: presentationTimeSeconds,
                depthFormat: depthFormat,
                displayOrientation: frameOrientation,
                decodeAdmission: decodeAdmission,
                token: token
            )
        }
    }

    private nonisolated func publishBackpressureFailure(
        presentationTimeSeconds: Double,
        decodeAdmission: TAPVideoDepthDecodeAdmission,
        decodeOwner: TAPVideoDepthDecodeAdmission.Owner
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.depthAnalysis.info("tap_video_depth_pipeline_backpressure_drop presentationTime=\(presentationTimeSeconds, privacy: .public) pending=\(decodeAdmission.activeDecodeCount, privacy: .public)")
        #endif
        let generation = decodeAdmission.currentGeneration(for: decodeOwner) ?? 0
        Task { @MainActor [weak self] in
            self?.publish(
                .decodeFailed(
                    reason: .backpressure,
                    presentationTimeSeconds: presentationTimeSeconds
                ),
                generation: generation
            )
        }
    }

    private nonisolated static func runPushDecode(
        output: TAPVideoDepthMetadataOutput?,
        item: AVMetadataItem,
        presentationTimeSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        decodeAdmission: TAPVideoDepthDecodeAdmission,
        token: TAPVideoDepthDecodeAdmission.Token
    ) async {
        defer {
            decodeAdmission.finish(token)
        }
        guard decodeAdmission.isCurrent(token),
              let payload = await TAPVideoDepthMetadataDecodeWorker.pushedPayload(
                  item: item,
                  presentationTimeSeconds: presentationTimeSeconds,
                  depthFormat: depthFormat,
                  displayOrientation: displayOrientation,
                  decodeAdmission: decodeAdmission,
                  token: token
              ),
              decodeAdmission.isCurrent(token) else {
            return
        }
        await MainActor.run { [weak output] in
            guard decodeAdmission.isCurrent(token) else {
                return
            }
            output?.publishFromPush(payload, generation: token.generation)
        }
    }

    private func publishFromPush(
        _ payload: TAPVideoDepthPipelineEvent.Payload,
        generation: UInt64
    ) {
        switch payload {
        case .frame(let frame):
            publishFrameFromPush(frame, generation: generation)
        case .noSample, .decodeFailed:
            publish(payload, generation: generation)
        }
    }

    private func publishFrameFromPush(
        _ frame: TAPDecodedDepthVideoFrame,
        generation: UInt64
    ) {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        publish(.frame(frame), generation: generation)
    }

    private func publishProbe(
        _ payload: TAPVideoDepthPipelineEvent.Payload,
        generation: UInt64,
        probeID: UInt64
    ) {
        guard probeID == probeSequence else {
            return
        }
        probeTask = nil
        publish(payload, generation: generation)
    }

    private func publish(
        _ payload: TAPVideoDepthPipelineEvent.Payload,
        generation: UInt64
    ) {
        guard generation == activeGeneration else {
            return
        }
        onEvent(TAPVideoDepthPipelineEvent(
            generation: generation,
            payload: payload
        ))
    }
}
