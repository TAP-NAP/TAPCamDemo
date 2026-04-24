//
//  AppAttestDemoViewModel.swift
//  TAPCamDemo
//

import Combine
import Foundation

@MainActor
final class AppAttestDemoViewModel: ObservableObject {
    @Published var subjectType = "demo"
    @Published var subjectId = "caller-owned-subject-id"
    @Published var requestMethod = "POST"
    @Published var requestPath = "/api/protected/demo"
    @Published var requestBody = #"{"demo":true}"#
    @Published var statusText = "Step 1: enter a backend credential scope.\nStep 2: run Ensure Attested to register an App Attest key.\nStep 3: generate an assertion for one protected request."
    @Published var headersText = ""
    @Published var debugJSON = ""
    @Published var attestationObjectDocument: AppAttestCBORDocument?
    @Published var isAttestationExporterPresented = false
    @Published var isWorking = false

    let backendDescription: String

    private let appAttest: any AppAttestClient
    #if DEBUG
    private let debugBackend: LocalDebugAppAttestBackend?
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
            let credential = try await self.appAttest.prepare(subject: self.currentSubject())
            self.statusText = """
            Attestation registered a new key.
            subject: \(credential.subject.type):\(credential.subject.id)
            keyId: \(credential.keyId)
            """
        }
    }

    func prepareIfNeeded() {
        runOperation("Ensure attested") {
            let credential = try await self.appAttest.prepareIfNeeded(subject: self.currentSubject())
            self.statusText = """
            Subject is attested and ready.
            subject: \(credential.subject.type):\(credential.subject.id)
            keyId: \(credential.keyId)
            """
        }
    }

    func generateAssertion() {
        runOperation("Generate assertion") {
            let request = AppAttestProtectedRequest(
                method: self.requestMethod,
                path: self.requestPath,
                body: Data(self.requestBody.utf8)
            )
            let envelope = try await self.appAttest.generateAssertion(
                subject: self.currentSubject(),
                request: request
            )
            var urlRequest = URLRequest(url: URL(string: "https://example.com\(self.requestPath)")!)
            try envelope.applyHeaders(to: &urlRequest)
            self.headersText = Self.formatHeaders(urlRequest.allHTTPHeaderFields ?? [:])
            self.statusText = """
            Assertion generated for one request.
            subject: \(envelope.subject.type):\(envelope.subject.id)
            challengeId: \(envelope.challengeId)
            """
        }
    }

    func refreshStatus() {
        runOperation("Check credential") {
            let status = try await self.appAttest.status(subject: self.currentSubject())
            self.statusText = """
            Credential status for selected subject:
            subject: \(self.currentSubject().type):\(self.currentSubject().id)
            status: \(status.rawValue)
            """
        }
    }

    func reset() {
        runOperation("Reset") {
            try await self.appAttest.reset(subject: self.currentSubject())
            self.statusText = """
            Local credential metadata was reset.
            subject: \(self.currentSubject().type):\(self.currentSubject().id)
            Run Ensure Attested before generating assertions again.
            """
            self.headersText = ""
        }
    }

    func exportDebugJSON() {
        #if DEBUG
        guard let debugBackend else {
            debugJSON = "No DEBUG local backend is active."
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
            statusText = "No DEBUG local backend is active."
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

    private func currentSubject() -> AppAttestSubject {
        AppAttestSubject(type: subjectType, id: subjectId)
    }

    private func runOperation(_ label: String, operation: @escaping () async throws -> Void) {
        isWorking = true
        statusText = "\(label)..."

        Task {
            do {
                try await operation()
            } catch {
                statusText = "\(label) failed\n\(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private static func formatHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}
