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

    nonisolated struct Proof: Codable, Equatable, Sendable {
        let type: String
        let algorithm: String
        let keyID: String?
        let createdAt: String?
        let value: String?
    }

    nonisolated struct Payload: Codable, Equatable, Sendable {
        let id: String
        let capturedAt: String
        let selectedCameraPlan: SelectedCameraPlan
        let container: Container
        let rgbTrack: RGBTrack
        let audioTrack: AudioTrack
        let depthCoverage: DepthCoverage
        let synchronization: Synchronization
        let stop: Stop
        let software: Software

        init(
            id: String,
            capturedAt: String,
            selectedCameraPlan: SelectedCameraPlan,
            container: Container,
            rgbTrack: RGBTrack,
            audioTrack: AudioTrack,
            depthCoverage: DepthCoverage,
            synchronization: Synchronization,
            stop: Stop,
            software: Software
        ) {
            self.id = id
            self.capturedAt = capturedAt
            self.selectedCameraPlan = selectedCameraPlan
            self.container = container
            self.rgbTrack = rgbTrack
            self.audioTrack = audioTrack
            self.depthCoverage = depthCoverage
            self.synchronization = synchronization
            self.stop = stop
            self.software = software
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case capturedAt
            case selectedCameraPlan
            case container
            case rgbTrack
            case audioTrack
            case depthCoverage
            case synchronization
            case stop
            case software
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(capturedAt, forKey: .capturedAt)
            try container.encode(selectedCameraPlan, forKey: .selectedCameraPlan)
            try container.encode(self.container, forKey: .container)
            try container.encode(rgbTrack, forKey: .rgbTrack)
            try container.encode(audioTrack, forKey: .audioTrack)
            try container.encode(depthCoverage, forKey: .depthCoverage)
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
        let nominalFrameRate: Double?
        let frameCount: Int?
        let transform: String?
    }

    nonisolated struct AudioTrack: Codable, Equatable, Sendable {
        let status: AudioStatus
        let trackID: Int32?
        let codec: String?
        let sampleRate: Double?
        let channelCount: Int?
    }

    nonisolated enum AudioStatus: String, Codable, Equatable, Sendable {
        case captured
        case notCaptured
        case unavailable
    }

    nonisolated struct DepthCoverage: Codable, Equatable, Sendable {
        let track: String?
        let sampleCount: Int
        let gapCount: Int
        let gaps: [DepthGap]
        let format: DepthFormat?

        init(
            track: String?,
            sampleCount: Int,
            gaps: [DepthGap] = [],
            format: DepthFormat?
        ) {
            self.track = track
            self.sampleCount = sampleCount
            self.gapCount = gaps.count
            self.gaps = gaps
            self.format = format
        }

        nonisolated static let none = DepthCoverage(
            track: nil,
            sampleCount: 0,
            gaps: [],
            format: nil
        )

        private enum CodingKeys: String, CodingKey {
            case track
            case sampleCount
            case gapCount
            case gaps
            case format
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(track, forKey: .track)
            try container.encode(sampleCount, forKey: .sampleCount)
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
        let rowStride: Int
        let compression: String
        let calibrationReference: String?
    }

    nonisolated struct DepthGap: Codable, Equatable, Sendable {
        let startTime: String
        let endTime: String
        let nearestStartRGBFrame: Int?
        let nearestEndRGBFrame: Int?
    }

    nonisolated struct Synchronization: Codable, Equatable, Sendable {
        let timing: String
        let rgbToDepthMapping: String
        let maxObservedDeltaSeconds: Double?
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
        try encoder.encode(manifest)
    }

    static func payloadDataExcludingProofs(_ payload: TAPVideoManifest.Payload) throws -> Data {
        try encoder.encode(payload)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
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
