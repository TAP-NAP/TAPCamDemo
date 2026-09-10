@preconcurrency import CoreMedia
@preconcurrency import CoreMotion
import Foundation

/// One recording's bounded motion stream. It never waits for sensors to start
/// and never owns camera, signing, or export state.
nonisolated final class TAPVideoMotionRecorder: @unchecked Sendable {
    private struct CapturedSample {
        let captureTime: Double
        let motionTime: Double
        let measurement: TAPVideoCaptureTelemetry.Sample
    }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "tapcam.video.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private let lock = NSLock()
    private var isActive = false
    private var isAvailable = false
    private var samples: [CapturedSample] = []
    private var droppedSampleCount = 0
    private var errorCount = 0

    deinit { manager.stopDeviceMotionUpdates() }

    func start(captureClock: CMClock?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isActive else { return }
        guard manager.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            return
        }
        guard let captureClock else {
            errorCount += 1
            return
        }
        isAvailable = true
        isActive = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
            self?.receive(motion, error: error, captureClock: captureClock)
        }
    }

    func stop(recordingError: Bool = false) {
        lock.lock()
        if recordingError && isActive { errorCount += 1 }
        isActive = false
        lock.unlock()
        manager.stopDeviceMotionUpdates()
    }

    private func receive(_ motion: CMDeviceMotion?, error: (any Error)?, captureClock: CMClock) {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { return }
        guard error == nil, let motion else {
            errorCount += 1
            return
        }
        guard samples.count < TAPVideoCaptureTelemetryBox.maximumSampleCount else {
            droppedSampleCount += 1
            return
        }
        guard motion.timestamp.isFinite, motion.timestamp >= 0 else {
            errorCount += 1
            return
        }
        // Core Motion's boot-relative seconds use the host-time epoch. Convert
        // every sample through the session clock; audio can choose its clock.
        let hostTime = CMTime(seconds: motion.timestamp, preferredTimescale: 1_000_000_000)
        let captureTime = CMSyncConvertTime(hostTime, from: CMClockGetHostTimeClock(), to: captureClock)
        let seconds = CMTimeGetSeconds(captureTime)
        let attitude = motion.attitude.quaternion
        let rotation = motion.rotationRate
        let gravity = motion.gravity
        let acceleration = motion.userAcceleration
        let sample = TAPVideoCaptureTelemetry.Sample(
            ptsSeconds: seconds,
            quaternion: [attitude.x, attitude.y, attitude.z, attitude.w],
            rotationRate: [rotation.x, rotation.y, rotation.z],
            gravity: [gravity.x, gravity.y, gravity.z],
            userAcceleration: [acceleration.x, acceleration.y, acceleration.z]
        )
        guard captureTime.isValid, !captureTime.isIndefinite, seconds.isFinite else {
            errorCount += 1
            return
        }
        guard sample.hasValidMeasurements,
              samples.last.map({ seconds > $0.captureTime }) ?? true else {
            droppedSampleCount += 1
            return
        }
        samples.append(CapturedSample(captureTime: seconds, motionTime: motion.timestamp, measurement: sample))
    }

    func snapshot(firstVideoTime: CMTime?, durationSeconds: Double) -> TAPVideoCaptureTelemetry.Motion {
        lock.lock()
        defer { lock.unlock() }
        var result = TAPVideoCaptureTelemetry.Motion(
            status: isAvailable && errorCount == 0 ? .noSamples : .unavailable,
            droppedSampleCount: droppedSampleCount,
            errorCount: errorCount
        )
        guard let firstVideoTime else { return result }
        let origin = CMTimeGetSeconds(firstVideoTime)
        for captured in samples {
            let time = captured.captureTime - origin
            guard time.isFinite, time >= 0, time <= durationSeconds else {
                continue
            }
            let sample = captured.measurement
            result.samples.append(.init(
                ptsSeconds: time,
                quaternion: sample.quaternion,
                rotationRate: sample.rotationRate,
                gravity: sample.gravity,
                userAcceleration: sample.userAcceleration
            ))
            if result.motionToCaptureOffsetSeconds == nil {
                result.motionToCaptureOffsetSeconds = time - captured.motionTime
            }
        }
        if !result.samples.isEmpty {
            result.status = result.droppedSampleCount > 0 || result.errorCount > 0 ? .partial : .available
        } else if result.errorCount > 0 {
            result.status = .unavailable
        }
        return result
    }
}
