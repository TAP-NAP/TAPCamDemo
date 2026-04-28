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
import ImageIO
import simd

/// Versioned metadata contract embedded into every TAP depth HEIC.
///
/// The HEIC file itself remains standards-friendly:
/// - the visible photo is the primary HEIC image item,
/// - Apple depth/disparity data stays in the HEIC auxiliary data attachment,
/// - normal EXIF/GPS/TIFF fields mirror common metadata for generic tools,
/// - this manifest is the only authoritative location for TAP-specific fields.
///
/// Proof data belongs in `proofs`. The business payload is intentionally
/// isolated under `payload` so verification code can canonicalize exactly that
/// subtree without chasing duplicate metadata in EXIF, GPS, or Photos.
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
        }
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
        capturePackage: CapturePackage
    ) throws -> TAPDepthManifest {
        let photo = capturePackage.photo
        let context = capturePackage.sourceContext
        let device = context.sessionConfiguration.device
        let selectionContext = context.sessionConfiguration.selectionContext
        let plan = context.sessionConfiguration.capturePlan

        guard let depthData = photo.depthData else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let captureID = UUID().uuidString
        let resolvedDimensions = photo.resolvedSettings.photoDimensions
        let payload = TAPDepthManifest.Payload(
            id: captureID,
            capturedAt: TAPDateFormatting.iso8601.string(from: context.capturedAt),
            sessionMode: selectionContext.sessionMode,
            pairingMode: selectionContext.pairingMode,
            alignmentStatus: selectionContext.alignmentStatus,
            sourceAPIs: .avFoundationPhotoDepth,
            capture: TAPDepthManifest.Capture(
                resolvedSettingsUniqueID: photo.resolvedSettings.uniqueID,
                requestedCodec: capturePackage.requestedCodec.rawValue,
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: true,
                depthDataFiltered: capturePackage.depthDataFiltered,
                photoQualityPrioritization: capturePackage.photoQualityPrioritization.tapDescription
            ),
            rgbSource: makeRGBSource(selectionContext, plan: plan),
            depthSource: makeDepthSourceSelection(selectionContext),
            pairing: makePairing(selectionContext, plan: plan),
            zoom: makeZoom(plan: plan),
            crop: makeCrop(plan: plan),
            resolvedSession: makeResolvedSession(selectionContext, device: device),
            selectedDepthCamera: makeSelectedDepthCamera(selectionContext),
            selectedZoom: makeSelectedZoom(selectionContext),
            photoLens: makePhotoLens(selectionContext, plan: plan, device: device),
            depthBackend: makeDepthBackend(selectionContext, device: device),
            camera: makeCamera(device: device),
            photo: TAPDepthManifest.Photo(
                width: resolvedDimensions.width,
                height: resolvedDimensions.height,
                orientation: Self.orientationDescription(from: photo.metadata),
                metadataKeys: photo.metadata.keys.sorted()
            ),
            depth: makeDepth(depthData: depthData, device: device),
            alignment: TAPDepthManifest.Alignment(depthToImage: "appleAuxiliaryDepthNative"),
            location: context.location.map(makeLocation),
            software: .current
        )

        return TAPDepthManifest(payload: payload)
    }

    private static func makeRGBSource(
        _ selectionContext: CaptureSelectionContext,
        plan: CaptureSourcePlan
    ) -> TAPDepthManifest.RGBSource {
        TAPDepthManifest.RGBSource(
            id: selectionContext.rgbSourceID,
            displayName: selectionContext.rgbSourceDisplayName,
            deviceType: selectionContext.rgbSourceDeviceType,
            deviceName: selectionContext.rgbSourceDeviceName,
            position: selectionContext.rgbSourcePosition,
            sourceKind: selectionContext.rgbSourceKind,
            requestedReferenceZoomFactor: plan.rgbSource.referenceZoomFactor
        )
    }

    private static func makeDepthSourceSelection(_ selectionContext: CaptureSelectionContext) -> TAPDepthManifest.DepthSourceSelection {
        TAPDepthManifest.DepthSourceSelection(
            selectionMode: selectionContext.selectionMode.rawValue,
            requestedDepthSourceID: selectionContext.depthSourceID,
            requestedDepthSourceDisplayName: selectionContext.depthSourceDisplayName,
            requestedDepthSourceKind: selectionContext.depthSourceKind,
            compatibilityStatus: selectionContext.compatibilityStatus,
            compatibilityReason: selectionContext.compatibilityReason,
            resolvedDeviceID: selectionContext.resolvedCaptureDeviceID,
            resolvedDeviceType: selectionContext.resolvedCaptureDeviceType,
            resolvedDeviceName: selectionContext.resolvedCaptureDeviceName
        )
    }

    private static func makePairing(
        _ selectionContext: CaptureSelectionContext,
        plan: CaptureSourcePlan
    ) -> TAPDepthManifest.Pairing {
        TAPDepthManifest.Pairing(
            mode: selectionContext.pairingMode,
            status: selectionContext.compatibilityStatus,
            requiresMultiCam: plan.pairingMode == .requiresMultiCam,
            releaseAllowed: plan.canCapturePhotoDepth,
            alignmentStatus: selectionContext.alignmentStatus
        )
    }

    private static func makeZoom(plan: CaptureSourcePlan) -> TAPDepthManifest.Zoom {
        TAPDepthManifest.Zoom(
            requestedZoomID: plan.zoom?.id,
            requestedZoomFactor: plan.zoom?.requestedZoomFactor,
            actualVideoZoomFactor: plan.zoom?.rawVideoZoomFactor,
            depthSafeRanges: plan.zoomCapability.depthSafeZoomRanges.map {
                TAPDepthManifest.ZoomRange(lowerBound: $0.lowerBound, upperBound: $0.upperBound)
            },
            isContinuous: plan.zoomCapability.isContinuous,
            isDiscrete: plan.zoomCapability.isDiscrete
        )
    }

    private static func makeCrop(plan: CaptureSourcePlan) -> TAPDepthManifest.Crop {
        TAPDepthManifest.Crop(
            mode: plan.cropPolicy.mode,
            cropRectNormalized: plan.cropPolicy.cropRectNormalized,
            destructiveFinalCropApplied: plan.cropPolicy.destructiveFinalCropApplied,
            sourceAPI: "AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)"
        )
    }

    private static func makeResolvedSession(
        _ selectionContext: CaptureSelectionContext,
        device: AVCaptureDevice
    ) -> TAPDepthManifest.ResolvedSession {
        let activePrimaryDevice = device.activePrimaryConstituent
        return TAPDepthManifest.ResolvedSession(
            mode: selectionContext.sessionMode,
            resolvedCaptureDeviceID: selectionContext.resolvedCaptureDeviceID,
            resolvedCaptureDeviceType: selectionContext.resolvedCaptureDeviceType,
            resolvedCaptureDeviceName: selectionContext.resolvedCaptureDeviceName,
            activePrimaryConstituentDeviceType: activePrimaryDevice?.deviceType.rawValue,
            activePrimaryConstituentDeviceName: activePrimaryDevice?.localizedName
        )
    }

    private static func makePhotoLens(
        _ selectionContext: CaptureSelectionContext,
        plan: CaptureSourcePlan,
        device: AVCaptureDevice
    ) -> TAPDepthManifest.PhotoLens {
        let activePrimaryDevice = device.activePrimaryConstituent
        let focalLabel = plan.requestedFocalLengthLabel

        return TAPDepthManifest.PhotoLens(
            requestedLensID: selectionContext.rgbSourceID,
            requestedDisplayName: selectionContext.rgbSourceDisplayName,
            requestedFocalLengthLabel: focalLabel.label,
            labelSource: focalLabel.source,
            requestedZoomFactor: selectionContext.selectedZoomFactor ?? 1.0,
            requestedReferenceZoomFactor: plan.rgbSource.referenceZoomFactor,
            requestedEquivalentFocalLength35mmMillimeters: focalLabel.equivalentMillimeters,
            position: selectionContext.rgbSourcePosition,
            resolvedCaptureDeviceType: device.deviceType.rawValue,
            resolvedCaptureDeviceName: device.localizedName,
            resolvedActivePrimaryConstituentDeviceType: activePrimaryDevice?.deviceType.rawValue,
            resolvedActivePrimaryConstituentDeviceName: activePrimaryDevice?.localizedName
        )
    }

    private static func makeSelectedDepthCamera(_ selectionContext: CaptureSelectionContext) -> TAPDepthManifest.SelectedDepthCamera {
        TAPDepthManifest.SelectedDepthCamera(
            id: selectionContext.depthSourceID ?? "none",
            displayName: selectionContext.depthSourceDisplayName ?? "None",
            deviceType: selectionContext.resolvedCaptureDeviceType,
            deviceName: selectionContext.resolvedCaptureDeviceName,
            position: selectionContext.rgbSourcePosition
        )
    }

    private static func makeSelectedZoom(_ selectionContext: CaptureSelectionContext) -> TAPDepthManifest.SelectedZoom {
        TAPDepthManifest.SelectedZoom(
            id: selectionContext.selectedZoomID ?? "zoom-unknown",
            displayName: selectionContext.selectedZoomDisplayName ?? "unknown",
            zoomFactor: selectionContext.selectedZoomFactor ?? 1.0
        )
    }

    private static func makeDepthBackend(
        _ selectionContext: CaptureSelectionContext,
        device: AVCaptureDevice
    ) -> TAPDepthManifest.DepthBackendSelection {
        /*
         This legacy section remains for readers that already understand the
         v1 `depthBackend` field. In SingleCam mode, the resolved backend is
         exactly the selected depth camera, and the selected zoom is recorded in
         `selectedZoom` as well as `actualVideoZoomFactor`.
        */
        return TAPDepthManifest.DepthBackendSelection(
            selectionMode: selectionContext.selectionMode.rawValue,
            requestedBackendID: selectionContext.depthSourceID,
            requestedBackendDisplayName: selectionContext.depthSourceDisplayName,
            resolvedBackendID: selectionContext.depthSourceID ?? selectionContext.resolvedCaptureDeviceID,
            resolvedBackendDisplayName: selectionContext.depthSourceDisplayName ?? selectionContext.resolvedCaptureDeviceName,
            resolvedCaptureDeviceType: device.deviceType.rawValue,
            resolvedCaptureDeviceName: device.localizedName,
            actualVideoZoomFactor: selectionContext.selectedZoomFactor ?? 1.0
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
        let auxiliaryKind = TAPDepthAuxiliaryKind(kind: depthData.depthDataType)
        let source = TAPDepthSourceClassifier.source(forDeviceType: device.deviceType.rawValue, localizedName: device.localizedName)

        return TAPDepthManifest.Depth(
            auxiliaryDataKind: auxiliaryKind.rawValue,
            depthDataType: TAPFourCharCode.string(from: depthData.depthDataType),
            metricUnit: auxiliaryKind == .depth ? "meters" : "convertDisparityToDepthMeters",
            conversionPath: auxiliaryKind == .depth ? "nativeDepthMeters" : "AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)",
            width: width,
            height: height,
            pixelFormat: TAPFourCharCode.string(from: CVPixelBufferGetPixelFormatType(pixelBuffer)),
            orientation: "appleAuxiliaryDepthNative",
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

    private static func orientationDescription(from metadata: [String: Any]) -> String {
        if let orientation = TAPDepthMapReader.orientationRawValue(from: metadata[kCGImagePropertyOrientation as String]) {
            return "cgImagePropertyOrientation:\(orientation)"
        }

        return "unspecified"
    }
}

/// Encodes manifests in one place so the app and tests use identical JSON
/// options.
///
/// `payloadDataExcludingProofs` deliberately excludes `proofs`. The app does not
/// create hashes or signatures; this helper exists so schema tests can assert
/// that placeholder proof records do not change the manifest payload bytes.
nonisolated enum TAPDepthManifestEncoder {
    static func manifestJSON(_ manifest: TAPDepthManifest) throws -> String {
        let data = try encoder.encode(manifest)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return json
    }

    static func payloadDataExcludingProofs(_ payload: TAPDepthManifest.Payload) throws -> Data {
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
    case unsupportedZoomFactor
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
    case assetNotFound
    case releasePackagingStrategyRejected
    case captureBackpressureLimitReached
    case incompatibleRGBDepthPairing
    case multicamRequired

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
        case .unsupportedZoomFactor:
            "The selected zoom factor does not support depth delivery on this camera."
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
        case .assetNotFound:
            "The selected Photos asset could not be found."
        case .releasePackagingStrategyRejected:
            "Release builds only support embedded single-photo artifacts."
        case .captureBackpressureLimitReached:
            "Too many capture jobs are already pending."
        case .incompatibleRGBDepthPairing:
            "The selected RGB source and depth source cannot produce a supported paired capture."
        case .multicamRequired:
            "This RGB and depth pairing is outside the SingleCam photo-depth pipeline."
        }
    }
}
