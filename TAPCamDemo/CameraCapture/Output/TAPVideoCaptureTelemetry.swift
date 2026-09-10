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

    func validate(manifest: TAPVideoManifest) throws {
        let maximumCount = 9_007_199_254_740_991
        let (delivered, overflow) = filtering.filteredSampleCount
            .addingReportingOverflow(filtering.unfilteredSampleCount)
        guard schema == Schema(), !overflow,
              [filtering.filteredSampleCount, filtering.unfilteredSampleCount,
               motion.droppedSampleCount, motion.errorCount].allSatisfy({ (0...maximumCount).contains($0) }),
              delivered == manifest.payload.depthCoverage.deliveredSampleCount,
              motion.referenceFrame == "xArbitraryZVertical",
              motion.deviceCoordinateSystem == "core-motion-device-right-handed",
              motion.timeBase == "capture-relative-seconds",
              motion.sampleIntervalSeconds.isFinite, motion.sampleIntervalSeconds > 0,
              motion.sampleIntervalSeconds <= 1,
              motion.samples.count <= TAPVideoCaptureTelemetryBox.maximumSampleCount,
              motion.motionToCaptureOffsetSeconds.map(\.isFinite) ?? true else {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid capture telemetry facts")
        }
        let hasSamples = !motion.samples.isEmpty
        let hasLoss = motion.droppedSampleCount > 0 || motion.errorCount > 0
        let validStatus: Bool
        switch motion.status {
        case .available: validStatus = hasSamples && !hasLoss
        case .partial: validStatus = hasSamples && hasLoss
        case .noSamples: validStatus = !hasSamples && motion.errorCount == 0
        case .unavailable: validStatus = !hasSamples
        }
        guard validStatus, !hasSamples || motion.motionToCaptureOffsetSeconds != nil else {
            throw TAPDepthCaptureError.invalidTAPManifest("inconsistent motion availability")
        }
        var previousTime = -Double.infinity
        let duration = manifest.payload.container.durationSeconds
        let tolerance = 1 / Double(max(manifest.payload.container.timeScale, 1))
        for sample in motion.samples {
            guard sample.hasValidMeasurements, sample.ptsSeconds >= 0,
                  sample.ptsSeconds > previousTime,
                  sample.ptsSeconds <= duration + tolerance else {
                throw TAPDepthCaptureError.invalidTAPManifest("invalid motion sample or timeline")
            }
            previousTime = sample.ptsSeconds
        }
    }
}

nonisolated enum TAPVideoCaptureTelemetryBox {
    static let uuid = Data("TAPCAMTELEMETRY1".utf8)
    static let maximumByteCount = 4 * 1024 * 1024
    static let maximumSampleCount = 8_192

    static func append(
        _ telemetry: TAPVideoCaptureTelemetry,
        manifest: TAPVideoManifest,
        to fileURL: URL
    ) throws {
        var telemetry = telemetry
        try telemetry.validate(manifest: manifest)
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
        try telemetry.validate(manifest: manifest)
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

    static func read(
        from fileURL: URL,
        manifest: TAPVideoManifest,
        layout: TAPVideoContainerLayout? = nil
    ) throws -> TAPVideoCaptureTelemetry? {
        let layout = try layout ?? TAPVideoContainerLayout.read(from: fileURL)
        let boxes = layout.topLevelBoxes.filter { $0.type == "uuid" && $0.userType == uuid }
        guard !boxes.isEmpty else { return nil }
        guard boxes.count == 1, let box = boxes.first else {
            throw TAPDepthCaptureError.invalidTAPManifest("duplicate capture telemetry box")
        }
        let data = try TAPBMFFStreamingFile.read(box.payloadRange, from: fileURL, maximumByteCount: maximumByteCount)
        let telemetry = try JSONDecoder().decode(TAPVideoCaptureTelemetry.self, from: data)
        // Compare structure and lexical rules without requiring one particular
        // decimal spelling for measured numbers. The signed bytes stay intact.
        guard try normalizedNumberTokens(JSONEncoder.tapCaptureCanonical.encode(telemetry))
                == normalizedNumberTokens(data) else {
            throw TAPDepthCaptureError.invalidTAPManifest("capture telemetry must use its exact canonical schema")
        }
        try telemetry.validate(manifest: manifest)
        return telemetry
    }

    private static func normalizedNumberTokens(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        let tokens = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"#)
        let source = text as NSString
        var previousString = ""
        var result = ""
        var cursor = 0
        let integerKeys: Set<String> = ["\"version\"", "\"filteredSampleCount\"", "\"unfilteredSampleCount\"", "\"droppedSampleCount\"", "\"errorCount\""]
        for match in tokens.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = source.substring(with: match.range)
            if token.first == "\"" {
                previousString = token
                result += token
            } else if integerKeys.contains(previousString) {
                result += token
            } else if let value = Double(token), value.isFinite {
                result += String(value)
            } else {
                throw TAPDepthCaptureError.invalidTAPManifest("nonfinite telemetry number")
            }
            cursor = NSMaxRange(match.range)
        }
        result += source.substring(from: cursor)
        return result
    }
}
