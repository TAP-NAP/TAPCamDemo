//
//  TAPDepthManifestBuilder.swift
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

/// Builds a TAP manifest from the Apple objects that exist at the moment the
/// photo delegate receives an `AVCapturePhoto`.
///
/// This builder is the source-of-truth map between Apple APIs and the on-disk
/// manifest. The README mirrors this mapping so third-party tools can parse the
/// file without depending on this app's runtime state.
nonisolated enum TAPDepthManifestBuilder {
    /// Builds the TAP manifest embedded into the final HEIC.
    ///
    /// This maps planning/runtime facts and Apple `AVCapturePhoto` metadata into
    /// the published v1 schema without changing schema keys or raw values.
    ///
    /// - Tag: BuildTAPDepthManifest
    static func makeManifest(
        capturePackage: CapturePackage
    ) throws -> TAPDepthManifest {
        let photo = capturePackage.photo
        let context = capturePackage.sourceContext
        let device = context.sessionConfiguration.device
        let selectionContext = context.sessionConfiguration.selectionContext
        let plan = context.sessionConfiguration.capturePlan
        let resolvedOutput = capturePackage.resolvedOutput

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
                requestedCodec: resolvedOutput.requestedCodec.rawValue,
                depthDataDeliveryEnabled: resolvedOutput.depthDataDeliveryEnabled,
                embedsDepthDataInPhoto: resolvedOutput.embedsDepthDataInPhoto,
                depthDataFiltered: resolvedOutput.depthDataFiltered,
                depthAvailability: capturePackage.depthAvailability,
                photoQualityPrioritization: resolvedOutput.photoQualityPolicy.requested.manifestDescription
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
            depth: makeDepth(depthData: photo.depthData, device: device),
            alignment: makeAlignment(depthAvailability: capturePackage.depthAvailability),
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

    private static func makeDepth(depthData: AVDepthData?, device: AVCaptureDevice) -> TAPDepthManifest.Depth {
        let source = TAPDepthSourceClassifier.source(forDeviceType: device.deviceType.rawValue, localizedName: device.localizedName)
        guard let depthData else {
            return TAPDepthManifest.Depth(
                availability: .unavailable,
                auxiliaryDataKind: "none",
                depthDataType: "none",
                metricUnit: "none",
                conversionPath: "depthUnavailable",
                width: 0,
                height: 0,
                pixelFormat: "none",
                orientation: "unavailable",
                accuracy: "unavailable",
                quality: "unavailable",
                isFiltered: false,
                source: source,
                cameraCalibration: nil
            )
        }

        let pixelBuffer = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let auxiliaryKind = TAPDepthAuxiliaryKind(kind: depthData.depthDataType)

        return TAPDepthManifest.Depth(
            availability: .available,
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

    private static func makeAlignment(depthAvailability: CaptureDepthAvailability) -> TAPDepthManifest.Alignment {
        switch depthAvailability {
        case .available:
            TAPDepthManifest.Alignment(depthToImage: "appleAuxiliaryDepthNative")
        case .unavailable:
            TAPDepthManifest.Alignment(depthToImage: "unavailable")
        }
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
