import DeviceCheck
import Foundation
import Security

nonisolated protocol AppAttestClient: Sendable {
    func prepare(credentialName: String) async throws -> AppAttestCredential
    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential
    func validateCredential(credentialName: String) async throws
    func reset(credentialName: String) async throws
}

nonisolated enum AppAttestEnvironment: String, Sendable {
    case development, production
}

nonisolated struct AppAttestCredential: Codable, Sendable {
    let credentialName: String
    let keyId: String
}

nonisolated protocol AppAttestCredentialStore: Sendable {
    func credential(named credentialName: String) throws -> AppAttestCredential?
    func save(_ credential: AppAttestCredential) throws
    func delete(credentialName: String) throws
}

nonisolated protocol AppAttestDeviceService: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

// The system service owns its key material and supports calls from multiple queues.
nonisolated final class DCAppAttestDeviceService: AppAttestDeviceService, @unchecked Sendable {
    private let service: DCAppAttestService

    init(service: DCAppAttestService = .shared) {
        self.service = service
    }

    var isSupported: Bool { service.isSupported }

    func generateKey() async throws -> String {
        try await service.generateKey()
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.attestKey(keyId, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

nonisolated enum AppAttestError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedDevice
    case invalidConfiguration(String)
    case invalidBase64URL(field: String)
    case invalidHTTPResponse
    case backendUnavailable(String)
    case challengeRejected(String)
    case attestationRejected(String)
    case credentialMissing(String)
    case keychain(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: "This device does not support App Attest."
        case .invalidConfiguration(let message): message
        case .invalidBase64URL(let field): "Invalid base64url value for \(field)."
        case .invalidHTTPResponse: "The App Attest backend returned an invalid HTTP response."
        case .backendUnavailable(let message): "The App Attest backend is unavailable: \(message)"
        case .challengeRejected(let message): "The App Attest challenge was rejected: \(message)"
        case .attestationRejected(let message): "The App Attest registration was rejected: \(message)"
        case .credentialMissing(let name): "No App Attest credential exists for \(name)."
        case .keychain(let status): "Keychain operation failed with status \(status)."
        }
    }
}
