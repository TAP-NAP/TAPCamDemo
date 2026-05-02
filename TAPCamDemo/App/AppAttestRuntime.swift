//
//  AppAttestRuntime.swift
//  TAPCamDemo
//

import Foundation
import AppAttestKit

enum AppAttestBackendMode: Hashable {
    case http(baseURL: URL)
    #if DEBUG
    case localDebug(challenge: String)
    #endif
}

enum AppAttestBackendSelection: String, CaseIterable, Identifiable {
    #if DEBUG
    case localDebug
    #endif
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        #if DEBUG
        case .localDebug:
            "Local Debug Backend"
        #endif
        case .http:
            "HTTP Backend"
        }
    }

    var showsHTTPSettings: Bool {
        self == .http
    }

    init(mode: AppAttestBackendMode?) {
        switch mode {
        #if DEBUG
        case .some(.localDebug(_)):
            self = .localDebug
        #endif
        case .some(.http(_)), .none:
            self = .http
        }
    }
}

struct AppAttestRuntime {
    let mode: AppAttestBackendMode?
    let client: any AppAttestClient
    let backendDescription: String
    #if DEBUG
    let debugBackend: LocalDebugAppAttestBackend?
    #endif

    #if DEBUG
    init(
        mode: AppAttestBackendMode? = nil,
        client: any AppAttestClient,
        backendDescription: String,
        debugBackend: LocalDebugAppAttestBackend? = nil
    ) {
        self.mode = mode
        self.client = client
        self.backendDescription = backendDescription
        self.debugBackend = debugBackend
    }
    #else
    init(mode: AppAttestBackendMode? = nil, client: any AppAttestClient, backendDescription: String) {
        self.mode = mode
        self.client = client
        self.backendDescription = backendDescription
    }
    #endif
}

enum AppAttestRuntimeFactory {
    #if DEBUG
    static func make(
        mode: AppAttestBackendMode = AppAttestRuntimeDefaults.mode,
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) throws -> AppAttestRuntime {
        switch mode {
        case .localDebug(let challenge):
            let backend = LocalDebugAppAttestBackend(challengeString: challenge)
            return AppAttestRuntime(
                mode: mode,
                client: DefaultAppAttestClient(
                    backend: backend,
                    credentialStore: KeychainAppAttestCredentialStore(),
                    deviceService: DCAppAttestDeviceService(),
                    environment: .development,
                    progressHandler: progressHandler
                ),
                backendDescription: "Local Debug Backend: \(challenge)",
                debugBackend: backend
            )

        case .http(let baseURL):
            let backend = try HTTPAppAttestBackend(baseURL: baseURL)
            let client = DefaultAppAttestClient(
                backend: backend,
                credentialStore: KeychainAppAttestCredentialStore(),
                deviceService: DCAppAttestDeviceService(),
                environment: .production,
                progressHandler: progressHandler
            )

            return AppAttestRuntime(
                mode: mode,
                client: client,
                backendDescription: "HTTP Backend: \(baseURL.absoluteString)",
                debugBackend: nil
            )
        }
    }
    #else
    static func make(mode: AppAttestBackendMode = AppAttestRuntimeDefaults.mode) throws -> AppAttestRuntime {
        switch mode {
        case .http(let baseURL):
            let backend = try HTTPAppAttestBackend(baseURL: baseURL)
            let client = DefaultAppAttestClient(
                backend: backend,
                credentialStore: KeychainAppAttestCredentialStore(),
                deviceService: DCAppAttestDeviceService(),
                environment: .production
            )

            return AppAttestRuntime(
                mode: mode,
                client: client,
                backendDescription: "HTTP Backend: \(baseURL.absoluteString)"
            )
        }
    }
    #endif

    static func fallbackRuntime(error: Error) -> AppAttestRuntime {
        #if DEBUG
        AppAttestRuntime(
            mode: nil,
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)",
            debugBackend: nil
        )
        #else
        AppAttestRuntime(
            mode: nil,
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)"
        )
        #endif
    }
}

enum AppAttestRuntimeDefaults {
    static let localDebugChallenge = "TapTapNapNap123123"
    static let httpBaseURLText = "https://example.com"

    static var mode: AppAttestBackendMode {
        #if DEBUG
        .localDebug(challenge: localDebugChallenge)
        #else
        .http(baseURL: URL(string: httpBaseURLText)!)
        #endif
    }

    static func httpBaseURLText(for mode: AppAttestBackendMode?) -> String {
        if case .http(let baseURL) = mode {
            return baseURL.absoluteString
        }
        return httpBaseURLText
    }

    static func mode(
        selection: AppAttestBackendSelection,
        httpBaseURLText: String
    ) throws -> AppAttestBackendMode {
        switch selection {
        #if DEBUG
        case .localDebug:
            return .localDebug(challenge: localDebugChallenge)
        #endif
        case .http:
            let trimmedBaseURL = httpBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let baseURL = URL(string: trimmedBaseURL) else {
                throw AppAttestError.invalidConfiguration("HTTP Backend URL is invalid.")
            }
            return .http(baseURL: baseURL)
        }
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
