//
//  AppAttestRuntime.swift
//  TAPCamDemo
//

import Foundation

struct AppAttestRuntime {
    let client: any AppAttestClient
    let backendDescription: String
    #if DEBUG
    let debugBackend: LocalDebugAppAttestBackend?
    #endif

    #if DEBUG
    init(
        client: any AppAttestClient,
        backendDescription: String,
        debugBackend: LocalDebugAppAttestBackend? = nil
    ) {
        self.client = client
        self.backendDescription = backendDescription
        self.debugBackend = debugBackend
    }
    #else
    init(client: any AppAttestClient, backendDescription: String) {
        self.client = client
        self.backendDescription = backendDescription
    }
    #endif
}

enum AppAttestRuntimeFactory {
    static func make(baseURL: URL = AppAttestRuntimeDefaults.baseURL) throws -> AppAttestRuntime {
        #if DEBUG
        if HTTPAppAttestBackend.isForbiddenReleaseHost(baseURL) {
            let backend = LocalDebugAppAttestBackend()
            return AppAttestRuntime(
                client: DefaultAppAttestClient(
                    backend: backend,
                    credentialStore: KeychainAppAttestCredentialStore(),
                    deviceService: DCAppAttestDeviceService(),
                    environment: .development
                ),
                backendDescription: "Local debug backend",
                debugBackend: backend
            )
        }
        #endif

        let backend = try HTTPAppAttestBackend(baseURL: baseURL)
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: KeychainAppAttestCredentialStore(),
            deviceService: DCAppAttestDeviceService(),
            environment: .production
        )

        #if DEBUG
        return AppAttestRuntime(
            client: client,
            backendDescription: "HTTP backend: \(baseURL.absoluteString)",
            debugBackend: nil
        )
        #else
        return AppAttestRuntime(
            client: client,
            backendDescription: "HTTP backend: \(baseURL.absoluteString)"
        )
        #endif
    }

    static func fallbackRuntime(error: Error) -> AppAttestRuntime {
        #if DEBUG
        AppAttestRuntime(
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)",
            debugBackend: nil
        )
        #else
        AppAttestRuntime(
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)"
        )
        #endif
    }
}

enum AppAttestRuntimeDefaults {
    static var baseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:8080")!
        #else
        return URL(string: "https://example.com")!
        #endif
    }
}

private actor UnavailableAppAttestClient: AppAttestClient {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func prepare(subject: AppAttestSubject) async throws -> AppAttestCredential {
        throw error
    }

    func prepareIfNeeded(subject: AppAttestSubject) async throws -> AppAttestCredential {
        throw error
    }

    func generateAssertion(
        subject: AppAttestSubject,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        throw error
    }

    func status(subject: AppAttestSubject) async throws -> AppAttestCredentialStatus {
        throw error
    }

    func reset(subject: AppAttestSubject) async throws {
        throw error
    }
}
