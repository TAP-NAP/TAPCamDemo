//
//  KeychainAppAttestCredentialStore.swift
//  TAPCamDemo
//

import Foundation
import Security

/// Keychain-backed storage for App Attest key metadata.
public actor KeychainAppAttestCredentialStore: AppAttestCredentialStore {
    private let service: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        service: String = "TAPCamDemo.AppAttestKit.Credentials",
        encoder: JSONEncoder = .appAttestCanonical,
        decoder: JSONDecoder = .appAttestDefault
    ) {
        self.service = service
        self.encoder = encoder
        self.decoder = decoder
    }

    public func credential(for subject: AppAttestSubject) async throws -> AppAttestCredential? {
        var query = baseQuery(for: subject)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw AppAttestError.keychain(status: status)
        }

        guard let data = result as? Data else {
            throw AppAttestError.keychain(status: errSecInternalError)
        }

        return try decoder.decode(AppAttestCredential.self, from: data)
    }

    public func save(_ credential: AppAttestCredential) async throws {
        let data = try encoder.encode(credential)
        let query = baseQuery(for: credential.subject)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AppAttestError.keychain(status: updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppAttestError.keychain(status: addStatus)
        }
    }

    public func delete(subject: AppAttestSubject) async throws {
        let status = SecItemDelete(baseQuery(for: subject) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppAttestError.keychain(status: status)
        }
    }

    private func baseQuery(for subject: AppAttestSubject) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: subject.storageKey
        ]
    }
}
