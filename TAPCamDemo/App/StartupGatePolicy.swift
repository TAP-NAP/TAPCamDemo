//
//  StartupGatePolicy.swift
//  TAPCamDemo
//

import Foundation

/// Shared status for first-launch requirements.
///
/// Some requirements are real OS permissions, while the security preflight is a
/// backend health check. Keep this generic so the gate reads as startup policy
/// instead of pretending every row is an iOS permission prompt.
nonisolated enum StartupGateRequirementStatus: Equatable, Sendable {
    case idle
    case requesting
    case granted
    case denied
    case skipped
}

/// Stable first-launch checks shown by the welcome gate.
///
/// The backend security preflight is intentionally required before first camera
/// entry. It is product security policy, not an iOS network permission.
nonisolated enum StartupGateRequirementKind: CaseIterable, Equatable, Sendable {
    case securityPreflight
    case camera
    case photoLibrary
    case location
}

nonisolated struct StartupGateStatusSnapshot: Equatable, Sendable {
    let securityPreflight: StartupGateRequirementStatus
    let camera: StartupGateRequirementStatus
    let photoLibrary: StartupGateRequirementStatus
    let location: StartupGateRequirementStatus

    var hasCompletedRequiredStartupChecks: Bool {
        StartupGatePolicy.hasCompletedRequiredStartupChecks(self)
    }

    var hasBlockingStartupFailure: Bool {
        StartupGatePolicy.hasBlockingStartupFailure(self)
    }

    var hasSecurityPreflightFailure: Bool {
        securityPreflight == .denied
    }

    var hasSettingsResolvablePermissionFailure: Bool {
        camera == .denied || photoLibrary == .denied
    }
}

nonisolated enum StartupGatePolicy {
    static let requiredRequirements: [StartupGateRequirementKind] = [
        .securityPreflight,
        .camera,
        .photoLibrary
    ]

    static let optionalRequirements: [StartupGateRequirementKind] = [
        .location
    ]

    static func hasCompletedRequiredStartupChecks(_ snapshot: StartupGateStatusSnapshot) -> Bool {
        snapshot.securityPreflight == .granted
            && snapshot.camera == .granted
            && snapshot.photoLibrary == .granted
    }

    static func hasBlockingStartupFailure(_ snapshot: StartupGateStatusSnapshot) -> Bool {
        snapshot.securityPreflight == .denied
            || snapshot.camera == .denied
            || snapshot.photoLibrary == .denied
    }
}

enum StartupGateDefaults {
    // Keep the original stored key string so existing installs do not repeat first-launch setup.
    static let didCompleteFirstInstallSetupKey = "TAPCamDemo.StartupGate.didCompleteFirstInstallPermissions"
}
