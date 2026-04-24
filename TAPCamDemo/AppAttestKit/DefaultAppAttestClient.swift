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

    public func prepare(credentialName: String) async throws -> AppAttestCredential {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        guard deviceService.isSupported else {
            throw AppAttestError.unsupportedDevice
        }

        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, credentialName: credentialName)
        )
        let keyId = try await deviceService.generateKey()
        let clientDataHash = Data(SHA256.hash(data: challenge.challenge))
        let attestationObject = try await deviceService.attestKey(keyId, clientDataHash: clientDataHash)

        let result = try await backend.registerAttestation(
            AppAttestRegistrationRequest(
                credentialName: credentialName,
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
            credentialName: credentialName,
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

    public func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        if let credential = try await credentialStore.credential(named: credentialName),
           credential.status == .ready {
            return credential
        }

        return try await prepare(credentialName: credentialName)
    }

    public func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        guard deviceService.isSupported else {
            throw AppAttestError.unsupportedDevice
        }

        guard let credential = try await credentialStore.credential(named: credentialName) else {
            throw AppAttestError.credentialMissing(credentialName)
        }

        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .assertion, credentialName: credentialName)
        )
        let binding = request.binding(challenge: challenge.challenge)
        let assertionObject = try await deviceService.generateAssertion(
            credential.keyId,
            clientDataHash: try binding.clientDataHash()
        )

        let envelope = AppAttestAssertionEnvelope(
            credentialName: credentialName,
            keyId: credential.keyId,
            challengeId: challenge.challengeId,
            assertionObject: assertionObject,
            requestBinding: binding
        )

        await backend.recordAssertionResult(
            AppAttestAssertionRecord(
                credentialName: credentialName,
                keyId: credential.keyId,
                challengeId: challenge.challengeId,
                assertionObject: assertionObject,
                requestBinding: binding,
                createdAt: Date()
            )
        )

        return envelope
    }

    public func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        guard let credential = try await credentialStore.credential(named: credentialName) else {
            return .notPrepared
        }

        let serverStatus = try await backend.credentialStatus(
            AppAttestCredentialStatusRequest(credentialName: credentialName, keyId: credential.keyId)
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

    public func reset(credentialName: String) async throws {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        try await credentialStore.delete(credentialName: credentialName)
    }

    private static func normalizedCredentialName(_ credentialName: String) throws -> String {
        let trimmed = credentialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppAttestError.invalidConfiguration("credentialName cannot be empty.")
        }
        return trimmed
    }
}
