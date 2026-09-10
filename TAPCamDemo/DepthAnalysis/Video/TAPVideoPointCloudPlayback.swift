@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import UIKit

/// One in-flight projection and one latest playhead. Cancellation keeps the physical
/// worker occupied until it exits; rapid seeks cannot enqueue unbounded work.
@MainActor
final class TAPVideoPointCloudPlayback {
    // At most 8 MiB each: current cache, a previous cache snapshot retained by
    // the sole worker, and warmup depth. Their conservative retained-data sum is
    // 24 MiB. Metadata decode scratch, one RGB buffer, and native/GPU allocations
    // are separate; this is not a process-memory limit.
    nonisolated static let depthCacheByteBudget = 8 * 1024 * 1024
    let store = TAPVideoPointCloudStore()
    var onStateChange: ((Bool) -> Void)?
    private(set) var isRequested = false
    private(set) var isAvailable = false
    private var configuration: TAPVideoPointCloudConfiguration?
    private var metadata: TAPVideoDepthMetadataOutput?
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var item: AVPlayerItem?
    private let cache = TAPVideoDepthFrameCache(maximumRetainedBytes: depthCacheByteBudget)
    private let worker = TAPVideoPointCloudWorker()
    private var workTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var metadataGeneration: UInt64 = 0
    private var time: Double = 0
    private var smoothing = false
    private var displayedTime: Double?
    private var requestedTime: Double?
    private var isSuspended = false
    private var needsHistoryWarmup = true
    private var runtimeHistoryCutoff: Double?

    func configure(fileURL: URL, presentation: TAPVideoPlaybackPresentation) {
        cancel()
        guard let descriptor = presentation.registrationDescriptor,
              descriptor.projection != nil,
              let format = presentation.depthFormat,
              format.width > 0, format.height > 0,
              format.uncompressedFrameByteCount > 0,
              format.uncompressedFrameByteCount <= Self.depthCacheByteBudget,
              Int64(format.width) * Int64(format.height)
                <= Int64((Self.depthCacheByteBudget - format.uncompressedFrameByteCount) / 4),
              let trackID = presentation.depthTrackID,
              let gaps = TAPVideoPointCloudSmoothing.validatedGaps(presentation.depthGaps),
              presentation.calibrationTable.contains(where: { TAPVideoPointCloudCalibration($0) != nil }) else {
            configuration = nil
            isAvailable = false
            return
        }
        configuration = TAPVideoPointCloudConfiguration(
            fileURL: fileURL, descriptor: descriptor, format: format,
            trackID: trackID, calibrations: presentation.calibrationTable, depthGaps: gaps
        )
        isAvailable = true
    }

    func begin(on item: AVPlayerItem, time: Double, smoothingEnabled: Bool) {
        guard let configuration else { return }
        cancel()
        self.item = item
        isRequested = true
        isSuspended = false
        smoothing = smoothingEnabled
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        let metadata = TAPVideoDepthMetadataOutput(
            displayOrientation: .up, depthFormat: configuration.format,
            depthTrackID: configuration.trackID, rendersHeatmap: false
        ) { [weak self, weak output] event in
            // Metadata generations restart for each attachment; a late callback
            // from a previous item or 3D visit must not populate this one.
            guard let self, let output, videoOutput === output else { return }
            receive(event)
        }
        self.metadata = metadata
        metadata.attach(to: item)
        metadataGeneration = metadata.beginNewGeneration()
        self.time = time
        probe()
        onStateChange?(false)
    }

    func cancel() {
        generation &+= 1
        workTask?.cancel()
        metadata?.detach()
        metadata = nil
        if let videoOutput { item?.remove(videoOutput) }
        videoOutput = nil
        item = nil
        isRequested = false
        clear()
    }

    func suspend() {
        isSuspended = true
        reset(at: time)
    }

    func resume(at time: Double) {
        isSuspended = false
        reset(at: time)
    }

    func reset(at time: Double) {
        generation &+= 1
        workTask?.cancel()
        self.time = max(0, time)
        clear(keepingPresentedFrame: true)
        metadataGeneration = metadata?.beginNewGeneration() ?? 0
        if !isSuspended { probe() }
    }

    func update(at time: Double) {
        guard isRequested, !isSuspended, time.isFinite else { return }
        self.time = max(0, time)
        guard let configuration else { return }
        let tolerance = configuration.staleTolerance
        guard !TAPVideoPointCloudSmoothing.crossesGap(from: self.time, to: self.time, gaps: configuration.depthGaps) else {
            unavailable()
            return
        }
        guard let frame = cache.nearestFrame(to: self.time, staleToleranceSeconds: tolerance) else {
            if let displayedTime, self.time - displayedTime > tolerance { unavailable() }
            return
        }
        guard !TAPVideoPointCloudSmoothing.crossesGap(from: frame.presentationTimeSeconds, to: self.time, gaps: configuration.depthGaps) else {
            unavailable()
            return
        }
        guard configuration.calibration(for: frame) != nil else {
            unavailable()
            return
        }
        guard displayedTime != frame.presentationTimeSeconds,
              requestedTime != frame.presentationTimeSeconds,
              workTask == nil else { return }
        launch(frame: frame, configuration: configuration)
    }

    private func receive(_ event: TAPVideoDepthPipelineEvent) {
        guard isRequested, !isSuspended, event.generation == metadataGeneration else { return }
        switch event.payload {
        case .frame(let frame):
            guard cache.insert(frame, around: time) else { return }
            update(at: time)
        case .noSample(let playbackTime):
            markHistoryCutoff(playbackTime)
            unavailable()
        case .decodeFailed(_, let timestamp):
            markHistoryCutoff(timestamp)
            if displayedTime == nil { unavailable() }
        }
    }

    private func launch(frame: TAPDecodedDepthVideoFrame, configuration: TAPVideoPointCloudConfiguration) {
        let token = generation
        requestedTime = frame.presentationTimeSeconds
        var actualTime = CMTime.invalid
        let pixelBuffer = videoOutput?.copyPixelBuffer(
            forItemTime: CMTime(seconds: frame.presentationTimeSeconds, preferredTimescale: 600),
            itemTimeForDisplay: &actualTime
        )
        let rgb = pixelBuffer.flatMap { buffer -> TAPVideoPointCloudRGB? in
            let seconds = CMTimeGetSeconds(actualTime)
            guard seconds.isFinite, abs(seconds - frame.presentationTimeSeconds) <= configuration.rgbTolerance else { return nil }
            return TAPVideoPointCloudRGB(pixelBuffer: buffer)
        }
        let history = smoothing ? Array(cache.frames.filter {
            let age = frame.presentationTimeSeconds - $0.presentationTimeSeconds
            return age > 0 && age <= TAPVideoPointCloudSmoothing.historySeconds
        }.suffix(TAPVideoPointCloudSmoothing.maximumHistoryFrames)) : []
        let warmsHistory = smoothing && needsHistoryWarmup
        let historyCutoff = smoothing ? runtimeHistoryCutoff.map { min($0, frame.presentationTimeSeconds) } : nil
        workTask = Task { [weak self, worker] in
            let result = try? await worker.make(
                frame: frame, rgb: rgb, configuration: configuration,
                history: history, warmsHistory: warmsHistory, historyCutoff: historyCutoff
            )
            guard let self else { return }
            workTask = nil
            requestedTime = nil
            guard generation == token, isRequested, !isSuspended else {
                update(at: time)
                return
            }
            let currentCutoff = smoothing ? runtimeHistoryCutoff.map { min($0, frame.presentationTimeSeconds) } : nil
            guard currentCutoff == historyCutoff else {
                update(at: time)
                return
            }
            if let current = cache.nearestFrame(to: time, staleToleranceSeconds: configuration.staleTolerance),
               configuration.calibration(for: current) == nil {
                unavailable()
                return
            }
            if let result {
                retainHistory(result.history, didWarm: warmsHistory)
            }
            if let payload = result?.payload,
               abs(payload.presentationTimeSeconds - time) <= configuration.staleTolerance,
               !TAPVideoPointCloudSmoothing.crossesGap(from: payload.presentationTimeSeconds, to: time, gaps: configuration.depthGaps) {
                store.present(payload)
                displayedTime = payload.presentationTimeSeconds
                onStateChange?(true)
            } else if result?.payload == nil {
                unavailable()
            }
            // There may be a newer frame after the physical worker releases capacity.
            if let current = cache.nearestFrame(to: time, staleToleranceSeconds: configuration.staleTolerance),
               current.presentationTimeSeconds != frame.presentationTimeSeconds {
                update(at: time)
            }
        }
    }

    private func retainHistory(_ frames: [TAPDecodedDepthVideoFrame], didWarm: Bool) {
        if didWarm { needsHistoryWarmup = false }
        for frame in frames { _ = cache.insert(frame, around: time) }
    }

    private func probe() {
        guard isRequested, let configuration else { return }
        metadata?.probe(fileURL: configuration.fileURL, playbackTimeSeconds: time,
                        staleToleranceSeconds: configuration.staleTolerance,
                        leadToleranceSeconds: TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds)
    }

    private func clear(keepingPresentedFrame: Bool = false) {
        needsHistoryWarmup = true
        runtimeHistoryCutoff = nil
        cache.clear()
        displayedTime = nil
        requestedTime = nil
        if !keepingPresentedFrame { store.clear() }
        onStateChange?(store.presentationTimeSeconds != nil)
    }

    private func markHistoryCutoff(_ timestamp: Double) {
        guard timestamp.isFinite else { return }
        // Metadata can arrive ahead of the playhead. A future failure conservatively
        // suppresses history until playback passes it; retained history stays bounded.
        runtimeHistoryCutoff = max(runtimeHistoryCutoff ?? -.infinity, timestamp)
    }

    private func unavailable() {
        markHistoryCutoff(time)
        needsHistoryWarmup = true
        // Hold this video's last rendered frame through gaps. Its original PTS
        // stays in the store; it is never reused as current depth or smoothing history.
        onStateChange?(store.presentationTimeSeconds != nil)
    }
}

nonisolated struct TAPVideoPointCloudConfiguration: Sendable {
    let fileURL: URL
    let descriptor: TAPVideoDepthRegistrationDescriptor
    let format: TAPVideoManifest.DepthFormat
    let trackID: CMPersistentTrackID
    let calibrations: [TAPVideoManifest.CameraCalibration]
    var depthGaps: [ClosedRange<Double>] = []
    var staleTolerance: Double {
        TAPVideoDepthGapPolicy.staleToleranceSeconds(nominalDepthFrameIntervalSeconds: descriptor.nominalDepthFrameIntervalSeconds)
    }
    var rgbTolerance: Double { min(0.08, staleTolerance) }

    func calibration(for frame: TAPDecodedDepthVideoFrame) -> TAPVideoManifest.CameraCalibration? {
        if let calibration = frame.inlineCalibration { return calibration }
        guard let index = frame.calibrationIndex, Int(index) < calibrations.count else { return nil }
        return calibrations[Int(index)]
    }
}

nonisolated struct TAPVideoPointCloudRGB: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    func image(configuration: TAPVideoPointCloudConfiguration, context: CIContext) -> CGImage? {
        guard let projection = configuration.descriptor.projection else { return nil }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let aperture = projection.rgbCleanAperture
        let crop: CGRect
        if Int(source.extent.width) == projection.encodedRGBWidth,
           Int(source.extent.height) == projection.encodedRGBHeight {
            crop = CGRect(x: aperture.x, y: source.extent.height - aperture.y - aperture.height,
                          width: aperture.width, height: aperture.height)
        } else if Int(source.extent.width) == Int(aperture.width), Int(source.extent.height) == Int(aperture.height) {
            crop = source.extent
        } else { return nil }
        let image = source.cropped(to: crop).transformed(by: .init(translationX: -crop.minX, y: -crop.minY))
        let scale = min(1, Double(TAPVideoPointCloudProjection.maximumRGBDimension) / max(crop.width, crop.height))
        let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }

}

nonisolated private struct TAPVideoPointCloudWorkResult {
    let payload: TAPVideoPointCloudPayload?
    let history: [TAPDecodedDepthVideoFrame]
}

private actor TAPVideoPointCloudWorker {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func make(frame: TAPDecodedDepthVideoFrame, rgb: TAPVideoPointCloudRGB?,
              configuration: TAPVideoPointCloudConfiguration,
              history cachedHistory: [TAPDecodedDepthVideoFrame],
              warmsHistory: Bool, historyCutoff: Double?) async throws -> TAPVideoPointCloudWorkResult? {
        try Task.checkCancellation()
        guard let savedCalibration = configuration.calibration(for: frame),
              let calibration = TAPVideoPointCloudCalibration(savedCalibration) else { return nil }
        let history: [TAPDecodedDepthVideoFrame]
        if warmsHistory {
            // A failed warmup provides no history, never a partial earlier segment.
            // The independently decoded current frame remains usable.
            history = (try? await TAPVideoDepthMetadataReader.readHistory(
                fileURL: configuration.fileURL, trackID: configuration.trackID,
                through: frame.presentationTimeSeconds, depthFormat: configuration.format,
                maximumRetainedBytes: TAPVideoPointCloudPlayback.depthCacheByteBudget,
                shouldContinue: { !Task.isCancelled }
            )) ?? []
        } else { history = cachedHistory }
        try Task.checkCancellation()
        let image: CGImage?
        if let rgb, let bufferedImage = rgb.image(configuration: configuration, context: context) { image = bufferedImage }
        else { image = try await fallbackImage(time: frame.presentationTimeSeconds, configuration: configuration) }
        try Task.checkCancellation()
        guard let image else { return nil }
        let payload = try TAPVideoPointCloudProjection.make(
            frame: frame, history: history, calibration: calibration,
            descriptor: configuration.descriptor, image: image,
            gaps: configuration.depthGaps, historyCutoff: historyCutoff
        )
        return TAPVideoPointCloudWorkResult(payload: payload, history: warmsHistory ? history : [])
    }

    private func fallbackImage(time: Double, configuration: TAPVideoPointCloudConfiguration) async throws -> CGImage? {
        // AVPlayerItemVideoOutput may have no new buffer when entering 3D while paused.
        // This bounded, exact-time fallback is also serialized by the same physical worker.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: configuration.fileURL))
        generator.appliesPreferredTrackTransform = false
        generator.apertureMode = .cleanAperture
        let dimension = TAPVideoPointCloudProjection.maximumRGBDimension
        generator.maximumSize = CGSize(width: dimension, height: dimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await withTaskCancellationHandler {
            let result = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            guard abs(CMTimeGetSeconds(result.actualTime) - time) <= configuration.rgbTolerance else { return nil }
            return result.image
        } onCancel: { generator.cancelAllCGImageGeneration() }
    }
}
