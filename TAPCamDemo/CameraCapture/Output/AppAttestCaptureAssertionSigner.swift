//
//  AppAttestCaptureAssertionSigner.swift
//  TAPCamDemo
//

import AppAttestKit
import CryptoKit
import Foundation
import OSLog

nonisolated protocol CaptureAssertionSigning: Sendable {
    func sign(
        contentDigest: CaptureContentDigest
    ) async throws -> CaptureAssertionProof
}

nonisolated struct CaptureAssertionProof: Equatable, Sendable {
    let proof: TAPDepthManifest.Proof
    let keyID: String
}

nonisolated struct AppAttestCaptureAssertionSigner: CaptureAssertionSigning {
    private let client: any AppAttestClient
    private let deviceService: any AppAttestDeviceService
    private let operationTimeout: Duration

    init(
        client: any AppAttestClient,
        deviceService: any AppAttestDeviceService = DCAppAttestDeviceService(),
        operationTimeout: Duration = AppAttestOperationTimeout.defaultDuration
    ) {
        self.client = client
        self.deviceService = deviceService
        self.operationTimeout = operationTimeout
    }

    func sign(
        contentDigest: CaptureContentDigest
    ) async throws -> CaptureAssertionProof {
        guard deviceService.isSupported else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("capture assertion unsupported captureID=\(contentDigest.captureID, privacy: .private)")
            #endif
            throw AppAttestError.unsupportedDevice
        }

        let operationID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("capture assertion sign start operationID=\(operationID, privacy: .public) captureID=\(contentDigest.captureID, privacy: .private)")
        #endif
        let credential = try await AppAttestOperationTimeout.run(
            operationDescription: "Prepare App Attest capture credential",
            timeout: operationTimeout
        ) {
            try await client.prepareIfNeeded(
                credentialName: AppAttestRuntimeDefaults.photoCredentialName
            )
        }
        let signingBinding = try CaptureSigningBinding(contentDigest: contentDigest)
        let clientDataHash = try signingBinding.clientDataHash()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("capture assertion credential ready operationID=\(operationID, privacy: .public) captureID=\(contentDigest.captureID, privacy: .private) keyID=\(Self.keyIDSummary(credential.keyId), privacy: .private)")
        #endif
        let assertionObject = try await AppAttestOperationTimeout.run(
            operationDescription: "Generate App Attest capture assertion",
            timeout: operationTimeout
        ) {
            try await deviceService.generateAssertion(
                credential.keyId,
                clientDataHash: clientDataHash
            )
        }

        let proofValue = CaptureAssertionProofValue(
            contentDigest: contentDigest,
            keyId: credential.keyId,
            assertionObject: assertionObject.appAttestBase64URL,
            signingBinding: signingBinding
        )
        let proofData = try proofValue.canonicalJSONData()
        let proof = TAPDepthManifest.Proof(
            type: "appAttestAssertion",
            algorithm: "TAPCam.AppAttestCaptureSignature.v1",
            keyID: credential.keyId,
            createdAt: contentDigest.capturedAt,
            value: proofData.appAttestBase64URL
        )

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("capture assertion sign success operationID=\(operationID, privacy: .public) captureID=\(contentDigest.captureID, privacy: .private) keyID=\(Self.keyIDSummary(credential.keyId), privacy: .private) proofBytes=\(proofData.count, privacy: .public)")
        #endif
        return CaptureAssertionProof(proof: proof, keyID: credential.keyId)
    }

    private static func keyIDSummary(_ keyID: String) -> String {
        guard keyID.count > 8 else {
            return keyID
        }
        return "\(keyID.prefix(8))...len\(keyID.count)"
    }
}

nonisolated struct CaptureAssertionProofValue: Codable, Equatable, Sendable {
    let contentDigest: CaptureContentDigest
    let keyId: String
    let assertionObject: String
    let signingBinding: CaptureSigningBinding

    func canonicalJSONData() throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(self)
    }
}

nonisolated struct CaptureSigningBinding: Codable, Equatable, Sendable {
    static let schemaIdentifier = "urn:tapnap:tapcam:app-attest-capture-signing:v1"
    static let operationIdentifier = "tapcam.capture.sign"

    let bodySHA256: String
    let captureID: String
    let operation: String
    let schemaID: String

    init(
        bodySHA256: String,
        captureID: String,
        operation: String = CaptureSigningBinding.operationIdentifier,
        schemaID: String = CaptureSigningBinding.schemaIdentifier
    ) {
        self.bodySHA256 = bodySHA256
        self.captureID = captureID
        self.operation = operation
        self.schemaID = schemaID
    }

    init(contentDigest: CaptureContentDigest) throws {
        self.init(
            bodySHA256: Data(SHA256.hash(data: try contentDigest.canonicalJSONData())).appAttestBase64URL,
            captureID: contentDigest.captureID
        )
    }

    func canonicalJSONData() throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(self)
    }

    func clientDataHash() throws -> Data {
        Data(SHA256.hash(data: try canonicalJSONData()))
    }
}
