//
//  CameraRouteContextStore.swift
//  TAPCamDemo
//

import CryptoKit
import Foundation
import Security

/// In-memory identity for one visible TAP Library item.
///
/// Raw item, capture, and Photos identifiers are used only while resolving the
/// current album list. The durable context stores HMAC tokens derived from these
/// values, never the identifiers themselves.
nonisolated struct CameraRouteAlbumAnchor: Equatable, Sendable {
    private static let maximumIdentifierUTF8Length = 2_048

    let itemID: String
    let captureID: String?
    let assetLocalIdentifier: String?

    init?(
        itemID: String,
        captureID: String? = nil,
        assetLocalIdentifier: String? = nil
    ) {
        guard let normalizedItemID = Self.normalizedIdentifier(itemID) else {
            return nil
        }
        self.itemID = normalizedItemID
        self.captureID = Self.normalizedIdentifier(captureID)
        self.assetLocalIdentifier = Self.normalizedIdentifier(assetLocalIdentifier)
    }

    var tokenInputs: [String] {
        var inputs = ["item:\(itemID)"]
        if let captureID {
            inputs.append("capture:\(captureID)")
        }
        if let assetLocalIdentifier {
            inputs.append("asset:\(assetLocalIdentifier)")
        }
        return inputs
    }

    static func normalizedIdentifier(_ id: String?) -> String? {
        guard let id else {
            return nil
        }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              trimmedID.utf8.count <= maximumIdentifierUTF8Length else {
            return nil
        }
        return trimmedID
    }
}

nonisolated struct CameraRouteContext: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultTimeToLive: TimeInterval = 24 * 60 * 60

    let schemaVersion: Int
    let updatedAt: Date
    let restoreAnchorTokens: [String]

    init(
        schemaVersion: Int = currentSchemaVersion,
        updatedAt: Date = Date(),
        restoreAnchorTokens: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.restoreAnchorTokens = Array(Set(restoreAnchorTokens)).sorted()
    }

    var isEmpty: Bool {
        restoreAnchorTokens.isEmpty
    }

    func isFresh(
        now: Date = Date(),
        timeToLive: TimeInterval = defaultTimeToLive
    ) -> Bool {
        schemaVersion == Self.currentSchemaVersion
            && now.timeIntervalSince(updatedAt) <= timeToLive
            && updatedAt <= now.addingTimeInterval(60)
    }
}

/// File-backed persistence for best-effort TAP Library scroll restoration.
///
/// The default location is Application Support, and writes reuse the same file
/// protection policy as local TAP photo artifacts. The persisted context stores
/// only HMAC tokens plus a short freshness window; route destination, raw item
/// identifiers, photo paths, manifest data, and proof material are intentionally
/// excluded.
nonisolated struct CameraRouteFileContextStore {
    private let contextURL: URL
    private let secretURL: URL
    private let fileManager: FileManager
    private let storagePolicy: TAPLocalArtifactStoragePolicy
    private let secretKey: SymmetricKey

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        storagePolicy: TAPLocalArtifactStoragePolicy = .privatePhotoArtifact
    ) {
        self.fileManager = fileManager
        self.storagePolicy = storagePolicy
        let baseURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.contextURL = baseURL.appendingPathComponent("CameraRouteContext.json")
        self.secretURL = baseURL.appendingPathComponent("CameraRouteContext.key")
        self.secretKey = Self.loadOrCreateSecretKey(
            at: secretURL,
            storagePolicy: storagePolicy,
            fileManager: fileManager
        )
    }

    func loadContext() -> CameraRouteContext {
        guard let data = try? Data(contentsOf: contextURL),
              let context = try? JSONDecoder().decode(CameraRouteContext.self, from: data),
              context.isFresh() else {
            return CameraRouteContext()
        }
        return context
    }

    func saveContext(_ context: CameraRouteContext) {
        do {
            try storagePolicy.createDirectoryIfNeeded(at: contextURL.deletingLastPathComponent(), fileManager: fileManager)
            let data = try JSONEncoder().encode(context)
            try storagePolicy.write(data, to: contextURL, fileManager: fileManager)
        } catch {
            // Route restoration is helpful, but it must never block capture.
        }
    }

    func token(for rawValue: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: Data(rawValue.utf8),
            using: secretKey
        )
        return code.map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let rootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return rootURL
            .appendingPathComponent("TAPCamDemo", isDirectory: true)
            .appendingPathComponent("CameraRoute", isDirectory: true)
    }

    private static func loadOrCreateSecretKey(
        at url: URL,
        storagePolicy: TAPLocalArtifactStoragePolicy,
        fileManager: FileManager
    ) -> SymmetricKey {
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            return SymmetricKey(data: data)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = status == errSecSuccess
            ? Data(bytes)
            : Data(UUID().uuidString.utf8)

        do {
            try storagePolicy.createDirectoryIfNeeded(at: url.deletingLastPathComponent(), fileManager: fileManager)
            try storagePolicy.write(data, to: url, fileManager: fileManager)
        } catch {
            // A non-persisted fallback key only disables cross-launch restore.
        }
        return SymmetricKey(data: data)
    }
}
