//
//  TAPDepthManifest.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import CoreLocation
import CoreVideo
import Foundation
import simd

/// Versioned metadata contract embedded into every TAP depth HEIC.
///
/// The HEIC file itself remains standards-friendly:
/// - the visible photo is the primary HEIC image item,
/// - Apple depth/disparity data stays in the HEIC auxiliary data attachment,
/// - normal EXIF/GPS/TIFF fields mirror common metadata for generic tools,
/// - this manifest is the only authoritative location for TAP-specific fields.
///
/// Future hash/signature data belongs in `proofs`. The signed business payload is
/// intentionally isolated under `payload` so a verifier can canonicalize exactly
/// that subtree without chasing duplicate metadata in EXIF, GPS, or Photos.
nonisolated struct TAPDepthManifest: Codable, Equatable {
    static let schemaIdentifier = "urn:tapnap:tapcam:depth-manifest:v1"
    static let mediaType = "application/vnd.tapnap.depth-manifest+json;version=1"
    static let xmpNamespaceURI = "urn:tapnap:tapcam:depth:1.0"
    static let xmpPrefix = "tapdepth"
    static let xmpManifestPath = "tapdepth:Manifest"
    static let exifUserCommentPointer = "TAPDepthHEIC/1; metadata=xmp:tapdepth:Manifest"

    let schema: Schema
    let payload: Payload
    let proofs: [Proof]

    init(payload: Payload, proofs: [Proof] = []) {
        self.schema = Schema()
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

        nonisolated init() {
            self.id = TAPDepthManifest.schemaIdentifier
            self.version = 1
            self.mediaType = TAPDepthManifest.mediaType
            self.xmpNamespaceURI = TAPDepthManifest.xmpNamespaceURI
            self.xmpPrefix = TAPDepthManifest.xmpPrefix
            self.xmpManifestPath = TAPDepthManifest.xmpManifestPath
        }
    }

    nonisolated struct Payload: Codable, Equatable {
        let id: String
        let capturedAt: String
        let sourceAPIs: SourceAPIs
        let capture: Capture
        let photoLens: PhotoLens
        let camera: Camera
        let photo: Photo
        let depth: Depth
        let location: Location?
        let software: Software
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
        let photoQualityPrioritization: String
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
        let requestedZoomFactor: Double
        let position: String
        let resolvedCaptureDeviceType: String
        let resolvedCaptureDeviceName: String
        let resolvedActivePrimaryConstituentDeviceType: String?
        let resolvedActivePrimaryConstituentDeviceName: String?
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
        let metadataKeys: [String]
    }

    nonisolated struct Depth: Codable, Equatable {
        let auxiliaryDataKind: String
        let depthDataType: String
        let width: Int
        let height: Int
        let accuracy: String
        let quality: String
        let isFiltered: Bool
        let source: DepthSource
        let cameraCalibration: CameraCalibration?
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

    nonisolated struct Proof: Codable, Equatable {
        let type: String
        let algorithm: String
        let keyID: String?
        let createdAt: String?
        let value: String?
    }
}

/// Builds a TAP manifest from the Apple objects that exist at the moment the
/// photo delegate receives an `AVCapturePhoto`.
///
/// This builder is the source-of-truth map between Apple APIs and the on-disk
/// manifest. The README mirrors this mapping so third-party tools can parse the
/// file without depending on this app's runtime state.
nonisolated enum TAPDepthManifestBuilder {
    static func makeManifest(
        photo: AVCapturePhoto,
        device: AVCaptureDevice,
        photoLens: PhotoLensOption,
        capturedAt: Date,
        location: CLLocation?,
        requestedCodec: AVVideoCodecType,
        depthDataFiltered: Bool,
        photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    ) throws -> TAPDepthManifest {
        guard let depthData = photo.depthData else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let captureID = UUID().uuidString
        let resolvedDimensions = photo.resolvedSettings.photoDimensions
        let payload = TAPDepthManifest.Payload(
            id: captureID,
            capturedAt: TAPDateFormatting.iso8601.string(from: capturedAt),
            sourceAPIs: .avFoundationPhotoDepth,
            capture: TAPDepthManifest.Capture(
                resolvedSettingsUniqueID: photo.resolvedSettings.uniqueID,
                requestedCodec: requestedCodec.rawValue,
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: true,
                depthDataFiltered: depthDataFiltered,
                photoQualityPrioritization: photoQualityPrioritization.tapDescription
            ),
            photoLens: makePhotoLens(photoLens, device: device),
            camera: makeCamera(device: device),
            photo: TAPDepthManifest.Photo(
                width: resolvedDimensions.width,
                height: resolvedDimensions.height,
                metadataKeys: photo.metadata.keys.sorted()
            ),
            depth: makeDepth(depthData: depthData, device: device),
            location: location.map(makeLocation),
            software: .current
        )

        return TAPDepthManifest(payload: payload)
    }

    private static func makePhotoLens(_ photoLens: PhotoLensOption, device: AVCaptureDevice) -> TAPDepthManifest.PhotoLens {
        let activePrimaryDevice = device.activePrimaryConstituent

        return TAPDepthManifest.PhotoLens(
            requestedLensID: photoLens.id,
            requestedDisplayName: photoLens.displayName,
            requestedZoomFactor: Double(photoLens.zoomFactor),
            position: photoLens.position.tapDescription,
            resolvedCaptureDeviceType: device.deviceType.rawValue,
            resolvedCaptureDeviceName: device.localizedName,
            resolvedActivePrimaryConstituentDeviceType: activePrimaryDevice?.deviceType.rawValue,
            resolvedActivePrimaryConstituentDeviceName: activePrimaryDevice?.localizedName
        )
    }

    private static func makeCamera(device: AVCaptureDevice) -> TAPDepthManifest.Camera {
        let activeFormat = device.activeFormat.tapCameraFormat
        let activeDepthFormat = device.activeDepthDataFormat?.tapCameraFormat
        let activePrimaryDevice = device.activePrimaryConstituent

        return TAPDepthManifest.Camera(
            localizedName: device.localizedName,
            uniqueID: device.uniqueID,
            modelID: device.modelID,
            deviceType: device.deviceType.rawValue,
            position: device.position.tapDescription,
            activePrimaryConstituentDeviceType: activePrimaryDevice?.deviceType.rawValue,
            activePrimaryConstituentDeviceName: activePrimaryDevice?.localizedName,
            activeFormat: activeFormat,
            activeDepthFormat: activeDepthFormat,
            lensPosition: device.isFocusModeSupported(.locked) || device.isFocusModeSupported(.autoFocus) || device.isFocusModeSupported(.continuousAutoFocus) ? device.lensPosition : nil,
            minimumFocusDistanceMillimeters: device.minimumFocusDistance > 0 ? device.minimumFocusDistance : nil,
            nominalFocalLengthIn35mmFilmMillimeters: device.tapNominalFocalLengthIn35mmFilm
        )
    }

    private static func makeDepth(depthData: AVDepthData, device: AVCaptureDevice) -> TAPDepthManifest.Depth {
        let pixelBuffer = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let auxiliaryKind = TAPDepthAuxiliaryKind(kind: depthData.depthDataType).rawValue
        let source = TAPDepthSourceClassifier.source(forDeviceType: device.deviceType.rawValue, localizedName: device.localizedName)

        return TAPDepthManifest.Depth(
            auxiliaryDataKind: auxiliaryKind,
            depthDataType: TAPFourCharCode.string(from: depthData.depthDataType),
            width: width,
            height: height,
            accuracy: depthData.depthDataAccuracy.tapDescription,
            quality: depthData.depthDataQuality.tapDescription,
            isFiltered: depthData.isDepthDataFiltered,
            source: source,
            cameraCalibration: depthData.cameraCalibrationData.map(makeCalibration)
        )
    }

    private static func makeCalibration(_ calibration: AVCameraCalibrationData) -> TAPDepthManifest.CameraCalibration {
        let intrinsic = calibration.intrinsicMatrix
        let extrinsic = calibration.extrinsicMatrix

        return TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: calibration.intrinsicMatrixReferenceDimensions.width,
            intrinsicMatrixReferenceHeight: calibration.intrinsicMatrixReferenceDimensions.height,
            pixelSizeMillimeters: calibration.pixelSize,
            lensDistortionLookupTablePresent: calibration.lensDistortionLookupTable != nil,
            inverseLensDistortionLookupTablePresent: calibration.inverseLensDistortionLookupTable != nil,
            lensDistortionCenterX: calibration.lensDistortionCenter.x,
            lensDistortionCenterY: calibration.lensDistortionCenter.y,
            intrinsicMatrix: [
                intrinsic.columns.0.x, intrinsic.columns.0.y, intrinsic.columns.0.z,
                intrinsic.columns.1.x, intrinsic.columns.1.y, intrinsic.columns.1.z,
                intrinsic.columns.2.x, intrinsic.columns.2.y, intrinsic.columns.2.z
            ],
            extrinsicMatrix: [
                extrinsic.columns.0.x, extrinsic.columns.0.y, extrinsic.columns.0.z,
                extrinsic.columns.1.x, extrinsic.columns.1.y, extrinsic.columns.1.z,
                extrinsic.columns.2.x, extrinsic.columns.2.y, extrinsic.columns.2.z,
                extrinsic.columns.3.x, extrinsic.columns.3.y, extrinsic.columns.3.z
            ]
        )
    }

    private static func makeLocation(_ location: CLLocation) -> TAPDepthManifest.Location {
        TAPDepthManifest.Location(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: TAPDateFormatting.iso8601.string(from: location.timestamp)
        )
    }
}

/// Encodes manifests in one place so the app, tests, and future command-line
/// readers use identical JSON options.
///
/// The `payloadDataForFutureProofing` function deliberately excludes `proofs`.
/// When hash/signature support is added, replace its encoder with a true RFC
/// 8785 JSON Canonicalization Scheme implementation and keep this exclusion.
nonisolated enum TAPDepthManifestEncoder {
    static func manifestJSON(_ manifest: TAPDepthManifest) throws -> String {
        let data = try encoder.encode(manifest)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return json
    }

    static func payloadDataForFutureProofing(_ payload: TAPDepthManifest.Payload) throws -> Data {
        try encoder.encode(payload)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

nonisolated enum TAPDepthSourceClassifier {
    static func source(forDeviceType deviceType: String, localizedName: String) -> TAPDepthManifest.DepthSource {
        let classification = classification(forDeviceType: deviceType)
        return TAPDepthManifest.DepthSource(
            captureDeviceType: deviceType,
            captureDeviceName: localizedName,
            sensingMethod: classification.sensingMethod,
            lidarParticipation: classification.lidarParticipation
        )
    }

    static func classification(forDeviceType deviceType: String) -> (sensingMethod: String, lidarParticipation: String) {
        switch deviceType {
        case AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue:
            ("lidarDepthCamera", "explicit")
        case AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue:
            ("trueDepthCamera", "notApplicable")
        case AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInDualWideCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInDualCamera.rawValue:
            ("multiCameraStereoOrComputational", "notAsserted")
        case AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInUltraWideCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInTelephotoCamera.rawValue:
            ("singleCameraComputationalOrUnknown", "notAsserted")
        default:
            ("singleCameraComputationalOrUnknown", "notAsserted")
        }
    }
}

nonisolated enum TAPDepthAuxiliaryKind: String {
    case depth
    case disparity

    init(kind: OSType) {
        switch kind {
        case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32:
            self = .depth
        case kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32:
            self = .disparity
        default:
            self = .depth
        }
    }
}

nonisolated enum TAPFourCharCode {
    static func string(from code: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]

        if bytes.allSatisfy({ (32...126).contains($0) }),
           let text = String(bytes: bytes, encoding: .ascii) {
            return text
        }

        return String(format: "0x%08X", code)
    }
}

nonisolated enum TAPDateFormatting {
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

extension TAPDepthManifest.Software {
    nonisolated static var current: TAPDepthManifest.Software {
        let bundle = Bundle.main
        return TAPDepthManifest.Software(
            appName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TAPCamDemo",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }
}

extension AVCaptureDevice.Format {
    nonisolated var tapCameraFormat: TAPDepthManifest.CameraFormat {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        return TAPDepthManifest.CameraFormat(
            mediaSubType: TAPFourCharCode.string(from: CMFormatDescriptionGetMediaSubType(formatDescription)),
            width: dimensions.width,
            height: dimensions.height,
            maxFrameRate: videoSupportedFrameRateRanges.map(\.maxFrameRate).max()
        )
    }
}

extension AVCaptureDevice {
    /// iOS 26 exposes a convenient 35mm-equivalent focal length directly on the
    /// capture device. The app's baseline is iOS 18, so the manifest treats this
    /// as an enhancement: present on iOS 26+, `null` on older systems. Generic
    /// EXIF focal length values from `AVCapturePhoto.metadata` are still preserved
    /// by `TAPPhotoFileMetadataCustomizer`.
    nonisolated var tapNominalFocalLengthIn35mmFilm: Float? {
        guard #available(iOS 26.0, *) else {
            return nil
        }

        return nominalFocalLengthIn35mmFilm > 0 ? nominalFocalLengthIn35mmFilm : nil
    }
}

extension AVCaptureDevice.Position {
    nonisolated var tapDescription: String {
        switch self {
        case .front:
            "front"
        case .back:
            "back"
        case .unspecified:
            "unspecified"
        @unknown default:
            "unknown"
        }
    }
}

extension AVCapturePhotoOutput.QualityPrioritization {
    nonisolated var tapDescription: String {
        switch self {
        case .speed:
            "speed"
        case .balanced:
            "balanced"
        case .quality:
            "quality"
        @unknown default:
            "unknown"
        }
    }
}

extension AVDepthData.Accuracy {
    nonisolated var tapDescription: String {
        switch self {
        case .relative:
            "relative"
        case .absolute:
            "absolute"
        @unknown default:
            "unknown"
        }
    }
}

extension AVDepthData.Quality {
    nonisolated var tapDescription: String {
        switch self {
        case .low:
            "low"
        case .high:
            "high"
        @unknown default:
            "unknown"
        }
    }
}

enum TAPDepthCaptureError: LocalizedError {
    case cameraAccessDenied
    case noDepthCameraAvailable
    case unableToAddCameraInput
    case unableToAddPhotoOutput
    case depthDeliveryUnsupported
    case missingDepthData
    case unableToCreatePhotoData
    case invalidUTF8Manifest
    case imageSourceCreationFailed
    case imageDestinationCreationFailed
    case xmpNamespaceRegistrationFailed(String)
    case xmpManifestWriteFailed
    case imageCopyFailed(String)
    case xmpManifestMissing
    case photoLibraryAccessDenied
    case albumCreationFailed
    case assetCreationFailed

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied:
            "Camera access is required to capture depth photos."
        case .noDepthCameraAvailable:
            "No camera with depth-capable formats is available on this device."
        case .unableToAddCameraInput:
            "Unable to add the selected camera input to the capture session."
        case .unableToAddPhotoOutput:
            "Unable to add AVCapturePhotoOutput to the capture session."
        case .depthDeliveryUnsupported:
            "The current session configuration does not support depth photo delivery."
        case .missingDepthData:
            "The captured photo did not include AVDepthData."
        case .unableToCreatePhotoData:
            "AVCapturePhoto could not produce HEIC data."
        case .invalidUTF8Manifest:
            "The TAP manifest could not be encoded as UTF-8 JSON."
        case .imageSourceCreationFailed:
            "ImageIO could not open the generated HEIC data."
        case .imageDestinationCreationFailed:
            "ImageIO could not create a HEIC destination."
        case .xmpNamespaceRegistrationFailed(let reason):
            "ImageIO could not register the TAP XMP namespace: \(reason)"
        case .xmpManifestWriteFailed:
            "ImageIO could not write tapdepth:Manifest into XMP metadata."
        case .imageCopyFailed(let reason):
            "ImageIO could not copy the HEIC source while injecting metadata: \(reason)"
        case .xmpManifestMissing:
            "The generated HEIC does not contain tapdepth:Manifest after writeback."
        case .photoLibraryAccessDenied:
            "Photo library access is required to save into the TAPCamDepth album."
        case .albumCreationFailed:
            "Unable to create or fetch the TAPCamDepth album."
        case .assetCreationFailed:
            "Unable to create a Photos asset from the depth HEIC."
        }
    }
}
