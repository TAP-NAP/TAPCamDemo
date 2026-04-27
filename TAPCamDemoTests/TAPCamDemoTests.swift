//
//  TAPCamDemoTests.swift
//  TAPCamDemoTests
//
//  Created by Harold on 2026/4/24.
//

import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCamDemoTests {
    @Test func manifestSchemaDefinesThePublishedXMPContract() throws {
        let manifest = TAPDepthManifest(payload: Self.samplePayload(location: nil))

        #expect(manifest.schema.id == "urn:tapnap:tapcam:depth-manifest:v1")
        #expect(manifest.schema.mediaType == "application/vnd.tapnap.depth-manifest+json;version=1")
        #expect(manifest.schema.xmpNamespaceURI == "urn:tapnap:tapcam:depth:1.0")
        #expect(manifest.schema.xmpPrefix == "tapdepth")
        #expect(manifest.schema.xmpManifestPath == "tapdepth:Manifest")
    }

    @Test func manifestJSONIsStableAndIncludesNullableLocation() throws {
        let manifest = TAPDepthManifest(payload: Self.samplePayload(location: nil))
        let json = try TAPDepthManifestEncoder.manifestJSON(manifest)

        #expect(json.contains("\"location\":null"))
        #expect(json.contains("\"proofs\":[]"))
        #expect(json.contains("\"depthDataType\":\"hdep\""))
        #expect(json.contains("\"metricUnit\":\"meters\""))
        #expect(json.contains("\"depthToImage\":\"appleAuxiliaryDepthNative\""))
        #expect(json.contains("\"photoLens\""))
        #expect(json.contains("\"sensingMethod\":\"lidarDepthCamera\""))
        #expect(json.contains("\"lidarParticipation\":\"explicit\""))
        #expect(json.contains("\"xmpManifestPath\":\"tapdepth:Manifest\""))
    }

    @Test func depthSourceClassificationUsesOnlyPublicDeviceTypeClaims() throws {
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue).sensingMethod == "lidarDepthCamera")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue).lidarParticipation == "explicit")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue).sensingMethod == "trueDepthCamera")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue).lidarParticipation == "notApplicable")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue).sensingMethod == "multiCameraStereoOrComputational")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue).lidarParticipation == "notAsserted")
        #expect(TAPDepthSourceClassifier.classification(forDeviceType: AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue).sensingMethod == "singleCameraComputationalOrUnknown")
    }

    @Test func proofChangesDoNotAffectPayloadHashInput() throws {
        let payload = Self.samplePayload(location: Self.sampleLocation)
        let manifestWithoutProof = TAPDepthManifest(payload: payload)
        let manifestWithProof = TAPDepthManifest(
            payload: payload,
            proofs: [
                TAPDepthManifest.Proof(
                    type: "tap.example.signature",
                    algorithm: "placeholder",
                    keyID: "test-key",
                    createdAt: "2026-04-25T00:00:00.000Z",
                    value: "not-a-real-signature"
                )
            ]
        )

        let unsignedInput = try TAPDepthManifestEncoder.payloadDataForFutureProofing(manifestWithoutProof.payload)
        let signedInput = try TAPDepthManifestEncoder.payloadDataForFutureProofing(manifestWithProof.payload)

        #expect(unsignedInput == signedInput)
    }

    @Test func projectorUsesCalibrationToProduceCameraCoordinates() throws {
        let depthMap = TAPMetricDepthMap(
            width: 8,
            height: 8,
            samples: Array(repeating: 2.0, count: 64),
            calibration: Self.sampleCalibration
        )

        let center = try #require(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 4, y: 4))
        let right = try #require(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 5, y: 4))

        #expect(abs(center.x) < 0.0001)
        #expect(abs(center.y) < 0.0001)
        #expect(abs(center.z - 2.0) < 0.0001)
        #expect(abs(right.x - 0.02) < 0.0001)
    }

    @Test func planeEstimatorFindsSyntheticFlatDepthRegion() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: 1.5, count: 256),
            calibration: TAPDepthManifest.CameraCalibration(
                intrinsicMatrixReferenceWidth: 16,
                intrinsicMatrixReferenceHeight: 16,
                pixelSizeMillimeters: 0.001,
                lensDistortionLookupTablePresent: false,
                inverseLensDistortionLookupTablePresent: false,
                lensDistortionCenterX: 8,
                lensDistortionCenterY: 8,
                intrinsicMatrix: [120, 0, 0, 0, 120, 0, 8, 8, 1],
                extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
            )
        )

        let plane = try #require(TAPPlaneEstimator.estimatePlane(depthMap: depthMap, region: CGRect(x: 0, y: 0, width: 16, height: 16)))

        #expect(plane.averageResidualMeters < 0.001)
        #expect(plane.inlierRatio > 0.95)
        #expect(abs(abs(plane.normal.z) - 1) < 0.001)
    }

    @Test func orientationMapperRoundTripsRightRotatedSelectionRect() throws {
        let nativeSize = CGSize(width: 4, height: 3)
        let nativeRect = CGRect(x: 1, y: 0, width: 2, height: 1)
        let displayedRect = TAPImageOrientationMapper.displayedRect(
            fromNative: nativeRect,
            nativeSize: nativeSize,
            orientation: .right
        )
        let roundTripped = TAPImageOrientationMapper.nativeRect(
            fromDisplayed: displayedRect,
            nativeSize: nativeSize,
            orientation: .right
        )

        #expect(roundTripped == nativeRect)
        #expect(TAPImageOrientationMapper.displayedSize(nativeSize: nativeSize, orientation: .right) == CGSize(width: 3, height: 4))
    }

    private static var sampleLocation: TAPDepthManifest.Location {
        TAPDepthManifest.Location(
            latitude: 31.2304,
            longitude: 121.4737,
            altitude: 12.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 8.0,
            timestamp: "2026-04-25T00:00:00.000Z"
        )
    }

    private static func samplePayload(location: TAPDepthManifest.Location?) -> TAPDepthManifest.Payload {
        TAPDepthManifest.Payload(
            id: "sample-capture",
            capturedAt: "2026-04-25T00:00:00.000Z",
            sourceAPIs: .avFoundationPhotoDepth,
            capture: TAPDepthManifest.Capture(
                resolvedSettingsUniqueID: 42,
                requestedCodec: "hvc1",
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: true,
                depthDataFiltered: true,
                photoQualityPrioritization: "quality"
            ),
            photoLens: TAPDepthManifest.PhotoLens(
                requestedLensID: "rear-1x",
                requestedDisplayName: "1x",
                requestedZoomFactor: 1.0,
                position: "back",
                resolvedCaptureDeviceType: "AVCaptureDeviceTypeBuiltInLiDARDepthCamera",
                resolvedCaptureDeviceName: "Back LiDAR Camera",
                resolvedActivePrimaryConstituentDeviceType: nil,
                resolvedActivePrimaryConstituentDeviceName: nil
            ),
            camera: TAPDepthManifest.Camera(
                localizedName: "Back LiDAR Camera",
                uniqueID: "com.apple.test-camera",
                modelID: "iPhone",
                deviceType: "AVCaptureDeviceTypeBuiltInLiDARDepthCamera",
                position: "back",
                activePrimaryConstituentDeviceType: nil,
                activePrimaryConstituentDeviceName: nil,
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
                auxiliaryDataKind: "depth",
                depthDataType: "hdep",
                metricUnit: "meters",
                conversionPath: "nativeDepthMeters",
                width: 256,
                height: 192,
                pixelFormat: "hdep",
                orientation: "appleAuxiliaryDepthNative",
                accuracy: "absolute",
                quality: "high",
                isFiltered: true,
                source: TAPDepthManifest.DepthSource(
                    captureDeviceType: "AVCaptureDeviceTypeBuiltInLiDARDepthCamera",
                    captureDeviceName: "Back LiDAR Camera",
                    sensingMethod: "lidarDepthCamera",
                    lidarParticipation: "explicit"
                ),
                cameraCalibration: nil
            ),
            alignment: TAPDepthManifest.Alignment(depthToImage: "appleAuxiliaryDepthNative"),
            location: location,
            software: TAPDepthManifest.Software(
                appName: "TAPCamDemo",
                bundleIdentifier: "TAP-NAP.TAPCamDemo",
                version: "1.0",
                build: "1"
            )
        )
    }

    private static var sampleCalibration: TAPDepthManifest.CameraCalibration {
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
}
