@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import UIKit
import simd

/// One in-flight projection and one registration, each with only the latest pending
/// target. Cancellation keeps physical capacity occupied until the work exits.
@MainActor
final class TAPVideoPointCloudPlayback {
    // At most 8 MiB each: current cache and the frame retained by the sole
    // projection worker. Their conservative retained-depth sum is 16 MiB.
    // Metadata decode scratch, RGB buffers, and native/GPU allocations
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
    private(set) var spatialHistory = TAPVideoPointCloudHistory()
    private var workTask: Task<Void, Never>?
    private var registrationTask: Task<TAPVideoPointCloudRegistrationResult?, Never>?
    // Registration retains at most three RGB images: the accepted reference,
    // the in-flight target, and this replaceable latest target. Projection decode
    // scratch is separate; there is no frame queue.
    private var latestObservation: TAPVideoPointCloudObservation?
    private var latestObservationTime: Double?
    private var latestGeometry: TAPVideoPointCloudPayload?
    private var presentationHistoryTime: Double?
    private var generation: UInt64 = 0
    private var metadataGeneration: UInt64 = 0
    private var time: Double = 0
    private var displayedTime: Double?
    private var pendingPayload: TAPVideoPointCloudPayload?
    private var requestedTime: Double?
    private var isSuspended = false
    private var isPlaybackPaused = false

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
              let gaps = TAPVideoDepthGapPolicy.validatedGaps(presentation.depthGaps),
              presentation.calibrationTable.contains(where: { TAPVideoPointCloudCalibration($0) != nil }) else {
            configuration = nil
            isAvailable = false
            return
        }
        configuration = TAPVideoPointCloudConfiguration(
            fileURL: fileURL, descriptor: descriptor, format: format,
            trackID: trackID, calibrations: presentation.calibrationTable, depthGaps: gaps,
            cameraMotion: presentation.cameraMotion
        )
        isAvailable = true
    }

    func begin(on item: AVPlayerItem, time: Double) {
        guard let configuration else { return }
        cancel()
        self.item = item
        isRequested = true
        isSuspended = false
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        let metadata = TAPVideoDepthMetadataOutput(
            displayOrientation: .up, depthFormat: configuration.format,
            depthTrackID: configuration.trackID
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
        invalidateWork()
        metadata?.detach()
        metadata = nil
        if let videoOutput { item?.remove(videoOutput) }
        videoOutput = nil
        item = nil
        isRequested = false
        clear()
    }

    func setPlaybackPaused(_ paused: Bool) {
        guard isPlaybackPaused != paused else { return }
        isPlaybackPaused = paused
        guard !paused else { return }
        if let pendingPayload {
            self.pendingPayload = nil
            receiveProjection(pendingPayload)
        }
        update(at: time)
    }

    /// The worker calls this only after its generation and PTS checks. Pause
    /// freezes the displayed scene without discarding the accepted accumulated map.
    func receiveProjection(_ payload: TAPVideoPointCloudPayload) {
        latestObservationTime = payload.presentationTimeSeconds
        if isPlaybackPaused, displayedTime != nil {
            pendingPayload = payload
            return
        }
        store.present(payload)
        displayedTime = payload.presentationTimeSeconds
        updateCameraRotation()
        onStateChange?(true)
    }

    private func updateCameraRotation() {
        guard let displayedTime,
              let rotation = configuration?.cameraMotion?.rotation(from: displayedTime, to: time) else { return }
        store.rotateCamera(rotation)
    }

    /// Registration alone promotes the map. An older completion may improve
    /// that map, but cannot replace newer current geometry or a paused pending frame.
    func acceptProjection(_ payload: TAPVideoPointCloudPayload,
                          spatialHistory candidate: TAPVideoPointCloudHistory) {
        spatialHistory = candidate
        if latestObservationTime.map({ payload.presentationTimeSeconds >= $0 }) ?? true {
            presentationHistoryTime = candidate.latestTime
            receiveProjection(payload)
        } else {
            refreshPresentation()
        }
    }

    private func refreshPresentation() {
        guard workTask == nil, isRequested, !isSuspended, latestGeometry != nil,
              presentationHistoryTime != spatialHistory.latestTime,
              let configuration else { return }
        let token = generation
        workTask = Task { [weak self] in
            guard let self else { return }
            _ = await composeLatestPresentation(configuration: configuration, generation: token)
            workTask = nil
            update(at: time)
        }
    }

    private func composeLatestPresentation(configuration: TAPVideoPointCloudConfiguration,
                                           generation token: UInt64) async -> Bool {
        while generation == token, isRequested, !isSuspended, let geometry = latestGeometry {
            let accepted = spatialHistory
            let payload = try? await worker.presentation(of: geometry,
                configuration: configuration, spatialHistory: accepted)
            guard generation == token, isRequested, !isSuspended, let payload else { return false }
            guard latestGeometry?.presentationTimeSeconds == payload.presentationTimeSeconds,
                  accepted.latestTime == spatialHistory.latestTime else { continue }
            guard latestObservationTime.map({ payload.presentationTimeSeconds >= $0 }) ?? true else { return false }
            presentationHistoryTime = accepted.latestTime
            receiveProjection(payload)
            return true
        }
        return false
    }

    private func queueRegistration(_ observation: TAPVideoPointCloudObservation) {
        latestObservation = observation
        startNextRegistration()
    }

    private func startNextRegistration() {
        guard registrationTask == nil, isRequested, !isSuspended,
              let observation = latestObservation else { return }
        latestObservation = nil
        let token = generation
        let accepted = spatialHistory
        let task = Task<TAPVideoPointCloudRegistrationResult?, Never>.detached(priority: .userInitiated) {
            do {
                var candidate = accepted
                guard let payload = try candidate.accept(observation.payload, image: observation.image) else { return nil }
                try Task.checkCancellation()
                return TAPVideoPointCloudRegistrationResult(payload: payload, spatialHistory: candidate)
            } catch { return nil }
        }
        registrationTask = task
        Task { [weak self] in
            let result = await task.value
            guard let self else { return }
            // Cancellation never releases the physical slot early. A new epoch
            // can replace the pending target while this old task finishes.
            registrationTask = nil
            if generation == token, isRequested, !isSuspended, let result {
                acceptProjection(result.payload, spatialHistory: result.spatialHistory)
            }
            startNextRegistration()
        }
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
        invalidateWork()
        self.time = max(0, time)
        clear(keepingPresentedFrame: true)
        metadataGeneration = metadata?.beginNewGeneration() ?? 0
        if !isSuspended { probe() }
    }

    func update(at time: Double) {
        guard isRequested, !isSuspended, time.isFinite else { return }
        self.time = max(0, time)
        // A new visit or seek may build one frame while paused. After that,
        // only resume can replace this generation's displayed scene.
        guard !isPlaybackPaused || displayedTime == nil else { return }
        // Camera attitude has its own recorded timeline. Missing depth or a busy
        // registration worker must not stop this lightweight viewing update.
        updateCameraRotation()
        guard let configuration else { return }
        let tolerance = configuration.staleTolerance
        guard !TAPVideoDepthGapPolicy.crossesGap(from: self.time, to: self.time, gaps: configuration.depthGaps) else {
            unavailable()
            return
        }
        guard let frame = cache.nearestFrame(to: self.time, staleToleranceSeconds: tolerance) else {
            if let displayedTime, self.time - displayedTime > tolerance { unavailable() }
            return
        }
        guard !TAPVideoDepthGapPolicy.crossesGap(from: frame.presentationTimeSeconds, to: self.time, gaps: configuration.depthGaps) else {
            unavailable()
            return
        }
        guard configuration.calibration(for: frame) != nil else {
            unavailable()
            return
        }
        guard displayedTime.map({ frame.presentationTimeSeconds > $0 }) ?? true,
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
        case .noSample:
            unavailable()
        case .decodeFailed:
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
        let latestRegisteredTime = spatialHistory.latestTime
        workTask = Task { [weak self, worker] in
            let result = try? await worker.make(
                frame: frame, rgb: rgb, configuration: configuration,
                latestRegisteredTime: latestRegisteredTime
            )
            guard let self else { return }
            defer {
                workTask = nil
                requestedTime = nil
                refreshPresentation()
                // A seek or a newer frame can proceed after physical capacity releases.
                if generation != token || cache.nearestFrame(to: time,
                    staleToleranceSeconds: configuration.staleTolerance)?.presentationTimeSeconds != frame.presentationTimeSeconds {
                    update(at: time)
                }
            }
            guard generation == token, isRequested, !isSuspended else {
                return
            }
            if let current = cache.nearestFrame(to: time, staleToleranceSeconds: configuration.staleTolerance),
               configuration.calibration(for: current) == nil {
                unavailable()
                return
            }
            if let result,
               result.payload.presentationTimeSeconds <= time + TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds {
                var geometry = result.payload
                geometry.rawSamples = []
                geometry.historicalFrames = []
                latestGeometry = geometry
                // Keep this physical slot until the latest map is composed. Map
                // changes repeat only composition, never RGB decode or projection.
                guard await composeLatestPresentation(configuration: configuration, generation: token) else { return }
                queueRegistration(result)
            } else if result == nil {
                unavailable()
            }
        }
    }

    private func probe() {
        guard isRequested, let configuration else { return }
        metadata?.probe(fileURL: configuration.fileURL, playbackTimeSeconds: time,
                        staleToleranceSeconds: configuration.staleTolerance,
                        leadToleranceSeconds: TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds)
    }

    private func clear(keepingPresentedFrame: Bool = false) {
        cache.clear()
        displayedTime = nil
        pendingPayload = nil
        latestObservation = nil
        latestObservationTime = nil
        latestGeometry = nil
        presentationHistoryTime = nil
        requestedTime = nil
        if !keepingPresentedFrame { store.clear() }
        onStateChange?(store.presentationTimeSeconds != nil)
    }

    private func invalidateWork() {
        generation &+= 1
        workTask?.cancel()
        registrationTask?.cancel()
        // Keep the physical worker occupied until its candidate returns. Only
        // MainActor owns the accepted map, so late candidates cannot clear it.
        spatialHistory = TAPVideoPointCloudHistory()
    }

    private func unavailable() {
        // Hold this video's last rendered frame through gaps. Its original PTS
        // stays in the store; it is never reused as current depth.
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
    var cameraMotion: TAPVideoPointCloudMotion?
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

nonisolated private struct TAPVideoPointCloudObservation: Sendable {
    let payload: TAPVideoPointCloudPayload
    let image: CGImage
}

nonisolated private struct TAPVideoPointCloudRegistrationResult: Sendable {
    let payload: TAPVideoPointCloudPayload
    let spatialHistory: TAPVideoPointCloudHistory
}

private actor TAPVideoPointCloudWorker {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func make(frame: TAPDecodedDepthVideoFrame, rgb: TAPVideoPointCloudRGB?,
              configuration: TAPVideoPointCloudConfiguration,
              latestRegisteredTime: Double?) async throws -> TAPVideoPointCloudObservation? {
        try Task.checkCancellation()
        guard latestRegisteredTime.map({ frame.presentationTimeSeconds >= $0 }) ?? true else { return nil }
        guard let savedCalibration = configuration.calibration(for: frame),
              let calibration = TAPVideoPointCloudCalibration(savedCalibration) else { return nil }
        let image: CGImage?
        if let rgb, let bufferedImage = rgb.image(configuration: configuration, context: context) { image = bufferedImage }
        else { image = try await fallbackImage(time: frame.presentationTimeSeconds, configuration: configuration) }
        try Task.checkCancellation()
        guard let image else { return nil }
        guard let projected = try TAPVideoPointCloudProjection.make(
            frame: frame, calibration: calibration,
            descriptor: configuration.descriptor, image: image
        ) else { return nil }
        return TAPVideoPointCloudObservation(payload: projected, image: image)
    }

    func presentation(of geometry: TAPVideoPointCloudPayload, configuration: TAPVideoPointCloudConfiguration,
                      spatialHistory: TAPVideoPointCloudHistory) throws -> TAPVideoPointCloudPayload {
        try Task.checkCancellation()
        var pose = spatialHistory.cameraToAnchor
        if let referenceTime = spatialHistory.latestTime,
           let rotation = configuration.cameraMotion?.rotation(from: referenceTime, to: geometry.presentationTimeSeconds) {
            // Motion supplies rotation only; translation stays at the last RGB-D estimate.
            pose *= simd_inverse(rotation)
        }
        let payload = spatialHistory.presentation(of: geometry, cameraToAnchor: pose)
        try Task.checkCancellation()
        return payload
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
