//
//  TAPCaptureManifestEncodingTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureManifestEncodingTests {
    @Test func proofChangesDoNotAffectPayloadBytes() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(location: TAPCamDemoTestFixtures.sampleLocation)
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

    @Test func highPrecisionLocationMetadataHashSurvivesPayloadJSONRoundTrip() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: TAPCamDemoTestFixtures.sampleHighPrecisionLocation
        )
        let encodedPayload = try TAPDepthManifestEncoder.payloadDataExcludingProofs(payload)
        let encodedPayloadJSON = try #require(String(data: encodedPayload, encoding: .utf8))
        let metadataHash = try CaptureContentDigest.MetadataHash(payload: payload)

        let decodedPayload = try JSONDecoder().decode(
            TAPDepthManifest.Payload.self,
            from: encodedPayload
        )
        let reencodedPayload = try TAPDepthManifestEncoder.payloadDataExcludingProofs(decodedPayload)
        let roundTrippedMetadataHash = try CaptureContentDigest.MetadataHash(payload: decodedPayload)

        #expect(decodedPayload.location == TAPCamDemoTestFixtures.sampleHighPrecisionLocation)
        #expect(encodedPayloadJSON.contains(#""altitude":123.45678901234567"#))
        #expect(reencodedPayload == encodedPayload)
        #expect(roundTrippedMetadataHash == metadataHash)
    }
}
