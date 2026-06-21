//
//  TAPCaptureAssertionSignerTests.swift
//  TAPCamDemoTests
//

import AppAttestKit
import CryptoKit
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureAssertionSignerTests {
    @Test func appAttestCaptureAssertionSignerBuildsProofValue() async throws {
        let digest = TAPCaptureProvenanceTestFixtures.sampleContentDigest()
        let client = SucceedingAssertionAppAttestClient()
        let deviceService = RecordingCaptureAssertionDeviceService()
        let signer = AppAttestCaptureAssertionSigner(client: client, deviceService: deviceService)
        let credentialName = await MainActor.run { AppAttestRuntimeDefaults.photoCredentialName }
        let assertionProof = try await signer.sign(contentDigest: digest)

        let proof = assertionProof.proof
        #expect(assertionProof.keyID == "test-key-id")
        #expect(proof.type == "appAttestAssertion")
        #expect(proof.algorithm == "TAPCam.AppAttestCaptureSignature.v1")
        #expect(proof.keyID == "test-key-id")
        #expect(proof.createdAt == digest.capturedAt)

        let encodedValue = try #require(proof.value)
        let proofValueData = try AppAttestBase64URL.decode(encodedValue, field: "proof.value")
        let proofValue = try JSONDecoder().decode(CaptureAssertionProofValue.self, from: proofValueData)
        let proofValueJSON = try #require(String(data: proofValueData, encoding: .utf8))
        let expectedBodyHash = Data(SHA256.hash(data: try digest.canonicalJSONData())).appAttestBase64URL
        let expectedSigningBinding = CaptureSigningBinding(
            bodySHA256: expectedBodyHash,
            captureID: "sample-capture"
        )
        let signingBindingData = try expectedSigningBinding.canonicalJSONData()
        let signingBindingJSON = try #require(String(data: signingBindingData, encoding: .utf8))
        let expectedClientDataHash = Data(SHA256.hash(data: signingBindingData))

        #expect(proofValue.contentDigest == digest)
        #expect(proofValue.keyId == "test-key-id")
        #expect(proofValue.assertionObject == Data([0xA1, 0x01]).appAttestBase64URL)
        #expect(proofValue.signingBinding == expectedSigningBinding)
        #expect(
            signingBindingJSON == #"{"bodySHA256":"\#(expectedBodyHash)","captureID":"sample-capture","operation":"tapcam.capture.sign","schemaID":"urn:tapnap:tapcam:app-attest-capture-signing:v1"}"#
        )
        #expect(!proofValueJSON.contains("challengeId"))
        #expect(!proofValueJSON.contains("requestBinding"))
        #expect(!proofValueJSON.contains("challengeSHA256"))
        #expect(client.operations() == [
            "prepareIfNeeded:\(credentialName)"
        ])

        let assertionCalls = deviceService.generateAssertionCalls()
        #expect(assertionCalls == [
            CaptureAssertionDeviceServiceCall(
                keyId: "test-key-id",
                clientDataHash: expectedClientDataHash
            )
        ])
    }

    @Test func appAttestCaptureAssertionSignerStopsWhenPrepareIfNeededFails() async throws {
        let digest = TAPCaptureProvenanceTestFixtures.sampleContentDigest()
        let client = FailingPrepareIfNeededAppAttestClient()
        let deviceService = RecordingCaptureAssertionDeviceService()
        let signer = AppAttestCaptureAssertionSigner(client: client, deviceService: deviceService)
        let credentialName = await MainActor.run { AppAttestRuntimeDefaults.photoCredentialName }

        await #expect(throws: (any Error).self) {
            try await signer.sign(contentDigest: digest)
        }

        #expect(client.operations() == [
            "prepareIfNeeded:\(credentialName)"
        ])
        #expect(deviceService.generateAssertionCalls().isEmpty)
    }
}
