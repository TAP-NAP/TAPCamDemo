//
//  TAPCamDemoTests.swift
//  TAPCamDemoTests
//
//  Created by Harold on 2026/4/24.
//

import AVFoundation
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
                metadataKeys: ["{Exif}", "{TIFF}"]
            ),
            depth: TAPDepthManifest.Depth(
                auxiliaryDataKind: "depth",
                depthDataType: "hdep",
                width: 256,
                height: 192,
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
            location: location,
            software: TAPDepthManifest.Software(
                appName: "TAPCamDemo",
                bundleIdentifier: "TAP-NAP.TAPCamDemo",
                version: "1.0",
                build: "1"
            )
        )
    }
}
