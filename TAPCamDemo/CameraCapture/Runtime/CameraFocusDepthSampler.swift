@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

nonisolated struct CameraFocusTargetMeasurement: Sendable {
    let meters: Double
}

/// Reads one small region from a fresh, unfiltered LiDAR frame. It retains no
/// depth frames and performs no work when no measurement is pending.
nonisolated final class CameraFocusDepthSampler: NSObject,
    AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    let depthOutput = AVCaptureDepthDataOutput()
    private let callbackQueue = DispatchQueue(label: "tapcam.camera-capture.focus-depth")
    private let lock = NSLock()
    private var pending: Request?

    private struct Request {
        let id: UUID
        let point: CameraManualControlIntent.NormalizedPoint
        let earliestTime: CMTime
        let clock: CMClock
        let completion: @Sendable (CameraFocusTargetMeasurement?) -> Void
    }

    override init() {
        super.init()
        depthOutput.isFilteringEnabled = false
        depthOutput.alwaysDiscardsLateDepthData = true
        depthOutput.setDelegate(self, callbackQueue: callbackQueue)
    }

    deinit {
        depthOutput.setDelegate(nil, callbackQueue: nil)
        pending?.completion(nil)
    }

    func request(
        id: UUID,
        point: CameraManualControlIntent.NormalizedPoint,
        earliestTime: CMTime,
        clock: CMClock,
        completion: @escaping @Sendable (CameraFocusTargetMeasurement?) -> Void
    ) {
        lock.lock()
        let previous = pending
        pending = Request(
            id: id, point: point, earliestTime: earliestTime,
            clock: clock, completion: completion
        )
        lock.unlock()
        previous?.completion(nil)
        callbackQueue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.cancel(id: id)
        }
    }

    func cancel(id: UUID? = nil) {
        lock.lock()
        guard let request = pending, id == nil || request.id == id else {
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()
        request.completion(nil)
    }

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        guard output === depthOutput,
              !connection.isVideoMirrored, connection.videoRotationAngle == 0 else { return }
        consume(depthData, timestamp: timestamp)
    }

    private func consume(_ depthData: AVDepthData, timestamp: CMTime) {
        lock.lock()
        guard let request = pending,
              Self.isFresh(
                timestamp: timestamp,
                earliestTime: request.earliestTime,
                now: CMClockGetTime(request.clock)
              ),
              Self.accepts(
                accuracy: depthData.depthDataAccuracy,
                quality: depthData.depthDataQuality,
                isFiltered: depthData.isDepthDataFiltered
              ) else {
            lock.unlock()
            return
        }
        let metric = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let distance = Self.distance(in: metric.depthDataMap, at: request.point)
        if distance != nil { pending = nil }
        lock.unlock()
        if let distance {
            request.completion(CameraFocusTargetMeasurement(meters: distance))
        }
    }

    static func accepts(
        accuracy: AVDepthData.Accuracy,
        quality: AVDepthData.Quality,
        isFiltered: Bool
    ) -> Bool {
        accuracy == .absolute && quality == .high && !isFiltered
    }

    static func isFresh(timestamp: CMTime, earliestTime: CMTime, now: CMTime) -> Bool {
        guard timestamp.isNumeric, earliestTime.isNumeric, now.isNumeric,
              CMTimeCompare(timestamp, earliestTime) >= 0 else { return false }
        let age = CMTimeGetSeconds(CMTimeSubtract(now, timestamp))
        let timeSinceLock = CMTimeGetSeconds(CMTimeSubtract(timestamp, earliestTime))
        return age >= 0 && age <= 0.35 && timeSinceLock <= 0.8
    }

    /// AF coordinates refer to the unrotated, unmirrored camera image. LiDAR
    /// depth shares that image's field of view and lens distortion, so the same
    /// normalized point selects the corresponding depth pixel (no 3D rectification).
    static func distance(
        in map: CVPixelBuffer,
        at point: CameraManualControlIntent.NormalizedPoint
    ) -> Double? {
        guard point.isInsideUnitRect,
              CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0,
              CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
        let pixels = base.assumingMemoryBound(to: Float.self)
        let x = min(width - 1, Int(point.x * Double(width)))
        let y = min(height - 1, Int(point.y * Double(height)))
        let xRange = max(0, x - 2)...min(width - 1, x + 2)
        let yRange = max(0, y - 2)...min(height - 1, y + 2)
        let center = Double(pixels[y * stride + x])
        guard center.isFinite, center > 0 else { return nil }
        var values: [Double] = []
        values.reserveCapacity(25)
        for row in yRange {
            for column in xRange {
                let value = Double(pixels[row * stride + column])
                if value.isFinite && value > 0 { values.append(value) }
            }
        }
        guard values.count >= max(5, (xRange.count * yRange.count + 1) / 2) else { return nil }
        values.sort()
        let median = values[values.count / 2]
        // A mixed foreground/background patch must not teach a false lens-
        // distance pair. These bounds express sample agreement, not accuracy.
        let tolerance = max(0.08, median * 0.12)
        let lower = values[values.count / 4]
        let upper = values[(values.count * 3) / 4]
        guard upper - lower <= tolerance,
              abs(center - median) <= tolerance else { return nil }
        return median
    }
}
