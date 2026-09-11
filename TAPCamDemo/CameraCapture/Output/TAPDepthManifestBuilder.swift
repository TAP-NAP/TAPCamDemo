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

/// Records the captured photo, depth and device facts in the embedded manifest.
nonisolated enum TAPDepthManifestBuilder {
    static func makeManifest(
        capturePackage: CapturePackage
    ) throws -> TAPDepthManifest {
        let photo = capturePackage.photo
        let context = capturePackage.sourceContext
        let device = context.sessionConfiguration.device

        let captureID = UUID().uuidString
        let resolvedDimensions = photo.resolvedSettings.photoDimensions
        let payload = TAPDepthManifest.Payload(
            id: captureID,
            capturedAt: TAPDateFormatting.iso8601.string(from: context.capturedAt),
            camera: makeCamera(device: device),
            photo: TAPDepthManifest.Photo(
                width: resolvedDimensions.width,
                height: resolvedDimensions.height,
                orientation: Self.orientationDescription(from: photo.metadata),
                metadataKeys: photo.metadata.keys.sorted()
            ),
            depth: makeDepth(depthData: photo.depthData, device: device),
            location: context.location.map(makeLocation),
            software: .current,
            livePhoto: makeLivePhoto(capturePackage.livePhotoMovie)
        )

        let schema: TAPDepthManifest.Schema = capturePackage.livePhotoMovie == nil
            ? TAPDepthManifest.Schema()
            : .livePhoto
        return TAPDepthManifest(payload: payload, schema: schema)
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

    private static func makeLivePhoto(_ movie: CapturedLivePhotoMovie?) -> TAPDepthManifest.LivePhoto? {
        guard let movie else {
            return nil
        }
        return TAPDepthManifest.LivePhoto(
            presence: "paired-video",
            pairedVideoFilename: "paired-video.mov",
            durationSeconds: max(0, movie.duration.seconds),
            photoDisplayTimeSeconds: max(0, movie.photoDisplayTime.seconds),
            width: movie.dimensions.width,
            height: movie.dimensions.height,
            videoCodec: movie.codec,
            audio: movie.capturesAudio ? "captured" : "not-captured"
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
            cameraCalibration: depthData.cameraCalibrationData.map(TAPDepthManifest.CameraCalibration.init)
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
