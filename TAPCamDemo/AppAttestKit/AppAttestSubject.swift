//
//  AppAttestSubject.swift
//  TAPCamDemo
//

import Foundation

/// Backend-defined scope used to index an App Attest credential.
///
/// The kit does not create, persist, or interpret install IDs, user IDs, tenant
/// IDs, or session IDs. This value is not an Apple attestation claim. It is only
/// sent to the backend and used locally to choose which registered keyId should
/// be reused for later assertions.
public nonisolated struct AppAttestSubject: Hashable, Codable {
    public let type: String
    public let id: String

    var storageKey: String {
        "\(type)#\(id)"
    }

    public init(type: String, id: String) {
        self.type = type
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            type: try container.decode(String.self, forKey: .type),
            id: try container.decode(String.self, forKey: .id)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
    }
}
