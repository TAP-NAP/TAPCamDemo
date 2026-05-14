//
//  AppAttestRuntime.swift
//  TAPCamDemo
//

import Foundation
import AppAttestKit

enum AppAttestBackendConfiguration {
    private static let backendURLKey = "APP_ATTEST_BACKEND_URL"

    static func baseURL(from bundle: Bundle = .main) throws -> URL {
        try parse(backendURL: bundle.appAttestConfigurationValue(for: backendURLKey))
    }

    static func parse(backendURL rawBackendURL: String?) throws -> URL {
        guard let rawBackendURL else {
            throw AppAttestError.invalidConfiguration("Set APP_ATTEST_BACKEND_URL to an https App Attest server URL.")
        }

        guard let components = URLComponents(string: rawBackendURL),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              !isUnsupportedHost(host),
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil,
              let url = components.url else {
            throw AppAttestError.invalidConfiguration("APP_ATTEST_BACKEND_URL must be an https base URL with a domain host.")
        }

        return url
    }

    private static func isUnsupportedHost(_ host: String) -> Bool {
        let lowercasedHost = host.lowercased()
        if lowercasedHost == "localhost" {
            return true
        }

        if lowercasedHost.contains(":") {
            return true
        }

        let segments = lowercasedHost.split(separator: ".")
        guard segments.count == 4 else {
            return false
        }

        return segments.allSatisfy { segment in
            guard let value = Int(segment), (0...255).contains(value) else {
                return false
            }
            return true
        }
    }
}

struct AppAttestRuntime {
    let client: any AppAttestClient
    let backendURL: URL?
    let environment: AppAttestEnvironment?
    let backendDescription: String

    init(
        client: any AppAttestClient,
        backendURL: URL? = nil,
        environment: AppAttestEnvironment? = nil,
        backendDescription: String
    ) {
        self.client = client
        self.backendURL = backendURL
        self.environment = environment
        self.backendDescription = backendDescription
    }
}

enum AppAttestRuntimeFactory {
    #if DEBUG
    static let configuredEnvironment: AppAttestEnvironment = .development
    #else
    static let configuredEnvironment: AppAttestEnvironment = .production
    #endif

    #if DEBUG
    static func make(
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) throws -> AppAttestRuntime {
        try make(baseURL: AppAttestBackendConfiguration.baseURL(), progressHandler: progressHandler)
    }

    static func make(
        baseURL: URL,
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) throws -> AppAttestRuntime {
        let backend = try HTTPAppAttestBackend(baseURL: baseURL)
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: KeychainAppAttestCredentialStore(),
            deviceService: DCAppAttestDeviceService(),
            environment: configuredEnvironment,
            progressHandler: progressHandler
        )

        return AppAttestRuntime(
            client: client,
            backendURL: baseURL,
            environment: configuredEnvironment,
            backendDescription: "HTTP Backend: \(baseURL.absoluteString)"
        )
    }
    #else
    static func make() throws -> AppAttestRuntime {
        try make(baseURL: AppAttestBackendConfiguration.baseURL())
    }

    static func make(baseURL: URL) throws -> AppAttestRuntime {
        let backend = try HTTPAppAttestBackend(baseURL: baseURL)
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: KeychainAppAttestCredentialStore(),
            deviceService: DCAppAttestDeviceService(),
            environment: configuredEnvironment
        )

        return AppAttestRuntime(
            client: client,
            backendURL: baseURL,
            environment: configuredEnvironment,
            backendDescription: "HTTP Backend: \(baseURL.absoluteString)"
        )
    }
    #endif

    static func fallbackRuntime(error: Error) -> AppAttestRuntime {
        AppAttestRuntime(
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)"
        )
    }
}

enum AppAttestRuntimeDefaults {
    static let photoCredentialName = "photo_keyid"
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

private extension Bundle {
    func appAttestConfigurationValue(for key: String) -> String? {
        guard let rawValue = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !trimmedValue.contains("$(") else {
            return nil
        }
        return trimmedValue
    }
}
