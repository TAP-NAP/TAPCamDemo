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

    @Test func backendConfigurationParsesHTTPSURL() throws {
        let baseURL = try AppAttestBackendConfiguration.parse(
            backendURL: "https://www.tapnap.net"
        )

        #expect(baseURL.absoluteString == "https://www.tapnap.net")
    }

    @Test func backendConfigurationParsesDebugHTTPSURL() throws {
        let baseURL = try AppAttestBackendConfiguration.parse(
            backendURL: "https://dev.tapnap.net"
        )

        #expect(baseURL.absoluteString == "https://dev.tapnap.net")
    }

    @Test func backendConfigurationRejectsMissingURL() {
        #expect(throws: (any Error).self) {
            try AppAttestBackendConfiguration.parse(backendURL: nil)
        }
    }

    @Test func backendConfigurationRejectsNonHTTPSURL() {
        #expect(throws: (any Error).self) {
            try AppAttestBackendConfiguration.parse(
                backendURL: "http://example.com"
            )
        }
    }

    @Test func backendConfigurationRejectsEndpointPath() {
        #expect(throws: (any Error).self) {
            try AppAttestBackendConfiguration.parse(
                backendURL: "https://www.tapnap.net/healthz"
            )
        }
    }

    #if DEBUG
    @Test func debugRuntimeUsesDevelopmentEnvironment() throws {
        let runtime = try AppAttestRuntimeFactory.make(
            baseURL: try #require(URL(string: "https://dev.tapnap.net"))
        )

        #expect(runtime.backendURL?.absoluteString == "https://dev.tapnap.net")
        #expect(runtime.environment == .development)
        #expect(runtime.backendDescription == "HTTP Backend: https://dev.tapnap.net")
    }
    #endif

    @Test @MainActor func resetLocalCredentialReportsResetFailure() async throws {
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
            userDefaults: userDefaults
        )
        await controller.resetLocalCredential()

        #expect(controller.credentialStatusText.contains("Reset photo_keyid failed"))
    }

    @Test @MainActor func resetAndPrepareCredentialResetsThenPreparesWhenNotPrepared() async throws {
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
            userDefaults: userDefaults
        )

        #expect(controller.canResetAndPrepareCredential)

        await controller.resetAndPrepareCredential()

        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepare:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "prepared-key-id")
        #expect(!controller.isPreparingCredential)
        #expect(!controller.canResetAndPrepareCredential)
    }

    @Test @MainActor func startupRegistersFreshCredentialWhenHealthTokenChanges() async throws {
        let client = RecordingAppAttestClient(
            prepareKeyID: "server-registered-key-id",
            assertionMode: .healthy
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendURL: try #require(URL(string: "https://www.tapnap.net")),
            environment: .production,
            backendDescription: "HTTP Backend: https://www.tapnap.net"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults.set(true, forKey: "TAPCamDemo.AppAttest.didAutoPreparePhotoCredential")
        userDefaults.set("stale-token", forKey: "TAPCamDemo.AppAttest.credentialHealthCheckToken")

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults
        )

        let didPrepare = await controller.preparePhotoCredentialAfterFirstInstallLaunch()

        #expect(didPrepare)
        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepare:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "server-registered-key-id")
    }

    @Test @MainActor func startupReusesCredentialWhenHealthTokenMatches() async throws {
        let client = RecordingAppAttestClient(
            prepareIfNeededKeyID: "existing-key-id"
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendURL: try #require(URL(string: "https://www.tapnap.net")),
            environment: .production,
            backendDescription: "HTTP Backend: https://www.tapnap.net"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let token = AppAttestRuntimeController.currentCredentialHealthCheckToken(runtime: runtime)
        userDefaults.set(true, forKey: "TAPCamDemo.AppAttest.didAutoPreparePhotoCredential")
        userDefaults.set(token, forKey: "TAPCamDemo.AppAttest.credentialHealthCheckToken")

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults
        )

        let didPrepare = await controller.preparePhotoCredentialAfterFirstInstallLaunch()

        #expect(didPrepare)
        #expect(await client.operations() == [
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "existing-key-id")
    }

    @Test @MainActor func startupReportsFailureWhenFreshPrepareFails() async throws {
        let client = RecordingAppAttestClient()
        let runtime = AppAttestRuntime(
            client: client,
            backendURL: try #require(URL(string: "https://www.tapnap.net")),
            environment: .production,
            backendDescription: "HTTP Backend: https://www.tapnap.net"
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

        let didPrepare = await controller.preparePhotoCredentialAfterFirstInstallLaunch()

        #expect(!didPrepare)
        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText.contains("Prepare credential failed"))
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
    }

    private let prepareKeyID: String?
    private let prepareIfNeededKeyID: String?
    private let assertionMode: AssertionMode
    private var operationLog: [String] = []
    private var currentKeyID: String?

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
        currentKeyID = prepareKeyID
        return credential(credentialName: credentialName, keyID: prepareKeyID)
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        guard let prepareIfNeededKeyID else {
            throw AppAttestRuntimeTestError.unused
        }
        operationLog.append("prepareIfNeeded:\(credentialName)")
        currentKeyID = prepareIfNeededKeyID
        return credential(credentialName: credentialName, keyID: prepareIfNeededKeyID)
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        operationLog.append("generateAssertion:\(credentialName):\(request.path)")

        guard assertionMode == .healthy,
              let currentKeyID else {
            throw AppAttestRuntimeTestError.unused
        }

        return try makeTestAssertionEnvelope(
            credentialName: credentialName,
            keyId: currentKeyID,
            request: request
        )
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {
        operationLog.append("reset:\(credentialName)")
        currentKeyID = nil
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
