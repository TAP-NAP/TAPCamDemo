//
//  TAPCaptureManifestEncodingTests.swift
//  TAPCamDemoTests
//

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
}
