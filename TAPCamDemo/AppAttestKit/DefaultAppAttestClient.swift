//
//  DefaultAppAttestClient.swift
//  TAPCamDemo
//

import CryptoKit
import Foundation

/// Default implementation of the reusable App Attest client.
public actor DefaultAppAttestClient: AppAttestClient {
    private let backend: AppAttestBackend
    private let credentialStore: AppAttestCredentialStore
    private let deviceService: AppAttestDeviceService
    private let environment: AppAttestEnvironment

    public init(
        backend: AppAttestBackend,
        credentialStore: AppAttestCredentialStore = KeychainAppAttestCredentialStore(),
        deviceService: AppAttestDeviceService = DCAppAttestDeviceService(),
        environment: AppAttestEnvironment = .production
    ) {
        self.backend = backend
        self.credentialStore = credentialStore
        self.deviceService = deviceService
        self.environment = environment
    }

    public func prepare(subject: AppAttestSubject) async throws -> AppAttestCredential {
        guard deviceService.isSupported else {
            throw AppAttestError.unsupportedDevice
        }

        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, subject: subject)
        )
        let keyId = try await deviceService.generateKey()
        let clientDataHash = Data(SHA256.hash(data: challenge.challenge))
        let attestationObject = try await deviceService.attestKey(keyId, clientDataHash: clientDataHash)

        let result = try await backend.registerAttestation(
            AppAttestRegistrationRequest(
                subject: subject,
                keyId: keyId,
                challengeId: challenge.challengeId,
                attestationObject: attestationObject
            )
        )

        guard result.status == .accepted else {
            throw AppAttestError.attestationRejected("Backend registration returned \(result.status.rawValue).")
        }

        let now = Date()
        let credential = AppAttestCredential(
            subject: subject,
            keyId: keyId,
            credentialId: result.credentialId,
            status: .ready,
            environment: environment,
            createdAt: now,
            updatedAt: now
        )

        try await credentialStore.save(credential)
        return credential
    }

    public func prepareIfNeeded(subject: AppAttestSubject) async throws -> AppAttestCredential {
        if let credential = try await credentialStore.credential(for: subject),
           credential.status == .ready {
            return credential
        }

        return try await prepare(subject: subject)
    }

    public func generateAssertion(
        subject: AppAttestSubject,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        guard deviceService.isSupported else {
            throw AppAttestError.unsupportedDevice
        }

        guard let credential = try await credentialStore.credential(for: subject) else {
            throw AppAttestError.credentialMissing(subject)
        }

        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .assertion, subject: subject)
        )
        let binding = request.binding(challenge: challenge.challenge)
        let assertionObject = try await deviceService.generateAssertion(
            credential.keyId,
            clientDataHash: try binding.clientDataHash()
        )

        let envelope = AppAttestAssertionEnvelope(
            subject: subject,
            keyId: credential.keyId,
            challengeId: challenge.challengeId,
            assertionObject: assertionObject,
            requestBinding: binding
        )

        await backend.recordAssertionResult(
            AppAttestAssertionRecord(
                subject: subject,
                keyId: credential.keyId,
                challengeId: challenge.challengeId,
                assertionObject: assertionObject,
                requestBinding: binding,
                createdAt: Date()
            )
        )

        return envelope
    }

    public func status(subject: AppAttestSubject) async throws -> AppAttestCredentialStatus {
        guard let credential = try await credentialStore.credential(for: subject) else {
            return .notPrepared
        }

        let serverStatus = try await backend.credentialStatus(
            AppAttestCredentialStatusRequest(subject: subject, keyId: credential.keyId)
        )

        switch serverStatus {
        case .accepted:
            return .ready
        case .revoked:
            return .revoked
        case .unknown:
            return credential.status
        }
    }

    public func reset(subject: AppAttestSubject) async throws {
        try await credentialStore.delete(subject: subject)
    }
}
