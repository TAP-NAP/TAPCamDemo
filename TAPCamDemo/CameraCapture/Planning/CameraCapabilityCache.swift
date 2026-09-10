@preconcurrency import AVFoundation
import CoreMedia
import CryptoKit
import Foundation

/// Startup-only persistence for format discovery. The caller commits its
/// waiting surface before discovery and runs both operations off MainActor.
/// Native device/format objects are rebound each process; only facts are saved.
nonisolated struct CameraCapabilityCache: Sendable {
    private let cacheURL: URL?

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("TAPCamDemo/Startup", isDirectory: true)
            .appendingPathComponent("camera-capabilities-v1.cache")
    }

    /// A miss never discovers formats. This lets startup publish and commit
    /// Resource Initialization before it calls `discoverAndCache`.
    func loadCached() -> CapabilityMatrix? {
        guard !Task.isCancelled,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let cacheURL,
              let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let devices = CameraCapabilityResolver.availableDevices()
        guard let identity = Identity.current(devices: devices),
              let snapshot = Snapshot.decode(data, matching: identity) else {
            return nil
        }
        let expected = CameraCapabilityResolver.depthDevices(in: devices)
        guard snapshot.candidates.count == expected.count else {
            return nil
        }
        var candidates: [DepthDeviceCandidate] = []
        for (stored, current) in zip(snapshot.candidates, expected) {
            guard !Task.isCancelled,
                  stored.kind == current.kind,
                  stored.deviceID == current.device.uniqueID,
                  let candidate = stored.restore(device: current.device) else {
                return nil
            }
            candidates.append(candidate)
        }
        guard !Task.isCancelled else { return nil }
        return CameraCapabilityResolver.matrix(
            devices: devices,
            depthCandidates: candidates,
            photographerModeFacts: snapshot.photographerModeFacts
        )
    }

    /// A failed write still returns this launch's usable matrix. It does not
    /// turn a transient empty/unauthorized enumeration into a persistent fact.
    func discoverAndCache() -> CapabilityMatrix {
        guard !Task.isCancelled else {
            return CapabilityMatrix(rgbSources: [], depthCandidates: [])
        }
        let devices = CameraCapabilityResolver.availableDevices()
        let matrix = CameraCapabilityResolver.discover(devices: devices)
        guard !Task.isCancelled,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let identity = Identity.current(devices: devices),
              let cacheURL else {
            return matrix
        }
        var candidates: [Candidate] = []
        for candidate in matrix.depthCandidates {
            guard !Task.isCancelled else { return matrix }
            candidates.append(Candidate(candidate))
        }
        let snapshot = Snapshot(
            identity: identity,
            candidates: candidates,
            photographerModeFacts: matrix.photographerModeFacts
        )
        do {
            let data = try snapshot.encoded()
            guard !Task.isCancelled else { return matrix }
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !Task.isCancelled,
                  AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                return matrix
            }
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Persistence is an optimization; retry only at the next startup.
        }
        return matrix
    }

    struct Identity: Codable, Equatable, Sendable {
        let runtime: StartupInitializationRuntimeIdentity
        let operatingSystem: String
        let deviceModel: String
        let deviceGenerationID: UUID
        let devices: [DeviceIdentity]

        static func current(devices: [AVCaptureDevice]) -> Identity? {
            guard !devices.isEmpty,
                  let runtime = StartupInitializationRuntimeIdentity.current(),
                  let deviceGenerationID = KeychainStartupDeviceGenerationStore().currentOrCreate() else {
                return nil
            }
            return Identity(
                runtime: runtime,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                deviceModel: DeviceModelIdentifier.current,
                deviceGenerationID: deviceGenerationID,
                devices: devices.map(DeviceIdentity.init).sorted { $0.id < $1.id }
            )
        }
    }

    struct DeviceIdentity: Codable, Equatable, Sendable {
        let id: String
        let type: String
        let position: Int
        let constituentIDs: [String]

        init(id: String, type: String, position: Int, constituentIDs: [String]) {
            self.id = id
            self.type = type
            self.position = position
            self.constituentIDs = constituentIDs
        }

        init(_ device: AVCaptureDevice) {
            self.init(
                id: device.uniqueID,
                type: device.deviceType.rawValue,
                position: device.position.rawValue,
                constituentIDs: device.constituentDevices.map(\.uniqueID).sorted()
            )
        }
    }

    struct Snapshot: Codable, Sendable {
        var schemaVersion = 1
        let identity: Identity
        let candidates: [Candidate]
        let photographerModeFacts: PhotographerModeCapabilityFacts

        func encoded() throws -> Data {
            let payload = try JSONEncoder().encode(self)
            // Detect damaged values or a truncated candidate list even when
            // the remaining bytes still form syntactically valid JSON.
            return Data(SHA256.hash(data: payload)) + payload
        }

        static func decode(_ data: Data, matching identity: Identity) -> Snapshot? {
            let payload = data.dropFirst(SHA256.byteCount)
            guard data.count > SHA256.byteCount,
                  Data(SHA256.hash(data: payload)) == data.prefix(SHA256.byteCount),
                  let snapshot = try? JSONDecoder().decode(Self.self, from: payload),
                  snapshot.schemaVersion == 1,
                  !identity.devices.isEmpty,
                  snapshot.identity == identity else {
                return nil
            }
            return snapshot
        }
    }

    struct Candidate: Codable, Sendable {
        let kind: DepthProfileKind
        let deviceID: String
        let videoFormatCount: Int
        let formats: [FormatPair]

        init(_ candidate: DepthDeviceCandidate) {
            kind = candidate.kind
            deviceID = candidate.device.uniqueID
            videoFormatCount = candidate.device.formats.count
            formats = candidate.formats.map(FormatPair.init)
        }

        func restore(device: AVCaptureDevice) -> DepthDeviceCandidate? {
            let nativeFormats = device.formats
            guard nativeFormats.count == videoFormatCount else { return nil }
            var restored: [DepthFormatCandidate] = []
            var previousVideoIndex = -1
            for pair in formats {
                let facts = pair.facts
                guard !Task.isCancelled,
                      facts.videoFormatIndex > previousVideoIndex,
                      nativeFormats.indices.contains(facts.videoFormatIndex) else {
                    return nil
                }
                let videoFormat = nativeFormats[facts.videoFormatIndex]
                let depthFormats = videoFormat.supportedDepthDataFormats
                guard depthFormats.count == pair.depthFormatCount,
                      depthFormats.indices.contains(facts.depthFormatIndex),
                      facts.score.isFinite,
                      facts.depthSafeZoomRanges == pair.video.depthZoomRanges,
                      VideoFingerprint(videoFormat) == pair.video else {
                    return nil
                }
                let depthFormat = depthFormats[facts.depthFormatIndex]
                guard FormatFingerprint(depthFormat) == pair.depth else {
                    return nil
                }
                restored.append(DepthFormatCandidate(
                    selection: PhotoDepthFormatSelection(videoFormat: videoFormat, depthFormat: depthFormat),
                    facts: facts
                ))
                previousVideoIndex = facts.videoFormatIndex
            }
            return DepthDeviceCandidate(kind: kind, device: device, formats: restored)
        }
    }

    struct FormatPair: Codable, Sendable {
        let facts: DepthFormatFacts
        let depthFormatCount: Int
        let video: VideoFingerprint
        let depth: FormatFingerprint

        init(_ candidate: DepthFormatCandidate) {
            facts = candidate.facts
            depthFormatCount = candidate.selection.videoFormat.supportedDepthDataFormats.count
            video = VideoFingerprint(candidate.selection.videoFormat)
            depth = FormatFingerprint(candidate.selection.depthFormat)
        }
    }

    /// No stable AVFoundation format ID exists. These exact indexed fields
    /// cover the format capabilities consumed by planning and session setup;
    /// a mismatch causes discovery, never a width/height-based substitution.
    struct VideoFingerprint: Codable, Equatable, Sendable {
        let format: FormatFingerprint
        let fieldOfView: Float
        let maximumZoom: Double
        let depthZoomRanges: [ClosedRange<Double>]
        let allowsZoomOutsideDepthRanges: Bool
        let recommendedZoomRange: ClosedRange<Double>?
        let minimumISO: Float
        let maximumISO: Float
        let minimumExposure: Time
        let maximumExposure: Time
        let photoDimensions: [Dimensions]
        let unsupportedOutputClasses: [String]

        init(_ format: AVCaptureDevice.Format) {
            self.format = FormatFingerprint(format)
            fieldOfView = format.videoFieldOfView
            maximumZoom = Double(format.videoMaxZoomFactor)
            depthZoomRanges = format.supportedVideoZoomRangesForDepthDataDelivery.map {
                Double($0.lowerBound)...Double($0.upperBound)
            }
            allowsZoomOutsideDepthRanges = format.zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported
            recommendedZoomRange = format.systemRecommendedVideoZoomRange.map {
                Double($0.lowerBound)...Double($0.upperBound)
            }
            minimumISO = format.minISO
            maximumISO = format.maxISO
            minimumExposure = Time(format.minExposureDuration)
            maximumExposure = Time(format.maxExposureDuration)
            photoDimensions = format.supportedMaxPhotoDimensions.map(Dimensions.init)
            unsupportedOutputClasses = format.unsupportedCaptureOutputClasses.map(NSStringFromClass).sorted()
        }
    }

    struct FormatFingerprint: Codable, Equatable, Sendable {
        let mediaType: UInt32
        let mediaSubtype: UInt32
        let dimensions: Dimensions
        let frameRates: [FrameRateRange]

        init(_ format: AVCaptureDevice.Format) {
            mediaType = CMFormatDescriptionGetMediaType(format.formatDescription)
            mediaSubtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            dimensions = Dimensions(CMVideoFormatDescriptionGetDimensions(format.formatDescription))
            frameRates = format.videoSupportedFrameRateRanges.map(FrameRateRange.init)
        }
    }

    struct Dimensions: Codable, Equatable, Sendable {
        let width: Int32
        let height: Int32

        init(_ dimensions: CMVideoDimensions) {
            width = dimensions.width
            height = dimensions.height
        }
    }

    struct FrameRateRange: Codable, Equatable, Sendable {
        let minimum: Double
        let maximum: Double
        let minimumDuration: Time
        let maximumDuration: Time

        init(_ range: AVFrameRateRange) {
            minimum = range.minFrameRate
            maximum = range.maxFrameRate
            minimumDuration = Time(range.minFrameDuration)
            maximumDuration = Time(range.maxFrameDuration)
        }
    }

    struct Time: Codable, Equatable, Sendable {
        let value: Int64
        let timescale: Int32
        let flags: UInt32
        let epoch: Int64

        init(_ time: CMTime) {
            value = time.value
            timescale = time.timescale
            flags = time.flags.rawValue
            epoch = time.epoch
        }
    }
}
