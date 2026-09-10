import Foundation
import Security

/// Stores the registered key handle. Apple retains the private key.
nonisolated struct KeychainAppAttestCredentialStore: AppAttestCredentialStore {
    private let service: String

    init(
        service: String = Bundle.main.bundleIdentifier.map { "\($0).AppAttest.Credentials" }
            ?? "AppAttest.Credentials"
    ) {
        self.service = service
    }

    func credential(named credentialName: String) throws -> AppAttestCredential? {
        var query = query(account: credentialName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AppAttestError.keychain(status: status) }
        guard let data = result as? Data else {
            throw AppAttestError.invalidConfiguration("Keychain returned non-data credential metadata.")
        }
        return try JSONDecoder().decode(AppAttestCredential.self, from: data)
    }

    func save(_ credential: AppAttestCredential) throws {
        let query = query(account: credential.credentialName)
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credential),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AppAttestError.keychain(status: status) }
        let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AppAttestError.keychain(status: addStatus) }
    }

    func delete(credentialName: String) throws {
        let status = SecItemDelete(query(account: credentialName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppAttestError.keychain(status: status)
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
