//
//  StartupGateCoordinatorTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Network
import Photos
import Testing
@testable import TAPCamDemo

struct StartupGateCoordinatorTests {
    @Test @MainActor func networkActivityWaitsForContinueAndKeepsPendingRequest() {
        let suiteName = "StartupGateNetwork.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var monitorStarts = 0
        var connectionStarts = 0
        let coordinator = StartupGateCoordinator(
            userDefaults: defaults,
            startNetworkConnection: { _ in connectionStarts += 1 },
            startNetworkMonitor: { _ in monitorStarts += 1 }
        )

        // Initial appearance and foregrounding must not start either network API.
        coordinator.refreshAuthorizationStatuses()
        coordinator.refreshNetworkAccessStatus()
        coordinator.refreshNetworkAccessStatus()
        #expect(monitorStarts == 0)
        #expect(connectionStarts == 0)
        #expect(coordinator.networkStatus == .idle)

        coordinator.requestNetworkAccess()
        #expect(monitorStarts == 1)
        #expect(connectionStarts == 1)
        #expect(coordinator.networkStatus == .requesting)
        coordinator.refreshAuthorizationStatuses()
        coordinator.refreshNetworkAccessStatus()
        coordinator.requestNetworkAccess()
        #expect(monitorStarts == 1)
        #expect(connectionStarts == 1)
        #expect(coordinator.networkStatus == .requesting)

        // An interrupted unanswered prompt is not a completed authorization.
        coordinator.cancelNetworkAccessRequest()
        let restarted = StartupGateCoordinator(
            userDefaults: defaults,
            startNetworkConnection: { _ in connectionStarts += 1 },
            startNetworkMonitor: { _ in monitorStarts += 1 }
        )
        restarted.refreshNetworkAccessStatus()
        #expect(restarted.networkStatus == .idle)
        #expect(monitorStarts == 1)
        #expect(connectionStarts == 1)
    }

    @Test @MainActor func networkPermissionRestoresAfterAppRecreationWithoutContactingBackend() {
        let suiteName = "StartupGateNetwork.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var monitorStarts = 0
        var connectionStarts = 0
        func makeCoordinator() -> StartupGateCoordinator {
            StartupGateCoordinator(
                userDefaults: defaults,
                startNetworkConnection: { _ in connectionStarts += 1 },
                startNetworkMonitor: { _ in monitorStarts += 1 }
            )
        }

        var coordinator: StartupGateCoordinator? = makeCoordinator()
        coordinator?.requestNetworkAccess()
        coordinator?.updateNetworkAccessStatus(pathStatus: .satisfied, reason: .notAvailable)
        #expect(coordinator?.networkStatus == .granted)

        // Opening Settings keeps the last system result and never reconnects.
        coordinator?.cancelNetworkAccessRequest()
        coordinator?.refreshAuthorizationStatuses()
        coordinator?.refreshNetworkAccessStatus()
        #expect(coordinator?.networkStatus == .granted)
        #expect(monitorStarts == 1)
        #expect(connectionStarts == 1)

        // Camera changes can recreate the app. Restore the label before observing.
        coordinator = nil
        coordinator = makeCoordinator()
        #expect(coordinator?.networkStatus == .granted)
        #expect(monitorStarts == 1)
        coordinator?.refreshNetworkAccessStatus()
        #expect(monitorStarts == 2)
        #expect(connectionStarts == 1)
        for reason: NWPath.UnsatisfiedReason in [.notAvailable, .vpnInactive] {
            coordinator?.updateNetworkAccessStatus(pathStatus: .unsatisfied, reason: reason)
            #expect(coordinator?.networkStatus == .granted)
        }
        for reason: NWPath.UnsatisfiedReason in [.wifiDenied, .cellularDenied] {
            coordinator?.updateNetworkAccessStatus(pathStatus: .unsatisfied, reason: reason)
            #expect(coordinator?.networkStatus == .denied)
        }
        coordinator = nil
        coordinator = makeCoordinator()
        #expect(coordinator?.networkStatus == .denied)
        coordinator?.refreshNetworkAccessStatus()
        coordinator?.updateNetworkAccessStatus(pathStatus: .satisfied, reason: .notAvailable)
        #expect(coordinator?.networkStatus == .granted)
        #expect(connectionStarts == 1)
    }

    @Test func limitedPhotoLibraryAccessCountsAsGranted() {
        #expect(StartupGateCoordinator.photoLibraryStatus(from: .limited) == .granted)
    }

    @Test(arguments: [
        StartupGateRequirementStatus.idle,
        .requesting,
        .denied,
        .restricted
    ])
    func startupGateRequiresBothCameraAndPhotos(status: StartupGateRequirementStatus) {
        let cameraBlocked = StartupGateStatusSnapshot(
            camera: status,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        )
        let photosBlocked = StartupGateStatusSnapshot(
            camera: .granted,
            photoLibrary: status,
            location: .idle,
            microphone: .idle
        )

        #expect(!cameraBlocked.hasCompletedRequiredStartupChecks)
        #expect(!photosBlocked.hasCompletedRequiredStartupChecks)
        #expect(StartupGatePolicy.firstInstallContinueAction(for: cameraBlocked) == .stayOnWelcome)
        #expect(StartupGatePolicy.firstInstallContinueAction(for: photosBlocked) == .stayOnWelcome)
    }

    @Test func startupGateContinueEntersCameraReadinessOnlyAfterRequiredSetup() {
        let completedSnapshot = StartupGateStatusSnapshot(
            camera: .granted,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        )
        let incompleteSnapshot = StartupGateStatusSnapshot(
            camera: .idle,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        )

        #expect(StartupGatePolicy.firstInstallContinueAction(for: completedSnapshot) == .enterResourceInitialization)
        #expect(StartupGatePolicy.firstInstallContinueAction(for: incompleteSnapshot) == .stayOnWelcome)
    }

    @Test func requiredPermissionSnapshotKeepsLimitedAndRestrictedDistinct() {
        #expect(
            RequiredPermissionSnapshot(
                camera: .authorized,
                photoLibrary: .limited
            ).isUsable
        )
        #expect(
            !RequiredPermissionSnapshot(
                camera: .restricted,
                photoLibrary: .authorized
            ).isUsable
        )
        #expect(
            StartupGateCoordinator.cameraPermissionStatus(from: .notDetermined)
                == .notDetermined
        )
        #expect(
            StartupGateCoordinator.cameraPermissionStatus(from: .restricted)
                == .restricted
        )
        #expect(
            StartupGateCoordinator.photoLibraryPermissionStatus(from: .limited)
                == .limited
        )
        #expect(
            StartupGateCoordinator.photoLibraryStatus(from: .restricted)
                == .restricted
        )
    }

    @Test func startupRouteUsesSetupThenPermissionThenInitializationPriority() {
        let usable = RequiredPermissionSnapshot(
            camera: .authorized,
            photoLibrary: .limited
        )
        let blocked = RequiredPermissionSnapshot(
            camera: .denied,
            photoLibrary: .authorized
        )
        let currentInitialization = InitializationCompletion(
            storageSchemaVersion:
                StartupInitializationRuntimeIdentity.currentStorageSchemaVersion,
            runtimeIdentity: StartupInitializationRuntimeIdentity(
                bundleIdentifier: "com.tap.test",
                shortVersion: "1.0",
                buildVersion: "1",
                initializationSchemaVersion: 1
            ),
            installationGenerationID: UUID(),
            deviceGenerationID: UUID(),
            completedAt: Date(timeIntervalSince1970: 42)
        )
        let currentCompletion = SetupCompletionRecord(
            schemaVersion: SetupCompletionRecord.currentSchemaVersion,
            installationGenerationID: UUID(),
            locationChoice: .skipped,
            microphoneChoice: .skipped,
            completedAt: Date(timeIntervalSince1970: 42)
        )

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .absent,
            requiredPermissions: blocked,
            initialization: .missing
        )) == .firstInstallSetup(.initial))

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .currentCompleted(currentCompletion),
            requiredPermissions: blocked,
            initialization: .missing
        )) == .requiredPermissionCheck(resumeTarget: .viewfinder))

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .currentCompleted(currentCompletion),
            requiredPermissions: usable,
            initialization: .missing
        )) == .resourceInitialization)

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .currentCompleted(currentCompletion),
            requiredPermissions: usable,
            initialization: .current(currentInitialization)
        )) == .viewfinder)
    }

    @Test func corruptCanonicalReceiptFailsClosed() throws {
        let suiteName = "StartupGateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = StartupInstallationGenerationStore(userDefaults: defaults).currentOrCreate()
        defaults.set(Data("corrupt".utf8), forKey: StartupGateDefaults.setupReceiptKey)

        let fact = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test"
        ).load()

        #expect(fact == .invalid(.corruptReceipt))
    }

    @Test func currentSetupCompletionRejectsCorruptOrMismatchedRecords() throws {
        let suiteName = "StartupGateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let installationGeneration = StartupInstallationGenerationStore(
            userDefaults: defaults
        ).currentOrCreate()
        let invalidRecords = [
            Data("corrupt".utf8),
            try JSONEncoder().encode(SetupCompletionRecord(
                schemaVersion: SetupCompletionRecord.currentSchemaVersion + 1,
                installationGenerationID: installationGeneration,
                locationChoice: .skipped,
                microphoneChoice: .skipped,
                completedAt: Date(timeIntervalSince1970: 42)
            )),
            try JSONEncoder().encode(SetupCompletionRecord(
                schemaVersion: SetupCompletionRecord.currentSchemaVersion,
                installationGenerationID: UUID(),
                locationChoice: .skipped,
                microphoneChoice: .skipped,
                completedAt: Date(timeIntervalSince1970: 42)
            ))
        ]

        for data in invalidRecords {
            defaults.set(data, forKey: StartupGateDefaults.setupCompletionKey)
            let fact = StartupSetupFactStore(
                userDefaults: defaults,
                bundleIdentifier: "com.tap.test"
            ).load()
            #expect(fact == .invalid(.corruptSetupCompletion))
        }
    }

    @Test func canonicalReceiptRequiresMatchingLocallyVerifiedCredentialBinding() throws {
        let suiteName = "StartupGateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let generation = StartupInstallationGenerationStore(
            userDefaults: defaults
        ).currentOrCreate()
        let binding = SetupCredentialBinding(
            credentialName: "install:test",
            keyIDFingerprint: "fingerprint",
            environment: "development"
        )
        let receipt = SetupReceipt(
            schemaVersion: SetupReceipt.currentSchemaVersion,
            bundleIdentifier: "com.tap.test",
            installationGenerationID: generation,
            credentialBinding: binding,
            locationChoice: .skipped,
            microphoneChoice: .granted,
            completedAt: Date(timeIntervalSince1970: 42)
        )
        defaults.set(
            try JSONEncoder().encode(receipt),
            forKey: StartupGateDefaults.setupReceiptKey
        )

        let unverified = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test"
        ).load()
        #expect(unverified == .invalid(.missingCredentialBinding))

        let mismatched = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test",
            verifiedCredentialBinding: VerifiedStartupCredentialBinding(
                value: SetupCredentialBinding(
                    credentialName: "install:test",
                    keyIDFingerprint: "other",
                    environment: "development"
                )
            )
        ).load()
        #expect(mismatched == .invalid(.credentialBindingMismatch))

        let verified = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test",
            verifiedCredentialBinding: VerifiedStartupCredentialBinding(value: binding)
        ).load()
        #expect(verified == .valid(receipt))
    }

    @Test func currentPermissionSetupCompletionWritesNoCanonicalReceipt() throws {
        let suiteName = "StartupGateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test"
        )
        let fact = store.recordCurrentCompletion(
            statusSnapshot: StartupGateStatusSnapshot(
                camera: .granted,
                photoLibrary: .granted,
                location: .granted,
                microphone: .idle
            ),
            now: Date(timeIntervalSince1970: 42)
        )

        #expect(defaults.object(forKey: StartupGateDefaults.setupReceiptKey) == nil)
        #expect(defaults.data(forKey: StartupGateDefaults.setupCompletionKey) != nil)
        guard case let .currentCompleted(record) = fact else {
            Issue.record("Expected current pre-release completion")
            return
        }
        #expect(record.locationChoice == .granted)
        #expect(record.microphoneChoice == .unresolved)
    }

    @Test func libraryObservationWaitsForSetupOrExplicitPhotosCompletion() {
        let currentCompletion = SetupCompletionRecord(
            schemaVersion: SetupCompletionRecord.currentSchemaVersion,
            installationGenerationID: UUID(),
            locationChoice: .skipped,
            microphoneChoice: .skipped,
            completedAt: Date(timeIntervalSince1970: 42)
        )
        #expect(!StartupGatePolicy.shouldActivatePhotoLibraryObservation(
            setup: .absent,
            didCompleteExplicitPhotosAction: false,
            photoLibraryStatus: .authorized
        ))
        #expect(StartupGatePolicy.shouldActivatePhotoLibraryObservation(
            setup: .absent,
            didCompleteExplicitPhotosAction: true,
            photoLibraryStatus: .limited
        ))
        #expect(StartupGatePolicy.shouldActivatePhotoLibraryObservation(
            setup: .currentCompleted(currentCompletion),
            didCompleteExplicitPhotosAction: false,
            photoLibraryStatus: .authorized
        ))
        #expect(!StartupGatePolicy.shouldActivatePhotoLibraryObservation(
            setup: .currentCompleted(currentCompletion),
            didCompleteExplicitPhotosAction: true,
            photoLibraryStatus: .denied
        ))
    }

    @Test func startupGateTreatsLocationAsOptional() {
        for locationStatus in [
            StartupGateRequirementStatus.idle,
            .requesting,
            .granted,
            .denied,
            .restricted
        ] {
            let snapshot = StartupGateStatusSnapshot(
                camera: .granted,
                photoLibrary: .granted,
                location: locationStatus,
                microphone: .idle
            )

            #expect(snapshot.hasCompletedRequiredStartupChecks)
            #expect(!snapshot.hasBlockingStartupFailure)
            #expect(StartupGatePolicy.firstInstallContinueAction(for: snapshot) == .enterResourceInitialization)
        }
    }

    @Test func startupGateTreatsMicrophoneAsOptional() {
        for microphoneStatus in [
            StartupGateRequirementStatus.idle,
            .requesting,
            .granted,
            .denied,
            .restricted
        ] {
            let snapshot = StartupGateStatusSnapshot(
                camera: .granted,
                photoLibrary: .granted,
                location: .idle,
                microphone: microphoneStatus
            )

            #expect(snapshot.hasCompletedRequiredStartupChecks)
            #expect(!snapshot.hasBlockingStartupFailure)
            #expect(StartupGatePolicy.firstInstallContinueAction(for: snapshot) == .enterResourceInitialization)
        }
    }

}
