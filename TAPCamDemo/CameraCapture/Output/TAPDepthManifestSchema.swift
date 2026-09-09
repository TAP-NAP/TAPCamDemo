//
//  TAPDepthManifestSchema.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import CoreLocation
import CoreVideo
import Foundation
import ImageIO
import simd

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

/// Versioned metadata contract embedded into every TAP depth HEIC/JPG photo.
///
/// The photo file itself remains standards-friendly:
/// - the visible image stays in the selected HEIC/JPG container,
/// - Apple depth/disparity data stays in its auxiliary data attachment,
/// - normal EXIF/GPS/TIFF fields mirror common metadata for generic tools,
/// - XMP `tapdepth:Manifest` is the authoritative TAP-specific location.
///
/// V1 always writes `proofs: []`; proof data lives only in the fixed proof slot.
/// The business payload stays under `payload` so verification can hash its exact
/// embedded bytes without chasing duplicate metadata in EXIF, GPS, or Photos.
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
        let sessionMode: String
        let pairingMode: String
        let alignmentStatus: String
        let sourceAPIs: SourceAPIs
        let capture: Capture
        let rgbSource: RGBSource
        let depthSource: DepthSourceSelection
        let pairing: Pairing
        let zoom: Zoom
        let crop: Crop
        let resolvedSession: ResolvedSession
        let selectedDepthCamera: SelectedDepthCamera
        let selectedZoom: SelectedZoom
        let photoLens: PhotoLens
        let depthBackend: DepthBackendSelection
        let camera: Camera
        let photo: Photo
        let depth: Depth
        let alignment: Alignment
        let location: Location?
        let software: Software
        let livePhoto: LivePhoto?

        nonisolated init(
            id: String,
            capturedAt: String,
            sessionMode: String,
            pairingMode: String,
            alignmentStatus: String,
            sourceAPIs: SourceAPIs,
            capture: Capture,
            rgbSource: RGBSource,
            depthSource: DepthSourceSelection,
            pairing: Pairing,
            zoom: Zoom,
            crop: Crop,
            resolvedSession: ResolvedSession,
            selectedDepthCamera: SelectedDepthCamera,
            selectedZoom: SelectedZoom,
            photoLens: PhotoLens,
            depthBackend: DepthBackendSelection,
            camera: Camera,
            photo: Photo,
            depth: Depth,
            alignment: Alignment,
            location: Location?,
            software: Software,
            livePhoto: LivePhoto? = nil
        ) {
            self.id = id
            self.capturedAt = capturedAt
            self.sessionMode = sessionMode
            self.pairingMode = pairingMode
            self.alignmentStatus = alignmentStatus
            self.sourceAPIs = sourceAPIs
            self.capture = capture
            self.rgbSource = rgbSource
            self.depthSource = depthSource
            self.pairing = pairing
            self.zoom = zoom
            self.crop = crop
            self.resolvedSession = resolvedSession
            self.selectedDepthCamera = selectedDepthCamera
            self.selectedZoom = selectedZoom
            self.photoLens = photoLens
            self.depthBackend = depthBackend
            self.camera = camera
            self.photo = photo
            self.depth = depth
            self.alignment = alignment
            self.location = location
            self.software = software
            self.livePhoto = livePhoto
        }

        enum CodingKeys: String, CodingKey {
            case id
            case capturedAt
            case sessionMode
            case pairingMode
            case alignmentStatus
            case sourceAPIs
            case capture
            case rgbSource
            case depthSource
            case pairing
            case zoom
            case crop
            case resolvedSession
            case selectedDepthCamera
            case selectedZoom
            case photoLens
            case depthBackend
            case camera
            case photo
            case depth
            case alignment
            case location
            case software
            case livePhoto
        }

        /// Encodes the payload with an explicit `location: null` when no
        /// location is available.
        ///
        /// Synthesized `Codable` uses `encodeIfPresent` for optionals and would
        /// omit the field. The manifest is an interchange contract rather than
        /// an app-private cache, so keeping the key present makes parsers and
        /// canonicalization rules easier to implement.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(capturedAt, forKey: .capturedAt)
            try container.encode(sessionMode, forKey: .sessionMode)
            try container.encode(pairingMode, forKey: .pairingMode)
            try container.encode(alignmentStatus, forKey: .alignmentStatus)
            try container.encode(sourceAPIs, forKey: .sourceAPIs)
            try container.encode(capture, forKey: .capture)
            try container.encode(rgbSource, forKey: .rgbSource)
            try container.encode(depthSource, forKey: .depthSource)
            try container.encode(pairing, forKey: .pairing)
            try container.encode(zoom, forKey: .zoom)
            try container.encode(crop, forKey: .crop)
            try container.encode(resolvedSession, forKey: .resolvedSession)
            try container.encode(selectedDepthCamera, forKey: .selectedDepthCamera)
            try container.encode(selectedZoom, forKey: .selectedZoom)
            try container.encode(photoLens, forKey: .photoLens)
            try container.encode(depthBackend, forKey: .depthBackend)
            try container.encode(camera, forKey: .camera)
            try container.encode(photo, forKey: .photo)
            try container.encode(depth, forKey: .depth)
            try container.encode(alignment, forKey: .alignment)
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

    nonisolated struct SourceAPIs: Codable, Equatable {
        let photo: String
        let depth: String
        let camera: String
        let location: String

        nonisolated static let avFoundationPhotoDepth = SourceAPIs(
            photo: "AVCapturePhotoOutput / AVCapturePhoto",
            depth: "AVCapturePhoto.depthData / AVDepthData",
            camera: "AVCaptureDevice / AVCaptureDevice.Format",
            location: "CLLocationManager.requestLocation / CLLocation"
        )
    }

    nonisolated struct Capture: Codable, Equatable {
        let resolvedSettingsUniqueID: Int64
        let requestedCodec: String
        let depthDataDeliveryEnabled: Bool
        let embedsDepthDataInPhoto: Bool
        let depthDataFiltered: Bool
        let depthAvailability: CaptureDepthAvailability
        let photoQualityPrioritization: String

        nonisolated init(
            resolvedSettingsUniqueID: Int64,
            requestedCodec: String,
            depthDataDeliveryEnabled: Bool,
            embedsDepthDataInPhoto: Bool,
            depthDataFiltered: Bool,
            depthAvailability: CaptureDepthAvailability = .available,
            photoQualityPrioritization: String
        ) {
            self.resolvedSettingsUniqueID = resolvedSettingsUniqueID
            self.requestedCodec = requestedCodec
            self.depthDataDeliveryEnabled = depthDataDeliveryEnabled
            self.embedsDepthDataInPhoto = embedsDepthDataInPhoto
            self.depthDataFiltered = depthDataFiltered
            self.depthAvailability = depthAvailability
            self.photoQualityPrioritization = photoQualityPrioritization
        }

        private enum CodingKeys: String, CodingKey {
            case resolvedSettingsUniqueID
            case requestedCodec
            case depthDataDeliveryEnabled
            case embedsDepthDataInPhoto
            case depthDataFiltered
            case depthAvailability
            case photoQualityPrioritization
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                resolvedSettingsUniqueID: try container.decode(Int64.self, forKey: .resolvedSettingsUniqueID),
                requestedCodec: try container.decode(String.self, forKey: .requestedCodec),
                depthDataDeliveryEnabled: try container.decode(Bool.self, forKey: .depthDataDeliveryEnabled),
                embedsDepthDataInPhoto: try container.decode(Bool.self, forKey: .embedsDepthDataInPhoto),
                depthDataFiltered: try container.decode(Bool.self, forKey: .depthDataFiltered),
                depthAvailability: try container.decode(
                    CaptureDepthAvailability.self,
                    forKey: .depthAvailability
                ),
                photoQualityPrioritization: try container.decode(String.self, forKey: .photoQualityPrioritization)
            )
        }
    }

    nonisolated struct SelectedDepthCamera: Codable, Equatable {
        let id: String
        let displayName: String
        let deviceType: String
        let deviceName: String
        let position: String
    }

    nonisolated struct SelectedZoom: Codable, Equatable {
        let id: String
        let displayName: String
        let zoomFactor: Double
    }

    nonisolated struct RGBSource: Codable, Equatable {
        let id: String
        let displayName: String
        let deviceType: String
        let deviceName: String
        let position: String
        let sourceKind: String
        let requestedReferenceZoomFactor: Double
    }

    nonisolated struct DepthSourceSelection: Codable, Equatable {
        let selectionMode: String
        let requestedDepthSourceID: String?
        let requestedDepthSourceDisplayName: String?
        let requestedDepthSourceKind: String?
        let compatibilityStatus: String
        let compatibilityReason: String?
        let resolvedDeviceID: String?
        let resolvedDeviceType: String?
        let resolvedDeviceName: String?
    }

    nonisolated struct Pairing: Codable, Equatable {
        let mode: String
        let status: String
        let requiresMultiCam: Bool
        let releaseAllowed: Bool
        let alignmentStatus: String
    }

    nonisolated struct Zoom: Codable, Equatable {
        let requestedZoomID: String?
        let requestedZoomFactor: Double?
        let actualVideoZoomFactor: Double?
        let depthSafeRanges: [ZoomRange]
        let isContinuous: Bool
        let isDiscrete: Bool
    }

    nonisolated struct ZoomRange: Codable, Equatable {
        let lowerBound: Double
        let upperBound: Double
    }

    nonisolated struct Crop: Codable, Equatable {
        let mode: String
        let cropRectNormalized: CropRectNormalized
        let destructiveFinalCropApplied: Bool
        let sourceAPI: String
    }

    nonisolated struct ResolvedSession: Codable, Equatable {
        let mode: String
        let resolvedCaptureDeviceID: String
        let resolvedCaptureDeviceType: String
        let resolvedCaptureDeviceName: String
        let activePrimaryConstituentDeviceType: String?
        let activePrimaryConstituentDeviceName: String?
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

    nonisolated struct PhotoLens: Codable, Equatable {
        let requestedLensID: String
        let requestedDisplayName: String
        let requestedFocalLengthLabel: String
        let labelSource: String
        let requestedZoomFactor: Double
        let requestedReferenceZoomFactor: Double
        let requestedEquivalentFocalLength35mmMillimeters: Double?
        let position: String
        let resolvedCaptureDeviceType: String
        let resolvedCaptureDeviceName: String
        let resolvedActivePrimaryConstituentDeviceType: String?
        let resolvedActivePrimaryConstituentDeviceName: String?
    }

    nonisolated struct DepthBackendSelection: Codable, Equatable {
        let selectionMode: String
        let requestedBackendID: String?
        let requestedBackendDisplayName: String?
        let resolvedBackendID: String
        let resolvedBackendDisplayName: String
        let resolvedCaptureDeviceType: String
        let resolvedCaptureDeviceName: String
        let actualVideoZoomFactor: Double
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

    nonisolated struct Alignment: Codable, Equatable {
        let depthToImage: String
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
