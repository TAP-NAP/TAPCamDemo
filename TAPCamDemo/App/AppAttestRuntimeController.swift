//
//  AppAttestRuntimeController.swift
//  TAPCamDemo
//

import AppAttestKit
import Combine
import Foundation

@MainActor
final class AppAttestRuntimeController: ObservableObject {
    @Published private(set) var runtime: AppAttestRuntime
    @Published private(set) var credentialStatusText = AppAttestRuntimeController.notPreparedStatusText
    @Published private(set) var credentialKeyIdText: String?
    @Published private(set) var isPreparingCredential = false
    @Published private(set) var isWorking = false

    private let userDefaults: UserDefaults
    private let attestationObjectStore: any AppAttestAttestationObjectStoring
    private var activeOperationCount = 0

    var canResetAndPrepareCredential: Bool {
        credentialStatusText == Self.notPreparedStatusText && !isWorking
    }

    init(
        runtime: AppAttestRuntime? = nil,
        userDefaults: UserDefaults = .standard,
        attestationObjectStore: any AppAttestAttestationObjectStoring = AppAttestAttestationObjectStore()
    ) {
        let resolvedRuntime = runtime ?? Self.makeRuntime()
        self.runtime = resolvedRuntime
        self.userDefaults = userDefaults
        self.attestationObjectStore = attestationObjectStore
    }

    func preparePhotoCredentialAfterFirstInstallLaunch() async {
        let didAutoPrepare = userDefaults.bool(forKey: Self.didAutoPreparePhotoCredentialKey)
        let shouldRefreshMissingDebugAttestationObject = runtime.debugBackend != nil && (try? attestationObjectStore.load()) == nil

        guard !didAutoPrepare || shouldRefreshMissingDebugAttestationObject else {
            return
        }

        await performCredentialOperation("Prepare credential", showsPreparationProgress: true) {
            try await self.prepareCredential(markAutoPrepared: true)
        }
    }

    func prepareCredential() async {
        await performCredentialOperation("Prepare credential", showsPreparationProgress: true) {
            try await self.prepareCredential(markAutoPrepared: false)
        }
    }

    func resetLocalCredential() async {
        beginOperation()
        defer { endOperation() }

        do {
            let resetError = try await resetLocalCredentialArtifacts()
            credentialKeyIdText = nil
            if let resetError {
                self.credentialStatusText = "Cleared stored attestationObject.cbor. Reset \(AppAttestRuntimeDefaults.photoCredentialName) failed: \(resetError.localizedDescription)"
            } else {
                self.credentialStatusText = "Reset \(AppAttestRuntimeDefaults.photoCredentialName) and cleared stored attestationObject.cbor."
            }
        } catch {
            self.credentialStatusText = "Reset \(AppAttestRuntimeDefaults.photoCredentialName) failed while clearing stored attestationObject.cbor: \(error.localizedDescription)"
        }
    }

    func resetAndPrepareCredential() async {
        await performCredentialOperation("Reset and prepare credential", showsPreparationProgress: true) {
            _ = try await self.resetLocalCredentialArtifacts()
            try await self.prepareCredential(markAutoPrepared: true)
        }
    }

    private func resetLocalCredentialArtifacts() async throws -> Error? {
        var resetError: Error?
        do {
            try await self.runtime.client.reset(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        } catch {
            resetError = error
        }

        try attestationObjectStore.delete()
        self.userDefaults.set(false, forKey: Self.didAutoPreparePhotoCredentialKey)
        return resetError
    }

    func attestationObjectForExport() async -> Data? {
        beginOperation()
        defer { endOperation() }

        do {
            if let storedData = try? attestationObjectStore.load() {
                credentialStatusText = "Loaded stored attestationObject.cbor for export."
                return storedData
            }

            guard let debugBackend = runtime.debugBackend else {
                throw AppAttestError.invalidConfiguration("Attestation CBOR export requires Local Debug Backend.")
            }

            let data = try await debugBackend.latestAttestationObject()
            try attestationObjectStore.save(data)
            credentialStatusText = "Stored attestationObject.cbor is ready to export."
            return data
        } catch {
            credentialStatusText = "Export Attestation CBOR failed: \(error.localizedDescription)"
            return nil
        }
    }

    func handleAttestationExportResult(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            credentialStatusText = "Saved attestationObject.cbor: \(url.lastPathComponent)"
        case .failure(let error):
            credentialStatusText = "Save attestationObject.cbor failed: \(error.localizedDescription)"
        }
    }

    private func prepareCredential(markAutoPrepared: Bool) async throws {
        let credential = try await runtime.client.prepare(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        _ = try await storeLatestAttestationObjectIfAvailable()
        if markAutoPrepared {
            self.userDefaults.set(true, forKey: Self.didAutoPreparePhotoCredentialKey)
        }
        self.credentialStatusText = Self.readyStatusText
        self.credentialKeyIdText = credential.keyId
    }

    private func storeLatestAttestationObjectIfAvailable() async throws -> Bool {
        guard let debugBackend = runtime.debugBackend else {
            return false
        }

        let data = try await debugBackend.latestAttestationObject()
        try attestationObjectStore.save(data)
        return true
    }

    private func performCredentialOperation(
        _ label: String,
        showsPreparationProgress: Bool = false,
        operation: @MainActor @escaping () async throws -> Void
    ) async {
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
            try await operation()
        } catch {
            credentialKeyIdText = nil
            credentialStatusText = "\(label) failed: \(error.localizedDescription)"
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
    private static let notPreparedStatusText = "Not prepared"
    private static let readyStatusText = "Ready"
}
