//
//  TAPVideoManifestSchema.swift
//  TAPCamDemo
//

import Foundation

/// Versioned TAP metadata contract for one signed video resource.
///
/// The artifact is always one MP4 resource. Depth coverage is a fact inside the
/// payload, not a separate product or verification family.
nonisolated struct TAPVideoManifest: Codable, Equatable, Sendable {
    static let schemaIdentifier = "urn:tapnap:tapcam:video-manifest:v1"
    static let mediaType = "application/vnd.tapnap.video-manifest+json;version=1"
    static let payloadMediaType = "application/vnd.tapnap.video-manifest.payload+json;version=1"

    let schema: Schema
    let payload: Payload
    let proofs: [Proof]

    init(payload: Payload, proofs: [Proof] = [], schema: Schema = Schema()) {
        self.schema = schema
        self.payload = payload
        self.proofs = proofs
    }
}

extension TAPVideoManifest {
    nonisolated struct Schema: Codable, Equatable, Sendable {
        let id: String
        let version: Int
        let mediaType: String

        init(
            id: String = TAPVideoManifest.schemaIdentifier,
            version: Int = 1,
            mediaType: String = TAPVideoManifest.mediaType
        ) {
            self.id = id
            self.version = version
            self.mediaType = mediaType
        }
    }

    typealias Proof = TAPCaptureProof

    nonisolated struct Payload: Codable, Equatable, Sendable {
        let id: String
        let packageID: String
        let capturedAt: String
        let selectedCameraPlan: SelectedCameraPlan
        let container: Container
        let rgbTrack: RGBTrack
        let audioTrack: AudioTrack
        let depthCoverage: DepthCoverage
        let spatialRegistration: SpatialRegistration
        let synchronization: Synchronization
        let stop: Stop
        let software: Software

        init(
            id: String,
            packageID: String = "unknown",
            capturedAt: String,
            selectedCameraPlan: SelectedCameraPlan,
            container: Container,
            rgbTrack: RGBTrack,
            audioTrack: AudioTrack,
            depthCoverage: DepthCoverage,
            spatialRegistration: SpatialRegistration = .unavailable,
            synchronization: Synchronization,
            stop: Stop,
            software: Software
        ) {
            self.id = id
            self.packageID = packageID
            self.capturedAt = capturedAt
            self.selectedCameraPlan = selectedCameraPlan
            self.container = container
            self.rgbTrack = rgbTrack
            self.audioTrack = audioTrack
            self.depthCoverage = depthCoverage
            self.spatialRegistration = spatialRegistration
            self.synchronization = synchronization
            self.stop = stop
            self.software = software
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case packageID
            case capturedAt
            case selectedCameraPlan
            case container
            case rgbTrack
            case audioTrack
            case depthCoverage
            case spatialRegistration
            case synchronization
            case stop
            case software
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(packageID, forKey: .packageID)
            try container.encode(capturedAt, forKey: .capturedAt)
            try container.encode(selectedCameraPlan, forKey: .selectedCameraPlan)
            try container.encode(self.container, forKey: .container)
            try container.encode(rgbTrack, forKey: .rgbTrack)
            try container.encode(audioTrack, forKey: .audioTrack)
            try container.encode(depthCoverage, forKey: .depthCoverage)
            try container.encode(spatialRegistration, forKey: .spatialRegistration)
            try container.encode(synchronization, forKey: .synchronization)
            try container.encode(stop, forKey: .stop)
            try container.encode(software, forKey: .software)
        }
    }

    nonisolated struct SelectedCameraPlan: Codable, Equatable, Sendable {
        let deviceUniqueID: String?
        let deviceType: String?
        let localizedName: String?
        let position: String
        let requestedFocalLengthLabel: String?
        let resolvedFocalLengthLabel: String?
        let resolvedZoomFactor: Double?
        let depthCapable: Bool
    }

    nonisolated struct Container: Codable, Equatable, Sendable {
        let fileType: String
        let mediaType: String
        let durationSeconds: Double
        let timeScale: Int32
        let trackCount: Int
    }

    nonisolated struct RGBTrack: Codable, Equatable, Sendable {
        let trackID: Int32?
        let codec: String
        let width: Int32
        let height: Int32
        let durationSeconds: Double
        let timeScale: Int32
        let nominalFrameRate: Double?
        let frameCount: Int?
        let transform: String?

        init(
            trackID: Int32?,
            codec: String,
            width: Int32,
            height: Int32,
            durationSeconds: Double,
            timeScale: Int32,
            nominalFrameRate: Double?,
            frameCount: Int?,
            transform: String?
        ) {
            self.trackID = trackID
            self.codec = codec
            self.width = width
            self.height = height
            self.durationSeconds = durationSeconds
            self.timeScale = timeScale
            self.nominalFrameRate = nominalFrameRate
            self.frameCount = frameCount
            self.transform = transform
        }
    }

    nonisolated struct AudioTrack: Codable, Equatable, Sendable {
        let status: AudioStatus
        let trackID: Int32?
        let codec: String?
        let durationSeconds: Double?
        let timeScale: Int32?
        let sampleRate: Double?
        let channelCount: Int?

        init(
            status: AudioStatus,
            trackID: Int32?,
            codec: String?,
            durationSeconds: Double?,
            timeScale: Int32?,
            sampleRate: Double?,
            channelCount: Int?
        ) {
            self.status = status
            self.trackID = trackID
            self.codec = codec
            self.durationSeconds = durationSeconds
            self.timeScale = timeScale
            self.sampleRate = sampleRate
            self.channelCount = channelCount
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case trackID
            case codec
            case durationSeconds
            case timeScale
            case sampleRate
            case channelCount
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(trackID, forKey: .trackID)
            try container.encode(codec, forKey: .codec)
            try container.encode(durationSeconds, forKey: .durationSeconds)
            try container.encode(timeScale, forKey: .timeScale)
            try container.encode(sampleRate, forKey: .sampleRate)
            try container.encode(channelCount, forKey: .channelCount)
        }
    }

    nonisolated enum AudioStatus: String, Codable, Equatable, Sendable {
        case captured
        case notCaptured
        case unavailable
    }

    nonisolated struct DepthCoverage: Codable, Equatable, Sendable {
        static let maximumGapCount = 1_024

        let trackID: Int32?
        let trackCodec: String?
        let trackDurationSeconds: Double?
        let trackTimeScale: Int32?
        let sampleCount: Int
        let deliveredSampleCount: Int
        let outputDropCount: Int
        let encodingDropCount: Int
        let metadataDropCount: Int
        let gapCount: Int
        let gaps: [DepthGap]
        let format: DepthFormat?

        init(
            trackID: Int32?,
            trackCodec: String? = nil,
            trackDurationSeconds: Double? = nil,
            trackTimeScale: Int32? = nil,
            sampleCount: Int,
            deliveredSampleCount: Int? = nil,
            outputDropCount: Int = 0,
            encodingDropCount: Int = 0,
            metadataDropCount: Int = 0,
            gaps: [DepthGap] = [],
            format: DepthFormat?
        ) {
            self.trackID = trackID
            self.trackCodec = trackCodec
            self.trackDurationSeconds = trackDurationSeconds
            self.trackTimeScale = trackTimeScale
            self.sampleCount = sampleCount
            self.deliveredSampleCount = deliveredSampleCount ?? sampleCount
            self.outputDropCount = outputDropCount
            self.encodingDropCount = encodingDropCount
            self.metadataDropCount = metadataDropCount
            self.gapCount = gaps.count
            self.gaps = gaps
            self.format = format
        }

        nonisolated static let none = DepthCoverage(
            trackID: nil,
            sampleCount: 0,
            gaps: [],
            format: nil
        )

        private enum CodingKeys: String, CodingKey {
            case trackID
            case trackCodec
            case trackDurationSeconds
            case trackTimeScale
            case sampleCount
            case deliveredSampleCount
            case outputDropCount
            case encodingDropCount
            case metadataDropCount
            case gapCount
            case gaps
            case format
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(trackID, forKey: .trackID)
            try container.encode(trackCodec, forKey: .trackCodec)
            try container.encode(trackDurationSeconds, forKey: .trackDurationSeconds)
            try container.encode(trackTimeScale, forKey: .trackTimeScale)
            try container.encode(sampleCount, forKey: .sampleCount)
            try container.encode(deliveredSampleCount, forKey: .deliveredSampleCount)
            try container.encode(outputDropCount, forKey: .outputDropCount)
            try container.encode(encodingDropCount, forKey: .encodingDropCount)
            try container.encode(metadataDropCount, forKey: .metadataDropCount)
            try container.encode(gapCount, forKey: .gapCount)
            try container.encode(gaps, forKey: .gaps)
            try container.encode(format, forKey: .format)
        }
    }

    nonisolated struct DepthFormat: Codable, Equatable, Sendable {
        let kind: String
        let pixelFormat: String
        let width: Int32
        let height: Int32
        let packedRowStride: Int
        let sourceRowStride: Int?
        let bytesPerSample: Int
        let byteOrder: String
        let uncompressedFrameByteCount: Int
        let compressionPolicy: String

        init(
            kind: String,
            pixelFormat: String,
            width: Int32,
            height: Int32,
            packedRowStride: Int,
            sourceRowStride: Int? = nil,
            bytesPerSample: Int,
            byteOrder: String = "little-endian",
            uncompressedFrameByteCount: Int,
            compressionPolicy: String = "per-frame:zstd1|raw"
        ) {
            self.kind = kind
            self.pixelFormat = pixelFormat
            self.width = width
            self.height = height
            self.packedRowStride = packedRowStride
            self.sourceRowStride = sourceRowStride
            self.bytesPerSample = bytesPerSample
            self.byteOrder = byteOrder
            self.uncompressedFrameByteCount = uncompressedFrameByteCount
            self.compressionPolicy = compressionPolicy
        }

        /// Compares only the bytes stored in each depth frame. The source
        /// pixel-buffer stride is capture-time padding and may legitimately
        /// vary without changing the packed payload contract.
        func hasSameStoredFrameLayout(as other: Self) -> Bool {
            kind == other.kind
                && pixelFormat == other.pixelFormat
                && width == other.width
                && height == other.height
                && packedRowStride == other.packedRowStride
                && bytesPerSample == other.bytesPerSample
                && byteOrder == other.byteOrder
                && uncompressedFrameByteCount == other.uncompressedFrameByteCount
                && compressionPolicy == other.compressionPolicy
        }
    }

    nonisolated struct CalibrationCoverage: Codable, Equatable, Sendable {
        let indexedSampleCount: Int
        let missingCalibrationSampleCount: Int
        let overflowUnindexedSampleCount: Int
        let tableOverflowed: Bool

        init(
            indexedSampleCount: Int,
            missingCalibrationSampleCount: Int,
            overflowUnindexedSampleCount: Int,
            tableOverflowed: Bool
        ) {
            self.indexedSampleCount = indexedSampleCount
            self.missingCalibrationSampleCount = missingCalibrationSampleCount
            self.overflowUnindexedSampleCount = overflowUnindexedSampleCount
            self.tableOverflowed = tableOverflowed
        }

        var accountedSampleCount: Int? {
            let (indexedAndMissing, firstOverflow) = indexedSampleCount
                .addingReportingOverflow(missingCalibrationSampleCount)
            guard !firstOverflow else {
                return nil
            }
            let (total, secondOverflow) = indexedAndMissing
                .addingReportingOverflow(overflowUnindexedSampleCount)
            return secondOverflow ? nil : total
        }

        static let none = CalibrationCoverage(
            indexedSampleCount: 0,
            missingCalibrationSampleCount: 0,
            overflowUnindexedSampleCount: 0,
            tableOverflowed: false
        )
    }

    nonisolated struct SpatialRegistration: Codable, Equatable, Sendable {
        static let maximumCalibrationCount = 16

        let status: RegistrationStatus
        let mapping: String
        let rgbReferenceDimensions: Dimensions?
        let depthReferenceDimensions: Dimensions?
        let rgbCleanAperture: Rect?
        let recordedTransform: String?
        let calibrationTable: [CameraCalibration]
        let calibrationCoverage: CalibrationCoverage
        let descriptor: RegistrationDescriptor?

        var calibration: CameraCalibration? {
            calibrationTable.first
        }

        init(
            status: RegistrationStatus,
            mapping: String,
            rgbReferenceDimensions: Dimensions?,
            depthReferenceDimensions: Dimensions?,
            rgbCleanAperture: Rect?,
            recordedTransform: String?,
            calibration: CameraCalibration? = nil,
            calibrationTable: [CameraCalibration]? = nil,
            calibrationCoverage: CalibrationCoverage = .none,
            descriptor: RegistrationDescriptor? = nil
        ) {
            self.status = status
            self.mapping = mapping
            self.rgbReferenceDimensions = rgbReferenceDimensions
            self.depthReferenceDimensions = depthReferenceDimensions
            self.rgbCleanAperture = rgbCleanAperture
            self.recordedTransform = recordedTransform
            self.calibrationTable = calibrationTable ?? calibration.map { [$0] } ?? []
            self.calibrationCoverage = calibrationCoverage
            self.descriptor = descriptor
        }

        static let unavailable = SpatialRegistration(
            status: .unavailable,
            mapping: "unavailable",
            rgbReferenceDimensions: nil,
            depthReferenceDimensions: nil,
            rgbCleanAperture: nil,
            recordedTransform: nil,
            calibration: nil,
            calibrationTable: [],
            calibrationCoverage: .none,
            descriptor: nil
        )
    }

    /// Reproducible RGB/depth mapping contract. Version 1 is intentionally
    /// narrow: AVFoundation has already lens-warped `AVDepthData` into the
    /// synchronized, pre-connection RGB image coordinate system. The affine
    /// maps depth pixel centers into that RGB coded space; `connectionTransform`
    /// then applies connection rotation followed by an optional horizontal
    /// mirror in encoded space; `rgbCleanAperture` defines the presented image.
    nonisolated struct RegistrationDescriptor: Codable, Equatable, Sendable {
        static let schemaID = "urn:tapnap:tapcam:video-depth-registration:avdepthdata-yuv-warp:v1"
        static let mappingModel = "avdepthdata-warped-to-synchronized-rgb-pixel-centers"

        let schema: String
        let version: Int
        let model: String
        let alignedRGBCodedDimensions: Dimensions
        let encodedRGBCodedDimensions: Dimensions
        let depthDimensions: Dimensions
        let depthToAlignedRGBPixelCenterAffine: [Double]
        let connectionTransform: String
        let isEncodedHorizontallyMirrored: Bool
        let rgbCleanAperture: Rect
        let videoStabilizationMode: String

        init(
            schema: String = Self.schemaID,
            version: Int = 1,
            model: String = Self.mappingModel,
            alignedRGBCodedDimensions: Dimensions,
            encodedRGBCodedDimensions: Dimensions,
            depthDimensions: Dimensions,
            depthToAlignedRGBPixelCenterAffine: [Double],
            connectionTransform: String,
            isEncodedHorizontallyMirrored: Bool = false,
            rgbCleanAperture: Rect,
            videoStabilizationMode: String = "off"
        ) {
            self.schema = schema
            self.version = version
            self.model = model
            self.alignedRGBCodedDimensions = alignedRGBCodedDimensions
            self.encodedRGBCodedDimensions = encodedRGBCodedDimensions
            self.depthDimensions = depthDimensions
            self.depthToAlignedRGBPixelCenterAffine = depthToAlignedRGBPixelCenterAffine
            self.connectionTransform = connectionTransform
            self.isEncodedHorizontallyMirrored = isEncodedHorizontallyMirrored
            self.rgbCleanAperture = rgbCleanAperture
            self.videoStabilizationMode = videoStabilizationMode
        }
    }

    nonisolated enum RegistrationStatus: String, Codable, Equatable, Sendable {
        case registered
        case approximate
        case unavailable
    }

    nonisolated struct Dimensions: Codable, Equatable, Sendable {
        let width: Double
        let height: Double
    }

    nonisolated struct Rect: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    nonisolated struct Point: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
    }

    nonisolated struct CameraCalibration: Codable, Equatable, Sendable {
        let intrinsicMatrix: [Float]
        let intrinsicMatrixReferenceDimensions: Dimensions
        let extrinsicMatrix: [Float]
        let pixelSizeMillimeters: Float
        let lensDistortionCenter: Point
        let lensDistortionLookupTable: Data?
        let inverseLensDistortionLookupTable: Data?
    }

    nonisolated struct DepthGap: Codable, Equatable, Sendable {
        let reason: DepthGapReason
        let startPTS: MediaTime
        let endPTS: MediaTime
        let nearestStartRGBFrame: Int?
        let nearestEndRGBFrame: Int?
    }

    nonisolated enum DepthGapReason: String, Codable, Equatable, Sendable {
        case outputDrop
        case encodingFailure
        case metadataBackpressure
        case silentCadence
        /// A conservative range used only after the bounded gap table reaches
        /// its hard limit. The range may include valid samples between several
        /// otherwise independent gaps, so readers treat current depth as
        /// unavailable throughout. A display may hold a prior valid frame.
        case boundedAggregation
    }

    nonisolated struct MediaTime: Codable, Equatable, Sendable {
        let value: Int64
        let timescale: Int32
    }

    nonisolated struct Synchronization: Codable, Equatable, Sendable {
        let timing: String
        let rgbToDepthMapping: String
        let maxObservedDeltaSeconds: Double?
        let maxObservedDepthIntervalSeconds: Double?
        let nominalDepthIntervalSeconds: Double?

        init(
            timing: String,
            rgbToDepthMapping: String,
            maxObservedDeltaSeconds: Double?,
            maxObservedDepthIntervalSeconds: Double? = nil,
            nominalDepthIntervalSeconds: Double? = nil
        ) {
            self.timing = timing
            self.rgbToDepthMapping = rgbToDepthMapping
            self.maxObservedDeltaSeconds = maxObservedDeltaSeconds
            self.maxObservedDepthIntervalSeconds = maxObservedDepthIntervalSeconds
            self.nominalDepthIntervalSeconds = nominalDepthIntervalSeconds
        }
    }

    nonisolated struct Stop: Codable, Equatable, Sendable {
        let reason: StopReason
        let recordedDurationSeconds: Double
    }

    nonisolated enum StopReason: String, Codable, Equatable, Sendable {
        case userStop
        case durationLimit
        case thermalPressure
        case systemPressure
        case appLifecycle
        case storageFailure
        case captureFailure
    }

    nonisolated struct Software: Codable, Equatable, Sendable {
        let appIdentifier: String
        let appVersion: String
        let buildNumber: String
        let schemaWriter: String
    }
}

nonisolated enum TAPVideoManifestEncoder {
    static func manifestJSON(_ manifest: TAPVideoManifest) throws -> String {
        let data = try manifestData(manifest)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return json
    }

    static func manifestData(_ manifest: TAPVideoManifest) throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(manifest)
    }

    static func payloadDataExcludingProofs(_ payload: TAPVideoManifest.Payload) throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(payload)
    }

    static func decodedDocument(from manifestData: Data) throws -> TAPVideoManifestDocument {
        let manifest = try JSONDecoder().decode(TAPVideoManifest.self, from: manifestData)
        let rawPayloadData = try TAPManifestPayloadBytes.rawPayloadData(in: manifestData)
        return TAPVideoManifestDocument(
            manifest: manifest,
            rawPayloadData: rawPayloadData
        )
    }
}

nonisolated struct TAPVideoManifestDocument {
    let manifest: TAPVideoManifest
    let rawPayloadData: Data
}

extension TAPVideoManifest.Software {
    nonisolated static var current: TAPVideoManifest.Software {
        let bundle = Bundle.main
        return TAPVideoManifest.Software(
            appIdentifier: bundle.bundleIdentifier ?? "unknown",
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            schemaWriter: "TAPCamDemo.TAPVideoManifestEncoder"
        )
    }
}
