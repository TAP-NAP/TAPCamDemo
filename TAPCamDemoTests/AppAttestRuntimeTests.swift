//
//  AppAttestRuntimeTests.swift
//  TAPCamDemoTests
//

import CryptoKit
import Foundation
import Testing
@testable import TAPCamDemo

@Suite(.serialized)
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

    @Test func diagnosticsDescriptionOmitsLocalizedDescriptionAndFailingURL() throws {
        let failingURL = try #require(URL(string: "https://secret.tapnap.net/health?token=secret-token"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [
                NSLocalizedDescriptionKey: "secret localized message with /private/photo.heic",
                NSURLErrorFailingURLErrorKey: failingURL,
                "NSErrorFailingURLStringKey": failingURL.absoluteString
            ]
        )

        let description = TAPDiagnostics.describe(error)

        #expect(description.contains("domain=\(NSURLErrorDomain)"))
        #expect(description.contains("code=\(NSURLErrorCannotConnectToHost)"))
        #expect(!description.contains("description="))
        #expect(!description.contains("url="))
        #expect(!description.contains("secret"))
        #expect(!description.contains("photo.heic"))
        #expect(!description.contains("tapnap.net"))
    }

    @Test func diagnosticsDescriptionKeepsVPNHintWithoutRawNetworkPath() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [
                "_NSURLErrorNWPathKey": "interface=utun4 gateway=198.18.0.1 token=secret-route"
            ]
        )
        let error = NSError(
            domain: "TAPDiagnosticsTests",
            code: 7,
            userInfo: [
                NSUnderlyingErrorKey: underlying
            ]
        )

        let description = TAPDiagnostics.describe(error)

        #expect(description.contains("domain=TAPDiagnosticsTests"))
        #expect(description.contains("code=7"))
        #expect(description.contains("underlyingDomain=\(NSURLErrorDomain)"))
        #expect(description.contains("underlyingCode=\(NSURLErrorNetworkConnectionLost)"))
        #expect(description.contains("vpnHint=true"))
        #expect(!description.contains("networkPath="))
        #expect(!description.contains("utun4"))
        #expect(!description.contains("198.18.0.1"))
        #expect(!description.contains("secret-route"))
    }

    @Test func diagnosticsDescriptionKeepsScalarStreamDiagnostics() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorSecureConnectionFailed,
            userInfo: [
                "_kCFStreamErrorDomainKey": 3,
                "_kCFStreamErrorCodeKey": -9807,
                "_kCFNetworkCFStreamSSLErrorOriginalValue": -9807,
                "_kCFStreamPropertySSLClientCertificateState": 1
            ]
        )

        let description = TAPDiagnostics.describe(error)

        #expect(description.contains("streamDomain=3"))
        #expect(description.contains("streamCode=-9807"))
        #expect(description.contains("sslOriginalValue=-9807"))
        #expect(description.contains("clientCertificateState=1"))
    }

    @Test func credentialKeyIDPresentationRedactsRawKeyID() {
        let rawKeyID = "server-registered-key-id"

        let presentation = AppAttestCredentialKeyIDPresentation(keyID: rawKeyID)

        #expect(!presentation.displayText.contains(rawKeyID))
        #expect(!presentation.accessibilityText.contains(rawKeyID))
        #expect(presentation.displayText.contains("\(rawKeyID.count) chars"))
        #expect(presentation.accessibilityText.contains("\(rawKeyID.count) characters"))
    }

    @Test func credentialKeyIDPresentationDoesNotExposeShortKeyIDVerbatim() {
        let rawKeyID = "short"

        let presentation = AppAttestCredentialKeyIDPresentation(keyID: rawKeyID)

        #expect(!presentation.displayText.contains(rawKeyID))
        #expect(!presentation.accessibilityText.contains(rawKeyID))
        #expect(presentation.displayText == "Prepared key (5 chars)")
    }

    #if DEBUG
    @Test func debugRuntimeUsesDevelopmentEnvironment() throws {
        let runtime = try AppAttestRuntimeFactory.make(
            baseURL: try #require(URL(string: "https://dev.tapnap.net"))
        )

        #expect(runtime.backendURL?.absoluteString == "https://dev.tapnap.net")
        #expect(runtime.environment == .development)
        #expect(runtime.backendDescription == "HTTP Backend configured")
        #expect(runtime.backendPublicSummary == "HTTP backend configured")
    }

    @Test func backendPublicSummaryDoesNotExposeConfiguredURL() throws {
        let runtime = try AppAttestRuntimeFactory.make(
            baseURL: try #require(URL(string: "https://tenant-secret.tapnap.net"))
        )

        #expect(runtime.backendURL?.absoluteString == "https://tenant-secret.tapnap.net")
        #expect(!runtime.backendDescription.contains("tenant-secret.tapnap.net"))
        #expect(!runtime.backendDescription.contains("https://"))
        #expect(!runtime.backendPublicSummary.contains("tenant-secret.tapnap.net"))
        #expect(!runtime.backendPublicSummary.contains("https://"))
        #expect(runtime.backendPublicSummary == "HTTP backend configured")
    }

    @Test func settingsViewUsesBackendPublicSummary() throws {
        let source = try Self.source(relativePath: "TAPCamDemo/App/Settings/DepthAnalyzerSettingsView.swift")

        #expect(source.contains("runtime.backendPublicSummary"))
        #expect(!source.contains("runtime.backendDescription"))
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

        #expect(controller.credentialStatusText == "Reset local credential failed. See diagnostics for details.")
        #expect(!controller.credentialStatusText.contains(AppAttestRuntimeDefaults.photoCredentialName))
    }

    @Test @MainActor func resetAndPrepareCredentialResetsThenPreparesWhenNotPrepared() async throws {
        let client = RecordingAppAttestClient(
            prepareKeyID: "prepared-key-id",
            assertionMode: .healthy
        )
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

        #expect(controller.canPreparePhotoIntegrity)
        #expect(controller.photoIntegrityReadiness == .notReady)

        await controller.resetAndPrepareCredential()

        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepare:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "prepared-key-id")
        #expect(controller.credentialKeyIDPresentation?.displayText != "prepared-key-id")
        #expect(controller.photoIntegrityReadiness == .ready)
        #expect(!controller.isPreparingCredential)
        #expect(!controller.canPreparePhotoIntegrity)
    }

    @Test @MainActor func resetAndPrepareCredentialReportsFailedReadinessWhenHealthCheckFails() async throws {
        let client = RecordingAppAttestClient(prepareKeyID: "unvalidated-key-id")
        let runtime = AppAttestRuntime(
            client: client,
            backendDescription: "Failing Health Check Backend"
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

        await controller.resetAndPrepareCredential()

        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepare:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health"
        ])
        #expect(controller.credentialKeyIdText == nil)
        #expect(controller.photoIntegrityReadiness == .preparationFailed)
        #expect(controller.canPreparePhotoIntegrity)
    }

    @Test @MainActor func pendingCaptureSigningWarmupRegistersFreshCredentialWhenHealthTokenChanges() async throws {
        let client = RecordingAppAttestClient(
            prepareKeyID: "server-registered-key-id",
            assertionMode: .healthy
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendURL: URL(string: "https://www.tapnap.net")!,
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

        let didPrepare = await controller.warmPendingCaptureSigningCredential()

        #expect(didPrepare)
        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "prepare:\(AppAttestRuntimeDefaults.photoCredentialName)",
            "generateAssertion:\(AppAttestRuntimeDefaults.photoCredentialName):/tapcam/app-attest/credential-health"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "server-registered-key-id")
        #expect(controller.photoIntegrityReadiness == .ready)
    }

    @Test @MainActor func pendingCaptureSigningWarmupReusesCredentialWhenHealthTokenMatches() async throws {
        let client = RecordingAppAttestClient(
            prepareIfNeededKeyID: "existing-key-id"
        )
        let runtime = AppAttestRuntime(
            client: client,
            backendURL: URL(string: "https://www.tapnap.net")!,
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

        let didPrepare = await controller.warmPendingCaptureSigningCredential()

        #expect(didPrepare)
        #expect(await client.operations() == [
            "prepareIfNeeded:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText == "Ready")
        #expect(controller.credentialKeyIdText == "existing-key-id")
        #expect(controller.photoIntegrityReadiness == .ready)
    }

    @Test @MainActor func pendingCaptureSigningWarmupReportsFailureWhenFreshPrepareFails() async throws {
        let client = RecordingAppAttestClient()
        let runtime = AppAttestRuntime(
            client: client,
            backendURL: URL(string: "https://www.tapnap.net")!,
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

        let didPrepare = await controller.warmPendingCaptureSigningCredential()

        #expect(!didPrepare)
        #expect(await client.operations() == [
            "reset:\(AppAttestRuntimeDefaults.photoCredentialName)"
        ])
        #expect(controller.credentialStatusText == "Prepare credential failed. See diagnostics for details.")
        #expect(controller.photoIntegrityReadiness == .preparationFailed)
        #expect(controller.canPreparePhotoIntegrity)
    }

    @Test @MainActor func credentialOperationFailureStatusOmitsLocalizedDescriptionAndFailingURL() async throws {
        let runtime = AppAttestRuntime(
            client: SensitivePrepareFailingAppAttestClient(),
            backendDescription: "Sensitive Prepare Backend"
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

        await controller.resetAndPrepareCredential()

        #expect(controller.credentialStatusText == "Reset and prepare credential failed. See diagnostics for details.")
        #expect(!controller.credentialStatusText.contains("secret localized"))
        #expect(!controller.credentialStatusText.contains("private/photo.heic"))
        #expect(!controller.credentialStatusText.contains("tapnap.net"))
        #expect(controller.canPreparePhotoIntegrity)
        #expect(controller.photoIntegrityReadiness == .preparationFailed)
    }

    @Test @MainActor func prepareTimeoutResetsWorkingStateAndAllowsRetry() async throws {
        let runtime = AppAttestRuntime(
            client: HangingPrepareAppAttestClient(),
            backendDescription: "Hanging Prepare Backend"
        )
        let suiteName = "TAPCamDemoTests.AppAttest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let controller = AppAttestRuntimeController(
            runtime: runtime,
            userDefaults: userDefaults,
            credentialOperationTimeout: .milliseconds(10)
        )

        await controller.resetAndPrepareCredential()

        #expect(controller.credentialStatusText == "Reset and prepare credential failed. See diagnostics for details.")
        #expect(!controller.isPreparingCredential)
        #expect(!controller.isWorking)
        #expect(controller.canPreparePhotoIntegrity)
        #expect(controller.photoIntegrityReadiness == .preparationFailed)
    }

    @Test @MainActor func debugPrepareWithoutCurrentHealthTokenDoesNotReportPhotoIntegrityReady() async throws {
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
        #expect(controller.photoIntegrityReadiness == .notReady)
        #expect(controller.canPreparePhotoIntegrity)
    }

    private static func source(relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func repositoryRoot(
        startingAt filePath: String = #filePath
    ) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            let projectPath = directory.appendingPathComponent("TAPCamDemo.xcodeproj").path
            let testsPath = directory.appendingPathComponent("TAPCamDemoTests").path
            let runtimePath = directory
                .appendingPathComponent("TAPCamDemo/App/AppAttestRuntime.swift")
                .path
            if fileManager.fileExists(atPath: projectPath),
               fileManager.fileExists(atPath: testsPath),
               fileManager.fileExists(atPath: runtimePath) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw AppAttestRuntimeTestError.repositoryRootNotFound(filePath)
    }
}

private enum AppAttestRuntimeTestError: Error {
    case repositoryRootNotFound(String)
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

    func validateCredential(credentialName: String) async throws {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {
        throw AppAttestRuntimeTestError.resetFailed
    }
}

private actor HangingPrepareAppAttestClient: AppAttestClient {
    func prepare(credentialName: String) async throws -> AppAttestCredential {
        try await Task.sleep(for: .seconds(60))
        throw AppAttestRuntimeTestError.unused
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        throw AppAttestRuntimeTestError.unused
    }

    func validateCredential(credentialName: String) async throws {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {}
}

private actor SensitivePrepareFailingAppAttestClient: AppAttestClient {
    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [
                NSLocalizedDescriptionKey: "secret localized message with /private/photo.heic",
                NSURLErrorFailingURLErrorKey: URL(string: "https://secret.tapnap.net/health?token=secret-token")!
            ]
        )
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        throw AppAttestRuntimeTestError.unused
    }

    func validateCredential(credentialName: String) async throws {
        throw AppAttestRuntimeTestError.unused
    }

    func reset(credentialName: String) async throws {}
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

    func validateCredential(credentialName: String) async throws {
        operationLog.append("generateAssertion:\(credentialName):/tapcam/app-attest/credential-health")

        guard assertionMode == .healthy,
              currentKeyID != nil else {
            throw AppAttestRuntimeTestError.unused
        }
    }

    func reset(credentialName: String) async throws {
        operationLog.append("reset:\(credentialName)")
        currentKeyID = nil
    }

    private func credential(credentialName: String, keyID: String) -> AppAttestCredential {
        AppAttestCredential(
            credentialName: credentialName,
            keyId: keyID
        )
    }
}
