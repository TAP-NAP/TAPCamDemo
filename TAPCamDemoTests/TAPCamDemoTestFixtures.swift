//
//  TAPCamDemoTestFixtures.swift
//  TAPCamDemoTests
//

import AVFoundation
import CoreLocation
import Foundation
import Testing
import UIKit
@testable import TAPCamDemo

enum TAPCamDemoTestFixtures {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPCamDemoTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var sampleLocation: TAPDepthManifest.Location {
        TAPDepthManifest.Location(
            latitude: 31.2304,
            longitude: 121.4737,
            altitude: 12.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 8.0,
            timestamp: "2026-04-25T00:00:00.000Z"
        )
    }

    static func samplePayload(
        id: String = "sample-capture",
        capturedAt: String = "2026-04-25T00:00:00.000Z",
        location: TAPDepthManifest.Location?,
        capture: TAPDepthManifest.Capture = sampleManifestCapture(),
        rgbSourceDisplayName: String = "Wide",
        selectedDepthCameraDisplayName: String = "Portrait Depth",
        requestedFocalLengthLabel: String = "2x",
        resolvedCaptureDeviceName: String = "Back Triple Camera",
        resolvedActivePrimaryConstituentDeviceName: String? = "Back Wide Camera",
        depthSourceCaptureDeviceName: String = "Back Triple Camera",
        depthSourceSensingMethod: String = "multiCameraStereoOrComputational",
        depthSourceLidarParticipation: String = "notAsserted",
        depthAvailability: CaptureDepthAvailability = .available,
        livePhoto: TAPDepthManifest.LivePhoto? = nil
    ) -> TAPDepthManifest.Payload {
        let hasDepth = depthAvailability == .available

        return TAPDepthManifest.Payload(
            id: id,
            capturedAt: capturedAt,
            sessionMode: "singleCam",
            pairingMode: "rgbWithApplePairedDepth",
            alignmentStatus: "sameCapturePipeline",
            sourceAPIs: .avFoundationPhotoDepth,
            capture: capture,
            rgbSource: TAPDepthManifest.RGBSource(
                id: "com.apple.test-wide",
                displayName: rgbSourceDisplayName,
                deviceType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
                deviceName: "Back Wide Camera",
                position: "back",
                sourceKind: "physical",
                requestedReferenceZoomFactor: 1.0
            ),
            depthSource: TAPDepthManifest.DepthSourceSelection(
                selectionMode: "auto",
                requestedDepthSourceID: "portraitSemanticDepth",
                requestedDepthSourceDisplayName: "Portrait Depth",
                requestedDepthSourceKind: "portraitSemanticDepth",
                compatibilityStatus: "compatible",
                compatibilityReason: nil,
                resolvedDeviceID: "com.apple.test-camera",
                resolvedDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                resolvedDeviceName: "Back Triple Camera"
            ),
            pairing: TAPDepthManifest.Pairing(
                mode: "rgbWithApplePairedDepth",
                status: "compatible",
                requiresMultiCam: false,
                releaseAllowed: true,
                alignmentStatus: "sameCapturePipeline"
            ),
            zoom: TAPDepthManifest.Zoom(
                requestedZoomID: "zoom-2x",
                requestedZoomFactor: 2.0,
                actualVideoZoomFactor: 2.0,
                depthSafeRanges: [
                    TAPDepthManifest.ZoomRange(lowerBound: 1.0, upperBound: 3.0)
                ],
                isContinuous: true,
                isDiscrete: false
            ),
            crop: TAPDepthManifest.Crop(
                mode: "previewOnly",
                cropRectNormalized: CropRectNormalized(x: 0, y: 0.125, width: 1, height: 0.75),
                destructiveFinalCropApplied: false,
                sourceAPI: "AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)"
            ),
            resolvedSession: TAPDepthManifest.ResolvedSession(
                mode: "singleCam",
                resolvedCaptureDeviceID: "com.apple.test-camera",
                resolvedCaptureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                resolvedCaptureDeviceName: "Back Triple Camera",
                activePrimaryConstituentDeviceType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
                activePrimaryConstituentDeviceName: "Back Wide Camera"
            ),
            selectedDepthCamera: TAPDepthManifest.SelectedDepthCamera(
                id: "portraitSemanticDepth",
                displayName: selectedDepthCameraDisplayName,
                deviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                deviceName: "Back Triple Camera",
                position: "back"
            ),
            selectedZoom: TAPDepthManifest.SelectedZoom(
                id: "zoom-2x",
                displayName: "2x",
                zoomFactor: 2.0
            ),
            photoLens: TAPDepthManifest.PhotoLens(
                requestedLensID: "com.apple.test-wide",
                requestedDisplayName: "Wide",
                requestedFocalLengthLabel: requestedFocalLengthLabel,
                labelSource: "rgbSourceAndDepthSafeZoom",
                requestedZoomFactor: 2.0,
                requestedReferenceZoomFactor: 2.0,
                requestedEquivalentFocalLength35mmMillimeters: nil,
                position: "back",
                resolvedCaptureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                resolvedCaptureDeviceName: resolvedCaptureDeviceName,
                resolvedActivePrimaryConstituentDeviceType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
                resolvedActivePrimaryConstituentDeviceName: resolvedActivePrimaryConstituentDeviceName
            ),
            depthBackend: TAPDepthManifest.DepthBackendSelection(
                selectionMode: "auto",
                requestedBackendID: "portraitSemanticDepth",
                requestedBackendDisplayName: "Portrait Depth",
                resolvedBackendID: "portraitSemanticDepth",
                resolvedBackendDisplayName: "Portrait Depth",
                resolvedCaptureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                resolvedCaptureDeviceName: "Back Triple Camera",
                actualVideoZoomFactor: 2.0
            ),
            camera: TAPDepthManifest.Camera(
                localizedName: "Back Triple Camera",
                uniqueID: "com.apple.test-camera",
                modelID: "iPhone",
                deviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                position: "back",
                activePrimaryConstituentDeviceType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
                activePrimaryConstituentDeviceName: "Back Wide Camera",
                activeFormat: TAPDepthManifest.CameraFormat(
                    mediaSubType: "420v",
                    width: 4032,
                    height: 3024,
                    maxFrameRate: 30
                ),
                activeDepthFormat: TAPDepthManifest.CameraFormat(
                    mediaSubType: "hdep",
                    width: 256,
                    height: 192,
                    maxFrameRate: 30
                ),
                lensPosition: 0.35,
                minimumFocusDistanceMillimeters: 120,
                nominalFocalLengthIn35mmFilmMillimeters: 24
            ),
            photo: TAPDepthManifest.Photo(
                width: 4032,
                height: 3024,
                orientation: "cgImagePropertyOrientation:1",
                metadataKeys: ["{Exif}", "{TIFF}"]
            ),
            depth: TAPDepthManifest.Depth(
                availability: depthAvailability,
                auxiliaryDataKind: hasDepth ? "depth" : "none",
                depthDataType: hasDepth ? "hdep" : "none",
                metricUnit: hasDepth ? "meters" : "none",
                conversionPath: hasDepth ? "nativeDepthMeters" : "depthUnavailable",
                width: hasDepth ? 256 : 0,
                height: hasDepth ? 192 : 0,
                pixelFormat: hasDepth ? "hdep" : "none",
                orientation: hasDepth ? "appleAuxiliaryDepthNative" : "unavailable",
                accuracy: hasDepth ? "absolute" : "unavailable",
                quality: hasDepth ? "high" : "unavailable",
                isFiltered: hasDepth,
                source: TAPDepthManifest.DepthSource(
                    captureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                    captureDeviceName: depthSourceCaptureDeviceName,
                    sensingMethod: depthSourceSensingMethod,
                    lidarParticipation: depthSourceLidarParticipation
                ),
                cameraCalibration: nil
            ),
            alignment: TAPDepthManifest.Alignment(
                depthToImage: hasDepth ? "appleAuxiliaryDepthNative" : "unavailable"
            ),
            location: location,
            software: TAPDepthManifest.Software(
                appName: "TAPCamDemo",
                bundleIdentifier: "TAP-NAP.TAPCamDemo",
                version: "1.0",
                build: "1"
            ),
            livePhoto: livePhoto
        )
    }

    static func sampleManifestCapture(
        requestedCodec: String = AVVideoCodecType.hevc.rawValue,
        depthDataDeliveryEnabled: Bool = true,
        embedsDepthDataInPhoto: Bool = true,
        depthDataFiltered: Bool = true,
        depthAvailability: CaptureDepthAvailability = .available,
        photoQualityPrioritization: String = "quality"
    ) -> TAPDepthManifest.Capture {
        TAPDepthManifest.Capture(
            resolvedSettingsUniqueID: 42,
            requestedCodec: requestedCodec,
            depthDataDeliveryEnabled: depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: embedsDepthDataInPhoto,
            depthDataFiltered: depthDataFiltered,
            depthAvailability: depthAvailability,
            photoQualityPrioritization: photoQualityPrioritization
        )
    }

    static func analysisInput(depthMap: TAPMetricDepthMap) throws -> TAPDepthAnalysisInput {
        let rgbaPixel = [UInt8(20), UInt8(20), UInt8(20), UInt8(255)]
        let image = try TAPDepthRGBAImageRenderer.image(
            pixels: Array(repeating: rgbaPixel, count: depthMap.samples.count).flatMap { $0 },
            width: depthMap.width,
            height: depthMap.height
        )

        return TAPDepthAnalysisInput(
            manifest: nil,
            image: image,
            imageOrientation: .up,
            depthMap: depthMap,
            depthAccuracy: "unknown",
            depthQuality: "unknown",
            heatmap: try TAPDepthHeatmapRenderer.heatmap(for: depthMap),
            validMask: try TAPDepthMaskRenderer.validMask(for: depthMap)
        )
    }

    static var sampleCalibration: TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: 8,
            intrinsicMatrixReferenceHeight: 8,
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: 4,
            lensDistortionCenterY: 4,
            intrinsicMatrix: [100, 0, 0, 0, 100, 0, 4, 4, 1],
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        )
    }

    static func sampleManualControlCapability(
        deviceID: String = "device-1",
        deviceDisplayName: String = "Wide",
        deviceTypeRawValue: String = "built-in-wide",
        supportsContinuousAutoExposure: Bool = true,
        supportsLockedExposure: Bool = true,
        supportsCustomExposure: Bool = true,
        supportsAutoFocus: Bool = true,
        supportsContinuousAutoFocus: Bool = true,
        supportsLockedFocus: Bool = true,
        supportsCustomLensPosition: Bool = true,
        supportsFocusPointOfInterest: Bool = true,
        supportsLockedWhiteBalance: Bool = true,
        supportsContinuousAutoWhiteBalance: Bool = true,
        minimumFocusDistanceMillimeters: Int? = 120,
        exposureBiasRange: CameraControlCapabilitySnapshot.DoubleRange = .init(minimum: -2, maximum: 2),
        isoRange: CameraControlCapabilitySnapshot.DoubleRange = .init(minimum: 32, maximum: 1_600),
        shutterDurationRangeSeconds: CameraControlCapabilitySnapshot.DoubleRange = .init(
            minimum: 1.0 / 12_000.0,
            maximum: 1
        ),
        currentISO: Double = 100,
        currentShutterDurationSeconds: Double = 1.0 / 120.0,
        currentExposureTargetOffset: Double = 0,
        currentLensPosition: Double = 0.5,
        zoomRange: CameraControlCapabilitySnapshot.DoubleRange = .init(minimum: 1, maximum: 15)
    ) -> CameraControlCapabilitySnapshot {
        CameraControlCapabilitySnapshot(
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            deviceTypeRawValue: deviceTypeRawValue,
            exposure: CameraControlCapabilitySnapshot.Exposure(
                supportsContinuousAutoExposure: supportsContinuousAutoExposure,
                supportsLockedExposure: supportsLockedExposure,
                supportsCustomExposure: supportsCustomExposure,
                exposureBiasRange: exposureBiasRange,
                isoRange: isoRange,
                shutterDurationRangeSeconds: shutterDurationRangeSeconds,
                currentISO: currentISO,
                currentShutterDurationSeconds: currentShutterDurationSeconds,
                currentExposureTargetOffset: currentExposureTargetOffset
            ),
            focus: CameraControlCapabilitySnapshot.Focus(
                supportsAutoFocus: supportsAutoFocus,
                supportsContinuousAutoFocus: supportsContinuousAutoFocus,
                supportsLockedFocus: supportsLockedFocus,
                supportsCustomLensPosition: supportsCustomLensPosition,
                supportsFocusPointOfInterest: supportsFocusPointOfInterest,
                supportsSmoothAutoFocus: true,
                minimumFocusDistanceMillimeters: minimumFocusDistanceMillimeters,
                currentLensPosition: currentLensPosition
            ),
            whiteBalance: CameraControlCapabilitySnapshot.WhiteBalance(
                supportsContinuousAutoWhiteBalance: supportsContinuousAutoWhiteBalance,
                supportsLockedWhiteBalance: supportsLockedWhiteBalance,
                maximumGain: 4
            ),
            aperture: CameraControlCapabilitySnapshot.Aperture(fixedLensAperture: 1.78),
            zoom: CameraControlCapabilitySnapshot.Zoom(range: zoomRange)
        )
    }

    static func samplePendingRecord(
        captureID: String,
        capturedAt: Date,
        status: TAPPendingCaptureStatus = .pending,
        unsignedHEICFilename: String? = "unsigned.heic",
        signedHEICFilename: String? = nil,
        thumbnailFilename: String? = nil,
        assetLocalIdentifier: String? = nil,
        failureReason: String? = nil,
        photoQualityLevel: CapturePhotoQualityLevel = .quality,
        captureScoreSummary: CaptureScoreSummary = .unknown,
        location: TAPPendingCaptureLocation? = nil
    ) -> TAPPendingCaptureRecord {
        TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            capturedAt: capturedAt,
            createdAt: capturedAt,
            updatedAt: capturedAt,
            status: status,
            photoQualityLevel: photoQualityLevel,
            captureScoreSummary: captureScoreSummary,
            unsignedHEICFilename: status == .exported ? nil : unsignedHEICFilename,
            signedHEICFilename: signedHEICFilename,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: assetLocalIdentifier,
            failureReason: failureReason,
            retryCount: 0,
            location: location
        )
    }

    static func samplePendingArtifact(
        photoData: Data,
        fileContainer: CapturePhotoFileContainer = .heic,
        photoQualityLevel: CapturePhotoQualityLevel = .quality,
        captureID: String = "sample-capture",
        capturedAt: Date = Date(timeIntervalSince1970: 0),
        livePhotoMovie: PackagedLivePhotoMovie? = nil
    ) -> PackagedCaptureArtifact {
        PackagedCaptureArtifact(
            packageID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            strategy: .embeddedPhoto,
            photoData: photoData,
            fileContainer: fileContainer,
            photoQualityLevel: photoQualityLevel,
            manifest: TAPDepthManifest(payload: samplePayload(
                id: captureID,
                capturedAt: TAPDateFormatting.iso8601.string(from: capturedAt),
                location: sampleLocation,
                capture: sampleManifestCapture(
                    photoQualityPrioritization: photoQualityLevel.manifestDescription
                )
            )),
            livePhotoMovie: livePhotoMovie,
            signatureStatus: .unsigned(reason: "test"),
            depthAvailability: .available,
            captureScoreSummary: CaptureScoreSummary.make(
                depthAvailability: .available,
                fileContainer: fileContainer,
                photoQualityLevel: photoQualityLevel,
                signatureStatus: .unsigned(reason: "test")
            ),
            packagingMetrics: CapturePackagingMetrics(),
            capturedAt: capturedAt,
            location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                altitude: 12,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        )
    }

    static func sampleThumbnailSourceData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
            context.cgContext.setFillColor(UIColor.systemTeal.cgColor)
            context.cgContext.fill(rect)
        }
    }

    static func pendingCaptureBundleJSON(rootURL: URL, captureID: String) throws -> String {
        let data = try Data(
            contentsOf: rootURL
                .appendingPathComponent(captureID, isDirectory: true)
                .appendingPathComponent("bundle.json")
        )
        return try #require(String(data: data, encoding: .utf8))
    }

    static func writePendingRecord(
        _ record: TAPPendingCaptureRecord,
        rootURL: URL,
        bundleCaptureID: String? = nil
    ) throws {
        let bundleURL = rootURL.appendingPathComponent(
            bundleCaptureID ?? record.captureID,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: bundleURL.appendingPathComponent("bundle.json"), options: Data.WritingOptions.atomic)
    }
}
