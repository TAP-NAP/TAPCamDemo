//
//  TAPSignedExportValidatorTests.swift
//  TAPCamDemoTests
//

import AppAttestKit
import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPSignedExportValidatorTests {
    @Test func signedExportValidatorRejectsWrongContainerBeforePhotosSave() throws {
        let signedData = try TAPDepthPhotoFileWriter.injectingManifest(
            try TAPCaptureProvenanceTestFixtures.sampleSignedManifest(),
            into: TAPCamDemoTestFixtures.sampleThumbnailSourceData()
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedData, expectedContainer: .heic),
                expectedCaptureID: "sample-capture",
                expectedProfile: .releasePhotoDepthHEIC
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
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: TAPCamDemoTestFixtures.sampleThumbnailSourceData(), expectedContainer: .heic),
                expectedCaptureID: "sample-capture",
                expectedProfile: .releasePhotoDepthHEIC
            )
            Issue.record("Expected final export validation to reject raw JPEG data.")
        } catch TAPDepthCaptureError.invalidHEICContainerType(let actual) {
            #expect(actual == "public.jpeg")
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
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
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
                expectedCaptureID: "sample-capture",
                expectedProfile: .releasePhotoDepthHEIC
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
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
                expectedCaptureID: "sample-capture",
                expectedProfile: .releasePhotoDepthHEIC
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
            let signedHEICData = try TAPDepthPhotoFileWriter.injectingManifest(
                manifestWithMultipleProofs,
                into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
            )

            do {
                _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                    .init(data: signedHEICData, expectedContainer: .heic),
                    expectedCaptureID: "sample-capture",
                    expectedProfile: .releasePhotoDepthHEIC
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
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
                expectedCaptureID: "record-capture",
                expectedProfile: .releasePhotoDepthHEIC
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
                _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                    .init(data: signedHEICData, expectedContainer: .heic),
                    expectedCaptureID: "sample-capture",
                    expectedProfile: .releasePhotoDepthHEIC
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
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
                expectedCaptureID: "sample-capture",
                expectedProfile: .releasePhotoDepthHEIC
            )
            Issue.record("Expected final export validation to reject missing auxiliary depth.")
        } catch TAPDepthCaptureError.missingDepthData {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func pendingSigningAndExportValidationAllowNoDepthCapture() async throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: nil,
            capture: TAPCamDemoTestFixtures.sampleManifestCapture(depthAvailability: .unavailable),
            depthAvailability: .unavailable
        )
        let unsignedData = try TAPDepthPhotoFileWriter.injectingManifest(
            TAPDepthManifest(payload: payload),
            into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        )
        let signer = SuccessfulCaptureAssertionSigner()
        let writer = TAPCaptureProvenanceWriter()

        let signedPhoto = try await writer.signedPhotoData(
            from: unsignedData,
            expectedCaptureID: "sample-capture",
            expectedProfile: .releasePhotoDepthHEIC,
            assertionSigner: signer
        )
        let validated = try writer.validateSignedExportPhoto(
            .init(data: signedPhoto.data, expectedContainer: .heic),
            expectedCaptureID: "sample-capture",
            expectedProfile: .releasePhotoDepthHEIC
        )
        let digest = try #require(await signer.lastDigest())

        #expect(validated.manifest.payload.capture.depthAvailability == .unavailable)
        #expect(validated.manifest.payload.depth.availability == .unavailable)
        #expect(digest.depthResource.presence == "unavailable")
        #expect(digest.depthResource.binding == "not-present")
    }

    @Test func livePhotoPrimaryValidatorAcceptsSignedPrimaryWhenMovieIsUnavailable() async throws {
        let livePhoto = TAPDepthManifest.LivePhoto(
            presence: "paired-video",
            pairedVideoFilename: "paired-video.mov",
            durationSeconds: 1.5,
            photoDisplayTimeSeconds: 0.75,
            width: 1_920,
            height: 1_440,
            videoCodec: "hvc1",
            audio: "not-captured"
        )
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: nil,
            capture: TAPCamDemoTestFixtures.sampleManifestCapture(depthAvailability: .unavailable),
            depthAvailability: .unavailable,
            livePhoto: livePhoto
        )
        let unsignedData = try TAPDepthPhotoFileWriter.injectingManifest(
            TAPDepthManifest(payload: payload, schema: .livePhoto),
            into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        )
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let movieURL = directoryURL.appendingPathComponent("paired-video.mov")
        try Data("paired-live-photo-video".utf8).write(to: movieURL)
        let signer = SuccessfulCaptureAssertionSigner()
        let writer = TAPCaptureProvenanceWriter()

        let signedPhoto = try await writer.signedPhotoData(
            from: unsignedData,
            expectedCaptureID: "sample-capture",
            expectedProfile: .releasePhotoDepthHEIC,
            assertionSigner: signer,
            pairedVideoURL: movieURL
        )
        let validatedPrimary = try writer.validateSignedExportLivePhotoPrimaryPhoto(
            signedPhoto.data,
            expectedCaptureID: "sample-capture",
            expectedProfile: .releasePhotoDepthHEIC
        )

        #expect(validatedPrimary.manifest.schema == .livePhoto)
        #expect(validatedPrimary.manifest.payload.livePhoto == livePhoto)
    }

    @Test func jpegSigningAndExportValidationPreserveHighPrecisionLocationMetadataHash() async throws {
        let location = TAPCamDemoTestFixtures.sampleHighPrecisionLocation
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: location,
            capture: TAPCamDemoTestFixtures.sampleManifestCapture(
                requestedCodec: AVVideoCodecType.jpeg.rawValue,
                depthAvailability: .unavailable
            ),
            depthAvailability: .unavailable
        )
        let unsignedData = try TAPDepthPhotoFileWriter.injectingManifest(
            TAPDepthManifest(payload: payload),
            into: TAPCamDemoTestFixtures.sampleThumbnailSourceData()
        )
        let signer = SuccessfulCaptureAssertionSigner()
        let writer = TAPCaptureProvenanceWriter()

        let signedPhoto = try await writer.signedPhotoData(
            from: unsignedData,
            expectedCaptureID: "sample-capture",
            expectedProfile: .releasePhotoDepthJPEG,
            assertionSigner: signer
        )
        let validated = try writer.validateSignedExportPhoto(
            .init(data: signedPhoto.data, expectedContainer: .jpeg),
            expectedCaptureID: "sample-capture",
            expectedProfile: .releasePhotoDepthJPEG
        )
        let signedDigest = try #require(await signer.lastDigest())
        let roundTrippedMetadataHash = try CaptureContentDigest.MetadataHash(
            payload: validated.manifest.payload
        )

        #expect(signedPhoto.fileContainer == .jpeg)
        #expect(validated.fileContainer == .jpeg)
        #expect(validated.manifest.payload.location == location)
        #expect(signedDigest.assetHash.fileContainer == CapturePhotoFileContainer.jpeg.rawValue)
        #expect(signedDigest.metadataHash == roundTrippedMetadataHash)
    }
}

private actor SuccessfulCaptureAssertionSigner: CaptureAssertionSigning {
    private var recordedDigest: CaptureContentDigest?

    func lastDigest() -> CaptureContentDigest? {
        recordedDigest
    }

    func sign(contentDigest: CaptureContentDigest) async throws -> CaptureAssertionProof {
        recordedDigest = contentDigest
        let proofValue = CaptureAssertionProofValue(
            contentDigest: contentDigest,
            keyId: "test-key-id",
            assertionObject: Data([0xA1, 0x01]).appAttestBase64URL,
            signingBinding: try CaptureSigningBinding(contentDigest: contentDigest)
        )
        let proofData = try proofValue.canonicalJSONData()
        let proof = TAPDepthManifest.Proof(
            type: "appAttestAssertion",
            algorithm: "TAPCam.AppAttestCaptureSignature.v1",
            keyID: "test-key-id",
            createdAt: contentDigest.capturedAt,
            value: proofData.appAttestBase64URL
        )
        return CaptureAssertionProof(proof: proof, keyID: "test-key-id")
    }
}
