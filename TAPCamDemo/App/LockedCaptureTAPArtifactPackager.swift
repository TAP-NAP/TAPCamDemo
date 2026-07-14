//
//  LockedCaptureTAPArtifactPackager.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import ImageIO

nonisolated enum LockedCaptureTAPArtifactPackager {
    private static let profile = CaptureOutputProfile.releasePhotoDepthHEIC

    static func packageStagingCapture(
        _ probe: LockedCaptureSessionContentCaptureProbe
    ) throws -> LockedCaptureSessionContentCaptureProbe {
        let stagingData = try Data(contentsOf: probe.photoURL)
        try TAPDepthPhotoFileReader.validateContainer(stagingData, expected: .heic)
        guard let depthData = try TAPDepthPhotoFileReader.depthData(from: stagingData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let photoInfo = try LockedCapturePhotoInfo(photoData: stagingData)
        let manifest = try makeManifest(
            metadata: probe.metadata,
            photoInfo: photoInfo,
            depthData: depthData
        )
        try CaptureOutputManifestPolicy(profile: profile).validate(manifest.payload.capture)

        let finalData = try TAPCaptureProvenanceWriter()
            .writeManifest(manifest, into: stagingData)
            .data
        let finalManifest = try TAPDepthPhotoFileReader.decodedManifest(from: finalData)
        guard finalManifest.payload.id == probe.metadata.captureID else {
            throw TAPDepthCaptureError.pendingCaptureManifestIDMismatch(
                expected: probe.metadata.captureID,
                actual: finalManifest.payload.id
            )
        }
        guard let finalDepthData = try TAPDepthPhotoFileReader.depthData(from: finalData) else {
            throw TAPDepthCaptureError.missingDepthData
        }
        _ = try TAPProofSlot.locate(in: finalData, fileContainer: .heic)

        var metadata = probe.metadata
        metadata.artifactKind = TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind
        metadata.photoFileName = TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName
        metadata.byteCount = finalData.count
        metadata.depthDataPresent = true
        metadata.depthDataType = finalDepthData.depthDataType
        metadata.isDepthDataFiltered = finalDepthData.isDepthDataFiltered
        metadata.resolvedPhotoWidth = Int(photoInfo.width)
        metadata.resolvedPhotoHeight = Int(photoInfo.height)

        let outputURL = try writeTemporaryArtifact(finalData)
        return LockedCaptureSessionContentCaptureProbe(
            metadata: metadata,
            photoURL: outputURL
        )
    }

    private static func makeManifest(
        metadata: TAPCamLockedRawCaptureMetadata,
        photoInfo: LockedCapturePhotoInfo,
        depthData: AVDepthData
    ) throws -> TAPDepthManifest {
        let captureID = metadata.captureID
        let capturedAt = TAPDateFormatting.iso8601.string(from: metadata.capturedAt)
        let deviceName = metadata.lensDisplayName
        let deviceType = metadata.captureDeviceTypeRawValue
        let deviceID = metadata.captureDeviceUniqueID
        let devicePosition = metadata.captureDevicePosition ?? "back"
        let zoomFactor = metadata.zoomFactor
        let sessionMode = "lockedCameraCapture"
        let pairingMode = "singleCamPhotoDepth"
        let alignmentStatus = "appleAuxiliaryDepthNative"
        let depthSource = TAPDepthSourceClassifier.source(
            forDeviceType: deviceType,
            localizedName: deviceName
        )
        let depthPixelBuffer = depthData.depthDataMap
        let depthFormat = TAPDepthManifest.CameraFormat(
            mediaSubType: TAPFourCharCode.string(
                from: CVPixelBufferGetPixelFormatType(depthPixelBuffer)
            ),
            width: Int32(CVPixelBufferGetWidth(depthPixelBuffer)),
            height: Int32(CVPixelBufferGetHeight(depthPixelBuffer)),
            maxFrameRate: nil
        )

        let payload = TAPDepthManifest.Payload(
            id: captureID,
            capturedAt: capturedAt,
            sessionMode: sessionMode,
            pairingMode: pairingMode,
            alignmentStatus: alignmentStatus,
            sourceAPIs: .avFoundationPhotoDepth,
            capture: TAPDepthManifest.Capture(
                resolvedSettingsUniqueID: 0,
                requestedCodec: AVVideoCodecType.hevc.rawValue,
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: true,
                depthDataFiltered: true,
                depthAvailability: .available,
                photoQualityPrioritization: profile.photoQualityPolicy.requested.manifestDescription
            ),
            rgbSource: TAPDepthManifest.RGBSource(
                id: metadata.lensID,
                displayName: metadata.lensDisplayName,
                deviceType: deviceType,
                deviceName: deviceName,
                position: devicePosition,
                sourceKind: "lockedCameraCaptureLens",
                requestedReferenceZoomFactor: zoomFactor
            ),
            depthSource: TAPDepthManifest.DepthSourceSelection(
                selectionMode: "lockedCameraAppContext",
                requestedDepthSourceID: nil,
                requestedDepthSourceDisplayName: nil,
                requestedDepthSourceKind: nil,
                compatibilityStatus: "compatible",
                compatibilityReason: nil,
                resolvedDeviceID: deviceID,
                resolvedDeviceType: deviceType,
                resolvedDeviceName: deviceName
            ),
            pairing: TAPDepthManifest.Pairing(
                mode: pairingMode,
                status: "compatible",
                requiresMultiCam: false,
                releaseAllowed: true,
                alignmentStatus: alignmentStatus
            ),
            zoom: TAPDepthManifest.Zoom(
                requestedZoomID: metadata.lensID,
                requestedZoomFactor: zoomFactor,
                actualVideoZoomFactor: zoomFactor,
                depthSafeRanges: [],
                isContinuous: false,
                isDiscrete: true
            ),
            crop: TAPDepthManifest.Crop(
                mode: "fullFrame",
                cropRectNormalized: .fullFrame,
                destructiveFinalCropApplied: false,
                sourceAPI: "LockedCameraCapture"
            ),
            resolvedSession: TAPDepthManifest.ResolvedSession(
                mode: sessionMode,
                resolvedCaptureDeviceID: deviceID,
                resolvedCaptureDeviceType: deviceType,
                resolvedCaptureDeviceName: deviceName,
                activePrimaryConstituentDeviceType: nil,
                activePrimaryConstituentDeviceName: nil
            ),
            selectedDepthCamera: TAPDepthManifest.SelectedDepthCamera(
                id: deviceID,
                displayName: deviceName,
                deviceType: deviceType,
                deviceName: deviceName,
                position: devicePosition
            ),
            selectedZoom: TAPDepthManifest.SelectedZoom(
                id: metadata.lensID,
                displayName: metadata.lensDisplayName,
                zoomFactor: zoomFactor
            ),
            photoLens: TAPDepthManifest.PhotoLens(
                requestedLensID: metadata.lensID,
                requestedDisplayName: metadata.lensDisplayName,
                requestedFocalLengthLabel: "\(Int(metadata.zoomFactor.rounded()))x",
                labelSource: "lockedCameraAppContext",
                requestedZoomFactor: zoomFactor,
                requestedReferenceZoomFactor: zoomFactor,
                requestedEquivalentFocalLength35mmMillimeters: nil,
                position: devicePosition,
                resolvedCaptureDeviceType: deviceType,
                resolvedCaptureDeviceName: deviceName,
                resolvedActivePrimaryConstituentDeviceType: nil,
                resolvedActivePrimaryConstituentDeviceName: nil
            ),
            depthBackend: TAPDepthManifest.DepthBackendSelection(
                selectionMode: "lockedCameraAppContext",
                requestedBackendID: nil,
                requestedBackendDisplayName: nil,
                resolvedBackendID: deviceID,
                resolvedBackendDisplayName: deviceName,
                resolvedCaptureDeviceType: deviceType,
                resolvedCaptureDeviceName: deviceName,
                actualVideoZoomFactor: zoomFactor
            ),
            camera: TAPDepthManifest.Camera(
                localizedName: deviceName,
                uniqueID: deviceID,
                modelID: "unknown",
                deviceType: deviceType,
                position: devicePosition,
                activePrimaryConstituentDeviceType: nil,
                activePrimaryConstituentDeviceName: nil,
                activeFormat: TAPDepthManifest.CameraFormat(
                    mediaSubType: CapturePhotoFileContainer.heic.uniformTypeIdentifier,
                    width: photoInfo.width,
                    height: photoInfo.height,
                    maxFrameRate: nil
                ),
                activeDepthFormat: depthFormat,
                lensPosition: nil,
                minimumFocusDistanceMillimeters: nil,
                nominalFocalLengthIn35mmFilmMillimeters: nil
            ),
            photo: TAPDepthManifest.Photo(
                width: photoInfo.width,
                height: photoInfo.height,
                orientation: photoInfo.orientation,
                metadataKeys: photoInfo.metadataKeys
            ),
            depth: makeDepth(
                depthData: depthData,
                source: depthSource
            ),
            alignment: TAPDepthManifest.Alignment(depthToImage: alignmentStatus),
            location: nil,
            software: .current
        )
        return TAPDepthManifest(payload: payload)
    }

    private static func makeDepth(
        depthData: AVDepthData,
        source: TAPDepthManifest.DepthSource
    ) -> TAPDepthManifest.Depth {
        let pixelBuffer = depthData.depthDataMap
        let auxiliaryKind = TAPDepthAuxiliaryKind(kind: depthData.depthDataType)

        return TAPDepthManifest.Depth(
            availability: .available,
            auxiliaryDataKind: auxiliaryKind.rawValue,
            depthDataType: TAPFourCharCode.string(from: depthData.depthDataType),
            metricUnit: auxiliaryKind == .depth ? "meters" : "convertDisparityToDepthMeters",
            conversionPath: auxiliaryKind == .depth
                ? "nativeDepthMeters"
                : "AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)",
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: TAPFourCharCode.string(
                from: CVPixelBufferGetPixelFormatType(pixelBuffer)
            ),
            orientation: "appleAuxiliaryDepthNative",
            accuracy: depthData.depthDataAccuracy.tapDescription,
            quality: depthData.depthDataQuality.tapDescription,
            isFiltered: depthData.isDepthDataFiltered,
            source: source,
            cameraCalibration: depthData.cameraCalibrationData.map(makeCalibration)
        )
    }

    private static func makeCalibration(
        _ calibration: AVCameraCalibrationData
    ) -> TAPDepthManifest.CameraCalibration {
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

    private static func writeTemporaryArtifact(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPLockedImportArtifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(
            TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName
        )
        try data.write(to: url, options: [.atomic])
        return url
    }
}

private nonisolated struct LockedCapturePhotoInfo {
    let width: Int32
    let height: Int32
    let orientation: String
    let metadataKeys: [String]

    init(photoData: Data) throws {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.int32Value ?? 0
        height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.int32Value ?? 0
        if let orientationValue = properties[kCGImagePropertyOrientation as String] {
            orientation = "cgImagePropertyOrientation:\(orientationValue)"
        } else {
            orientation = "unspecified"
        }
        metadataKeys = properties.keys.sorted()
    }
}
