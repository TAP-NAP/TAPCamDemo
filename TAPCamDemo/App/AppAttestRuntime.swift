//
//  AppAttestRuntime.swift
//  TAPCamDemo
//

import Foundation

enum AppAttestBackendMode: Hashable {
    case http(baseURL: URL)
    #if DEBUG
    case mockDebug
    #endif
}

struct AppAttestRuntime {
    let client: any AppAttestClient
    let backendDescription: String
    #if DEBUG
    let debugBackend: MockDebugAppAttestBackend?
    #endif

    #if DEBUG
    init(
        client: any AppAttestClient,
        backendDescription: String,
        debugBackend: MockDebugAppAttestBackend? = nil
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
    static func make(mode: AppAttestBackendMode = AppAttestRuntimeDefaults.mode) throws -> AppAttestRuntime {
        switch mode {
        #if DEBUG
        case .mockDebug:
            let backend = MockDebugAppAttestBackend()
            return AppAttestRuntime(
                client: DefaultAppAttestClient(
                    backend: backend,
                    credentialStore: KeychainAppAttestCredentialStore(),
                    deviceService: DCAppAttestDeviceService(),
                    environment: .development
                ),
                backendDescription: "Mock debug backend",
                debugBackend: backend
            )
        #endif

        case .http(let baseURL):
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
    static var mode: AppAttestBackendMode {
        #if DEBUG
        .mockDebug
        #else
        .http(baseURL: URL(string: "https://example.com")!)
        #endif
    }
}

private actor UnavailableAppAttestClient: AppAttestClient {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw error
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        throw error
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        throw error
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw error
    }

    func reset(credentialName: String) async throws {
        throw error
    }
}
