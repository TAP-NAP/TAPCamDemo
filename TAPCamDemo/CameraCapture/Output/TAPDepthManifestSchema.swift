//
//  TAPDepthManifestSchema.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import Foundation

nonisolated enum CaptureDepthAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable

    var viewfinderHint: String? {
        switch self {
        case .available:
            nil
        case .unavailable:
            "Depth unavailable"
        }
    }
}

/// Photo metadata embedded at XMP `tapdepth:Manifest`.
/// The producer writes `proofs: []`; proof data lives in the fixed proof slot.
nonisolated struct TAPDepthManifest: Codable, Equatable {
    static let schemaIdentifier = "urn:tapnap:tapcam:still-photo-manifest:v1"
    static let mediaType = "application/vnd.tapnap.still-photo-manifest+json;version=1"
    static let payloadMediaType = "application/vnd.tapnap.still-photo-manifest.payload+json;version=1"
    static let livePhotoSchemaIdentifier = "urn:tapnap:tapcam:live-photo-manifest:v1"
    static let livePhotoMediaType = "application/vnd.tapnap.live-photo-manifest+json;version=1"
    static let livePhotoPayloadMediaType = "application/vnd.tapnap.live-photo-manifest.payload+json;version=1"
    static let xmpNamespaceURI = "urn:tapnap:tapcam:depth:1.0"
    static let xmpPrefix = "tapdepth"
    static let xmpManifestPath = "tapdepth:Manifest"
    /// Legacy-named discovery hint required verbatim in both HEIC and JPG.
    /// It is not the manifest, a format identifier, a hash, or proof evidence.
    static let exifUserCommentPointer = "TAPDepthHEIC/1; metadata=xmp:tapdepth:Manifest"

    let schema: Schema
    let payload: Payload
    let proofs: [Proof]

    init(payload: Payload, proofs: [Proof] = [], schema: Schema = Schema()) {
        self.schema = schema
        self.payload = payload
        self.proofs = proofs
    }
}

extension TAPDepthManifest {
    nonisolated struct Schema: Codable, Equatable {
        let id: String
        let version: Int
        let mediaType: String
        let xmpNamespaceURI: String
        let xmpPrefix: String
        let xmpManifestPath: String

        nonisolated init(
            id: String = TAPDepthManifest.schemaIdentifier,
            version: Int = 1,
            mediaType: String = TAPDepthManifest.mediaType
        ) {
            self.id = id
            self.version = version
            self.mediaType = mediaType
            self.xmpNamespaceURI = TAPDepthManifest.xmpNamespaceURI
            self.xmpPrefix = TAPDepthManifest.xmpPrefix
            self.xmpManifestPath = TAPDepthManifest.xmpManifestPath
        }

        nonisolated static var livePhoto: Schema {
            Schema(
                id: TAPDepthManifest.livePhotoSchemaIdentifier,
                version: 1,
                mediaType: TAPDepthManifest.livePhotoMediaType
            )
        }
    }

    nonisolated struct Payload: Codable, Equatable {
        let id: String
        let capturedAt: String
        let camera: Camera
        let photo: Photo
        let depth: Depth
        let location: Location?
        let software: Software
        let livePhoto: LivePhoto?

        enum CodingKeys: String, CodingKey {
            case id
            case capturedAt
            case camera
            case photo
            case depth
            case location
            case software
            case livePhoto
        }

        /// Preserve the producer convention of an explicit `location: null`.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(capturedAt, forKey: .capturedAt)
            try container.encode(camera, forKey: .camera)
            try container.encode(photo, forKey: .photo)
            try container.encode(depth, forKey: .depth)
            try container.encode(location, forKey: .location)
            try container.encode(software, forKey: .software)
            try container.encodeIfPresent(livePhoto, forKey: .livePhoto)
        }
    }

    nonisolated struct LivePhoto: Codable, Equatable {
        let presence: String
        let pairedVideoFilename: String
        let durationSeconds: Double
        let photoDisplayTimeSeconds: Double
        let width: Int32
        let height: Int32
        let videoCodec: String?
        let audio: String
    }

    nonisolated struct Camera: Codable, Equatable {
        let localizedName: String
        let uniqueID: String
        let modelID: String
        let deviceType: String
        let position: String
        let activePrimaryConstituentDeviceType: String?
        let activePrimaryConstituentDeviceName: String?
        let activeFormat: CameraFormat
        let activeDepthFormat: CameraFormat?
        let lensPosition: Float?
        let minimumFocusDistanceMillimeters: Int?
        let nominalFocalLengthIn35mmFilmMillimeters: Float?
    }

    nonisolated struct CameraFormat: Codable, Equatable {
        let mediaSubType: String
        let width: Int32
        let height: Int32
        let maxFrameRate: Double?
    }

    nonisolated struct Photo: Codable, Equatable {
        let width: Int32
        let height: Int32
        let orientation: String
        let metadataKeys: [String]
    }

    nonisolated struct Depth: Codable, Equatable {
        let availability: CaptureDepthAvailability
        let auxiliaryDataKind: String
        let depthDataType: String
        let metricUnit: String
        let conversionPath: String
        let width: Int
        let height: Int
        let pixelFormat: String
        let orientation: String
        let accuracy: String
        let quality: String
        let isFiltered: Bool
        let source: DepthSource
        let cameraCalibration: CameraCalibration?

        nonisolated init(
            availability: CaptureDepthAvailability = .available,
            auxiliaryDataKind: String,
            depthDataType: String,
            metricUnit: String,
            conversionPath: String,
            width: Int,
            height: Int,
            pixelFormat: String,
            orientation: String,
            accuracy: String,
            quality: String,
            isFiltered: Bool,
            source: DepthSource,
            cameraCalibration: CameraCalibration?
        ) {
            self.availability = availability
            self.auxiliaryDataKind = auxiliaryDataKind
            self.depthDataType = depthDataType
            self.metricUnit = metricUnit
            self.conversionPath = conversionPath
            self.width = width
            self.height = height
            self.pixelFormat = pixelFormat
            self.orientation = orientation
            self.accuracy = accuracy
            self.quality = quality
            self.isFiltered = isFiltered
            self.source = source
            self.cameraCalibration = cameraCalibration
        }

        private enum CodingKeys: String, CodingKey {
            case availability
            case auxiliaryDataKind
            case depthDataType
            case metricUnit
            case conversionPath
            case width
            case height
            case pixelFormat
            case orientation
            case accuracy
            case quality
            case isFiltered
            case source
            case cameraCalibration
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                availability: try container.decode(
                    CaptureDepthAvailability.self,
                    forKey: .availability
                ),
                auxiliaryDataKind: try container.decode(String.self, forKey: .auxiliaryDataKind),
                depthDataType: try container.decode(String.self, forKey: .depthDataType),
                metricUnit: try container.decode(String.self, forKey: .metricUnit),
                conversionPath: try container.decode(String.self, forKey: .conversionPath),
                width: try container.decode(Int.self, forKey: .width),
                height: try container.decode(Int.self, forKey: .height),
                pixelFormat: try container.decode(String.self, forKey: .pixelFormat),
                orientation: try container.decode(String.self, forKey: .orientation),
                accuracy: try container.decode(String.self, forKey: .accuracy),
                quality: try container.decode(String.self, forKey: .quality),
                isFiltered: try container.decode(Bool.self, forKey: .isFiltered),
                source: try container.decode(DepthSource.self, forKey: .source),
                cameraCalibration: try container.decodeIfPresent(CameraCalibration.self, forKey: .cameraCalibration)
            )
        }
    }

    nonisolated struct DepthSource: Codable, Equatable {
        let captureDeviceType: String
        let captureDeviceName: String
        let sensingMethod: String
        let lidarParticipation: String
    }

    nonisolated struct CameraCalibration: Codable, Equatable {
        let intrinsicMatrixReferenceWidth: Double
        let intrinsicMatrixReferenceHeight: Double
        let pixelSizeMillimeters: Float
        let lensDistortionLookupTablePresent: Bool
        let inverseLensDistortionLookupTablePresent: Bool
        let lensDistortionCenterX: Double
        let lensDistortionCenterY: Double
        let intrinsicMatrix: [Float]
        let extrinsicMatrix: [Float]
    }

    nonisolated struct Location: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let timestamp: String
    }

    nonisolated struct Software: Codable, Equatable {
        let appName: String
        let bundleIdentifier: String
        let version: String
        let build: String
    }

    typealias Proof = TAPCaptureProof
}

/// The proof envelope has the same fields for still photos, Live Photos, and video.
nonisolated struct TAPCaptureProof: Codable, Equatable, Sendable {
    let type: String
    let algorithm: String
    let keyID: String?
    let createdAt: String?
    let value: String?
}

// The excluded proof slot's timestamp is descriptive, not part of the binding.
// Keep producer encoding unchanged; verification uses contentDigest.capturedAt.
extension TAPCaptureProof {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            type: try container.decode(String.self, forKey: .type),
            algorithm: try container.decode(String.self, forKey: .algorithm),
            keyID: try container.decodeIfPresent(String.self, forKey: .keyID),
            createdAt: try? container.decode(String.self, forKey: .createdAt),
            value: try container.decodeIfPresent(String.self, forKey: .value)
        )
    }
}
