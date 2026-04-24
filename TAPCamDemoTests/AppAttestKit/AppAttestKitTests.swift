//
//  AppAttestKitTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct AppAttestKitTests {
    @Test func subjectCodableKeepsTypeAndId() throws {
        let subject = AppAttestSubject(type: "tenantUser", id: "tenant-1:user-2")
        let data = try JSONEncoder.appAttestCanonical.encode(subject)
        let decoded = try JSONDecoder.appAttestDefault.decode(AppAttestSubject.self, from: data)

        #expect(decoded == subject)
        #expect(decoded.type == "tenantUser")
        #expect(decoded.id == "tenant-1:user-2")
    }

    @Test func prepareStoresCredentialOnlyAfterBackendAccepts() async throws {
        let subject = AppAttestSubject(type: "install", id: "install-1")
        let store = InMemoryCredentialStore()
        let backend = MockAppAttestBackend()
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        let credential = try await client.prepare(subject: subject)
        let stored = try await store.credential(for: subject)

        #expect(credential.subject == subject)
        #expect(stored?.keyId == "mock-key-id")
        #expect(await backend.challengeRequests.map(\.purpose) == [.attestation])
        #expect(await backend.registrationRequests.count == 1)
        #expect(deviceService.didGenerateKey)
        #expect(deviceService.attestedKeyId == "mock-key-id")
    }

    @Test func prepareIfNeededReusesExistingCredential() async throws {
        let subject = AppAttestSubject(type: "user", id: "user-1")
        let now = Date()
        let existing = AppAttestCredential(
            subject: subject,
            keyId: "existing-key",
            credentialId: "server-existing-key",
            status: .ready,
            environment: .production,
            createdAt: now,
            updatedAt: now
        )
        let store = InMemoryCredentialStore()
        try await store.save(existing)

        let backend = MockAppAttestBackend()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .production
        )

        let credential = try await client.prepareIfNeeded(subject: subject)

        #expect(credential.keyId == "existing-key")
        #expect(await backend.challengeRequests.isEmpty)
    }

    @Test func resetOnlyDeletesSelectedSubject() async throws {
        let install = AppAttestSubject(type: "install", id: "install-1")
        let user = AppAttestSubject(type: "user", id: "user-1")
        let now = Date()
        let store = InMemoryCredentialStore()
        try await store.save(
            AppAttestCredential(
                subject: install,
                keyId: "install-key",
                credentialId: nil,
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )
        try await store.save(
            AppAttestCredential(
                subject: user,
                keyId: "user-key",
                credentialId: nil,
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let client = DefaultAppAttestClient(
            backend: MockAppAttestBackend(),
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        try await client.reset(subject: install)

        #expect(try await store.credential(for: install) == nil)
        #expect(try await store.credential(for: user)?.keyId == "user-key")
    }

    @Test func assertionUsesBackendChallengeAndRecordsEnvelope() async throws {
        let subject = AppAttestSubject(type: "user", id: "user-1")
        let store = InMemoryCredentialStore()
        let now = Date()
        try await store.save(
            AppAttestCredential(
                subject: subject,
                keyId: "stored-key",
                credentialId: nil,
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let backend = MockAppAttestBackend()
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        let envelope = try await client.generateAssertion(
            subject: subject,
            request: AppAttestProtectedRequest(
                method: "POST",
                path: "/api/protected",
                body: Data("one".utf8)
            )
        )

        #expect(envelope.keyId == "stored-key")
        #expect(await backend.challengeRequests.map(\.purpose) == [.assertion])
        #expect(await backend.assertionRecords.count == 1)
        #expect(deviceService.assertedKeyId == "stored-key")
    }

    @Test func requestBindingChangesWhenBodyChanges() throws {
        let challenge = Data("challenge".utf8)
        let first = AppAttestProtectedRequest(
            method: "POST",
            path: "/api/protected",
            body: Data("one".utf8)
        ).binding(challenge: challenge)
        let second = AppAttestProtectedRequest(
            method: "POST",
            path: "/api/protected",
            body: Data("two".utf8)
        ).binding(challenge: challenge)

        #expect(try first.clientDataHash() != second.clientDataHash())
    }

    @Test func httpBackendDetectsForbiddenLocalHosts() {
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://localhost:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://127.0.0.1:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://printer.local")!))
        #expect(!HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "https://api.example.com")!))
    }

    #if DEBUG
    @Test func localDebugBackendExportsGeneratedObjects() async throws {
        let backend = LocalDebugAppAttestBackend()
        let subject = AppAttestSubject(type: "install", id: "install-1")
        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, subject: subject)
        )
        _ = try await backend.registerAttestation(
            AppAttestRegistrationRequest(
                subject: subject,
                keyId: "debug-key",
                challengeId: challenge.challengeId,
                attestationObject: Data("attestation".utf8)
            )
        )
        await backend.recordAssertionResult(
            AppAttestAssertionRecord(
                subject: subject,
                keyId: "debug-key",
                challengeId: challenge.challengeId,
                assertionObject: Data("assertion".utf8),
                requestBinding: AppAttestProtectedRequest(
                    method: "GET",
                    path: "/debug"
                ).binding(challenge: challenge.challenge),
                createdAt: Date()
            )
        )

        let json = try await backend.exportDebugJSONString()

        #expect(json.contains("attestationObject"))
        #expect(json.contains("assertionObject"))
        #expect(json.contains("debug-key"))
    }
    #endif
}

private actor InMemoryCredentialStore: AppAttestCredentialStore {
    private var credentials: [AppAttestSubject: AppAttestCredential] = [:]

    func credential(for subject: AppAttestSubject) async throws -> AppAttestCredential? {
        credentials[subject]
    }

    func save(_ credential: AppAttestCredential) async throws {
        credentials[credential.subject] = credential
    }

    func delete(subject: AppAttestSubject) async throws {
        credentials.removeValue(forKey: subject)
    }
}

private actor MockAppAttestBackend: AppAttestBackend {
    private(set) var challengeRequests: [AppAttestChallengeRequest] = []
    private(set) var registrationRequests: [AppAttestRegistrationRequest] = []
    private(set) var assertionRecords: [AppAttestAssertionRecord] = []

    func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        challengeRequests.append(request)
        return AppAttestChallenge(
            challengeId: "challenge-\(challengeRequests.count)",
            challenge: Data("challenge-\(challengeRequests.count)".utf8),
            expiresAt: Date().addingTimeInterval(300)
        )
    }

    func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult {
        registrationRequests.append(request)
        return AppAttestRegistrationResult(
            credentialId: "server-\(request.keyId)",
            status: .accepted
        )
    }

    func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        .unknown
    }

    func recordAssertionResult(_ record: AppAttestAssertionRecord) async {
        assertionRecords.append(record)
    }
}

private final class MockAppAttestDeviceService: AppAttestDeviceService {
    var isSupported = true
    private(set) var didGenerateKey = false
    private(set) var attestedKeyId: String?
    private(set) var assertedKeyId: String?

    func generateKey() async throws -> String {
        didGenerateKey = true
        return "mock-key-id"
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestedKeyId = keyId
        return Data("mock-attestation".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        assertedKeyId = keyId
        return Data("mock-assertion".utf8)
    }
}
