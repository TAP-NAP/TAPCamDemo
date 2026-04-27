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

    @Test func manifestJSONDocumentsSingleCamSelectionAndNullableLocation() throws {
        let manifest = TAPDepthManifest(payload: Self.samplePayload(location: nil))
        let json = try TAPDepthManifestEncoder.manifestJSON(manifest)

        #expect(json.contains("\"location\":null"))
        #expect(json.contains("\"proofs\":[]"))
        #expect(json.contains("\"depthDataType\":\"hdep\""))
        #expect(json.contains("\"metricUnit\":\"meters\""))
        #expect(json.contains("\"depthToImage\":\"appleAuxiliaryDepthNative\""))
        #expect(json.contains("\"sessionMode\":\"singleCam\""))
        #expect(json.contains("\"pairingMode\":\"rgbWithApplePairedDepth\""))
        #expect(json.contains("\"alignmentStatus\":\"sameCapturePipeline\""))
        #expect(json.contains("\"rgbSource\""))
        #expect(json.contains("\"depthSource\""))
        #expect(json.contains("\"pairing\""))
        #expect(json.contains("\"zoom\""))
        #expect(json.contains("\"crop\""))
        #expect(json.contains("\"resolvedSession\""))
        #expect(json.contains("\"selectedDepthCamera\""))
        #expect(json.contains("\"selectedZoom\""))
        #expect(json.contains("\"displayName\":\"Wide\""))
        #expect(json.contains("\"displayName\":\"2x\""))
        #expect(json.contains("\"selectionMode\":\"auto\""))
        #expect(json.contains("\"labelSource\":\"rgbSourceAndDepthSafeZoom\""))
        #expect(json.contains("\"sensingMethod\":\"multiCameraStereoOrComputational\""))
        #expect(json.contains("\"lidarParticipation\":\"notAsserted\""))
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

    @Test func depthRowsKeepFixedDebugOrdering() throws {
        #expect(DepthProfileKind.lidarDepth.fixedOrder < DepthProfileKind.trueDepth.fixedOrder)
        #expect(DepthProfileKind.trueDepth.fixedOrder < DepthProfileKind.dualCameraDisparity.fixedOrder)
        #expect(DepthProfileKind.dualCameraDisparity.fixedOrder < DepthProfileKind.dualWideDisparity.fixedOrder)
        #expect(DepthProfileKind.dualWideDisparity.fixedOrder < DepthProfileKind.portraitSemanticDepth.fixedOrder)
    }

    @Test func automaticPriorityPrefersApplePairedVirtualPhotoPipelines() throws {
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInTripleCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInDualWideCamera))
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInDualWideCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInDualCamera))
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInDualCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInWideAngleCamera))
        #expect(CameraCapabilityResolver.automaticPriority(for: .builtInLiDARDepthCamera) > CameraCapabilityResolver.automaticPriority(for: .builtInTrueDepthCamera))
    }

    @Test func zoomProfilesDisableUnsupportedDepthDeliveryRanges() throws {
        let profiles = CameraCapabilityResolver.makeZoomProfiles(
            candidateZooms: [1, 2, 3],
            minimumZoom: 1,
            maximumZoom: 3,
            depthDeliveryRanges: [1.0...2.0],
            allowsZoomOutsideDepthDeliveryRanges: false
        )

        #expect(profiles.map(\.displayName) == ["1x", "2x", "3x"])
        #expect(profiles[0].isEnabled)
        #expect(profiles[1].isEnabled)
        #expect(!profiles[2].isEnabled)
        #expect(profiles[2].disabledReason == "Outside depth zoom range")
    }

    @Test func zoomProfilesStillDisableZoomOutsideDepthSafeRangesWhenFormatAllowsPreviewZoom() throws {
        let profiles = CameraCapabilityResolver.makeZoomProfiles(
            candidateZooms: [1, 2, 3],
            minimumZoom: 1,
            maximumZoom: 3,
            depthDeliveryRanges: [1.0...1.0],
            allowsZoomOutsideDepthDeliveryRanges: true
        )

        #expect(profiles[0].isEnabled)
        #expect(!profiles[1].isEnabled)
        #expect(!profiles[2].isEnabled)
        #expect(profiles[1].disabledReason == "Zoom would drop depth delivery")
    }

    @Test func zoomProfilesWithoutDepthPairingUseCameraZoomRange() throws {
        let profiles = CameraCapabilityResolver.makeZoomProfiles(
            candidateZooms: [1, 2, 3],
            minimumZoom: 1,
            maximumZoom: 3,
            depthDeliveryRanges: [],
            allowsZoomOutsideDepthDeliveryRanges: true,
            requiresDepthSafeZoom: false
        )

        #expect(profiles.allSatisfy { $0.isEnabled })
    }

    @Test func debugZoomFOVUsesBaseEquivalentFocalLengthTimesVideoZoom() throws {
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 24, zoomFactor: 1) == 24)
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 24, zoomFactor: 2) == 48)
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 24, zoomFactor: 3) == 72)
        #expect(FocalLengthLabelResolver.debugEquivalentMillimeters(baseMillimeters: 13, zoomFactor: 2) == 26)
    }

    @Test func virtualDepthPipelinesUseWideBaselineForFOVLabels() throws {
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue))
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInDualWideCamera.rawValue))
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInDualCamera.rawValue))
        #expect(FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue))
        #expect(!FocalLengthLabelResolver.usesWideBaselineForVirtualFOV(deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue))
        #expect(FocalLengthLabelResolver.equivalentMillimeters(baseMillimeters: 24, zoomFactor: 1) == 24)
        #expect(FocalLengthLabelResolver.equivalentMillimeters(baseMillimeters: 24, zoomFactor: 2) == 48)
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 13, zoomFactor: 0.5))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 13, zoomFactor: 1))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 24, zoomFactor: 1))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 48, zoomFactor: 2))
        #expect(FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 77, zoomFactor: 3))
        #expect(!FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 26, zoomFactor: 2))
        #expect(!FocalLengthLabelResolver.isSemanticFOVSlot(equivalentMillimeters: 154, zoomFactor: 2))
    }

    @Test func discovered48mmFOVOptionUsesResolvedRawVideoZoomWhenAvailable() throws {
        let options = CameraCapabilityResolver.discover().focalLengthOptions()
        if let option = options.first(where: { $0.displayName == "48mm" && $0.isEnabled }) {
            let expectedRawZoom = FocalLengthLabelResolver.releaseVideoZoomFactor(
                for: option.rgbSource,
                targetEquivalentMillimeters: 48,
                formatSelection: option.depthSource?.formatSelection
            )
            #expect(abs(option.zoom.rawVideoZoomFactor - expectedRawZoom) < 0.001)

            let lowerDepthSafeBound = option.depthSource?.formatSelection?.videoFormat.supportedVideoZoomRangesForDepthDataDelivery
                .map { Double($0.lowerBound) }
                .min() ?? 1
            if lowerDepthSafeBound > 1.0 {
                #expect(option.zoom.rawVideoZoomFactor > 2.0)
            }
        }
        #expect(!options.contains(where: { $0.displayName == "26mm" && $0.zoom.rawVideoZoomFactor == 2.0 }))
        #expect(!options.contains(where: { $0.displayName == "154mm" && $0.zoom.rawVideoZoomFactor == 2.0 }))
    }

    @Test func pairingPlanKeepsCustomReleaseFOVZoomFactor() throws {
        let options = CameraCapabilityResolver.discover().focalLengthOptions()
        if let option = options.first(where: { $0.displayName == "48mm" && $0.isEnabled }) {
            let plan = RGBDepthPairingCoordinator.makePlan(
                rgbSource: option.rgbSource,
                depthSource: option.depthSource,
                selectionMode: .automatic,
                selectedZoomID: option.zoom.id,
                selectedZoomFactor: option.zoom.rawVideoZoomFactor,
                cropRectNormalized: .fullFrame
            )

            #expect(abs((plan.zoom?.rawVideoZoomFactor ?? 0) - option.zoom.rawVideoZoomFactor) < 0.001)
        }
    }

    @Test func runtimePackagingStrategyIsEmbeddedPhotoOnly() throws {
        #expect(PackagingStrategy.embeddedPhoto.rawValue == "embeddedPhoto")
    }

    @Test func depthSelectionModeKeepsPublishedManifestRawValues() throws {
        #expect(DepthSelectionMode.automatic.rawValue == "auto")
        #expect(DepthSelectionMode.manual.rawValue == "manual")
        #expect(DepthSelectionMode.debugDepthOverride.rawValue == "debugDepthOverride")
    }

    @Test func proofChangesDoNotAffectPayloadBytes() throws {
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

        let payloadBytesWithoutProofs = try TAPDepthManifestEncoder.payloadDataExcludingProofs(manifestWithoutProof.payload)
        let payloadBytesWithProofs = try TAPDepthManifestEncoder.payloadDataExcludingProofs(manifestWithProof.payload)

        #expect(payloadBytesWithoutProofs == payloadBytesWithProofs)
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
            sessionMode: "singleCam",
            pairingMode: "rgbWithApplePairedDepth",
            alignmentStatus: "sameCapturePipeline",
            sourceAPIs: .avFoundationPhotoDepth,
            capture: TAPDepthManifest.Capture(
                resolvedSettingsUniqueID: 42,
                requestedCodec: "hvc1",
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: true,
                depthDataFiltered: true,
                photoQualityPrioritization: "quality"
            ),
            rgbSource: TAPDepthManifest.RGBSource(
                id: "com.apple.test-wide",
                displayName: "Wide",
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
                displayName: "Portrait Depth",
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
                requestedFocalLengthLabel: "2x",
                labelSource: "rgbSourceAndDepthSafeZoom",
                requestedZoomFactor: 2.0,
                requestedReferenceZoomFactor: 2.0,
                requestedEquivalentFocalLength35mmMillimeters: nil,
                position: "back",
                resolvedCaptureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                resolvedCaptureDeviceName: "Back Triple Camera",
                resolvedActivePrimaryConstituentDeviceType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
                resolvedActivePrimaryConstituentDeviceName: "Back Wide Camera"
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
                    captureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                    captureDeviceName: "Back Triple Camera",
                    sensingMethod: "multiCameraStereoOrComputational",
                    lidarParticipation: "notAsserted"
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
