//
//  AppAttestProtocols.swift
//  TAPCamDemo
//

import Foundation

/// High-level App Attest API used by application code.
public nonisolated protocol AppAttestClient {
    /// Creates and registers a new App Attest key for the supplied subject.
    func prepare(subject: AppAttestSubject) async throws -> AppAttestCredential

    /// Returns an existing credential or creates one if no local credential exists.
    func prepareIfNeeded(subject: AppAttestSubject) async throws -> AppAttestCredential

    /// Generates an assertion envelope for a caller-selected protected request.
    func generateAssertion(
        subject: AppAttestSubject,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope

    /// Returns local status, optionally refined by the configured backend.
    func status(subject: AppAttestSubject) async throws -> AppAttestCredentialStatus

    /// Deletes local credential metadata for a subject.
    func reset(subject: AppAttestSubject) async throws
}

/// Server boundary for all App Attest communication.
public nonisolated protocol AppAttestBackend {
    func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge
    func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult
    func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus
    func recordAssertionResult(_ record: AppAttestAssertionRecord) async
}

public nonisolated extension AppAttestBackend {
    func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        .unknown
    }

    func recordAssertionResult(_ record: AppAttestAssertionRecord) async {}
}

/// Local storage for App Attest key metadata.
public nonisolated protocol AppAttestCredentialStore {
    func credential(for subject: AppAttestSubject) async throws -> AppAttestCredential?
    func save(_ credential: AppAttestCredential) async throws
    func delete(subject: AppAttestSubject) async throws
}

/// Thin wrapper over Apple's DCAppAttestService, kept injectable for tests.
public nonisolated protocol AppAttestDeviceService {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}
