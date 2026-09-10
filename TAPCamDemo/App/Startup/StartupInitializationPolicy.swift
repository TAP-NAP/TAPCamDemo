//
//  StartupInitializationPolicy.swift
//  TAPCamDemo
//

import Darwin
import Foundation
import Security

/// Build identity that invalidates Resource Initialization after an app update
/// or initialization-schema change. Permission and credential evidence do not
/// belong in this value.
nonisolated struct StartupInitializationRuntimeIdentity: Codable, Equatable, Sendable {
    static let currentStorageSchemaVersion = 1
    static let currentInitializationSchemaVersion = 1

    let bundleIdentifier: String
    let shortVersion: String
    let buildVersion: String
    let initializationSchemaVersion: Int

    static func current(
        bundle: Bundle = .main
    ) -> StartupInitializationRuntimeIdentity? {
        guard let bundleIdentifier = bundle.bundleIdentifier,
              let shortVersion = bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              !shortVersion.isEmpty,
              let buildVersion = bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
              ) as? String,
              !buildVersion.isEmpty else {
            return nil
        }
        return StartupInitializationRuntimeIdentity(
            bundleIdentifier: bundleIdentifier,
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            initializationSchemaVersion: currentInitializationSchemaVersion
        )
    }
}

/// Canonical independent `I` marker. It is one encoded value written only
/// after both Camera interaction and the first usable Library catalog are
/// ready.
nonisolated struct InitializationCompletion: Codable, Equatable, Sendable {
    let storageSchemaVersion: Int
    let runtimeIdentity: StartupInitializationRuntimeIdentity
    let installationGenerationID: UUID
    let deviceGenerationID: UUID
    let completedAt: Date
}

nonisolated enum StartupInitializationInvalidReason: Equatable, Sendable {
    case corruptMarker
    case unsupportedStorageSchema
    case bundleMismatch
    case shortVersionMismatch
    case buildVersionMismatch
    case initializationSchemaMismatch
    case installationGenerationMismatch
    case deviceGenerationMismatch
    case deviceGenerationUnavailable
    case runtimeIdentityUnavailable
    case storageUnavailable
    case capabilitySnapshotUnavailable
}

nonisolated enum StartupInitializationFact: Equatable, Sendable {
    case missing
    case current(InitializationCompletion)
    case invalid(StartupInitializationInvalidReason)

    var isCurrent: Bool {
        if case .current = self {
            return true
        }
        return false
    }
}

nonisolated protocol StartupDeviceGenerationProviding: Sendable {
    func currentOrCreate() -> UUID?
}

/// A non-migrating local device-generation token. The value is independent of
/// App Attest and performs no network work. `ThisDeviceOnly` prevents a restored
/// UserDefaults marker from validating on another device.
nonisolated struct KeychainStartupDeviceGenerationStore:
    StartupDeviceGenerationProviding,
    @unchecked Sendable
{
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier.map {
            "\($0).StartupLifecycle"
        } ?? "TAPCamDemo.StartupLifecycle",
        account: String = "device-generation.v1"
    ) {
        self.service = service
        self.account = account
    }

    func currentOrCreate() -> UUID? {
        switch loadResult() {
        case .value(let stored):
            return stored
        case .corrupt:
            return replaceCorruptValue()
        case .unavailable:
            return nil
        case .missing:
            break
        }

        let generation = UUID()
        let data = Data(generation.uuidString.utf8)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        switch SecItemAdd(query as CFDictionary, nil) {
        case errSecSuccess:
            return generation
        case errSecDuplicateItem:
            switch loadResult() {
            case .value(let stored):
                return stored
            case .corrupt:
                return replaceCorruptValue()
            case .missing, .unavailable:
                return nil
            }
        default:
            return nil
        }
    }

    private enum LoadResult {
        case value(UUID)
        case missing
        case corrupt
        case unavailable
    }

    private func loadResult() -> LoadResult {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data,
                  let rawValue = String(data: data, encoding: .utf8),
                  let generation = UUID(uuidString: rawValue) else {
                return .corrupt
            }
            return .value(generation)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    private func replaceCorruptValue() -> UUID? {
        let generation = UUID()
        let attributes: [String: Any] = [
            kSecValueData as String: Data(generation.uuidString.utf8),
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        ) == errSecSuccess else {
            return nil
        }
        return generation
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Prepared marker bytes whose only remaining operation is the atomic rename.
/// Production prepares this off-MainActor, then performs the point of no return
/// on MainActor in the same synchronous turn that publishes `t4`.
nonisolated final class StartupPreparedInitializationCommit: @unchecked Sendable {
    let completion: InitializationCompletion

    private let temporaryURL: URL
    private let markerURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var isFinalized = false

    init(
        completion: InitializationCompletion,
        temporaryURL: URL,
        markerURL: URL,
        fileManager: FileManager
    ) {
        self.completion = completion
        self.temporaryURL = temporaryURL
        self.markerURL = markerURL
        self.fileManager = fileManager
    }

    @discardableResult
    func commit() -> Bool {
        guard beginFinalization() else { return false }
        let result = temporaryURL.path.withCString { sourcePath in
            markerURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            try? fileManager.removeItem(at: temporaryURL)
            return false
        }
        return true
    }

    func discard() {
        guard beginFinalization() else { return }
        try? fileManager.removeItem(at: temporaryURL)
    }

    private func beginFinalization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinalized else { return false }
        isFinalized = true
        return true
    }

    deinit {
        discard()
    }
}

nonisolated struct StartupInitializationStore: @unchecked Sendable {
    private let runtimeIdentity: StartupInitializationRuntimeIdentity?
    private let installationGenerationStore: StartupInstallationGenerationStore
    private let deviceGenerationStore: any StartupDeviceGenerationProviding
    private let markerURL: URL?
    private let fileManager: FileManager

    init(
        userDefaults: UserDefaults = .standard,
        runtimeIdentity: StartupInitializationRuntimeIdentity? = .current(),
        deviceGenerationStore: any StartupDeviceGenerationProviding =
            KeychainStartupDeviceGenerationStore(),
        markerURL: URL? = nil,
        defaultMarkerURLProvider: @Sendable (FileManager) -> URL? = {
            StartupInitializationStore.defaultMarkerURL(fileManager: $0)
        },
        fileManager: FileManager = .default
    ) {
        self.runtimeIdentity = runtimeIdentity
        self.installationGenerationStore = StartupInstallationGenerationStore(
            userDefaults: userDefaults
        )
        self.deviceGenerationStore = deviceGenerationStore
        self.fileManager = fileManager
        self.markerURL = markerURL ?? defaultMarkerURLProvider(fileManager)
    }

    func load() -> StartupInitializationFact {
        guard let markerURL else {
            return .invalid(.storageUnavailable)
        }
        guard fileManager.fileExists(atPath: markerURL.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: markerURL),
              let completion = try? JSONDecoder().decode(
            InitializationCompletion.self,
            from: data
        ) else {
            return .invalid(.corruptMarker)
        }

        return validate(completion)
    }

    /// Performs Keychain access, encoding, protected-file creation, and fsync,
    /// but deliberately stops before the atomic rename commit point.
    func prepareCurrent(
        now: Date = Date(),
        preparationFault: (InitializationCompletion) throws -> Void = { _ in }
    ) -> StartupPreparedInitializationCommit? {
        guard let runtimeIdentity,
              let markerURL,
              let deviceGenerationID = deviceGenerationStore.currentOrCreate() else {
            return nil
        }

        let completion = InitializationCompletion(
            storageSchemaVersion:
                StartupInitializationRuntimeIdentity.currentStorageSchemaVersion,
            runtimeIdentity: runtimeIdentity,
            installationGenerationID:
                installationGenerationStore.currentOrCreate(),
            deviceGenerationID: deviceGenerationID,
            completedAt: now
        )
        guard let data = try? JSONEncoder().encode(completion) else {
            return nil
        }

        let directoryURL = markerURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".initialization-completion-\(UUID().uuidString.lowercased()).tmp",
            isDirectory: false
        )
        do {
            try createProtectedDirectoryIfNeeded(at: directoryURL)
            try data.write(to: temporaryURL, options: [.atomic])
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: temporaryURL.path
            )
            try preparationFault(completion)

            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            return StartupPreparedInitializationCommit(
                completion: completion,
                temporaryURL: temporaryURL,
                markerURL: markerURL,
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            return nil
        }
    }

    private func validate(
        _ completion: InitializationCompletion
    ) -> StartupInitializationFact {
        guard let runtimeIdentity else {
            return .invalid(.runtimeIdentityUnavailable)
        }
        guard completion.storageSchemaVersion
                == StartupInitializationRuntimeIdentity.currentStorageSchemaVersion else {
            return .invalid(.unsupportedStorageSchema)
        }
        guard completion.runtimeIdentity.bundleIdentifier
                == runtimeIdentity.bundleIdentifier else {
            return .invalid(.bundleMismatch)
        }
        guard completion.runtimeIdentity.shortVersion
                == runtimeIdentity.shortVersion else {
            return .invalid(.shortVersionMismatch)
        }
        guard completion.runtimeIdentity.buildVersion
                == runtimeIdentity.buildVersion else {
            return .invalid(.buildVersionMismatch)
        }
        guard completion.runtimeIdentity.initializationSchemaVersion
                == runtimeIdentity.initializationSchemaVersion else {
            return .invalid(.initializationSchemaMismatch)
        }
        guard completion.installationGenerationID
                == installationGenerationStore.currentOrCreate() else {
            return .invalid(.installationGenerationMismatch)
        }
        guard let deviceGenerationID = deviceGenerationStore.currentOrCreate() else {
            return .invalid(.deviceGenerationUnavailable)
        }
        guard completion.deviceGenerationID == deviceGenerationID else {
            return .invalid(.deviceGenerationMismatch)
        }
        return .current(completion)
    }

    private func createProtectedDirectoryIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    fileprivate static func defaultMarkerURL(fileManager: FileManager) -> URL? {
        guard let rootURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return rootURL
            .appendingPathComponent("TAPCamDemo", isDirectory: true)
            .appendingPathComponent("Startup", isDirectory: true)
            .appendingPathComponent(
                "initialization-completion-v1.json",
                isDirectory: false
            )
    }
}
