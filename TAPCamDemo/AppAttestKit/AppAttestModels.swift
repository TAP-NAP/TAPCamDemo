//
//  AppAttestModels.swift
//  TAPCamDemo
//

import CryptoKit
import Foundation

public nonisolated enum AppAttestPurpose: String, Codable, Hashable {
    case attestation
    case assertion
}

public nonisolated enum AppAttestEnvironment: String, Codable, Hashable {
    case development
    case production
}

public nonisolated enum AppAttestCredentialStatus: String, Codable, Hashable {
    case notPrepared
    case ready
    case revoked
    case unknown
}

public nonisolated enum AppAttestRegistrationStatus: String, Codable, Hashable {
    case accepted
    case rejected
}

public nonisolated enum AppAttestServerCredentialStatus: String, Codable, Hashable {
    case accepted
    case revoked
    case unknown
}

public nonisolated struct AppAttestCredential: Codable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String
    public let credentialId: String?
    public let status: AppAttestCredentialStatus
    public let environment: AppAttestEnvironment
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        subject: AppAttestSubject,
        keyId: String,
        credentialId: String?,
        status: AppAttestCredentialStatus,
        environment: AppAttestEnvironment,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.subject = subject
        self.keyId = keyId
        self.credentialId = credentialId
        self.status = status
        self.environment = environment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public nonisolated struct AppAttestChallengeRequest: Codable, Hashable {
    public let purpose: AppAttestPurpose
    public let subject: AppAttestSubject

    public init(purpose: AppAttestPurpose, subject: AppAttestSubject) {
        self.purpose = purpose
        self.subject = subject
    }

    private enum CodingKeys: String, CodingKey {
        case purpose
        case subjectType
        case subjectId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .subjectType)
        let id = try container.decode(String.self, forKey: .subjectId)
        self.init(
            purpose: try container.decode(AppAttestPurpose.self, forKey: .purpose),
            subject: AppAttestSubject(type: type, id: id)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(subject.type, forKey: .subjectType)
        try container.encode(subject.id, forKey: .subjectId)
    }
}

public nonisolated struct AppAttestChallenge: Codable, Hashable {
    public let challengeId: String
    public let challenge: Data
    public let expiresAt: Date?

    public init(challengeId: String, challenge: Data, expiresAt: Date?) {
        self.challengeId = challengeId
        self.challenge = challenge
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case challenge
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try container.decode(String.self, forKey: .challengeId)
        self.challenge = try AppAttestBase64URL.decode(
            try container.decode(String.self, forKey: .challenge),
            field: "challenge"
        )
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(challenge.appAttestBase64URL, forKey: .challenge)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

public nonisolated struct AppAttestRegistrationRequest: Encodable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String
    public let challengeId: String
    public let attestationObject: Data

    public init(
        subject: AppAttestSubject,
        keyId: String,
        challengeId: String,
        attestationObject: Data
    ) {
        self.subject = subject
        self.keyId = keyId
        self.challengeId = challengeId
        self.attestationObject = attestationObject
    }

    private enum CodingKeys: String, CodingKey {
        case subjectType
        case subjectId
        case keyId
        case challengeId
        case attestationObject
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subject.type, forKey: .subjectType)
        try container.encode(subject.id, forKey: .subjectId)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(attestationObject.appAttestBase64URL, forKey: .attestationObject)
    }
}

public nonisolated struct AppAttestRegistrationResult: Codable, Hashable {
    public let credentialId: String?
    public let status: AppAttestRegistrationStatus

    public init(credentialId: String?, status: AppAttestRegistrationStatus) {
        self.credentialId = credentialId
        self.status = status
    }
}

public nonisolated struct AppAttestCredentialStatusRequest: Codable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String?

    public init(subject: AppAttestSubject, keyId: String?) {
        self.subject = subject
        self.keyId = keyId
    }
}

public nonisolated struct AppAttestQueryItem: Codable, Hashable {
    public let name: String
    public let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}

/// Request data that should be bound into an App Attest assertion.
public nonisolated struct AppAttestProtectedRequest: Hashable {
    public let method: String
    public let path: String
    public let query: [AppAttestQueryItem]
    public let body: Data?
    public let nonce: String?

    public init(
        method: String,
        path: String,
        query: [AppAttestQueryItem] = [],
        body: Data? = nil,
        nonce: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.nonce = nonce
    }

    func binding(challenge: Data) -> AppAttestRequestBinding {
        let sortedQuery = query.sorted {
            if $0.name == $1.name {
                return ($0.value ?? "") < ($1.value ?? "")
            }
            return $0.name < $1.name
        }

        return AppAttestRequestBinding(
            method: method.uppercased(),
            path: path,
            query: sortedQuery,
            bodySHA256: Self.sha256(body ?? Data()),
            challengeSHA256: Self.sha256(challenge),
            nonce: nonce
        )
    }

    private static func sha256(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).appAttestBase64URL
    }
}

public nonisolated struct AppAttestRequestBinding: Codable, Hashable {
    public let method: String
    public let path: String
    public let query: [AppAttestQueryItem]
    public let bodySHA256: String
    public let challengeSHA256: String
    public let nonce: String?

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder.appAttestCanonical
        return try encoder.encode(self)
    }

    public func clientDataHash() throws -> Data {
        Data(SHA256.hash(data: try canonicalData()))
    }

    public func headerValue() throws -> String {
        try canonicalData().appAttestBase64URL
    }
}

public nonisolated struct AppAttestAssertionEnvelope: Encodable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String
    public let challengeId: String
    public let assertionObject: Data
    public let requestBinding: AppAttestRequestBinding

    public init(
        subject: AppAttestSubject,
        keyId: String,
        challengeId: String,
        assertionObject: Data,
        requestBinding: AppAttestRequestBinding
    ) {
        self.subject = subject
        self.keyId = keyId
        self.challengeId = challengeId
        self.assertionObject = assertionObject
        self.requestBinding = requestBinding
    }

    private enum CodingKeys: String, CodingKey {
        case subjectType
        case subjectId
        case keyId
        case challengeId
        case assertionObject
        case requestBinding
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subject.type, forKey: .subjectType)
        try container.encode(subject.id, forKey: .subjectId)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(assertionObject.appAttestBase64URL, forKey: .assertionObject)
        try container.encode(requestBinding, forKey: .requestBinding)
    }

    /// Applies assertion metadata to a caller-owned business request.
    ///
    /// The kit never intercepts requests automatically; callers opt in by
    /// applying this envelope only to APIs that should be protected.
    public func applyHeaders(to request: inout URLRequest) throws {
        request.setValue(subject.type, forHTTPHeaderField: "X-App-Attest-Subject-Type")
        request.setValue(subject.id, forHTTPHeaderField: "X-App-Attest-Subject-Id")
        request.setValue(keyId, forHTTPHeaderField: "X-App-Attest-Key-Id")
        request.setValue(challengeId, forHTTPHeaderField: "X-App-Attest-Challenge-Id")
        request.setValue(assertionObject.appAttestBase64URL, forHTTPHeaderField: "X-App-Attest-Assertion")
        request.setValue(try requestBinding.headerValue(), forHTTPHeaderField: "X-App-Attest-Request-Binding")
    }
}

public nonisolated struct AppAttestAssertionRecord: Encodable, Hashable {
    public let subject: AppAttestSubject
    public let keyId: String
    public let challengeId: String
    public let assertionObject: Data
    public let requestBinding: AppAttestRequestBinding
    public let createdAt: Date

    public init(
        subject: AppAttestSubject,
        keyId: String,
        challengeId: String,
        assertionObject: Data,
        requestBinding: AppAttestRequestBinding,
        createdAt: Date
    ) {
        self.subject = subject
        self.keyId = keyId
        self.challengeId = challengeId
        self.assertionObject = assertionObject
        self.requestBinding = requestBinding
        self.createdAt = createdAt
    }

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

public nonisolated extension JSONEncoder {
    static var appAttestCanonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var appAttestPretty: JSONEncoder {
        let encoder = JSONEncoder.appAttestCanonical
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public nonisolated extension JSONDecoder {
    static var appAttestDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
