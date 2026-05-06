//
//  TAPCamDemoTests.swift
//  TAPCamDemoTests
//
//  Created by Harold on 2026/4/24.
//

import AppAttestKit
import AVFoundation
import CoreGraphics
import CoreLocation
import CryptoKit
import Foundation
import ImageIO
import Photos
import simd
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

    @Test func debugZoomDisplayIsRelativeToWideFOVBaseline() throws {
        #expect(FocalLengthLabelResolver.displayZoomFactor(rawVideoZoomFactor: 2, wideReferenceZoomFactor: 2) == 1)
        #expect(FocalLengthLabelResolver.displayZoomFactor(rawVideoZoomFactor: 4, wideReferenceZoomFactor: 2) == 2)
        #expect(FocalLengthLabelResolver.displayZoomFactor(rawVideoZoomFactor: 6, wideReferenceZoomFactor: 2) == 3)

        let profile = ZoomProfile.enabled(2, displayZoomFactor: 1)
        #expect(profile.id == "zoom-2x")
        #expect(profile.displayName == "1x")
        #expect(profile.rawVideoZoomFactor == 2)
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
            let plan = CaptureSourcePlan.make(
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

    @Test func captureContentDigestCanonicalJSONIsStable() throws {
        let digest = Self.sampleContentDigest()
        let first = try digest.canonicalJSONData()
        let second = try digest.canonicalJSONData()
        let decoded = try JSONDecoder().decode(CaptureContentDigest.self, from: first)
        let json = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(decoded == digest)
        #expect(json.contains("\"captureID\":\"sample-capture\""))
        #expect(json.contains("\"schemaID\":\"urn:tapnap:tapcam:capture-content-digest:v1\""))
    }

    @Test func appAttestCaptureAssertionSignerBuildsProofValue() async throws {
        let digest = Self.sampleContentDigest()
        let client = SucceedingAssertionAppAttestClient()
        let signer = AppAttestCaptureAssertionSigner(client: client)
        let assertionProof = try await signer.sign(contentDigest: digest)

        let proof = assertionProof.proof
        #expect(assertionProof.keyID == "test-key-id")
        #expect(proof.type == "appAttestAssertion")
        #expect(proof.algorithm == "AppAttestKit.AppAttestAssertionEnvelope.v1")
        #expect(proof.keyID == "test-key-id")
        #expect(proof.createdAt == digest.capturedAt)

        let encodedValue = try #require(proof.value)
        let proofValueData = try AppAttestBase64URL.decode(encodedValue, field: "proof.value")
        let proofValue = try JSONDecoder().decode(CaptureAssertionProofValue.self, from: proofValueData)
        let expectedBodyHash = Data(SHA256.hash(data: try digest.canonicalJSONData())).appAttestBase64URL

        #expect(proofValue.contentDigest == digest)
        #expect(proofValue.assertionEnvelope.credentialName == AppAttestRuntimeDefaults.photoCredentialName)
        #expect(proofValue.assertionEnvelope.keyId == "test-key-id")
        #expect(proofValue.assertionEnvelope.requestBinding.method == "POST")
        #expect(proofValue.assertionEnvelope.requestBinding.path == "/tapcam/captures/sample-capture/assertion")
        #expect(proofValue.assertionEnvelope.requestBinding.nonce == "sample-capture")
        #expect(proofValue.assertionEnvelope.requestBinding.bodySHA256 == expectedBodyHash)
        #expect(await client.operations() == [
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
    }

    @Test func unsignedCaptureManifestKeepsProofsEmptyWhenSignerIsMissing() async throws {
        let manifest = TAPDepthManifest(payload: Self.samplePayload(location: nil))
        let result = await EmbeddedPhotoPackager.manifestByApplyingCaptureAssertion(
            to: manifest,
            baseHEICData: Data(),
            depthData: nil,
            assertionSigner: nil
        )

        #expect(result.manifest.proofs.isEmpty)
        #expect(result.status == .unsigned(reason: "App Attest signer unavailable."))
    }

    @Test func pendingCaptureStorePersistsLedgerAcrossInstances() async throws {
        let rootURL = try Self.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = Self.samplePendingArtifact(photoData: Data("unsigned".utf8))

        let record = try await store.ingest(artifact)

        #expect(record.captureID == "sample-capture")
        #expect(record.status == .pending)
        #expect(try await store.unsignedHEICData(captureID: record.captureID) == Data("unsigned".utf8))

        let reloadedStore = TAPPendingCaptureStore(rootURL: rootURL)
        let reloadedRecords = try await reloadedStore.visiblePendingRecords()

        #expect(reloadedRecords.map(\.captureID) == ["sample-capture"])
        #expect(reloadedRecords.first?.status == .pending)
    }

    @Test func pendingCaptureStoreTracksSigningExportAndCleanup() async throws {
        let rootURL = try Self.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = Self.samplePendingArtifact(photoData: Data("unsigned".utf8))
        let record = try await store.ingest(artifact)

        _ = try await store.updateStatus(captureID: record.captureID, status: .waitingNetwork, failureReason: "offline", incrementsRetryCount: true)
        let waitingRecord = try await store.readRecord(captureID: record.captureID)
        #expect(waitingRecord.status == .waitingNetwork)
        #expect(waitingRecord.retryCount == 1)

        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: record.captureID)
        #expect(try await store.signedHEICData(captureID: record.captureID) == Data("signed".utf8))

        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: "asset-id")
        let exportedRecord = try await store.readRecord(captureID: record.captureID)
        #expect(exportedRecord.status == .exported)
        #expect(exportedRecord.assetLocalIdentifier == "asset-id")
        #expect(try await store.visiblePendingRecords().isEmpty)
    }

    @Test func pendingCaptureStoreRetriesInterruptedSigningRecords() async throws {
        let rootURL = try Self.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = Self.samplePendingArtifact(photoData: Data("unsigned".utf8))
        let record = try await store.ingest(artifact)

        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)

        let candidateIDs = try await store.processingCandidates().map(\.captureID)
        #expect(candidateIDs == [record.captureID])
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

    @Test func planeDetectorFindsAndFiltersHighConfidenceFlatRegions() throws {
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

        let planes = TAPPlaneEstimator.detectPlanes(depthMap: depthMap)

        #expect(!planes.isEmpty)
        #expect(planes.first?.confidence ?? 0 > 0.95)
        #expect(TAPPlaneEstimator.filteredPlanes(planes, minimumConfidence: 0.95).count == planes.count)
        #expect(TAPPlaneEstimator.filteredPlanes(planes, minimumConfidence: 1.01).isEmpty)
    }

    @Test func seedPlaneGrowthFindsLargeTiltedPlaneRegion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68
        )

        #expect(region.sampleCount > 700)
        #expect(region.confidence > 0.82)
        #expect(region.flatnessScore > 0.90)
        #expect(region.areaSquareMeters > 0)
        #expect(!region.pixelRuns.isEmpty)
        #expect(!region.gridCells.isEmpty)
        #expect(region.gridCells.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })
        #expect(!region.contourPoints.isEmpty)
    }

    @Test func seedPlaneGrowthFindsContinuousPlanesAcrossTiltAngles() throws {
        let width = 56
        let height = 44
        let cases: [(normal: SIMD3<Float>, seed: CGPoint)] = [
            (simd_normalize(SIMD3<Float>(-0.20, 0.00, 0.98)), CGPoint(x: 28, y: 22)),
            (simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70)), CGPoint(x: 22, y: 22)),
            (simd_normalize(SIMD3<Float>(0.74, -0.24, 0.63)), CGPoint(x: 34, y: 20)),
            (simd_normalize(SIMD3<Float>(-0.86, 0.18, 0.48)), CGPoint(x: 20, y: 24))
        ]

        for testCase in cases {
            let depthMap = Self.syntheticObliqueWallDepthMap(
                width: width,
                height: height,
                normal: testCase.normal
            )

            let region = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: testCase.seed,
                strictness: 0.68
            )

            #expect(region.sampleCount > Int(Double(width * height) * 0.70))
            #expect(region.confidence > 0.80)
            #expect(region.flatnessScore > 0.88)
            #expect(region.imageBounds.width > CGFloat(width) * 0.65)
            #expect(region.imageBounds.height > CGFloat(height) * 0.65)
        }
    }

    @Test func seedPlaneGrowthKeepsNoisyObliqueWallConnected() throws {
        let depthMap = Self.syntheticNoisyObliqueWallDepthMap(width: 52, height: 42)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 24, y: 21),
            strictness: 0.55
        )

        #expect(region.sampleCount > 1_100)
        #expect(region.gridCells.count > 8)
        #expect(region.confidence > 0.62)
    }

    @Test func seedPlaneGrowthDoesNotLeakAcrossObliqueWallBoundary() throws {
        let depthMap = Self.syntheticSplitPlaneDepthMap(width: 48, height: 40)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 14, y: 20),
            strictness: 0.62
        )

        #expect(region.sampleCount > 650)
        #expect(region.imageBounds.maxX < 30)
    }

    @Test func seedPlaneGrowthShrinksOnCurvedDepthWhenStrictnessIncreases() throws {
        let depthMap = Self.syntheticCurvedDepthMap(width: 36, height: 36)

        let loose = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 18, y: 18),
            strictness: 0.35
        )
        let strict = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 18, y: 18),
            strictness: 0.95
        )

        #expect(strict.sampleCount <= loose.sampleCount)
        #expect(strict.flatnessScore <= loose.flatnessScore || strict.sampleCount < loose.sampleCount)
    }

    @Test func seedPlaneGrowthRejectsInvalidSeed() throws {
        var samples = Array(repeating: Float(1.4), count: 16 * 16)
        samples[8 + 8 * 16] = 0
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: samples,
            calibration: Self.calibration(width: 16, height: 16)
        )

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 8, y: 8),
                strictness: 0.68
            )
            #expect(Bool(false), "Expected invalid seed to throw.")
        } catch TAPPlaneGrowthError.invalidSeed {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func seedPlaneGrowthReportsMissingCameraCalibration() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: Float(1.4), count: 16 * 16),
            calibration: nil
        )

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 8, y: 8),
                strictness: 0.68
            )
            #expect(Bool(false), "Expected missing calibration to throw.")
        } catch TAPPlaneGrowthError.cameraCalibrationMissing {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
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

    @Test func imageOrientationReaderAcceptsImageIONumericMetadataTypes() throws {
        let intProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: Int(CGImagePropertyOrientation.right.rawValue)
        ]
        let numberProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: NSNumber(value: CGImagePropertyOrientation.left.rawValue)
        ]

        #expect(TAPDepthMapReader.imageOrientation(from: intProperties) == .right)
        #expect(TAPDepthMapReader.imageOrientation(from: numberProperties) == .left)
    }

    @Test func heatmapVisualizationPublishesRangeLegendAndDistinctColors() throws {
        let depthMap = TAPMetricDepthMap(
            width: 3,
            height: 1,
            samples: [0, 1.0, 3.0],
            calibration: nil
        )

        let heatmap = try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        #expect(abs(heatmap.rangeMeters.lowerBound - 1.0) < 0.0001)
        #expect(abs(heatmap.rangeMeters.upperBound - 3.0) < 0.0001)
        #expect(heatmap.legendStops.count == 5)
        #expect(heatmap.legendStops.first?.label.contains("Near") == true)
        #expect(heatmap.legendStops.last?.label.contains("Far") == true)

        let near = TAPDepthHeatmapRenderer.viridisColor(normalized: 0)
        let middle = TAPDepthHeatmapRenderer.viridisColor(normalized: 0.5)
        let far = TAPDepthHeatmapRenderer.viridisColor(normalized: 1)
        #expect(near != middle)
        #expect(middle != far)
        #expect(near != far)

        let pixels = TAPDepthHeatmapRenderer.heatmapPixels(for: depthMap, rangeMeters: heatmap.rangeMeters)
        #expect(pixels[3] == 0)
        #expect(pixels[7] == 255)
    }

    @Test func regionHeatmapUsesSelectedSamplesForRangeAndMasksOutsideRegion() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 1,
            samples: [1.0, 2.0, 8.0, 9.0],
            calibration: nil
        )

        let globalHeatmap = try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        let regionHeatmap = try TAPDepthHeatmapRenderer.heatmap(
            for: depthMap,
            region: CGRect(x: 2, y: 0, width: 2, height: 1)
        )
        let regionPixels = TAPDepthHeatmapRenderer.heatmapPixels(
            for: depthMap,
            rangeMeters: regionHeatmap.rangeMeters,
            visibleRegion: CGRect(x: 2, y: 0, width: 2, height: 1)
        )

        #expect(globalHeatmap.rangeScope == .global)
        #expect(regionHeatmap.rangeScope == .region)
        #expect(abs(globalHeatmap.rangeMeters.lowerBound - 1.0) < 0.0001)
        #expect(abs(globalHeatmap.rangeMeters.upperBound - 9.0) < 0.0001)
        #expect(abs(regionHeatmap.rangeMeters.lowerBound - 8.0) < 0.0001)
        #expect(abs(regionHeatmap.rangeMeters.upperBound - 9.0) < 0.0001)
        #expect(regionHeatmap.legendStops.count == 5)
        #expect(regionPixels[3] == 0)
        #expect(regionPixels[7] == 0)
        #expect(regionPixels[11] == 255)
        #expect(regionPixels[15] == 255)
    }

    @Test func regionHeatmapRejectsInvalidOnlySelection() throws {
        let depthMap = TAPMetricDepthMap(
            width: 3,
            height: 1,
            samples: [0, .nan, 2.0],
            calibration: nil
        )

        do {
            _ = try TAPDepthHeatmapRenderer.heatmap(
                for: depthMap,
                region: CGRect(x: 0, y: 0, width: 2, height: 1)
            )
            #expect(Bool(false), "Expected invalid-only region to throw.")
        } catch TAPDepthAnalysisError.noValidDepthSamples {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func maskOverlayUsesTransparencyAndBoundaryColorInsteadOfPureWhite() throws {
        let fullValid = TAPMetricDepthMap(
            width: 3,
            height: 3,
            samples: Array(repeating: 1.0, count: 9),
            calibration: nil
        )

        let pixels = TAPDepthMaskRenderer.overlayPixels(for: fullValid)
        let centerOffset = (1 + 1 * fullValid.width) * 4
        let cornerOffset = 0
        #expect(pixels[centerOffset + 3] == TAPDepthMaskRenderer.validFillColor.alpha)
        #expect(pixels[cornerOffset + 3] == TAPDepthMaskRenderer.boundaryColor.alpha)
        #expect(Array(pixels[centerOffset..<(centerOffset + 3)]) != [255, 255, 255])

        let mixed = TAPMetricDepthMap(
            width: 1,
            height: 2,
            samples: [1.0, 0],
            calibration: nil
        )
        let mixedPixels = TAPDepthMaskRenderer.overlayPixels(for: mixed)
        #expect(mixedPixels[3] == TAPDepthMaskRenderer.boundaryColor.alpha)
        #expect(mixedPixels[7] == 0)

        let mask = try TAPDepthMaskRenderer.validMask(for: mixed)
        #expect(mask.validSampleCount == 1)
        #expect(mask.totalSampleCount == 2)
        #expect(mask.validRatio == 0.5)
        #expect(mask.legendStops.map(\.label) == ["Valid depth", "Valid/invalid edge"])
    }

    @Test func analysisViewModesAllPublishUserFacingExplanations() throws {
        for viewMode in DepthAnalysisViewMode.allCases {
            #expect(!viewMode.shortExplanation.isEmpty)
            #expect(!viewMode.detailedExplanation.isEmpty)
            #expect(!viewMode.legendDescription.isEmpty)
        }
    }

    @Test func analysisDepthAndMaskViewModeButtonsAreDebugOnly() throws {
        #expect(DepthAnalysisViewMode.heatmap.isDebugOnlyAnalysisButton)
        #expect(DepthAnalysisViewMode.mask.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.rgb.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.planes.isDebugOnlyAnalysisButton)
        #expect(!DepthAnalysisViewMode.pointCloud.isDebugOnlyAnalysisButton)
    }

    @Test func analyzerHelpPreferenceDefaultsToEnabled() throws {
        #expect(DepthAnalyzerPreferences.defaultShowsAnalysisHelp)
        #expect(!DepthAnalyzerPreferences.showsAnalysisHelpKey.isEmpty)
    }

    @Test func appAppearanceIsLockedToDarkMode() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String == "Dark")
    }

    @Test func shutterHapticsPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterHapticsEnabled)
        #expect(!CameraFeedbackPreferences.shutterHapticsEnabledKey.isEmpty)
    }

    @Test func shutterSoundPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterSoundEnabled)
        #expect(!CameraFeedbackPreferences.shutterSoundEnabledKey.isEmpty)
    }

    @Test func photoSettingsSuppressShutterSoundOnlyWhenRequestedAndSupported() throws {
        let photoOutput = AVCapturePhotoOutput()
        let defaultSettings = SingleCamPhotoSettingsFactory.make(photoOutput: photoOutput)
        let quietSettings = SingleCamPhotoSettingsFactory.make(
            photoOutput: photoOutput,
            suppressesShutterSound: true
        )

        #expect(!defaultSettings.isShutterSoundSuppressionEnabled)
        #expect(quietSettings.isShutterSoundSuppressionEnabled == photoOutput.isShutterSoundSuppressionSupported)
    }

    @Test func analysisInteractionStateSeparatesDrawingFromRegionInspection() throws {
        #expect(!AnalysisInteractionState.idle.showsRegionInspector)
        #expect(!AnalysisInteractionState.drawingSelection.showsRegionInspector)
        #expect(AnalysisInteractionState.regionSelected.showsRegionInspector)
    }

    @Test func analysisPanelDestinationSelectsInspectorsOnly() throws {
        #expect(AnalysisPanelDestination.inspector(.region).selectedInspector == .region)
        #expect(AnalysisPanelDestination.inspector(.measurements).selectedInspector == .measurements)
    }

    @Test @MainActor func depthAnalysisViewModelBuildsRegionProductsOnlyAfterExplicitSelection() throws {
        let viewModel = DepthAnalysisViewModel()
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 4,
            samples: (1...16).map(Float.init),
            calibration: nil
        )
        viewModel.input = try Self.analysisInput(depthMap: depthMap)

        #expect(viewModel.selectionRect == nil)
        #expect(viewModel.interactionState == .idle)
        #expect(viewModel.regionStats == nil)
        #expect(viewModel.regionHeatmap == nil)

        let explicitRegion = CGRect(x: 1, y: 1, width: 2, height: 2)
        viewModel.finishSelection(explicitRegion)

        #expect(viewModel.selectionRect == explicitRegion)
        #expect(viewModel.interactionState == .regionSelected)
        #expect(viewModel.regionStats?.validSampleCount == 4)
        #expect(viewModel.regionStats?.totalSampleCount == 4)
        #expect(viewModel.regionStats?.minimumDepthMeters == 6)
        #expect(viewModel.regionStats?.maximumDepthMeters == 11)
        #expect(viewModel.regionHeatmap?.rangeScope == .region)
    }

    @Test @MainActor func depthAnalysisViewModelClearSelectionRemovesDerivedRegionProducts() throws {
        let viewModel = DepthAnalysisViewModel()
        viewModel.selectionRect = CGRect(x: 1, y: 1, width: 4, height: 4)
        viewModel.interactionState = .regionSelected
        viewModel.regionStats = TAPDepthRegionStats(
            validSampleCount: 3,
            totalSampleCount: 4,
            minimumDepthMeters: 1,
            maximumDepthMeters: 2,
            medianDepthMeters: 1.5,
            validRatio: 0.75
        )
        viewModel.planeEstimate = TAPPlaneEstimate(
            normal: SIMD3<Float>(0, 0, 1),
            centroid: SIMD3<Float>(0, 0, 1),
            averageResidualMeters: 0.01,
            inlierRatio: 0.9,
            depthRangeMeters: 1...2,
            imageBounds: CGRect(x: 1, y: 1, width: 4, height: 4)
        )
        viewModel.planeSeedPoint = CGPoint(x: 3, y: 3)
        viewModel.selectedPlaneRegion = TAPPlaneRegion(
            seedPixel: CGPoint(x: 3, y: 3),
            estimate: viewModel.planeEstimate!,
            pixelRuns: [TAPPlanePixelRun(y: 3, xStart: 3, xEndExclusive: 5)],
            gridCells: [
                TAPPlaneGridCell(
                    row: 0,
                    column: 0,
                    imageBounds: CGRect(x: 3, y: 3, width: 2, height: 1),
                    coverage: 1,
                    averageResidualMeters: 0.01,
                    confidence: 0.8,
                    sampleCount: 2
                )
            ],
            contourPoints: [CGPoint(x: 3, y: 3)],
            imageBounds: CGRect(x: 3, y: 3, width: 2, height: 1),
            confidence: 0.8,
            flatnessScore: 0.9,
            sampleCount: 2,
            areaSquareMeters: 0.01
        )
        viewModel.planeRegionErrorMessage = "stale plane"
        viewModel.regionHeatmapErrorMessage = "stale"

        viewModel.clearSelection()

        #expect(viewModel.selectionRect == nil)
        #expect(viewModel.interactionState == .idle)
        #expect(viewModel.regionStats == nil)
        #expect(viewModel.planeEstimate == nil)
        #expect(viewModel.regionHeatmap == nil)
        #expect(viewModel.regionHeatmapErrorMessage == nil)
        #expect(viewModel.planeSeedPoint == nil)
        #expect(viewModel.selectedPlaneRegion == nil)
        #expect(viewModel.planeRegionErrorMessage == nil)
    }

    @Test func analysisViewModesAndInspectorsExposeLabelsAndIcons() throws {
        for viewMode in DepthAnalysisViewMode.allCases {
            #expect(!viewMode.title.isEmpty)
            #expect(!viewMode.systemImage.isEmpty)
        }

        for inspector in AnalysisInspector.allCases {
            #expect(!inspector.title.isEmpty)
            #expect(!inspector.systemImage.isEmpty)
        }
    }

    @Test func analyzerAuthorizationStatusTextIsPassiveAndDeterministic() throws {
        #expect(DepthAnalyzerAuthorizationStatusText.camera(.authorized) == "Authorized")
        #expect(DepthAnalyzerAuthorizationStatusText.camera(.notDetermined) == "Not requested")
        #expect(DepthAnalyzerAuthorizationStatusText.photos(.limited) == "Limited")
        #expect(DepthAnalyzerAuthorizationStatusText.photos(.denied) == "Denied")
        #expect(DepthAnalyzerAuthorizationStatusText.location(.authorizedWhenInUse) == "While using app")
        #expect(DepthAnalyzerAuthorizationStatusText.location(.restricted) == "Restricted")
    }

    private static func syntheticPlaneDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.18, 0.08, 1.0))
        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: depthSamples(width: width, height: height, normal: normal, planeD: -1.55, calibration: calibration),
            calibration: calibration
        )
    }

    private static func analysisInput(depthMap: TAPMetricDepthMap) throws -> TAPDepthAnalysisInput {
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

    private static func syntheticCurvedDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.10, 0.04, 1.0))
        var samples = depthSamples(width: width, height: height, normal: normal, planeD: -1.45, calibration: calibration)
        let centerX = Float(width - 1) / 2
        let centerY = Float(height - 1) / 2

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                samples[x + y * width] += (dx * dx + dy * dy) * 0.00022
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func syntheticObliqueWallDepthMap(
        width: Int,
        height: Int,
        normal: SIMD3<Float> = simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70))
    ) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: depthSamples(width: width, height: height, normal: normal, planeD: -1.55, calibration: calibration),
            calibration: calibration
        )
    }

    private static func syntheticNoisyObliqueWallDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.70, 0.03, 0.71))
        var samples = depthSamples(width: width, height: height, normal: normal, planeD: -1.60, calibration: calibration)

        for y in 0..<height {
            for x in 0..<width {
                let index = x + y * width
                if (x + y * 3).isMultiple(of: 23) {
                    samples[index] = 0
                } else {
                    let deterministicNoise = Float(((x * 17 + y * 29) % 11) - 5) * 0.0012
                    samples[index] += deterministicNoise
                }
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func syntheticSplitPlaneDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let leftNormal = simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70))
        let rightNormal = simd_normalize(SIMD3<Float>(0.18, -0.04, 1.0))
        let left = depthSamples(width: width, height: height, normal: leftNormal, planeD: -1.52, calibration: calibration)
        let right = depthSamples(width: width, height: height, normal: rightNormal, planeD: -2.25, calibration: calibration)
        var samples = left

        for y in 0..<height {
            for x in width / 2..<width {
                samples[x + y * width] = right[x + y * width]
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func depthSamples(
        width: Int,
        height: Int,
        normal: SIMD3<Float>,
        planeD: Float,
        calibration: TAPDepthManifest.CameraCalibration
    ) -> [Float] {
        let intrinsics = TAPCameraIntrinsics(calibration: calibration, depthWidth: width, depthHeight: height)!
        var samples: [Float] = []
        samples.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let ray = SIMD3<Float>(
                    (Float(x) - intrinsics.cx) / intrinsics.fx,
                    (Float(y) - intrinsics.cy) / intrinsics.fy,
                    1
                )
                let denominator = simd_dot(normal, ray)
                samples.append(-planeD / denominator)
            }
        }

        return samples
    }

    private static func calibration(width: Int, height: Int) -> TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: Double(width),
            intrinsicMatrixReferenceHeight: Double(height),
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: Double(width) / 2,
            lensDistortionCenterY: Double(height) / 2,
            intrinsicMatrix: [140, 0, 0, 0, 140, 0, Float(width) / 2, Float(height) / 2, 1],
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        )
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPCamDemoTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func samplePendingArtifact(photoData: Data) -> PackagedCaptureArtifact {
        PackagedCaptureArtifact(
            packageID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            strategy: .embeddedPhoto,
            photoData: photoData,
            manifest: TAPDepthManifest(payload: samplePayload(location: sampleLocation)),
            signatureStatus: .unsigned(reason: "test"),
            packagingMetrics: CapturePackagingMetrics(),
            capturedAt: Date(timeIntervalSince1970: 0),
            location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                altitude: 12,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        )
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

    private static func sampleContentDigest() -> CaptureContentDigest {
        CaptureContentDigest(
            captureID: "sample-capture",
            capturedAt: "2026-04-25T00:00:00.123Z",
            rgb: CaptureContentDigest.Component(
                mediaType: "image/heic-primary-rgba8",
                width: 2,
                height: 2,
                value: "rgb-digest"
            ),
            depth: CaptureContentDigest.Component(
                mediaType: "application/vnd.tapnap.depth-float32",
                width: 2,
                height: 2,
                value: "depth-digest"
            ),
            metadata: CaptureContentDigest.Component(
                mediaType: "application/vnd.tapnap.depth-manifest.payload+json;version=1",
                width: nil,
                height: nil,
                value: "metadata-digest"
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

private enum CaptureAssertionTestError: Error {
    case unused
}

private actor SucceedingAssertionAppAttestClient: AppAttestClient {
    private var operationLog: [String] = []

    func operations() -> [String] {
        operationLog
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw CaptureAssertionTestError.unused
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        operationLog.append("prepareIfNeeded:\(credentialName)")
        return AppAttestCredential(
            credentialName: credentialName,
            keyId: "test-key-id",
            credentialId: nil,
            status: .ready,
            environment: .development,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        operationLog.append("generateAssertion:\(credentialName)")
        let bodySHA256 = Data(SHA256.hash(data: request.body ?? Data())).appAttestBase64URL
        let challengeSHA256 = Data(SHA256.hash(data: Data("test-challenge".utf8))).appAttestBase64URL
        let bindingJSON = """
        {
          "bodySHA256": "\(bodySHA256)",
          "challengeSHA256": "\(challengeSHA256)",
          "method": "\(request.method.uppercased())",
          "nonce": "\(request.nonce ?? "")",
          "path": "\(request.path)",
          "query": []
        }
        """
        let requestBinding = try JSONDecoder().decode(
            AppAttestRequestBinding.self,
            from: Data(bindingJSON.utf8)
        )

        return AppAttestAssertionEnvelope(
            credentialName: credentialName,
            keyId: "test-key-id",
            challengeId: "test-challenge",
            assertionObject: Data([0xA1, 0x01]),
            requestBinding: requestBinding
        )
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw CaptureAssertionTestError.unused
    }

    func reset(credentialName: String) async throws {
        throw CaptureAssertionTestError.unused
    }
}
