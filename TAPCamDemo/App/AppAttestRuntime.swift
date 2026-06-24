//
//  AppAttestRuntime.swift
//  TAPCamDemo
//

import Foundation
import AppAttestKit
import OSLog

nonisolated enum TAPDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TAPCamDemo"

    static let appAttest = Logger(subsystem: subsystem, category: "AppAttest")
    static let cameraCapture = Logger(subsystem: subsystem, category: "CameraCapture")
    static let pendingCapture = Logger(subsystem: subsystem, category: "PendingCapture")
    static let securityPreflight = Logger(subsystem: subsystem, category: "SecurityPreflight")
    static let photoLibrary = Logger(subsystem: subsystem, category: "PhotoLibrary")

    /// Public log-safe error summary.
    ///
    /// `localizedDescription`, failing URLs, and raw network paths may contain
    /// endpoints, file paths, or device routing details. Keep those out of
    /// public OSLog fields while preserving domain/code and low-cardinality
    /// network hints for diagnosis.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if let streamDomain = firstUserInfoValue(for: "_kCFStreamErrorDomainKey", in: nsError) {
            parts.append("streamDomain=\(streamDomain)")
        }

        if let streamCode = firstUserInfoValue(for: "_kCFStreamErrorCodeKey", in: nsError) {
            parts.append("streamCode=\(streamCode)")
        }

        if let sslOriginalValue = firstUserInfoValue(for: "_kCFNetworkCFStreamSSLErrorOriginalValue", in: nsError) {
            parts.append("sslOriginalValue=\(sslOriginalValue)")
        }

        if let clientCertificateState = firstUserInfoValue(for: "_kCFStreamPropertySSLClientCertificateState", in: nsError) {
            parts.append("clientCertificateState=\(clientCertificateState)")
        }

        if errorLooksVPNRelated(error) {
            parts.append("vpnHint=true")
        }

        return parts.joined(separator: " ")
    }

    static func errorLooksVPNRelated(_ error: Error) -> Bool {
        guard let path = networkPathDescription(in: error as NSError)?.lowercased() else {
            return false
        }
        return path.contains("utun")
            || path.contains("vpn")
            || path.contains("198.18.")
    }

    private static func networkPathDescription(in error: NSError) -> String? {
        guard let value = firstUserInfoValue(for: "_NSURLErrorNWPathKey", in: error) else {
            return nil
        }
        return String(describing: value)
    }

    private static func firstUserInfoValue(for key: String, in error: NSError) -> Any? {
        if let value = error.userInfo[key] {
            return value
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return firstUserInfoValue(for: key, in: underlying)
        }
        return nil
    }
}

nonisolated enum AppAttestBackendConfiguration {
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
    let backendPublicSummary: String

    init(
        client: any AppAttestClient,
        backendURL: URL? = nil,
        environment: AppAttestEnvironment? = nil,
        backendDescription: String,
        backendPublicSummary: String? = nil
    ) {
        self.client = client
        self.backendURL = backendURL
        self.environment = environment
        self.backendDescription = backendDescription
        self.backendPublicSummary = backendPublicSummary ?? AppAttestBackendPresentation.publicSummary(
            backendURL: backendURL,
            backendDescription: backendDescription
        )
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
        let defaultClient = DefaultAppAttestClient(
            backend: backend,
            credentialStore: KeychainAppAttestCredentialStore(),
            deviceService: DCAppAttestDeviceService(),
            environment: configuredEnvironment,
            progressHandler: progressHandler
        )
        let client = LoggingAppAttestClient(wrapping: defaultClient)

        return AppAttestRuntime(
            client: client,
            backendURL: baseURL,
            environment: configuredEnvironment,
            backendDescription: "HTTP Backend configured",
            backendPublicSummary: AppAttestBackendPresentation.configuredHTTPBackendSummary
        )
    }
    #else
    static func make() throws -> AppAttestRuntime {
        try make(baseURL: AppAttestBackendConfiguration.baseURL())
    }

    static func make(baseURL: URL) throws -> AppAttestRuntime {
        let backend = try HTTPAppAttestBackend(baseURL: baseURL)
        let defaultClient = DefaultAppAttestClient(
            backend: backend,
            credentialStore: KeychainAppAttestCredentialStore(),
            deviceService: DCAppAttestDeviceService(),
            environment: configuredEnvironment
        )
        let client = LoggingAppAttestClient(wrapping: defaultClient)

        return AppAttestRuntime(
            client: client,
            backendURL: baseURL,
            environment: configuredEnvironment,
            backendDescription: "HTTP Backend configured",
            backendPublicSummary: AppAttestBackendPresentation.configuredHTTPBackendSummary
        )
    }
    #endif

    static func fallbackRuntime(error: Error) -> AppAttestRuntime {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.error("runtime configuration fallback error=\(TAPDiagnostics.describe(error), privacy: .public)")
        #endif
        return AppAttestRuntime(
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration unavailable",
            backendPublicSummary: AppAttestBackendPresentation.unavailableBackendSummary
        )
    }
}

enum AppAttestRuntimeDefaults {
    static let photoCredentialName = "photo_keyid"
}

private actor LoggingAppAttestClient: AppAttestClient {
    private let wrapped: any AppAttestClient

    init(wrapping wrapped: any AppAttestClient) {
        self.wrapped = wrapped
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        let operationID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("prepare start operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private)")
        #endif
        do {
            let credential = try await wrapped.prepare(credentialName: credentialName)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.info("prepare success operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) keyID=\(Self.keyIDSummary(credential.keyId), privacy: .private)")
            #endif
            return credential
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("prepare failed operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw error
        }
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        let operationID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("prepareIfNeeded start operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private)")
        #endif
        do {
            let credential = try await wrapped.prepareIfNeeded(credentialName: credentialName)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.info("prepareIfNeeded success operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) keyID=\(Self.keyIDSummary(credential.keyId), privacy: .private)")
            #endif
            return credential
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("prepareIfNeeded failed operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw error
        }
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        let operationID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("generateAssertion start operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) method=\(request.method, privacy: .public) path=\(request.path, privacy: .public)")
        #endif
        do {
            let assertion = try await wrapped.generateAssertion(credentialName: credentialName, request: request)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.info("generateAssertion success operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) path=\(request.path, privacy: .public)")
            #endif
            return assertion
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("generateAssertion failed operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) path=\(request.path, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw error
        }
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        let operationID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("status start operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private)")
        #endif
        do {
            let status = try await wrapped.status(credentialName: credentialName)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.info("status success operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) status=\(String(describing: status), privacy: .public)")
            #endif
            return status
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("status failed operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw error
        }
    }

    func reset(credentialName: String) async throws {
        let operationID = UUID().uuidString
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.appAttest.info("reset start operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private)")
        #endif
        do {
            try await wrapped.reset(credentialName: credentialName)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.info("reset success operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private)")
            #endif
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("reset failed operationID=\(operationID, privacy: .public) credentialName=\(credentialName, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw error
        }
    }

    private nonisolated static func keyIDSummary(_ keyID: String) -> String {
        guard keyID.count > 8 else {
            return keyID
        }
        return "\(keyID.prefix(8))...len\(keyID.count)"
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

private extension Bundle {
    nonisolated func appAttestConfigurationValue(for key: String) -> String? {
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
