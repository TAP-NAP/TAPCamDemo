//
//  AppAttestCaptureAssertionSigner.swift
//  TAPCamDemo
//

import AppAttestKit
import Foundation

nonisolated protocol CaptureAssertionSigning: Sendable {
    func sign(
        contentDigest: CaptureContentDigest,
        capturedAt: Date
    ) async throws -> CaptureAssertionProof
}

nonisolated struct CaptureAssertionProof: Equatable, Sendable {
    let proof: TAPDepthManifest.Proof
    let keyID: String
}

nonisolated struct AppAttestCaptureAssertionSigner: CaptureAssertionSigning {
    private let client: any AppAttestClient

    init(client: any AppAttestClient) {
        self.client = client
    }

    func sign(
        contentDigest: CaptureContentDigest,
        capturedAt: Date
    ) async throws -> CaptureAssertionProof {
        let body = try contentDigest.canonicalJSONData()
        let request = AppAttestProtectedRequest(
            method: "POST",
            path: "/tapcam/captures/\(contentDigest.captureID)/assertion",
            body: body,
            nonce: contentDigest.captureID
        )

        _ = try await client.prepareIfNeeded(
            credentialName: AppAttestRuntimeDefaults.photoCredentialName
        )
        let envelope = try await client.generateAssertion(
            credentialName: AppAttestRuntimeDefaults.photoCredentialName,
            request: request
        )

        let proofValue = CaptureAssertionProofValue(
            contentDigest: contentDigest,
            assertionEnvelope: StoredAppAttestAssertionEnvelope(envelope)
        )
        let proofData = try proofValue.canonicalJSONData()
        let proof = TAPDepthManifest.Proof(
            type: "appAttestAssertion",
            algorithm: "AppAttestKit.AppAttestAssertionEnvelope.v1",
            keyID: envelope.keyId,
            createdAt: TAPDateFormatting.iso8601.string(from: capturedAt),
            value: proofData.appAttestBase64URL
        )

        return CaptureAssertionProof(proof: proof, keyID: envelope.keyId)
    }
}

nonisolated struct CaptureAssertionProofValue: Codable, Equatable, Sendable {
    let contentDigest: CaptureContentDigest
    let assertionEnvelope: StoredAppAttestAssertionEnvelope

    func canonicalJSONData() throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(self)
    }
}

nonisolated struct StoredAppAttestAssertionEnvelope: Codable, Equatable, Sendable {
    let credentialName: String
    let keyId: String
    let challengeId: String
    let assertionObject: String
    let requestBinding: AppAttestRequestBinding

    init(
        credentialName: String,
        keyId: String,
        challengeId: String,
        assertionObject: String,
        requestBinding: AppAttestRequestBinding
    ) {
        self.credentialName = credentialName
        self.keyId = keyId
        self.challengeId = challengeId
        self.assertionObject = assertionObject
        self.requestBinding = requestBinding
    }

    init(_ envelope: AppAttestAssertionEnvelope) {
        self.credentialName = envelope.credentialName
        self.keyId = envelope.keyId
        self.challengeId = envelope.challengeId
        self.assertionObject = envelope.assertionObject.appAttestBase64URL
        self.requestBinding = envelope.requestBinding
    }
}
