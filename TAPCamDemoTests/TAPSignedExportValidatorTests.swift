//
//  TAPSignedExportValidatorTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPSignedExportValidatorTests {
    @Test func signedExportValidatorRejectsWrongContainerBeforePhotosSave() throws {
        let signedData = try TAPDepthHEICWriter.injectingManifest(
            try TAPCaptureProvenanceTestFixtures.sampleSignedManifest(),
            into: TAPCamDemoTestFixtures.sampleThumbnailSourceData()
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                signedData,
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject JPEG-backed data.")
        } catch TAPDepthCaptureError.invalidHEICContainerType(let actual) {
            #expect(actual == "public.jpeg")
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func validatedTAPDepthPhotoRejectsRawContainerBeforePhotosWriterCanBeCalled() throws {
        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                TAPCamDemoTestFixtures.sampleThumbnailSourceData(),
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject raw JPEG data.")
        } catch TAPDepthCaptureError.invalidHEICContainerType(let actual) {
            #expect(actual == "public.jpeg")
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func signedExportValidatorCoversReleaseResourcePlanBeforePhotosSave() throws {
        let releasePlan = try CaptureOutputProfile.releasePhotoDepthHEIC
            .resolvedPhotoOutput(availablePhotoCodecTypes: [.hevc])
            .resourcePlan
        let requiredKinds = releasePlan.resources
            .filter(\.requiredForExport)
            .map(\.kind)
        let provenanceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift"
        )
        let validatorSource = try #require(TAPCamDemoTestSourceInspection.substring(
            in: provenanceSource,
            from: "func validateSignedExportPhoto",
            to: "private func validateManifestSchema"
        ))

        #expect(requiredKinds == [
            .primaryPhoto,
            .appleAuxiliaryDepth,
            .tapManifest,
            .appAttestCaptureProof
        ])
        #expect(validatorSource.contains("TAPDepthPhotoFileReader.validateContainer"))
        #expect(validatorSource.contains("decodedManifest"))
        #expect(validatorSource.contains("validateManifestSchema"))
        #expect(validatorSource.contains("validateManifestID"))
        #expect(validatorSource.contains("CaptureOutputManifestPolicy(profile: expectedProfile).validate"))
        #expect(validatorSource.contains("validateManifestCarriesNoProofBody"))
        #expect(validatorSource.contains("decodedCaptureProof"))
        #expect(validatorSource.contains("TAPDepthPhotoFileReader.depthData"))
        #expect(validatorSource.contains("CaptureContentDigest.make"))
        #expect(validatorSource.contains("validateCaptureProof"))
        #expect(validatorSource.contains("ValidatedTAPDepthPhoto"))
    }

    @Test func captureOutputManifestPolicyRejectsReleaseFactDrift() throws {
        let policy = CaptureOutputManifestPolicy.releasePhotoDepthHEIC
        let releaseCapture = TAPCamDemoTestFixtures.sampleManifestCapture()
        let driftedCapture = TAPCamDemoTestFixtures.sampleManifestCapture(
            requestedCodec: AVVideoCodecType.jpeg.rawValue,
            depthDataFiltered: false
        )

        #expect(policy.violations(in: releaseCapture).isEmpty)
        #expect(policy.violations(in: driftedCapture) == [
            .requestedCodec,
            .depthDataFiltered
        ])

        do {
            try policy.validate(driftedCapture)
            Issue.record("Expected manifest policy to reject Release output fact drift.")
        } catch TAPDepthCaptureError.invalidCaptureOutputProfile(let reason) {
            #expect(reason.contains("requestedCodec"))
            #expect(reason.contains("depthDataFiltered"))
        } catch {
            Issue.record("Unexpected manifest policy validation error: \(error)")
        }
    }

    @Test func signedExportValidatorRejectsMissingProofAfterContainerCheck() throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(location: nil))
        let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
            manifest: manifest,
            hasDepth: true
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                signedHEICData,
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject missing proof.")
        } catch TAPDepthCaptureError.pendingCaptureProofMissing {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func signedExportValidatorRejectsInvalidProofEnvelopeAfterContainerCheck() throws {
        let manifest = TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(location: nil),
            proofs: [
                TAPDepthManifest.Proof(
                    type: "notAppAttest",
                    algorithm: "TAPCam.AppAttestCaptureSignature.v1",
                    keyID: "test-key-id",
                    createdAt: "2026-04-25T00:00:00.000Z",
                    value: "test-proof"
                )
            ]
        )
        let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
            manifest: manifest,
            hasDepth: true
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                signedHEICData,
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject invalid proof envelope.")
        } catch TAPDepthCaptureError.pendingCaptureProofInvalid(let reason) {
            #expect(reason.contains("proof type"))
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func signedExportValidatorRejectsManifestProofBodiesBeforePhotosSave() throws {
        let signedManifest = try TAPCaptureProvenanceTestFixtures.sampleSignedManifest()
        let proof = try #require(signedManifest.proofs.first)
        let futureProof = TAPDepthManifest.Proof(
            type: "c2paPlaceholder",
            algorithm: "future.provenance.placeholder",
            keyID: "future-key",
            createdAt: proof.createdAt,
            value: "future-proof"
        )
        let proofSets = [
            [proof, futureProof],
            [futureProof, proof],
            [proof, proof]
        ]

        for proofSet in proofSets {
            let manifestWithMultipleProofs = TAPDepthManifest(
                payload: signedManifest.payload,
                proofs: proofSet
            )
            let signedHEICData = try TAPDepthHEICWriter.injectingManifest(
                manifestWithMultipleProofs,
                into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
            )

            do {
                _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                    signedHEICData,
                    expectedCaptureID: "sample-capture"
                )
                Issue.record("Expected final export validation to reject manifest proof bodies.")
            } catch TAPDepthCaptureError.pendingCaptureProofInvalid(let reason) {
                #expect(reason.contains("manifest proofs"))
            } catch {
                Issue.record("Unexpected final export validation error: \(error)")
            }
        }
    }

    @Test func signedExportValidatorRejectsManifestMismatchAfterContainerCheck() throws {
        let manifest = try TAPCaptureProvenanceTestFixtures.sampleSignedManifest(id: "embedded-capture")
        let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
            manifest: manifest,
            hasDepth: true
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                signedHEICData,
                expectedCaptureID: "record-capture"
            )
            Issue.record("Expected final export validation to reject manifest mismatch.")
        } catch TAPDepthCaptureError.pendingCaptureManifestIDMismatch(let expected, let actual) {
            #expect(expected == "record-capture")
            #expect(actual == "embedded-capture")
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func signedExportValidatorRejectsReleaseOutputPolicyDriftBeforePhotosSave() throws {
        let driftedCaptures: [(TAPDepthManifest.Capture, String)] = [
            (
                TAPCamDemoTestFixtures.sampleManifestCapture(requestedCodec: AVVideoCodecType.jpeg.rawValue),
                "requestedCodec"
            ),
            (
                TAPCamDemoTestFixtures.sampleManifestCapture(depthDataDeliveryEnabled: false),
                "depthDataDeliveryEnabled"
            ),
            (
                TAPCamDemoTestFixtures.sampleManifestCapture(embedsDepthDataInPhoto: false),
                "embedsDepthDataInPhoto"
            ),
            (
                TAPCamDemoTestFixtures.sampleManifestCapture(depthDataFiltered: false),
                "depthDataFiltered"
            ),
            (
                TAPCamDemoTestFixtures.sampleManifestCapture(photoQualityPrioritization: "balanced"),
                "photoQualityPrioritization"
            )
        ]

        for (capture, expectedReasonToken) in driftedCaptures {
            let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(
                location: nil,
                capture: capture
            ))
            let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
                manifest: manifest,
                hasDepth: true
            )

            do {
                _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                    signedHEICData,
                    expectedCaptureID: "sample-capture"
                )
                Issue.record("Expected final export validation to reject output policy drift.")
            } catch TAPDepthCaptureError.invalidCaptureOutputProfile(let reason) {
                #expect(reason.contains(expectedReasonToken))
            } catch {
                Issue.record("Unexpected final export validation error: \(error)")
            }
        }
    }

    @Test func signedExportValidatorRejectsMissingAuxiliaryDepthAfterContainerCheck() throws {
        let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
            manifest: try TAPCaptureProvenanceTestFixtures.sampleSignedManifest(),
            hasDepth: false
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                signedHEICData,
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject missing auxiliary depth.")
        } catch TAPDepthCaptureError.missingDepthData {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }
}
