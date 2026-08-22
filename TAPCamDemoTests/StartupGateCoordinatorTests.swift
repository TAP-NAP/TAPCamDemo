//
//  StartupGateCoordinatorTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Photos
import Testing
@testable import TAPCamDemo

struct StartupGateCoordinatorTests {
    @Test func limitedPhotoLibraryAccessCountsAsGranted() {
        #expect(StartupGateCoordinator.photoLibraryStatus(from: .limited) == .granted)
    }

    @Test func startupGatePolicyNamesRequiredAndOptionalRequirements() {
        #expect(StartupGatePolicy.requiredRequirements == [
            .securityPreflight,
            .camera,
            .photoLibrary
        ])
        #expect(StartupGatePolicy.optionalRequirements == [.location, .microphone])
    }

    @Test func startupGateRequiresSecurityPreflightCameraAndPhotos() {
        let completedSnapshot = StartupGateStatusSnapshot(
            securityPreflight: .granted,
            camera: .granted,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        )

        #expect(completedSnapshot.hasCompletedRequiredStartupChecks)

        #expect(!StartupGateCoordinator.hasCompletedRequiredStartupChecks(
            securityPreflightStatus: .idle,
            cameraStatus: .granted,
            photoLibraryStatus: .granted
        ))
        #expect(!StartupGateCoordinator.hasCompletedRequiredStartupChecks(
            securityPreflightStatus: .granted,
            cameraStatus: .idle,
            photoLibraryStatus: .granted
        ))
        #expect(!StartupGateCoordinator.hasCompletedRequiredStartupChecks(
            securityPreflightStatus: .granted,
            cameraStatus: .granted,
            photoLibraryStatus: .idle
        ))
    }

    @Test func startupGateContinueEntersCameraReadinessOnlyAfterRequiredSetup() {
        let completedSnapshot = StartupGateStatusSnapshot(
            securityPreflight: .granted,
            camera: .granted,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        )
        let incompleteSnapshot = StartupGateStatusSnapshot(
            securityPreflight: .granted,
            camera: .idle,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        )

        #expect(StartupGatePolicy.firstInstallContinueAction(for: completedSnapshot) == .enterResourceInitialization)
        #expect(StartupGatePolicy.firstInstallContinueAction(for: incompleteSnapshot) == .stayOnWelcome)
    }

    @Test func startupGateStoredKeyPreservesExistingInstallMarker() {
        #expect(
            StartupGateDefaults.legacyCombinedCompletionKey
                == "TAPCamDemo.StartupGate.didCompleteFirstInstallPermissions"
        )
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

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .absent,
            requiredPermissions: blocked,
            initialization: .missing
        )) == .firstInstallSetup(.initial))

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .legacyCompleted(nil),
            requiredPermissions: blocked,
            initialization: .missing
        )) == .requiredPermissionCheck(resumeTarget: .viewfinder))

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .legacyCompleted(nil),
            requiredPermissions: usable,
            initialization: .missing
        )) == .resourceInitialization)

        #expect(StartupGatePolicy.route(for: StartupRouteFacts(
            setup: .legacyCompleted(nil),
            requiredPermissions: usable,
            initialization: .current(currentInitialization)
        )) == .viewfinder)
    }

    @Test func invalidCanonicalReceiptNeverFallsBackToLegacyBoolean() throws {
        let suiteName = "StartupGateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = StartupInstallationGenerationStore(userDefaults: defaults).currentOrCreate()
        defaults.set(Data("corrupt".utf8), forKey: StartupGateDefaults.setupReceiptKey)

        let fact = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test"
        ).load(legacyCombinedCompletion: true)

        #expect(fact == .invalid(.corruptReceipt))
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
        ).load(legacyCombinedCompletion: true)
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
        ).load(legacyCombinedCompletion: true)
        #expect(mismatched == .invalid(.credentialBindingMismatch))

        let verified = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test",
            verifiedCredentialBinding: VerifiedStartupCredentialBinding(value: binding)
        ).load(legacyCombinedCompletion: true)
        #expect(verified == .valid(receipt))
    }

    @Test func frozenHealthPreflightCompletionWritesNoCanonicalReceipt() throws {
        let suiteName = "StartupGateCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StartupSetupFactStore(
            userDefaults: defaults,
            bundleIdentifier: "com.tap.test"
        )
        let fact = store.recordFrozenLegacyCompletion(
            statusSnapshot: StartupGateStatusSnapshot(
                securityPreflight: .granted,
                camera: .granted,
                photoLibrary: .granted,
                location: .skipped,
                microphone: .idle
            ),
            now: Date(timeIntervalSince1970: 42)
        )

        #expect(defaults.object(forKey: StartupGateDefaults.setupReceiptKey) == nil)
        #expect(defaults.data(forKey: StartupGateDefaults.legacySetupCompletionKey) != nil)
        guard case let .legacyCompleted(record?) = fact else {
            Issue.record("Expected explicit frozen legacy completion")
            return
        }
        #expect(record.evidence == .frozenLegacySecurityPreflight)
        #expect(record.locationChoice == .skipped)
        #expect(record.microphoneChoice == .unresolved)
    }

    @Test func libraryObservationWaitsForSetupOrExplicitPhotosCompletion() {
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
            setup: .legacyCompleted(nil),
            didCompleteExplicitPhotosAction: false,
            photoLibraryStatus: .authorized
        ))
        #expect(!StartupGatePolicy.shouldActivatePhotoLibraryObservation(
            setup: .legacyCompleted(nil),
            didCompleteExplicitPhotosAction: true,
            photoLibraryStatus: .denied
        ))
    }

    @Test func securityPreflightPolicyNamesDeadlineAndRetryWindow() {
        let policy = StartupSecurityPreflightPolicy(
            timeoutSeconds: 30,
            retryDelayNanoseconds: 1_000_000_000
        )
        let startedAt = Date(timeIntervalSince1970: 100)
        let deadline = policy.deadline(startedAt: startedAt)

        #expect(deadline == Date(timeIntervalSince1970: 130))
        #expect(policy.canStartAttempt(now: startedAt, deadline: deadline))
        #expect(!policy.canStartAttempt(now: deadline, deadline: deadline))
        #expect(policy.shouldSleepBeforeRetry(now: Date(timeIntervalSince1970: 128), deadline: deadline))
        #expect(!policy.shouldSleepBeforeRetry(now: Date(timeIntervalSince1970: 129), deadline: deadline))
    }

    @Test func securityPreflightPolicyRejectsZeroDelayRetryLoop() {
        let policy = StartupSecurityPreflightPolicy(
            timeoutSeconds: 30,
            retryDelayNanoseconds: 0
        )
        let startedAt = Date(timeIntervalSince1970: 100)
        let deadline = policy.deadline(startedAt: startedAt)

        #expect(!policy.shouldSleepBeforeRetry(now: startedAt, deadline: deadline))
    }

    @Test func startupGateRejectsNonGrantedSecurityPreflightStates() {
        for securityPreflightStatus in [
            StartupGateRequirementStatus.idle,
            .requesting,
            .denied,
            .skipped
        ] {
            #expect(!StartupGateCoordinator.hasCompletedRequiredStartupChecks(
                securityPreflightStatus: securityPreflightStatus,
                cameraStatus: .granted,
                photoLibraryStatus: .granted
            ))
        }
    }

    @Test func startupGateTreatsSecurityPreflightDenialAsBlocking() {
        #expect(StartupGateStatusSnapshot(
            securityPreflight: .denied,
            camera: .granted,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        ).hasBlockingStartupFailure)
        #expect(!StartupGateStatusSnapshot(
            securityPreflight: .requesting,
            camera: .granted,
            photoLibrary: .granted,
            location: .idle,
            microphone: .idle
        ).hasBlockingStartupFailure)
    }

    @Test func startupGateTreatsLocationAsOptional() {
        for locationStatus in [
            StartupGateRequirementStatus.idle,
            .requesting,
            .granted,
            .denied,
            .skipped
        ] {
            let snapshot = StartupGateStatusSnapshot(
                securityPreflight: .granted,
                camera: .granted,
                photoLibrary: .granted,
                location: locationStatus,
                microphone: .idle
            )

            #expect(snapshot.hasCompletedRequiredStartupChecks)
            #expect(!snapshot.hasBlockingStartupFailure)
        }
    }

    @Test func startupGateTreatsMicrophoneAsOptional() {
        for microphoneStatus in [
            StartupGateRequirementStatus.idle,
            .requesting,
            .granted,
            .denied,
            .skipped
        ] {
            let snapshot = StartupGateStatusSnapshot(
                securityPreflight: .granted,
                camera: .granted,
                photoLibrary: .granted,
                location: .idle,
                microphone: microphoneStatus
            )

            #expect(snapshot.hasCompletedRequiredStartupChecks)
            #expect(!snapshot.hasBlockingStartupFailure)
        }
    }

    @Test @MainActor func coordinatorReadsInjectedSecurityPreflightStatus() {
        let coordinator = StartupGateCoordinator(
            securityPreflight: StubSecurityPreflight(currentStatus: .granted, requestedStatus: .denied)
        )

        #expect(coordinator.securityPreflightStatus == .granted)
    }

    @Test @MainActor func coordinatorRunsInjectedSecurityPreflight() async {
        let coordinator = StartupGateCoordinator(
            securityPreflight: StubSecurityPreflight(currentStatus: nil, requestedStatus: .granted)
        )

        #expect(coordinator.securityPreflightStatus == .idle)
        await coordinator.requestSecurityPreflight()
        #expect(coordinator.securityPreflightStatus == .granted)
    }

    @Test @MainActor func coordinatorKeepsDeniedSecurityPreflightBlockingAfterRequest() async {
        let coordinator = StartupGateCoordinator(
            securityPreflight: StubSecurityPreflight(currentStatus: nil, requestedStatus: .denied)
        )

        await coordinator.requestSecurityPreflight()

        #expect(coordinator.securityPreflightStatus == .denied)
        #expect(!StartupGateCoordinator.hasCompletedRequiredStartupChecks(
            securityPreflightStatus: coordinator.securityPreflightStatus,
            cameraStatus: .granted,
            photoLibraryStatus: .granted
        ))
        #expect(StartupGateCoordinator.hasBlockingStartupFailure(
            securityPreflightStatus: coordinator.securityPreflightStatus,
            cameraStatus: .granted,
            photoLibraryStatus: .granted
        ))
    }

    @Test @MainActor func requiredPermissionRefreshDoesNotStartNetworkPreflight() {
        let preflight = RecordingSecurityPreflight(currentStatus: .denied)
        let coordinator = StartupGateCoordinator(securityPreflight: preflight)

        coordinator.refreshRequiredPermissionStatuses()
        coordinator.refreshAuthorizationStatus(for: .camera)
        coordinator.refreshAuthorizationStatus(for: .photoLibrary)

        #expect(preflight.requestCount == 0)
    }

    @Test func backendSecurityPreflightDeniesMissingBackendURLWithoutQuery() async {
        let clock = StartupPreflightTestClock()
        let query = StartupPreflightAttemptRecorder(outcomes: [.granted])
        let preflight = StartupBackendSecurityPreflight(
            policy: StartupSecurityPreflightPolicy(timeoutSeconds: 1, retryDelayNanoseconds: 1_000_000_000),
            healthCheckURL: { nil },
            queryBackendHealth: { url in
                query.record(url)
            },
            now: clock.now,
            sleep: clock.sleep
        )

        let status = await preflight.performRequiredPreflight()

        #expect(status == .denied)
        #expect(query.attemptCount == 0)
    }

    @Test func backendSecurityPreflightDeniesZeroTimeoutWithoutQuery() async {
        let clock = StartupPreflightTestClock()
        let query = StartupPreflightAttemptRecorder(outcomes: [.granted])
        let preflight = StartupBackendSecurityPreflight(
            policy: StartupSecurityPreflightPolicy(timeoutSeconds: 0, retryDelayNanoseconds: 1_000_000_000),
            healthCheckURL: { URL(string: "https://www.tapnap.net/healthz") },
            queryBackendHealth: { url in
                query.record(url)
            },
            now: clock.now,
            sleep: clock.sleep
        )

        let status = await preflight.performRequiredPreflight()

        #expect(status == .denied)
        #expect(query.attemptCount == 0)
        #expect(clock.elapsedSeconds == 0)
    }

    @Test func backendSecurityPreflightRetriesUntilSuccessWithinWindow() async {
        let clock = StartupPreflightTestClock()
        let query = StartupPreflightAttemptRecorder(outcomes: [.denied, .granted])
        let preflight = StartupBackendSecurityPreflight(
            policy: StartupSecurityPreflightPolicy(timeoutSeconds: 3, retryDelayNanoseconds: 1_000_000_000),
            healthCheckURL: { URL(string: "https://www.tapnap.net/healthz") },
            queryBackendHealth: { url in
                query.record(url)
            },
            now: clock.now,
            sleep: clock.sleep
        )

        let status = await preflight.performRequiredPreflight()

        #expect(status == .granted)
        #expect(query.attemptCount == 2)
        #expect(clock.elapsedSeconds == 1)
    }

    @Test func backendSecurityPreflightDeniesAtTimeoutWithoutExtraSleep() async {
        let clock = StartupPreflightTestClock()
        let query = StartupPreflightAttemptRecorder(outcomes: [.denied, .denied, .granted])
        let preflight = StartupBackendSecurityPreflight(
            policy: StartupSecurityPreflightPolicy(timeoutSeconds: 2, retryDelayNanoseconds: 1_000_000_000),
            healthCheckURL: { URL(string: "https://www.tapnap.net/healthz") },
            queryBackendHealth: { url in
                query.record(url)
            },
            now: clock.now,
            sleep: clock.sleep
        )

        let status = await preflight.performRequiredPreflight()

        #expect(status == .denied)
        #expect(query.attemptCount == 2)
        #expect(clock.elapsedSeconds == 1)
    }
}

private struct StubSecurityPreflight: StartupSecurityPreflightChecking {
    let currentStatus: StartupGateRequirementStatus?
    let requestedStatus: StartupGateRequirementStatus

    func currentRequirementStatus() -> StartupGateRequirementStatus? {
        currentStatus
    }

    func performRequiredPreflight() async -> StartupGateRequirementStatus {
        requestedStatus
    }
}

private final class RecordingSecurityPreflight: StartupSecurityPreflightChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let currentStatus: StartupGateRequirementStatus?
    private var requests = 0

    init(currentStatus: StartupGateRequirementStatus?) {
        self.currentStatus = currentStatus
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    func currentRequirementStatus() -> StartupGateRequirementStatus? {
        currentStatus
    }

    func performRequiredPreflight() async -> StartupGateRequirementStatus {
        lock.withLock { requests += 1 }
        return .denied
    }
}

private final class StartupPreflightTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0

    var elapsedSeconds: TimeInterval {
        lock.withLock { seconds }
    }

    func now() -> Date {
        lock.withLock { Date(timeIntervalSince1970: seconds) }
    }

    func sleep(nanoseconds: UInt64) async {
        lock.withLock {
            seconds += TimeInterval(nanoseconds) / 1_000_000_000
        }
    }
}

private final class StartupPreflightAttemptRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let outcomes: [StartupGateRequirementStatus]
    private var urls: [URL] = []

    init(outcomes: [StartupGateRequirementStatus]) {
        self.outcomes = outcomes
    }

    var attemptCount: Int {
        lock.withLock { urls.count }
    }

    func record(_ url: URL) -> Bool {
        lock.withLock {
            urls.append(url)
            let outcomeIndex = urls.count - 1
            guard outcomeIndex < outcomes.count else {
                return false
            }
            return outcomes[outcomeIndex] == .granted
        }
    }
}
