//
//  AppAttestDemoViewModel.swift
//  TAPCamDemo
//

import Combine
import Foundation

@MainActor
final class AppAttestDemoViewModel: ObservableObject {
    @Published var credentialName = "demo:nearbycommunity"
    @Published var requestMethod = "POST"
    @Published var requestPath = "/api/protected/demo"
    @Published var requestBody = #"{"demo":true}"#
    @Published var statusText = "Step 1: enter a credential name.\nStep 2: run Ensure Attested to register an App Attest key.\nStep 3: generate an assertion for one protected request."
    @Published var headersText = ""
    @Published var debugJSON = ""
    @Published var attestationObjectDocument: AppAttestCBORDocument?
    @Published var isAttestationExporterPresented = false
    @Published private(set) var isWorking = false

    let backendDescription: String

    private let appAttest: any AppAttestClient
    private var activeOperationCount = 0
    #if DEBUG
    private let debugBackend: MockDebugAppAttestBackend?
    #endif

    init(runtime: AppAttestRuntime) {
        self.appAttest = runtime.client
        self.backendDescription = runtime.backendDescription
        #if DEBUG
        self.debugBackend = runtime.debugBackend
        #endif
    }

    var isDebugExportAvailable: Bool {
        #if DEBUG
        return debugBackend != nil
        #else
        return false
        #endif
    }

    func prepare() {
        runOperation("Force new attestation") {
            let credential = try await self.appAttest.prepare(credentialName: self.cleanedCredentialName())
            self.statusText = """
            Attestation registered a new key.
            credentialName: \(credential.credentialName)
            keyId: \(credential.keyId)
            """
        }
    }

    func prepareIfNeeded() {
        runOperation("Ensure attested") {
            let credential = try await self.appAttest.prepareIfNeeded(credentialName: self.cleanedCredentialName())
            self.statusText = """
            Credential is attested and ready.
            credentialName: \(credential.credentialName)
            keyId: \(credential.keyId)
            """
        }
    }

    func generateAssertion() {
        runOperation("Generate assertion") {
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
            Assertion generated for one request.
            credentialName: \(envelope.credentialName)
            challengeId: \(envelope.challengeId)
            """
        }
    }

    func refreshStatus() {
        runOperation("Check credential") {
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
        runOperation("Reset") {
            let name = try self.cleanedCredentialName()
            try await self.appAttest.reset(credentialName: name)
            self.statusText = """
            Local credential metadata was reset.
            credentialName: \(name)
            Run Ensure Attested before generating assertions again.
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
