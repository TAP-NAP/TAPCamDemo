//
//  AppAttestRuntimeController.swift
//  TAPCamDemo
//

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

    var credentialKeyIDPresentation: AppAttestCredentialKeyIDPresentation? {
        credentialKeyIdText.map(AppAttestCredentialKeyIDPresentation.init(keyID:))
    }

    var photoIntegrityReadiness: PhotoIntegrityReadiness {
        if isPreparingCredential {
            return .preparing
        }
        if isPhotoCredentialReady && hasCurrentCredentialHealthCheck {
            return .ready
        }
        if AppAttestCredentialPresentation.isFailureStatusText(credentialStatusText) {
            return .preparationFailed
        }
        return .notReady
    }

    var canPreparePhotoIntegrity: Bool {
        !isWorking && photoIntegrityReadiness != .ready
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
                    healthCheckToken: currentHealthCheckToken
                )
            } else {
                try await self.loadOrPrepareCredential()
            }
        }
    }

    func prepareCredentialIfNeeded() async {
        _ = await performCredentialOperation("Prepare credential", showsPreparationProgress: true) {
            try await self.loadOrPrepareCredential()
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
            #if DEBUG
            TAPDiagnostics.appAttest.error("credential reset failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
        }
    }

    func resetAndPrepareCredential() async {
        let currentHealthCheckToken = Self.currentCredentialHealthCheckToken(runtime: runtime)
        _ = await performCredentialOperation("Reset and prepare credential", showsPreparationProgress: true) {
            try await self.resetLocalCredentialMetadata()
            try await self.prepareAndValidateCredential(
                healthCheckToken: currentHealthCheckToken
            )
        }
    }

    private func resetLocalCredentialMetadata() async throws {
        try await self.runtime.client.reset(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        self.userDefaults.set(false, forKey: Self.didAutoPreparePhotoCredentialKey)
        self.userDefaults.removeObject(forKey: Self.credentialHealthCheckTokenKey)
    }

    @discardableResult
    private func prepareCredential() async throws -> AppAttestCredential {
        let credential = try await runtime.client.prepare(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        self.userDefaults.set(true, forKey: Self.didAutoPreparePhotoCredentialKey)
        self.credentialStatusText = AppAttestCredentialPresentation.readyStatusText
        self.credentialKeyIdText = credential.keyId
        return credential
    }

    @discardableResult
    private func loadOrPrepareCredential() async throws -> AppAttestCredential {
        let credential = try await runtime.client.prepareIfNeeded(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        self.credentialStatusText = AppAttestCredentialPresentation.readyStatusText
        self.credentialKeyIdText = credential.keyId
        return credential
    }

    private func prepareAndValidateCredential(
        healthCheckToken: String
    ) async throws {
        _ = try await prepareCredential()

        do {
            try await validateCredentialCanGenerateAssertion()
        } catch where Self.isInvalidSystemAppAttestKey(error) {
            try await resetLocalCredentialMetadata()
            _ = try await prepareCredential()
            try await validateCredentialCanGenerateAssertion()
        }
        self.userDefaults.set(healthCheckToken, forKey: Self.credentialHealthCheckTokenKey)
    }

    private func validateCredentialCanGenerateAssertion() async throws {
        try await runtime.client.validateCredential(
            credentialName: AppAttestRuntimeDefaults.photoCredentialName
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
            return true
        } catch {
            credentialKeyIdText = nil
            credentialStatusText = AppAttestCredentialPresentation.failureStatusText(label: label)
            #if DEBUG
            TAPDiagnostics.appAttest.error("credential operation failed label=\(label, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
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

    private var hasCurrentCredentialHealthCheck: Bool {
        userDefaults.string(forKey: Self.credentialHealthCheckTokenKey)
            == Self.currentCredentialHealthCheckToken(runtime: runtime)
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
}
