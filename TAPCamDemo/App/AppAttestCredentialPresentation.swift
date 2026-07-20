//
//  AppAttestCredentialPresentation.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation

nonisolated enum AppAttestCredentialPresentation {
    static let notPreparedStatusText = "Not prepared"
    static let readyStatusText = "Ready"
    static let resetStatusText = "Reset local credential."

    static func failureStatusText(label: String) -> String {
        "\(label) failed. See diagnostics for details."
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
