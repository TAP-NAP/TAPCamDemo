//
//  AppAttestRuntimeTests.swift
//  TAPCamDemoTests
//

import AppAttestKit
import CryptoKit
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

        let client = RecordingAppAttestClient(prepareKeyID: "prepared-key-id")
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
        let client = RecordingAppAttestClient(
            prepareIfNeededKeyID: "healthy-key-id",
            assertionMode: .healthy
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendDescription: "Health Checking Backend"
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
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "healthy-key-id")
    }

    @Test @MainActor func manualPrepareUsesPrepareIfNeededToAvoidKeyRotation() async throws {
        let client = RecordingAppAttestClient(
            prepareIfNeededKeyID: "prepared-if-needed-key-id"
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendDescription: "Prepare If Needed Backend"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults
        )

        await controller.prepareCredentialIfNeeded()

        #expect(await client.operations() == [
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "prepared-if-needed-key-id")
    }

    @Test @MainActor func startupHealthCheckResetsAndPreparesWhenSavedKeyIsInvalid() async throws {
        let client = RecordingAppAttestClient(
            prepareIfNeededKeyID: "healthy-key-id",
            assertionMode: .invalidUntilReset
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendDescription: "Invalid Then Healthy Backend"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults
        )

        await controller.preparePhotoCredentialAfterFirstInstallLaunch()

        #expect(await client.operations() == [
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health",
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "healthy-key-id")
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

private actor RecordingAppAttestClient: AppAttestClient {
    enum AssertionMode {
        case unused
        case healthy
        case invalidUntilReset
    }

    private let prepareKeyID: String?
    private let prepareIfNeededKeyID: String?
    private let assertionMode: AssertionMode
    private var operationLog: [String] = []
    private var didReset = false

    init(
        prepareKeyID: String? = nil,
        prepareIfNeededKeyID: String? = nil,
        assertionMode: AssertionMode = .unused
    ) {
        self.prepareKeyID = prepareKeyID
        self.prepareIfNeededKeyID = prepareIfNeededKeyID
        self.assertionMode = assertionMode
    }

    func operations() -> [String] {
        operationLog
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        guard let prepareKeyID else {
            throw AppAttestRuntimeTestError.unused
        }
        operationLog.append("prepare:\(credentialName)")
        return credential(credentialName: credentialName, keyID: prepareKeyID)
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        guard let prepareIfNeededKeyID else {
            throw AppAttestRuntimeTestError.unused
        }
        operationLog.append("prepareIfNeeded:\(credentialName)")
        let keyID = assertionMode == .invalidUntilReset && !didReset
            ? "stale-key-id"
            : prepareIfNeededKeyID
        return credential(credentialName: credentialName, keyID: keyID)
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        operationLog.append("generateAssertion:\(credentialName):\(request.path)")

        if assertionMode == .invalidUntilReset && !didReset {
            throw NSError(domain: "com.apple.devicecheck.error", code: 3)
        }
        guard assertionMode != .unused,
              let prepareIfNeededKeyID else {
            throw AppAttestRuntimeTestError.unused
        }

        return try makeTestAssertionEnvelope(
            credentialName: credentialName,
            keyId: prepareIfNeededKeyID,
            request: request
        )
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {
        operationLog.append("reset:\(credentialName)")
        didReset = true
    }

    private func credential(credentialName: String, keyID: String) -> AppAttestCredential {
        AppAttestCredential(
            credentialName: credentialName,
            keyId: keyID,
            credentialId: nil,
            status: .ready,
            environment: .development,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private func makeTestAssertionEnvelope(
    credentialName: String,
    keyId: String,
    request: AppAttestProtectedRequest
) throws -> AppAttestAssertionEnvelope {
    let bodySHA256 = Data(SHA256.hash(data: request.body ?? Data())).appAttestBase64URL
    let challengeSHA256 = Data(SHA256.hash(data: Data("test-challenge".utf8))).appAttestBase64URL
    let bindingJSON = """
    {
      "bodySHA256": "\(bodySHA256)",
      "challengeSHA256": "\(challengeSHA256)",
      "method": "\(request.method.uppercased())",
      "nonce": "\(request.nonce ?? "")",
      "path": "\(request.path)",
      "query": []
    }
    """
    let requestBinding = try JSONDecoder().decode(
        AppAttestRequestBinding.self,
        from: Data(bindingJSON.utf8)
    )

    return AppAttestAssertionEnvelope(
        credentialName: credentialName,
        keyId: keyId,
        challengeId: "test-challenge",
        assertionObject: Data([0xA1, 0x03]),
        requestBinding: requestBinding
    )
}
