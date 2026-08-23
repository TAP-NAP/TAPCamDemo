//
//  StartupInitializationPolicyTests.swift
//  TAPCamDemoTests
//

import Foundation
import Security
import Testing
@testable import TAPCamDemo

struct StartupInitializationPolicyTests {
    @Test func markerIsMissingUntilOneAtomicCompletionIsCommitted() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }

        #expect(fixture.store.load() == .missing)

        let completion = try #require(
            fixture.store.commitCurrent(now: Date(timeIntervalSince1970: 42))
        )
        #expect(fixture.store.load() == .current(completion))
        #expect(completion.runtimeIdentity == fixture.identity)
        #expect(completion.deviceGenerationID == fixture.deviceGenerationID)
    }

    @Test func everyRuntimeAndGenerationMismatchRequiresInitialization() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }
        _ = try #require(fixture.store.commitCurrent())

        let changedVersion = fixture.store(
            identity: fixture.identity.replacing(shortVersion: "2.0")
        )
        #expect(changedVersion.load() == .invalid(.shortVersionMismatch))

        let changedBuild = fixture.store(
            identity: fixture.identity.replacing(buildVersion: "2")
        )
        #expect(changedBuild.load() == .invalid(.buildVersionMismatch))

        let changedSchema = fixture.store(
            identity: fixture.identity.replacing(initializationSchemaVersion: 2)
        )
        #expect(changedSchema.load() == .invalid(.initializationSchemaMismatch))

        let changedBundle = fixture.store(
            identity: fixture.identity.replacing(bundleIdentifier: "com.tap.other")
        )
        #expect(changedBundle.load() == .invalid(.bundleMismatch))

        let originalInstallationGeneration = try #require(
            fixture.committedInstallationGenerationID
        )
        fixture.defaults.set(
            UUID().uuidString,
            forKey: StartupGateDefaults.installationGenerationKey
        )
        #expect(fixture.store.load() == .invalid(.installationGenerationMismatch))

        let restoredSuiteName =
            "StartupInitializationPolicyTests.\(UUID().uuidString)"
        let restoredDefaults = try #require(
            UserDefaults(suiteName: restoredSuiteName)
        )
        defer {
            restoredDefaults.removePersistentDomain(forName: restoredSuiteName)
        }
        restoredDefaults.set(
            originalInstallationGeneration.uuidString,
            forKey: StartupGateDefaults.installationGenerationKey
        )
        let migratedDevice = StartupInitializationStore(
            userDefaults: restoredDefaults,
            runtimeIdentity: fixture.identity,
            deviceGenerationStore: FixedStartupDeviceGenerationStore(value: UUID()),
            markerURL: fixture.markerURL
        )
        #expect(migratedDevice.load() == .invalid(.deviceGenerationMismatch))
    }

    @Test func corruptMarkerFailsClosed() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }

        try FileManager.default.createDirectory(
            at: fixture.markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("corrupt".utf8).write(to: fixture.markerURL)

        #expect(fixture.store.load() == .invalid(.corruptMarker))
    }

    @Test func unsupportedStorageSchemaAndUnavailableLocalFactsFailClosed() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }
        let completion = try #require(fixture.store.commitCurrent())

        let unsupported = InitializationCompletion(
            storageSchemaVersion: completion.storageSchemaVersion + 1,
            runtimeIdentity: completion.runtimeIdentity,
            installationGenerationID: completion.installationGenerationID,
            deviceGenerationID: completion.deviceGenerationID,
            completedAt: completion.completedAt
        )
        try JSONEncoder().encode(unsupported).write(to: fixture.markerURL)
        #expect(fixture.store.load() == .invalid(.unsupportedStorageSchema))

        try JSONEncoder().encode(completion).write(to: fixture.markerURL)
        let unavailableRuntime = StartupInitializationStore(
            userDefaults: fixture.defaults,
            runtimeIdentity: nil,
            deviceGenerationStore: FixedStartupDeviceGenerationStore(
                value: fixture.deviceGenerationID
            ),
            markerURL: fixture.markerURL
        )
        #expect(
            unavailableRuntime.load()
                == .invalid(.runtimeIdentityUnavailable)
        )

        let unavailableDevice = StartupInitializationStore(
            userDefaults: fixture.defaults,
            runtimeIdentity: fixture.identity,
            deviceGenerationStore: FixedStartupDeviceGenerationStore(value: nil),
            markerURL: fixture.markerURL
        )
        #expect(
            unavailableDevice.load()
                == .invalid(.deviceGenerationUnavailable)
        )
        #expect(unavailableDevice.commitCurrent() == nil)
    }

    @Test func preCommitFailureLeavesPreviousCanonicalMarkerUntouched() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }
        let previous = try #require(
            fixture.store.commitCurrent(now: Date(timeIntervalSince1970: 1))
        )
        let previousData = try Data(contentsOf: fixture.markerURL)

        let updatedStore = fixture.store(
            identity: fixture.identity.replacing(buildVersion: "2")
        )
        let failed = updatedStore.commitCurrent(
            now: Date(timeIntervalSince1970: 2)
        ) { _ in
            throw InitializationTestError.injected
        }

        #expect(failed == nil)
        #expect(try Data(contentsOf: fixture.markerURL) == previousData)
        #expect(fixture.store.load() == .current(previous))
        #expect(updatedStore.load() == .invalid(.buildVersionMismatch))

        let updated = try #require(
            updatedStore.commitCurrent(now: Date(timeIntervalSince1970: 3))
        )
        #expect(updatedStore.load() == .current(updated))
    }

    @Test func preCommitFailureWithoutMarkerLeavesNoCanonicalOrTemporaryFile() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }

        let failed = fixture.store.commitCurrent { _ in
            throw InitializationTestError.injected
        }

        #expect(failed == nil)
        #expect(fixture.store.load() == .missing)
        let directory = fixture.markerURL.deletingLastPathComponent()
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        #expect(remainingNames.isEmpty)
    }

    @Test func preparedMarkerIsNotCanonicalUntilExplicitPointOfNoReturn() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }

        let discarded = try #require(fixture.store.prepareCurrent())
        #expect(fixture.store.load() == .missing)
        discarded.discard()
        #expect(fixture.store.load() == .missing)

        let committed = try #require(fixture.store.prepareCurrent())
        #expect(fixture.store.load() == .missing)
        #expect(committed.commit())
        #expect(!committed.commit())
        #expect(fixture.store.load() == .current(committed.completion))
    }

    @Test func unavailableApplicationSupportNeverFallsBackToTemporaryStorage() throws {
        let fixture = try InitializationStoreFixture()
        defer { fixture.cleanup() }
        let unavailable = StartupInitializationStore(
            userDefaults: fixture.defaults,
            runtimeIdentity: fixture.identity,
            deviceGenerationStore: FixedStartupDeviceGenerationStore(
                value: fixture.deviceGenerationID
            ),
            defaultMarkerURLProvider: { _ in nil }
        )

        #expect(unavailable.load() == .invalid(.storageUnavailable))
        #expect(unavailable.commitCurrent() == nil)
    }

    @Test func corruptKeychainDeviceGenerationRepairsInPlace() throws {
        let service = "StartupInitializationPolicyTests.\(UUID().uuidString)"
        let account = "device-generation"
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)
        defer { SecItemDelete(baseQuery as CFDictionary) }

        var corruptQuery = baseQuery
        corruptQuery[kSecValueData as String] = Data("not-a-uuid".utf8)
        corruptQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        try #require(SecItemAdd(corruptQuery as CFDictionary, nil) == errSecSuccess)

        let store = KeychainStartupDeviceGenerationStore(
            service: service,
            account: account
        )
        let repaired = try #require(store.currentOrCreate())
        #expect(store.currentOrCreate() == repaired)

        var readQuery = baseQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        try #require(
            SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess
        )
        let data = try #require(result as? Data)
        let rawValue = try #require(String(data: data, encoding: .utf8))
        #expect(UUID(uuidString: rawValue) == repaired)
    }
}

private final class InitializationStoreFixture {
    let suiteName: String
    let defaults: UserDefaults
    let rootURL: URL
    let markerURL: URL
    let identity = StartupInitializationRuntimeIdentity(
        bundleIdentifier: "com.tap.test",
        shortVersion: "1.0",
        buildVersion: "1",
        initializationSchemaVersion: 1
    )
    let deviceGenerationID = UUID()

    init() throws {
        suiteName = "StartupInitializationPolicyTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TAPCamDemo-StartupInitialization-\(UUID().uuidString)",
            isDirectory: true
        )
        markerURL = rootURL.appendingPathComponent(
            "initialization-completion-v1.json",
            isDirectory: false
        )
    }

    lazy var store = StartupInitializationStore(
        userDefaults: defaults,
        runtimeIdentity: identity,
        deviceGenerationStore: FixedStartupDeviceGenerationStore(
            value: deviceGenerationID
        ),
        markerURL: markerURL
    )

    var committedInstallationGenerationID: UUID? {
        guard let rawValue = defaults.string(
            forKey: StartupGateDefaults.installationGenerationKey
        ) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    func store(
        identity: StartupInitializationRuntimeIdentity
    ) -> StartupInitializationStore {
        StartupInitializationStore(
            userDefaults: defaults,
            runtimeIdentity: identity,
            deviceGenerationStore: FixedStartupDeviceGenerationStore(
                value: deviceGenerationID
            ),
            markerURL: markerURL
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct FixedStartupDeviceGenerationStore: StartupDeviceGenerationProviding {
    let value: UUID?

    func currentOrCreate() -> UUID? {
        value
    }
}

private enum InitializationTestError: Error {
    case injected
}

private extension StartupInitializationRuntimeIdentity {
    func replacing(
        bundleIdentifier: String? = nil,
        shortVersion: String? = nil,
        buildVersion: String? = nil,
        initializationSchemaVersion: Int? = nil
    ) -> StartupInitializationRuntimeIdentity {
        StartupInitializationRuntimeIdentity(
            bundleIdentifier: bundleIdentifier ?? self.bundleIdentifier,
            shortVersion: shortVersion ?? self.shortVersion,
            buildVersion: buildVersion ?? self.buildVersion,
            initializationSchemaVersion:
                initializationSchemaVersion ?? self.initializationSchemaVersion
        )
    }
}
