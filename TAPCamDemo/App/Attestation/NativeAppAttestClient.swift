import CryptoKit
import Foundation

/// Registration and credential health for TAPCam. Capture signing stays offline.
actor NativeAppAttestClient: AppAttestClient {
    private let baseURL: URL
    private let credentialStore: any AppAttestCredentialStore
    private let deviceService: any AppAttestDeviceService
    private let urlSession: URLSession
    private var preparationTasks: [String: Task<AppAttestCredential, Error>] = [:]

    init(
        baseURL: URL,
        credentialStore: any AppAttestCredentialStore = KeychainAppAttestCredentialStore(),
        deviceService: any AppAttestDeviceService = DCAppAttestDeviceService(),
        urlSession: URLSession = .shared
    ) throws {
        _ = try AppAttestBackendConfiguration.parse(backendURL: baseURL.absoluteString)
        #if !DEBUG
        guard baseURL.host?.lowercased().hasSuffix(".local") != true else {
            throw AppAttestError.invalidConfiguration("Release builds cannot use a .local App Attest backend.")
        }
        #endif
        self.baseURL = baseURL
        self.credentialStore = credentialStore
        self.deviceService = deviceService
        self.urlSession = urlSession
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        let name = try normalizedName(credentialName)
        guard deviceService.isSupported else { throw AppAttestError.unsupportedDevice }
        let challenge = try await requestChallenge(purpose: "attestation", name: name)
        let keyID = try await deviceService.generateKey()
        let attestation = try await deviceService.attestKey(
            keyID, clientDataHash: Data(SHA256.hash(data: challenge.challenge))
        )
        let result: RegistrationResult = try await post(
            path: "app-attest/attestations",
            body: RegistrationRequest(
                credentialName: name, keyId: keyID, challengeId: challenge.challengeId,
                attestationObject: attestation.appAttestBase64URL
            )
        )
        guard result.status == "accepted" else {
            throw AppAttestError.attestationRejected("Backend registration returned \(result.status).")
        }
        let credential = AppAttestCredential(credentialName: name, keyId: keyID)
        try credentialStore.save(credential)
        return credential
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        let name = try normalizedName(credentialName)
        if let credential = try credentialStore.credential(named: name) { return credential }
        if let task = preparationTasks[name] { return try await task.value }
        let task = Task { try await self.prepare(credentialName: name) }
        preparationTasks[name] = task
        defer { preparationTasks.removeValue(forKey: name) }
        return try await task.value
    }

    func validateCredential(credentialName: String) async throws {
        let name = try normalizedName(credentialName)
        guard deviceService.isSupported else { throw AppAttestError.unsupportedDevice }
        guard let credential = try credentialStore.credential(named: name) else {
            throw AppAttestError.credentialMissing(name)
        }
        let challenge = try await requestChallenge(purpose: "assertion", name: name)
        let binding = HealthBinding(challengeSHA256: Data(SHA256.hash(data: challenge.challenge)).appAttestBase64URL)
        let hash = Data(SHA256.hash(data: try encode(binding)))
        _ = try await deviceService.generateAssertion(credential.keyId, clientDataHash: hash)
    }

    func reset(credentialName: String) async throws {
        try credentialStore.delete(credentialName: normalizedName(credentialName))
    }

    private func requestChallenge(purpose: String, name: String) async throws -> Challenge {
        let challenge: Challenge = try await post(
            path: "app-attest/challenges", body: ChallengeRequest(purpose: purpose, credentialName: name)
        )
        guard challenge.challenge.count >= 16 else {
            throw AppAttestError.challengeRejected("Challenge is shorter than 16 bytes.")
        }
        if let expiresAt = challenge.expiresAt, expiresAt <= Date() {
            throw AppAttestError.challengeRejected("Challenge expired.")
        }
        return challenge
    }

    private func post<Request: Encodable, Response: Decodable>(path: String, body: Request) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encode(body)
        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppAttestError.invalidHTTPResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw AppAttestError.backendUnavailable("HTTP \(response.statusCode)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        // Keep the health binding's existing slash escaping and key ordering.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func normalizedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppAttestError.invalidConfiguration("credentialName cannot be empty.") }
        return name
    }

    nonisolated private struct ChallengeRequest: Encodable {
        let purpose: String
        let credentialName: String
    }

    nonisolated private struct Challenge: Decodable {
        let challengeId: String
        let challenge: Data
        let expiresAt: Date?

        private enum CodingKeys: String, CodingKey { case challengeId, challenge, expiresAt }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            challengeId = try values.decode(String.self, forKey: .challengeId)
            challenge = try AppAttestBase64URL.decode(values.decode(String.self, forKey: .challenge), field: "challenge")
            expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt)
        }
    }

    nonisolated private struct RegistrationRequest: Encodable {
        let credentialName: String
        let keyId: String
        let challengeId: String
        let attestationObject: String
    }

    nonisolated private struct RegistrationResult: Decodable {
        let status: String
    }

    nonisolated private struct HealthBinding: Encodable {
        let method = "POST"
        let path = "/tapcam/app-attest/credential-health"
        let query: [String] = []
        let bodySHA256 = Data(SHA256.hash(data: Data(
            #"{"schemaID":"urn:tapnap:tapcam:app-attest-credential-health:v1"}"#.utf8
        ))).appAttestBase64URL
        let challengeSHA256: String
        let nonce = "tapcam-app-attest-credential-health"
    }
}
