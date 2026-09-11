import Foundation

/// Optional signed capture facts. Display smoothing never writes this document.
nonisolated struct TAPVideoCaptureTelemetry: Codable, Equatable, Sendable {
    struct Schema: Codable, Equatable, Sendable {
        var id = "urn:tapnap:tapcam:video-capture-telemetry:v1"
        var version = 1
        var mediaType = "application/vnd.tapnap.video-capture-telemetry+json;version=1"
    }

    struct Filtering: Codable, Equatable, Sendable {
        let requestedEnabled: Bool
        var filteredSampleCount = 0
        var unfilteredSampleCount = 0
    }

    struct Motion: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable { case available, unavailable, noSamples, partial }
        var status: Status
        var referenceFrame = "xArbitraryZVertical"
        var deviceCoordinateSystem = "core-motion-device-right-handed"
        var timeBase = "capture-relative-seconds"
        var motionToCaptureOffsetSeconds: Double?
        var sampleIntervalSeconds = 1.0 / 30.0
        var droppedSampleCount = 0
        var errorCount = 0
        var samples: [Sample] = []

        private enum CodingKeys: String, CodingKey {
            case status, referenceFrame, deviceCoordinateSystem, timeBase
            case motionToCaptureOffsetSeconds, sampleIntervalSeconds
            case droppedSampleCount, errorCount, samples
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(referenceFrame, forKey: .referenceFrame)
            try container.encode(deviceCoordinateSystem, forKey: .deviceCoordinateSystem)
            try container.encode(timeBase, forKey: .timeBase)
            try container.encode(motionToCaptureOffsetSeconds, forKey: .motionToCaptureOffsetSeconds)
            try container.encode(sampleIntervalSeconds, forKey: .sampleIntervalSeconds)
            try container.encode(droppedSampleCount, forKey: .droppedSampleCount)
            try container.encode(errorCount, forKey: .errorCount)
            try container.encode(samples, forKey: .samples)
        }
    }

    struct Sample: Codable, Equatable, Sendable {
        let ptsSeconds: Double
        let quaternion: [Double]
        let rotationRate: [Double]
        let gravity: [Double]
        let userAcceleration: [Double]

        var hasValidMeasurements: Bool {
            let normSquared = quaternion.reduce(0) { $0 + $1 * $1 }
            return ptsSeconds.isFinite && quaternion.count == 4
                && abs(normSquared - 1) <= 0.01
                && [rotationRate, gravity, userAcceleration].allSatisfy { $0.count == 3 }
                && [quaternion, rotationRate, gravity, userAcceleration]
                    .allSatisfy { $0.allSatisfy(\.isFinite) }
        }
    }

    var schema = Schema()
    let filtering: Filtering
    var motion: Motion
}

nonisolated enum TAPVideoCaptureTelemetryBox {
    static let uuid = Data("TAPCAMTELEMETRY1".utf8)
    static let maximumByteCount = 4 * 1024 * 1024
    static let maximumSampleCount = 8_192

    static func append(
        _ telemetry: TAPVideoCaptureTelemetry,
        to fileURL: URL
    ) throws {
        var telemetry = telemetry
        let layout = try TAPVideoContainerLayout.read(from: fileURL)
        guard !layout.topLevelBoxes.contains(where: { $0.userType == uuid }),
              layout.topLevelBoxes.last?.usesToEndSize != true else {
            throw TAPDepthCaptureError.invalidTAPManifest("cannot append capture telemetry box")
        }
        var payload = try JSONEncoder.tapCaptureCanonical.encode(telemetry)
        while payload.count > maximumByteCount, !telemetry.motion.samples.isEmpty {
            let discardCount = max(1, telemetry.motion.samples.count / 4)
            telemetry.motion.samples.removeLast(discardCount)
            telemetry.motion.droppedSampleCount += discardCount
            if telemetry.motion.samples.isEmpty {
                telemetry.motion.status = telemetry.motion.errorCount > 0 ? .unavailable : .noSamples
                telemetry.motion.motionToCaptureOffsetSeconds = nil
            } else {
                telemetry.motion.status = .partial
            }
            payload = try JSONEncoder.tapCaptureCanonical.encode(telemetry)
        }
        guard payload.count <= maximumByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("capture telemetry exceeds bounded payload limit")
        }
        var size = UInt32(payload.count + uuid.count + 8).bigEndian
        var box = withUnsafeBytes(of: &size) { Data($0) }
        box.append(Data("uuid".utf8))
        box.append(uuid)
        box.append(payload)
        try TAPBMFFStreamingFile.append(box, to: fileURL)
    }
}
