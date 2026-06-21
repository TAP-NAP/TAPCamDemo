//
//  AppAttestRuntimeController.swift
//  TAPCamDemo
//

import AppAttestKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppAttestRuntimeController: ObservableObject {
    @Published private(set) var runtime: AppAttestRuntime
    @Published private(set) var credentialStatusText = AppAttestCredentialPresentation.notPreparedStatusText
    @Published private(set) var credentialKeyIdText: String?
    @Published private(set) var isPreparingCredential = false
    @Published private(set) var isWorking = false

    private let userDefaults: UserDefaults
    private let credentialOperationTimeout: Duration
    private var activeOperationCount = 0

    var isPhotoCredentialReady: Bool {
        credentialStatusText == AppAttestCredentialPresentation.readyStatusText && credentialKeyIdText != nil
    }

    var canResetAndPrepareCredential: Bool {
        !isPhotoCredentialReady && !isWorking
    }

    var credentialPreparationActionTitle: String {
        credentialStatusText == AppAttestCredentialPresentation.notPreparedStatusText ? "Prepare" : "Retry"
    }

    var credentialKeyIDPresentation: AppAttestCredentialKeyIDPresentation? {
        credentialKeyIdText.map(AppAttestCredentialKeyIDPresentation.init(keyID:))
    }

    init(
        runtime: AppAttestRuntime? = nil,
        userDefaults: UserDefaults = .standard,
        credentialOperationTimeout: Duration = AppAttestOperationTimeout.defaultDuration
    ) {
        let resolvedRuntime = runtime ?? Self.makeRuntime()
        self.runtime = resolvedRuntime
        self.userDefaults = userDefaults
        self.credentialOperationTimeout = credentialOperationTimeout
    }

    @discardableResult
    func warmPendingCaptureSigningCredential() async -> Bool {
        let didAutoPrepare = userDefaults.bool(forKey: Self.didAutoPreparePhotoCredentialKey)
        let storedHealthCheckToken = userDefaults.string(forKey: Self.credentialHealthCheckTokenKey)
        let currentHealthCheckToken = Self.currentCredentialHealthCheckToken(runtime: runtime)
        let shouldRegisterFreshCredential = !didAutoPrepare || storedHealthCheckToken != currentHealthCheckToken

        return await performCredentialOperation(
            "Prepare credential",
            showsPreparationProgress: shouldRegisterFreshCredential
        ) {
            if shouldRegisterFreshCredential {
                try await self.resetLocalCredentialMetadata()
                try await self.prepareAndValidateCredential(
                    markAutoPrepared: true,
                    healthCheckToken: currentHealthCheckToken
                )
            } else {
                try await self.prepareCredentialIfNeeded(markAutoPrepared: false)
            }
        }
    }

    func prepareCredentialIfNeeded() async {
        _ = await performCredentialOperation("Prepare credential", showsPreparationProgress: true) {
            try await self.prepareCredentialIfNeeded(markAutoPrepared: false)
        }
    }

    func resetLocalCredential() async {
        beginOperation()
        defer { endOperation() }

        do {
            try await resetLocalCredentialMetadata()
            credentialKeyIdText = nil
            self.credentialStatusText = AppAttestCredentialPresentation.resetStatusText
        } catch {
            self.credentialStatusText = AppAttestCredentialPresentation.failureStatusText(label: "Reset local credential")
            TAPDiagnostics.appAttest.error("credential reset failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
        }
    }

    func resetAndPrepareCredential() async {
        _ = await performCredentialOperation("Reset and prepare credential", showsPreparationProgress: true) {
            try await self.resetLocalCredentialMetadata()
            try await self.prepareCredential(markAutoPrepared: true)
        }
    }

    private func resetLocalCredentialMetadata() async throws {
        try await self.runtime.client.reset(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        self.userDefaults.set(false, forKey: Self.didAutoPreparePhotoCredentialKey)
        self.userDefaults.removeObject(forKey: Self.credentialHealthCheckTokenKey)
    }

    @discardableResult
    private func prepareCredential(markAutoPrepared: Bool) async throws -> AppAttestCredential {
        let credential = try await runtime.client.prepare(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        if markAutoPrepared {
            self.userDefaults.set(true, forKey: Self.didAutoPreparePhotoCredentialKey)
        }
        self.credentialStatusText = AppAttestCredentialPresentation.readyStatusText
        self.credentialKeyIdText = credential.keyId
        return credential
    }

    @discardableResult
    private func prepareCredentialIfNeeded(markAutoPrepared: Bool) async throws -> AppAttestCredential {
        let credential = try await runtime.client.prepareIfNeeded(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        if markAutoPrepared {
            self.userDefaults.set(true, forKey: Self.didAutoPreparePhotoCredentialKey)
        }
        self.credentialStatusText = AppAttestCredentialPresentation.readyStatusText
        self.credentialKeyIdText = credential.keyId
        return credential
    }

    private func prepareAndValidateCredential(
        markAutoPrepared: Bool,
        healthCheckToken: String
    ) async throws {
        _ = try await prepareCredential(markAutoPrepared: markAutoPrepared)

        do {
            try await validateCredentialCanGenerateAssertion()
        } catch where Self.isInvalidSystemAppAttestKey(error) {
            try await resetLocalCredentialMetadata()
            _ = try await prepareCredential(markAutoPrepared: markAutoPrepared)
            try await validateCredentialCanGenerateAssertion()
        }
        self.userDefaults.set(healthCheckToken, forKey: Self.credentialHealthCheckTokenKey)
    }

    private func validateCredentialCanGenerateAssertion() async throws {
        let request = AppAttestProtectedRequest(
            method: "POST",
            path: "/tapcam/app-attest/credential-health",
            body: Self.credentialHealthCheckBody,
            nonce: Self.credentialHealthCheckNonce
        )
        _ = try await runtime.client.generateAssertion(
            credentialName: AppAttestRuntimeDefaults.photoCredentialName,
            request: request
        )
    }

    private static func isInvalidSystemAppAttestKey(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.devicecheck.error" && nsError.code == 3
    }

    static func currentCredentialHealthCheckToken(
        runtime: AppAttestRuntime,
        bundle: Bundle = .main
    ) -> String {
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown.bundle"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown-version"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown-build"
        return [
            bundleIdentifier,
            version,
            build,
            runtime.backendURL?.absoluteString ?? runtime.backendDescription,
            runtime.environment?.rawValue ?? "unknown-environment",
            AppAttestRuntimeDefaults.photoCredentialName
        ].joined(separator: "|")
    }

    private func performCredentialOperation(
        _ label: String,
        showsPreparationProgress: Bool = false,
        operation: @MainActor @Sendable @escaping () async throws -> Void
    ) async -> Bool {
        let operationID = UUID().uuidString
        TAPDiagnostics.appAttest.info("credential operation start operationID=\(operationID, privacy: .public) label=\(label, privacy: .public) backend=\(self.runtime.backendPublicSummary, privacy: .public)")
        beginOperation()
        if showsPreparationProgress {
            isPreparingCredential = true
            credentialKeyIdText = nil
        }
        defer {
            if showsPreparationProgress {
                isPreparingCredential = false
            }
            endOperation()
        }

        do {
            try await AppAttestOperationTimeout.run(
                operationDescription: label,
                timeout: credentialOperationTimeout
            ) {
                try await operation()
            }
            TAPDiagnostics.appAttest.info("credential operation success operationID=\(operationID, privacy: .public) label=\(label, privacy: .public)")
            return true
        } catch {
            credentialKeyIdText = nil
            credentialStatusText = AppAttestCredentialPresentation.failureStatusText(label: label)
            TAPDiagnostics.appAttest.error("credential operation failed operationID=\(operationID, privacy: .public) label=\(label, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            return false
        }
    }

    private func beginOperation() {
        activeOperationCount += 1
        isWorking = activeOperationCount > 0
    }

    private func endOperation() {
        activeOperationCount = max(0, activeOperationCount - 1)
        isWorking = activeOperationCount > 0
    }

    private static func makeRuntime() -> AppAttestRuntime {
        do {
            return try AppAttestRuntimeFactory.make()
        } catch {
            return AppAttestRuntimeFactory.fallbackRuntime(error: error)
        }
    }

    private static let didAutoPreparePhotoCredentialKey = "TAPCamDemo.AppAttest.didAutoPreparePhotoCredential"
    private static let credentialHealthCheckTokenKey = "TAPCamDemo.AppAttest.credentialHealthCheckToken"
    private static let credentialHealthCheckNonce = "tapcam-app-attest-credential-health"
    private static let credentialHealthCheckBody = Data(
        """
        {"schemaID":"urn:tapnap:tapcam:app-attest-credential-health:v1"}
        """.utf8
    )
}
