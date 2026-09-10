//
//  AppAttestCredentialPresentation.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation

nonisolated enum PhotoIntegrityReadiness: Equatable, Sendable {
    case notReady
    case preparing
    case ready
    case preparationFailed

    var statusText: String {
        switch self {
        case .notReady:
            "Not Ready"
        case .preparing:
            "Preparing"
        case .ready:
            "Ready"
        case .preparationFailed:
            "Preparation Failed"
        }
    }

    var preparationActionTitle: String {
        self == .preparationFailed ? "Retry" : "Prepare"
    }
}

nonisolated enum AppAttestCredentialPresentation {
    static let notPreparedStatusText = "Not prepared"
    static let readyStatusText = "Ready"
    static let resetStatusText = "Reset local credential."
    private static let failureStatusSuffix = " failed. See diagnostics for details."

    static func failureStatusText(label: String) -> String {
        "\(label)\(failureStatusSuffix)"
    }

    static func isFailureStatusText(_ statusText: String) -> Bool {
        statusText.hasSuffix(failureStatusSuffix)
    }
}

nonisolated enum AppAttestBackendPresentation {
    static let configuredHTTPBackendSummary = "HTTP backend configured"
    static let unavailableBackendSummary = "Backend configuration unavailable"
    static let configuredBackendSummary = "Backend configured"

    static func publicSummary(
        backendURL: URL?,
        backendDescription: String
    ) -> String {
        if backendURL != nil {
            return configuredHTTPBackendSummary
        }
        if backendDescription == unavailableBackendSummary || backendDescription == "Configuration unavailable" {
            return unavailableBackendSummary
        }
        return configuredBackendSummary
    }
}

nonisolated struct AppAttestCredentialKeyIDPresentation: Equatable {
    let displayText: String
    let accessibilityText: String

    init(keyID: String) {
        let count = keyID.count
        if count > 8 {
            displayText = "\(keyID.prefix(4))...\(keyID.suffix(4)) (\(count) chars)"
        } else {
            displayText = "Prepared key (\(count) chars)"
        }
        accessibilityText = "Prepared App Attest key identifier, redacted, \(count) characters."
    }
}
