//
//  StartupGatePolicy.swift
//  TAPCamDemo
//

import Foundation

/// Shared status for the visible first-install rows.
///
/// Some rows are OS permissions, while the frozen Network row is a backend
/// health check. Permission-specific routing uses
/// `RequiredPermissionSnapshot` below so `.limited` and `.restricted` are not
/// collapsed into this presentation model.
nonisolated enum StartupGateRequirementStatus: Equatable, Sendable {
    case idle
    case requesting
    case granted
    case denied
    case restricted
    case skipped
}

nonisolated enum StartupGateRequirementKind: CaseIterable, Equatable, Sendable {
    case securityPreflight
    case camera
    case photoLibrary
    case location
    case microphone
}

nonisolated struct StartupGateStatusSnapshot: Equatable, Sendable {
    let securityPreflight: StartupGateRequirementStatus
    let camera: StartupGateRequirementStatus
    let photoLibrary: StartupGateRequirementStatus
    let location: StartupGateRequirementStatus
    let microphone: StartupGateRequirementStatus

    var hasCompletedRequiredStartupChecks: Bool {
        StartupGatePolicy.hasCompletedRequiredStartupChecks(self)
    }

    var hasBlockingStartupFailure: Bool {
        StartupGatePolicy.hasBlockingStartupFailure(self)
    }

    var hasSecurityPreflightFailure: Bool {
        securityPreflight == .denied
    }
}

// MARK: - Canonical setup fact and frozen compatibility fact

/// Credential evidence required by a canonical Setup receipt.
///
/// No current `/healthz` result can construct this evidence. TAP-0008 keeps
/// that Network implementation frozen, so production does not write a
/// canonical receipt in this delivery.
nonisolated struct SetupCredentialBinding: Codable, Equatable, Sendable {
    let credentialName: String
    let keyIDFingerprint: String
    let environment: String

    var isStructurallyValid: Bool {
        !credentialName.isEmpty && !keyIDFingerprint.isEmpty && !environment.isEmpty
    }
}

/// A locally verified credential binding supplied by the App Attest storage
/// boundary. Merely decoding the same strings from UserDefaults does not create
/// one of these values. The current frozen Network implementation supplies no
/// production instance, so a canonical receipt cannot silently self-validate.
nonisolated struct VerifiedStartupCredentialBinding: Equatable, Sendable {
    let value: SetupCredentialBinding
}

nonisolated enum OptionalSetupChoice: String, Codable, Equatable, Sendable {
    case granted
    case skipped
    case unresolved
}

/// Canonical `S` shape. Version/build intentionally do not live here; they
/// belong to TAP-0009's initialization marker.
nonisolated struct SetupReceipt: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let bundleIdentifier: String
    let installationGenerationID: UUID
    let credentialBinding: SetupCredentialBinding
    let locationChoice: OptionalSetupChoice
    let microphoneChoice: OptionalSetupChoice
    let completedAt: Date
}

/// Explicitly non-canonical completion record used while Network/App Attest is
/// frozen. It separates Setup completion from the legacy camera-readiness bit
/// without claiming that `/healthz` supplied a credential binding.
nonisolated struct LegacySetupCompletionRecord: Codable, Equatable, Sendable {
    enum Evidence: String, Codable, Equatable, Sendable {
        case frozenLegacySecurityPreflight
        case migratedCombinedBoolean
    }

    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let installationGenerationID: UUID
    let evidence: Evidence
    let locationChoice: OptionalSetupChoice
    let microphoneChoice: OptionalSetupChoice
    let completedAt: Date
}

nonisolated enum SetupReceiptInvalidReason: Equatable, Sendable {
    case corruptReceipt
    case unsupportedSchema
    case bundleMismatch
    case installationGenerationMismatch
    case missingCredentialBinding
    case credentialBindingMismatch
    case corruptLegacyCompletion
}

nonisolated enum StartupSetupFact: Equatable, Sendable {
    case absent
    case valid(SetupReceipt)
    case invalid(SetupReceiptInvalidReason)
    case legacyCompleted(LegacySetupCompletionRecord?)

    var permitsPostSetupRouting: Bool {
        switch self {
        case .valid, .legacyCompleted:
            true
        case .absent, .invalid:
            false
        }
    }
}

/// Container-local generation. Delete-and-reinstall creates a new value;
/// offload preserves it. Restore/device validity still requires the canonical
/// credential binding and is deliberately not inferred from this UUID alone.
nonisolated struct StartupInstallationGenerationStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func currentOrCreate() -> UUID {
        if let rawValue = userDefaults.string(
            forKey: StartupGateDefaults.installationGenerationKey
        ), let generation = UUID(uuidString: rawValue) {
            return generation
        }

        let generation = UUID()
        userDefaults.set(
            generation.uuidString,
            forKey: StartupGateDefaults.installationGenerationKey
        )
        return generation
    }
}

/// Reads canonical S first, then the explicitly named frozen compatibility
/// record, and only then the historical combined Boolean. A present but invalid
/// newer record never falls back to the old Boolean.
struct StartupSetupFactStore {
    private let userDefaults: UserDefaults
    private let bundleIdentifier: String
    private let installationGenerationStore: StartupInstallationGenerationStore
    private let verifiedCredentialBinding: VerifiedStartupCredentialBinding?

    init(
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        verifiedCredentialBinding: VerifiedStartupCredentialBinding? = nil
    ) {
        self.userDefaults = userDefaults
        self.bundleIdentifier = bundleIdentifier
        self.verifiedCredentialBinding = verifiedCredentialBinding
        self.installationGenerationStore = StartupInstallationGenerationStore(
            userDefaults: userDefaults
        )
    }

    func load(legacyCombinedCompletion: Bool) -> StartupSetupFact {
        let installationGenerationID = installationGenerationStore.currentOrCreate()

        if userDefaults.object(forKey: StartupGateDefaults.setupReceiptKey) != nil {
            guard let data = userDefaults.data(forKey: StartupGateDefaults.setupReceiptKey),
                  let receipt = try? JSONDecoder().decode(SetupReceipt.self, from: data) else {
                return .invalid(.corruptReceipt)
            }
            return validate(
                receipt,
                installationGenerationID: installationGenerationID
            )
        }

        if userDefaults.object(forKey: StartupGateDefaults.legacySetupCompletionKey) != nil {
            guard let data = userDefaults.data(
                forKey: StartupGateDefaults.legacySetupCompletionKey
            ), let record = try? JSONDecoder().decode(
                LegacySetupCompletionRecord.self,
                from: data
            ), record.schemaVersion == LegacySetupCompletionRecord.currentSchemaVersion,
               record.installationGenerationID == installationGenerationID else {
                return .invalid(.corruptLegacyCompletion)
            }
            return .legacyCompleted(record)
        }

        return legacyCombinedCompletion ? .legacyCompleted(nil) : .absent
    }

    /// Records only the current frozen compatibility fact. This method cannot
    /// write `SetupReceipt` and therefore cannot turn `/healthz` into App Attest
    /// credential evidence.
    @discardableResult
    func recordFrozenLegacyCompletion(
        statusSnapshot: StartupGateStatusSnapshot,
        now: Date = Date()
    ) -> StartupSetupFact? {
        guard statusSnapshot.hasCompletedRequiredStartupChecks else {
            return nil
        }

        let record = LegacySetupCompletionRecord(
            schemaVersion: LegacySetupCompletionRecord.currentSchemaVersion,
            installationGenerationID: installationGenerationStore.currentOrCreate(),
            evidence: .frozenLegacySecurityPreflight,
            locationChoice: Self.optionalChoice(for: statusSnapshot.location),
            microphoneChoice: Self.optionalChoice(for: statusSnapshot.microphone),
            completedAt: now
        )
        guard let data = try? JSONEncoder().encode(record) else {
            return nil
        }
        userDefaults.set(data, forKey: StartupGateDefaults.legacySetupCompletionKey)
        return .legacyCompleted(record)
    }

    private func validate(
        _ receipt: SetupReceipt,
        installationGenerationID: UUID
    ) -> StartupSetupFact {
        guard receipt.schemaVersion == SetupReceipt.currentSchemaVersion else {
            return .invalid(.unsupportedSchema)
        }
        guard receipt.bundleIdentifier == bundleIdentifier else {
            return .invalid(.bundleMismatch)
        }
        guard receipt.installationGenerationID == installationGenerationID else {
            return .invalid(.installationGenerationMismatch)
        }
        guard receipt.credentialBinding.isStructurallyValid else {
            return .invalid(.missingCredentialBinding)
        }
        guard let verifiedCredentialBinding else {
            return .invalid(.missingCredentialBinding)
        }
        guard receipt.credentialBinding == verifiedCredentialBinding.value else {
            return .invalid(.credentialBindingMismatch)
        }
        return .valid(receipt)
    }

    private static func optionalChoice(
        for status: StartupGateRequirementStatus
    ) -> OptionalSetupChoice {
        switch status {
        case .granted:
            .granted
        case .skipped:
            .skipped
        case .idle, .requesting, .denied, .restricted:
            .unresolved
        }
    }
}

// MARK: - Required permission snapshot and route

nonisolated enum RequiredPermissionStatus: Equatable, Sendable {
    case authorized
    case limited
    case notDetermined
    case denied
    case restricted
    case unknown
}

nonisolated struct RequiredPermissionSnapshot: Equatable, Sendable {
    let camera: RequiredPermissionStatus
    let photoLibrary: RequiredPermissionStatus

    static let unresolved = RequiredPermissionSnapshot(
        camera: .unknown,
        photoLibrary: .unknown
    )

    var isUsable: Bool {
        camera == .authorized
            && (photoLibrary == .authorized || photoLibrary == .limited)
    }
}

nonisolated enum StartupSetupMode: Equatable, Sendable {
    case initial
    case credentialRecovery
}

nonisolated enum StartupResumeTarget: Equatable, Sendable {
    case viewfinder
}

nonisolated struct StartupRouteFacts: Equatable, Sendable {
    let setup: StartupSetupFact
    let requiredPermissions: RequiredPermissionSnapshot
    let initialization: StartupInitializationFact
}

nonisolated enum StartupRoute: Equatable, Sendable {
    case firstInstallSetup(StartupSetupMode)
    case requiredPermissionCheck(resumeTarget: StartupResumeTarget)
    case resourceInitialization
    case viewfinder
}

nonisolated enum StartupFirstInstallContinueAction: Equatable, Sendable {
    case stayOnWelcome
    case enterResourceInitialization
}

nonisolated enum StartupGatePolicy {
    static let requiredRequirements: [StartupGateRequirementKind] = [
        .securityPreflight,
        .camera,
        .photoLibrary
    ]

    static let optionalRequirements: [StartupGateRequirementKind] = [
        .location,
        .microphone
    ]

    static func hasCompletedRequiredStartupChecks(
        _ snapshot: StartupGateStatusSnapshot
    ) -> Bool {
        snapshot.securityPreflight == .granted
            && snapshot.camera == .granted
            && snapshot.photoLibrary == .granted
    }

    static func hasBlockingStartupFailure(_ snapshot: StartupGateStatusSnapshot) -> Bool {
        [snapshot.securityPreflight, snapshot.camera, snapshot.photoLibrary]
            .contains { $0 == .denied || $0 == .restricted }
    }

    static func firstInstallContinueAction(
        for snapshot: StartupGateStatusSnapshot
    ) -> StartupFirstInstallContinueAction {
        hasCompletedRequiredStartupChecks(snapshot)
            ? .enterResourceInitialization
            : .stayOnWelcome
    }

    static func route(for facts: StartupRouteFacts) -> StartupRoute {
        switch facts.setup {
        case .absent:
            return .firstInstallSetup(.initial)
        case .invalid:
            return .firstInstallSetup(.credentialRecovery)
        case .valid, .legacyCompleted:
            break
        }

        guard facts.requiredPermissions.isUsable else {
            return .requiredPermissionCheck(resumeTarget: .viewfinder)
        }

        return facts.initialization.isCurrent ? .viewfinder : .resourceInitialization
    }

    static func shouldActivatePhotoLibraryObservation(
        setup: StartupSetupFact,
        didCompleteExplicitPhotosAction: Bool,
        photoLibraryStatus: RequiredPermissionStatus
    ) -> Bool {
        let photosUsable = photoLibraryStatus == .authorized
            || photoLibraryStatus == .limited
        return photosUsable
            && (setup.permitsPostSetupRouting || didCompleteExplicitPhotosAction)
    }
}

nonisolated enum StartupGateDefaults {
    /// Historical combined Setup/camera-readiness bit. New code reads it only
    /// as a compatibility input and never calls it a canonical S or I marker.
    static let legacyCombinedCompletionKey =
        "TAPCamDemo.StartupGate.didCompleteFirstInstallPermissions"
    static let setupReceiptKey = "TAPCamDemo.StartupGate.setupReceipt.v1"
    static let legacySetupCompletionKey =
        "TAPCamDemo.StartupGate.legacySetupCompletion.v1"
    static let installationGenerationKey =
        "TAPCamDemo.StartupGate.installationGeneration.v1"
}
