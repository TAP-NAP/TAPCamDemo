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
        let signedData = try TAPDepthPhotoFileWriter.injectingManifest(
            try TAPCaptureProvenanceTestFixtures.sampleSignedManifest(),
            into: TAPCamDemoTestFixtures.sampleThumbnailSourceData()
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedData, expectedContainer: .heic),
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
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: TAPCamDemoTestFixtures.sampleThumbnailSourceData(), expectedContainer: .heic),
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject raw JPEG data.")
        } catch TAPDepthCaptureError.invalidHEICContainerType(let actual) {
            #expect(actual == "public.jpeg")
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func signedExportValidatorRejectsMissingProofAfterContainerCheck() throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(location: nil))
        let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
            manifest: manifest
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
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
            manifest: manifest
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
                expectedCaptureID: "sample-capture"
            )
            Issue.record("Expected final export validation to reject invalid proof envelope.")
        } catch TAPDepthCaptureError.pendingCaptureProofInvalid(let reason) {
            #expect(reason.contains("proof type"))
        } catch {
            Issue.record("Unexpected final export validation error: \(error)")
        }
    }

    @Test func signedExportValidatorRejectsManifestMismatchAfterContainerCheck() throws {
        let manifest = try TAPCaptureProvenanceTestFixtures.sampleSignedManifest(id: "embedded-capture")
        let signedHEICData = try TAPCaptureProvenanceTestFixtures.sampleSignedHEICData(
            manifest: manifest
        )

        do {
            _ = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                .init(data: signedHEICData, expectedContainer: .heic),
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

    @Test func signingAndExportPreserveCaptureDeclarationsWithoutRequiringDepth() async throws {
        let capture = TAPCamDemoTestFixtures.sampleManifestCapture(
            requestedCodec: AVVideoCodecType.jpeg.rawValue,
            depthDataDeliveryEnabled: false,
            embedsDepthDataInPhoto: false,
            depthDataFiltered: false,
            depthAvailability: .unavailable,
            photoQualityPrioritization: "balanced"
        )
        // The declaration may disagree with the file and with other metadata.
        // The signature covers those recorded bytes without certifying depth.
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(
            location: nil, capture: capture, depthAvailability: .available
        ))
        let unsignedData = try TAPDepthPhotoFileWriter.injectingManifest(
            manifest, into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        )
        let signer = SuccessfulCaptureAssertionSigner()
        let writer = TAPCaptureProvenanceWriter()
        let signedPhoto = try await writer.signedPhotoData(
            from: unsignedData, expectedCaptureID: "sample-capture",
            expectedContainer: .heic, assertionSigner: signer
        )
        let validated = try writer.validateSignedExportPhoto(
            .init(data: signedPhoto.data, expectedContainer: .heic),
            expectedCaptureID: "sample-capture"
        )
        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validated.data)).payload.capture == capture)
        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validated.data)).payload.depth.availability == .available)
        #expect(try TAPDepthPhotoFileReader.depthData(from: validated.data) == nil)
        #expect(await signer.lastDigest()?.depthResource.presence == "required")
    }

    @Test func noDepthPhotoIgnoresOuterProofTimeButRejectsBoundTimeMutation() async throws {
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
            expectedContainer: .heic,
            assertionSigner: signer
        )
        let validated = try writer.validateSignedExportPhoto(
            .init(data: signedPhoto.data, expectedContainer: .heic),
            expectedCaptureID: "sample-capture"
        )
        for outerTimestamp in ["unbound-time", nil, 7] as [Any?] {
            let changed = try Self.rewritingOuterProofTimestamp(
                signedPhoto.data, value: outerTimestamp
            )
            _ = try writer.validateSignedExportPhoto(
                .init(data: changed, expectedContainer: .heic), expectedCaptureID: "sample-capture"
            )
        }
        var changedManifestTime = signedPhoto.data
        let timeRange = try #require(changedManifestTime.range(of: Data(payload.capturedAt.utf8)))
        changedManifestTime[timeRange.lowerBound] = 0x33
        #expect(throws: TAPDepthCaptureError.self) {
            try writer.validateSignedExportPhoto(
                .init(data: changedManifestTime, expectedContainer: .heic), expectedCaptureID: "sample-capture"
            )
        }
        let digest = try #require(await signer.lastDigest())

        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validated.data)).payload.capture.depthAvailability == .unavailable)
        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validated.data)).payload.depth.availability == .unavailable)
        #expect(digest.depthResource.presence == "unavailable")
        #expect(digest.depthResource.binding == "not-present")
    }

    @Test func livePhotoValidatorsIgnoreOuterProofTimeAndAllowPrimaryWithoutMovie() async throws {
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
            expectedContainer: .heic,
            assertionSigner: signer,
            pairedVideoURL: movieURL
        )
        let validatedPrimary = try writer.validateSignedExportLivePhotoPrimaryPhoto(
            signedPhoto.data,
            expectedCaptureID: "sample-capture"
        )

        for outerTimestamp in ["unbound-time", nil] as [String?] {
            let changed = try Self.rewritingOuterProofTimestamp(
                signedPhoto.data, value: outerTimestamp
            )
            _ = try writer.validateSignedExportLivePhotoPrimaryPhoto(
                changed, expectedCaptureID: "sample-capture"
            )
            _ = try writer.validateSignedExportLivePhoto(
                .init(data: changed, expectedContainer: .heic), pairedVideoURL: movieURL,
                expectedCaptureID: "sample-capture"
            )
        }
        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validatedPrimary.data)).schema == .livePhoto)
        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validatedPrimary.data)).payload.livePhoto == livePhoto)
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
            expectedContainer: .jpeg,
            assertionSigner: signer
        )
        let validated = try writer.validateSignedExportPhoto(
            .init(data: signedPhoto.data, expectedContainer: .jpeg),
            expectedCaptureID: "sample-capture"
        )
        let signedDigest = try #require(await signer.lastDigest())
        let roundTrippedMetadataHash = try CaptureContentDigest.MetadataHash(
            payload: (try TAPDepthPhotoFileReader.decodedManifest(from: validated.data)).payload
        )

        #expect(signedPhoto.fileContainer == .jpeg)
        #expect(validated.fileContainer == .jpeg)
        #expect((try TAPDepthPhotoFileReader.decodedManifest(from: validated.data)).payload.location == location)
        #expect(signedDigest.assetHash.fileContainer == CapturePhotoFileContainer.jpeg.rawValue)
        #expect(signedDigest.metadataHash == roundTrippedMetadataHash)
    }
    private static func rewritingOuterProofTimestamp(_ photoData: Data, value: Any?) throws -> Data {
        let envelope = try TAPProofSlot.proofEnvelopeData(from: photoData, fileContainer: .heic)
        var proof = try #require(JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        proof["createdAt"] = value
        return try TAPProofSlot.writeProofEnvelope(
            JSONSerialization.data(withJSONObject: proof), into: photoData, fileContainer: .heic
        )
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
