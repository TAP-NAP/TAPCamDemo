//
//  LocalDebugAppAttestBackend.swift
//  TAPCamDemo
//

import Foundation
import Security

#if DEBUG
/// DEBUG-only backend that lets the app generate local challenges and export
/// App Attest objects when no server is available.
///
/// This does not perform production-grade attestation or assertion validation.
public actor LocalDebugAppAttestBackend: AppAttestBackend {
    private var challenges: [String: AppAttestDebugChallengeRecord] = [:]
    private var registrations: [AppAttestDebugRegistrationRecord] = []
    private var assertions: [AppAttestDebugAssertionRecord] = []

    public init() {}

    public func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        let challengeId = UUID().uuidString
        let challenge = try Self.randomData(byteCount: 32)
        let expiresAt = Date().addingTimeInterval(300)

        challenges[challengeId] = AppAttestDebugChallengeRecord(
            challengeId: challengeId,
            challenge: challenge,
            purpose: request.purpose,
            subject: request.subject,
            expiresAt: expiresAt,
            createdAt: Date()
        )

        return AppAttestChallenge(
            challengeId: challengeId,
            challenge: challenge,
            expiresAt: expiresAt
        )
    }

    public func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult {
        registrations.append(
            AppAttestDebugRegistrationRecord(
                subject: request.subject,
                keyId: request.keyId,
                challengeId: request.challengeId,
                attestationObject: request.attestationObject,
                createdAt: Date()
            )
        )

        return AppAttestRegistrationResult(
            credentialId: "local-debug-\(request.keyId)",
            status: .accepted
        )
    }

    public func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        .accepted
    }

    public func recordAssertionResult(_ record: AppAttestAssertionRecord) async {
        assertions.append(
            AppAttestDebugAssertionRecord(
                subject: record.subject,
                keyId: record.keyId,
                challengeId: record.challengeId,
                assertionObject: record.assertionObject,
                requestBinding: record.requestBinding,
                createdAt: record.createdAt
            )
        )
    }

    public func exportDebugData() throws -> Data {
        let export = AppAttestDebugExport(
            exportedAt: Date(),
            challenges: challenges.values.sorted { $0.createdAt < $1.createdAt },
            registrations: registrations,
            assertions: assertions
        )

        return try JSONEncoder.appAttestPretty.encode(export)
    }

    public func exportDebugJSONString() throws -> String {
        String(data: try exportDebugData(), encoding: .utf8) ?? "{}"
    }

    /// Returns the most recent raw attestation object produced by
    /// `DCAppAttestService.attestKey`.
    public func latestAttestationObject() throws -> Data {
        guard let registration = registrations.last else {
            throw AppAttestDebugExportError.noAttestationObject
        }
        return registration.attestationObject
    }

    /// Returns the most recent raw attestation object as base64url.
    public func latestAttestationObjectBase64URL() throws -> String {
        try latestAttestationObject().appAttestBase64URL
    }

    private static func randomData(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw AppAttestError.keychain(status: status)
        }
        return Data(bytes)
    }
}

public nonisolated enum AppAttestDebugExportError: Error, LocalizedError {
    case noAttestationObject

    public var errorDescription: String? {
        switch self {
        case .noAttestationObject:
            return "No attestationObject has been generated yet. Run attestation first."
        }
    }
}

public nonisolated struct AppAttestDebugExport: Encodable, Hashable {
    public let exportedAt: Date
    public let challenges: [AppAttestDebugChallengeRecord]
    public let registrations: [AppAttestDebugRegistrationRecord]
    public let assertions: [AppAttestDebugAssertionRecord]
}

public nonisolated struct AppAttestDebugChallengeRecord: Encodable, Hashable {
    public let challengeId: String
    public let challenge: Data
    public let purpose: AppAttestPurpose
    public let subject: AppAttestSubject
    public let expiresAt: Date
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case challenge
        case purpose
        case subject
        case expiresAt
        case createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(challenge.appAttestBase64URL, forKey: .challenge)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(subject, forKey: .subject)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public nonisolated struct AppAttestDebugRegistrationRecord: Encodable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String
    public let challengeId: String
    public let attestationObject: Data
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case subject
        case keyId
        case challengeId
        case attestationObject
        case attestationCertificates
        case attestationCertificateExportError
        case createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subject, forKey: .subject)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(attestationObject.appAttestBase64URL, forKey: .attestationObject)
        do {
            try container.encode(
                Self.attestationCertificates(from: attestationObject),
                forKey: .attestationCertificates
            )
        } catch {
            try container.encode(error.localizedDescription, forKey: .attestationCertificateExportError)
        }
        try container.encode(createdAt, forKey: .createdAt)
    }

    private static func attestationCertificates(from attestationObject: Data) throws -> [AppAttestDebugCertificate] {
        var decoder = AppAttestCBORDecoder(data: attestationObject)
        guard case .map(let root) = try decoder.decode(),
              case .map(let attestationStatement)? = root[text: "attStmt"],
              case .array(let certificateValues)? = attestationStatement[text: "x5c"] else {
            return []
        }

        return certificateValues.enumerated().compactMap { index, value in
            guard case .bytes(let der) = value else {
                return nil
            }
            return AppAttestDebugCertificate(index: index, der: der)
        }
    }
}

public nonisolated struct AppAttestDebugCertificate: Encodable, Hashable {
    public let index: Int
    public let der: Data

    private enum CodingKeys: String, CodingKey {
        case index
        case derBase64
        case derBase64URL
        case pem
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(der.base64EncodedString(), forKey: .derBase64)
        try container.encode(der.appAttestBase64URL, forKey: .derBase64URL)
        try container.encode(Self.pemString(from: der), forKey: .pem)
    }

    private static func pemString(from der: Data) -> String {
        let body = der.base64EncodedString()
            .chunkedForPEM()
            .joined(separator: "\n")
        return """
        -----BEGIN CERTIFICATE-----
        \(body)
        -----END CERTIFICATE-----
        """
    }
}

public nonisolated struct AppAttestDebugAssertionRecord: Encodable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String
    public let challengeId: String
    public let assertionObject: Data
    public let requestBinding: AppAttestRequestBinding
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case subject
        case keyId
        case challengeId
        case assertionObject
        case requestBinding
        case createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subject, forKey: .subject)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(assertionObject.appAttestBase64URL, forKey: .assertionObject)
        try container.encode(requestBinding, forKey: .requestBinding)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

private extension String {
    func chunkedForPEM() -> [String] {
        var chunks: [String] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 64, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[index..<nextIndex]))
            index = nextIndex
        }
        return chunks
    }
}
#else
@available(*, unavailable, message: "LocalDebugAppAttestBackend is DEBUG-only and cannot be used in Release builds.")
public final class LocalDebugAppAttestBackend {
    public init() {}
}
#endif
