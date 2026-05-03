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
    @Published private(set) var credentialStatusText = "Not prepared"
    @Published private(set) var isWorking = false

    private let userDefaults: UserDefaults
    private let attestationObjectStore: any AppAttestAttestationObjectStoring
    private var activeOperationCount = 0

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

        await prepareCredential(markAutoPrepared: true)
    }

    func prepareCredential() async {
        await prepareCredential(markAutoPrepared: false)
    }

    func resetLocalCredential() async {
        beginOperation()
        defer { endOperation() }

        var resetError: Error?
        do {
            try await self.runtime.client.reset(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
        } catch {
            resetError = error
        }

        do {
            try attestationObjectStore.delete()
            self.userDefaults.set(false, forKey: Self.didAutoPreparePhotoCredentialKey)
            if let resetError {
                self.credentialStatusText = "Cleared stored attestationObject.cbor. Reset \(AppAttestRuntimeDefaults.photoCredentialName) failed: \(resetError.localizedDescription)"
            } else {
                self.credentialStatusText = "Reset \(AppAttestRuntimeDefaults.photoCredentialName) and cleared stored attestationObject.cbor."
            }
        } catch {
            self.credentialStatusText = "Reset \(AppAttestRuntimeDefaults.photoCredentialName) failed while clearing stored attestationObject.cbor: \(error.localizedDescription)"
        }
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

    private func prepareCredential(markAutoPrepared: Bool) async {
        await performCredentialOperation("Prepare credential") {
            let credential = try await self.runtime.client.prepare(credentialName: AppAttestRuntimeDefaults.photoCredentialName)
            let didStoreAttestationObject = try await self.storeLatestAttestationObjectIfAvailable()
            if markAutoPrepared {
                self.userDefaults.set(true, forKey: Self.didAutoPreparePhotoCredentialKey)
            }
            self.credentialStatusText = """
            Ready: \(credential.credentialName)
            keyId: \(credential.keyId)
            attestationObject.cbor: \(didStoreAttestationObject ? "Stored" : "Not available")
            """
        }
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
        operation: @MainActor @escaping () async throws -> Void
    ) async {
        beginOperation()
        defer { endOperation() }

        do {
            try await operation()
        } catch {
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
}
