//
//  AppAttestRuntimeTests.swift
//  TAPCamDemoTests
//

import AppAttestKit
import Foundation
import Testing
@testable import TAPCamDemo

struct AppAttestRuntimeTests {
    @Test func defaultPhotoCredentialNameIsStable() {
        #expect(AppAttestRuntimeDefaults.photoCredentialName == "photo_keyid")
    }

    @Test @MainActor func resetLocalCredentialClearsStoredAttestationObjectWhenResetFails() async throws {
        let storedAttestationObject = Data([0xA1, 0x01, 0x02])
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPCamDemoTests.AppAttest.\(UUID().uuidString)", isDirectory: true)
        let attestationObjectStore = AppAttestAttestationObjectStore(baseDirectoryURL: temporaryDirectory)
        try attestationObjectStore.save(storedAttestationObject)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let runtime = AppAttestRuntime(
            client: ResetFailingAppAttestClient(),
            backendDescription: "Reset Failing Backend"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults,
            attestationObjectStore: attestationObjectStore
        )
        await controller.resetLocalCredential()

        #expect((try? attestationObjectStore.load()) == nil)
        #expect(controller.credentialStatusText.contains("Cleared stored attestationObject.cbor"))
    }

    @Test @MainActor func resetAndPrepareCredentialResetsThenPreparesWhenNotPrepared() async throws {
        let storedAttestationObject = Data([0xA1, 0x01, 0x02])
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPCamDemoTests.AppAttest.\(UUID().uuidString)", isDirectory: true)
        let attestationObjectStore = AppAttestAttestationObjectStore(baseDirectoryURL: temporaryDirectory)
        try attestationObjectStore.save(storedAttestationObject)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let client = ResetAndPrepareAppAttestClient()
        let runtime = AppAttestRuntime(
            client: client,
            backendDescription: "Reset And Prepare Backend"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults,
            attestationObjectStore: attestationObjectStore
        )

        #expect(controller.canResetAndPrepareCredential)

        await controller.resetAndPrepareCredential()

        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepare:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect((try? attestationObjectStore.load()) == nil)
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "prepared-key-id")
        #expect(!controller.isPreparingCredential)
        #expect(!controller.canResetAndPrepareCredential)
    }

    @Test @MainActor func startupRechecksPhotoCredentialWhenAutoPrepareWasPreviouslyMarkedDone() async throws {
        let client = PrepareIfNeededAppAttestClient()
        let runtime = AppAttestRuntime(
            client: client,
            backendDescription: "Prepare If Needed Backend"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults.set(true, forKey: "TAPCamDemo.AppAttest.didAutoPreparePhotoCredential")

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults
        )

        await controller.preparePhotoCredentialAfterFirstInstallLaunch()

        #expect(await client.operations() == [
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "prepared-if-needed-key-id")
    }

    #if DEBUG
    @Test @MainActor func debugRuntimeUsesLocalDebugBackendWithSharedChallenge() async throws {
        let runtime = try AppAttestRuntimeFactory.make(
            mode: .localDebug(challenge: AppAttestRuntimeDefaults.localDebugChallenge)
        )

        #expect(runtime.backendDescription == "Local Debug Backend: TapTapNapNap123123")
        #expect(runtime.debugBackend != nil)

        let attestationChallenge = try await runtime.debugBackend?.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, credentialName: "demo-attestation")
        )
        let assertionChallenge = try await runtime.debugBackend?.requestChallenge(
            AppAttestChallengeRequest(purpose: .assertion, credentialName: "demo-assertion")
        )

        #expect(attestationChallenge?.challengeId == "TapTapNapNap123123")
        #expect(String(data: attestationChallenge?.challenge ?? Data(), encoding: .utf8) == "TapTapNapNap123123")
        #expect(assertionChallenge?.challengeId == "TapTapNapNap123123")
        #expect(String(data: assertionChallenge?.challenge ?? Data(), encoding: .utf8) == "TapTapNapNap123123")
    }
    #endif

    @Test func backendConfigurationParsesDefaultLocalDebugMode() throws {
        let mode = try AppAttestBackendConfiguration.parse(
            mode: "localDebug",
            backendURL: nil,
            localChallenge: nil
        )

        guard case .localDebug(let challenge) = mode else {
            Issue.record("Expected local debug backend mode.")
            return
        }
        #expect(challenge == "TapTapNapNap123123")
    }

    @Test func backendConfigurationParsesHTTPMode() throws {
        let mode = try AppAttestBackendConfiguration.parse(
            mode: "http",
            backendURL: "https://api.example.com",
            localChallenge: nil
        )

        guard case .http(let baseURL) = mode else {
            Issue.record("Expected HTTP backend mode.")
            return
        }
        #expect(baseURL.absoluteString == "https://api.example.com")
    }

    @Test func backendConfigurationRejectsHTTPModeWithoutURL() {
        #expect(throws: (any Error).self) {
            try AppAttestBackendConfiguration.parse(
                mode: "http",
                backendURL: nil,
                localChallenge: nil
            )
        }
    }

    @Test func backendConfigurationRejectsShortLocalDebugChallenge() {
        #expect(throws: (any Error).self) {
            try AppAttestBackendConfiguration.parse(
                mode: "localDebug",
                backendURL: nil,
                localChallenge: "short"
            )
        }
    }

}

private enum AppAttestRuntimeTestError: Error {
    case resetFailed
    case unused
}

private actor ResetFailingAppAttestClient: AppAttestClient {
    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw AppAttestRuntimeTestError.unused
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        throw AppAttestRuntimeTestError.unused
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        throw AppAttestRuntimeTestError.unused
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {
        throw AppAttestRuntimeTestError.resetFailed
    }
}

private actor ResetAndPrepareAppAttestClient: AppAttestClient {
    private var operationLog: [String] = []

    func operations() -> [String] {
        operationLog
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        operationLog.append("prepare:\(credentialName)")
        return AppAttestCredential(
            credentialName: credentialName,
            keyId: "prepared-key-id",
            credentialId: nil,
            status: .ready,
            environment: .development,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        throw AppAttestRuntimeTestError.unused
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        throw AppAttestRuntimeTestError.unused
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {
        operationLog.append("reset:\(credentialName)")
    }
}

private actor PrepareIfNeededAppAttestClient: AppAttestClient {
    private var operationLog: [String] = []

    func operations() -> [String] {
        operationLog
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw AppAttestRuntimeTestError.unused
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        operationLog.append("prepareIfNeeded:\(credentialName)")
        return AppAttestCredential(
            credentialName: credentialName,
            keyId: "prepared-if-needed-key-id",
            credentialId: nil,
            status: .ready,
            environment: .development,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        throw AppAttestRuntimeTestError.unused
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {
        throw AppAttestRuntimeTestError.unused
    }
}
