//
//  AppAttestDemoViewModel.swift
//  TAPCamDemo
//

import Combine
import Foundation

enum AppAttestDemoBackendMode: String, CaseIterable, Identifiable {
    #if DEBUG
    case mock
    #endif
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        #if DEBUG
        case .mock:
            "Mock Backend"
        #endif
        case .http:
            "HTTP Backend"
        }
    }
}

@MainActor
final class AppAttestDemoViewModel: ObservableObject {
    @Published var selectedBackendMode: AppAttestDemoBackendMode
    @Published var httpBaseURL = "https://example.com"
    @Published var credentialName = "installation_keyid"
    @Published var requestMethod = "POST"
    @Published var requestPath = "/api/protected/demo"
    @Published var requestBody = #"{"demo":true}"#
    @Published var statusText = "Step 1: enter a credential name.\nStep 2: prepare the credential.\nStep 3: sign one protected request."
    @Published var headersText = ""
    @Published var debugJSON = ""
    @Published var attestationObjectDocument: AppAttestCBORDocument?
    @Published var isAttestationExporterPresented = false
    @Published private(set) var isWorking = false
    @Published private(set) var backendDescription: String

    private var appAttest: any AppAttestClient
    private var activeOperationCount = 0
    #if DEBUG
    private var debugBackend: MockDebugAppAttestBackend?
    #endif

    init(runtime: AppAttestRuntime) {
        self.appAttest = runtime.client
        self.backendDescription = runtime.backendDescription
        #if DEBUG
        self.debugBackend = runtime.debugBackend
        self.selectedBackendMode = runtime.debugBackend == nil ? .http : .mock
        #else
        self.selectedBackendMode = .http
        #endif
    }

    var shouldShowHTTPSettings: Bool {
        selectedBackendMode == .http
    }

    var isDebugExportAvailable: Bool {
        #if DEBUG
        return debugBackend != nil
        #else
        return false
        #endif
    }

    func applyBackendSelection() {
        do {
            let mode: AppAttestBackendMode
            switch selectedBackendMode {
            #if DEBUG
            case .mock:
                mode = .mockDebug
            #endif
            case .http:
                guard let baseURL = URL(string: httpBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw AppAttestError.invalidConfiguration("HTTP Backend URL is invalid.")
                }
                mode = .http(baseURL: baseURL)
            }

            install(runtime: try AppAttestRuntimeFactory.make(mode: mode))
            headersText = ""
            debugJSON = ""
            statusText = """
            Backend changed.
            \(backendDescription)
            """
        } catch {
            install(runtime: AppAttestRuntimeFactory.fallbackRuntime(error: error))
            statusText = "Backend configuration failed\n\(error.localizedDescription)"
        }
    }

    func prepare() {
        runOperation("Register new key") {
            let credential = try await self.appAttest.prepare(credentialName: self.cleanedCredentialName())
            self.statusText = """
            Registered a new App Attest key.
            credentialName: \(credential.credentialName)
            keyId: \(credential.keyId)
            \(try await self.latestChallengeText())
            """
        }
    }

    func prepareIfNeeded() {
        runOperation("Prepare credential") {
            let credential = try await self.appAttest.prepareIfNeeded(credentialName: self.cleanedCredentialName())
            self.statusText = """
            Credential is ready.
            credentialName: \(credential.credentialName)
            keyId: \(credential.keyId)
            \(try await self.latestChallengeText())
            """
        }
    }

    func generateAssertion() {
        runOperation("Sign protected request") {
            let request = AppAttestProtectedRequest(
                method: self.requestMethod,
                path: self.cleanedRequestPath(),
                body: Data(self.requestBody.utf8)
            )
            let envelope = try await self.appAttest.generateAssertion(
                credentialName: self.cleanedCredentialName(),
                request: request
            )
            var urlRequest = URLRequest(url: self.demoURL(path: request.path))
            try envelope.applyHeaders(to: &urlRequest)
            self.headersText = Self.formatHeaders(urlRequest.allHTTPHeaderFields ?? [:])
            self.statusText = """
            Protected request headers are ready.
            credentialName: \(envelope.credentialName)
            challengeId: \(envelope.challengeId)
            """
        }
    }

    func refreshStatus() {
        runOperation("Check status") {
            let name = try self.cleanedCredentialName()
            let status = try await self.appAttest.status(credentialName: name)
            self.statusText = """
            Credential status:
            credentialName: \(name)
            status: \(status.rawValue)
            """
        }
    }

    func reset() {
        runOperation("Reset local credential") {
            let name = try self.cleanedCredentialName()
            try await self.appAttest.reset(credentialName: name)
            self.statusText = """
            Local credential metadata was reset.
            credentialName: \(name)
            Run Prepare Credential before signing requests again.
            """
            self.headersText = ""
        }
    }

    func exportDebugJSON() {
        #if DEBUG
        guard let debugBackend else {
            debugJSON = "No DEBUG mock backend is active."
            return
        }

        runOperation("Export debug JSON") {
            self.debugJSON = try await debugBackend.exportDebugJSONString()
        }
        #endif
    }

    func handleAttestationObjectExportResult(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            statusText = "Saved attestationObject.cbor\n\(url.lastPathComponent)"
        case .failure(let error):
            statusText = "Save attestationObject.cbor failed\n\(error.localizedDescription)"
        }
    }

    func saveAttestationObject() {
        #if DEBUG
        guard let debugBackend else {
            statusText = "No DEBUG mock backend is active."
            return
        }

        runOperation("Prepare attestationObject file") {
            let data = try await debugBackend.latestAttestationObject()
            self.attestationObjectDocument = AppAttestCBORDocument(data: data)
            self.isAttestationExporterPresented = true
            self.statusText = "Choose where to save attestationObject.cbor."
        }
        #endif
    }

    private func cleanedCredentialName() throws -> String {
        let name = credentialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppAttestError.invalidConfiguration("credentialName cannot be empty.")
        }
        return name
    }

    private func cleanedRequestPath() -> String {
        let path = requestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return "/"
        }
        return path.hasPrefix("/") ? path : "/\(path)"
    }

    private func demoURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.com"
        components.path = path
        return components.url ?? URL(string: "https://example.com/")!
    }

    private func install(runtime: AppAttestRuntime) {
        appAttest = runtime.client
        backendDescription = runtime.backendDescription
        #if DEBUG
        debugBackend = runtime.debugBackend
        #endif
    }

    private func latestChallengeText() async throws -> String {
        #if DEBUG
        guard let debugBackend else {
            return "challenge: issued by HTTP Backend"
        }
        let challenge = try await debugBackend.latestChallenge()
        let challengeString = String(data: challenge.challenge, encoding: .utf8) ?? challenge.challenge.appAttestBase64URL
        return """
        challengeId: \(challenge.challengeId)
        challenge: \(challengeString)
        """
        #else
        return "challenge: issued by HTTP Backend"
        #endif
    }

    private func runOperation(_ label: String, operation: @escaping () async throws -> Void) {
        activeOperationCount += 1
        isWorking = activeOperationCount > 0
        statusText = "\(label)..."

        Task {
            defer {
                activeOperationCount -= 1
                isWorking = activeOperationCount > 0
            }

            do {
                try await operation()
            } catch {
                statusText = "\(label) failed\n\(error.localizedDescription)"
            }
        }
    }

    private static func formatHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}
