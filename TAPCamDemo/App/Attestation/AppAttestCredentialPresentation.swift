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

nonisolated enum AppAttestCredentialStatus: Equatable {
    case notPrepared
    case ready
    case reset
    case failed(operation: String)

    var statusText: String {
        switch self {
        case .notPrepared:
            "Not prepared"
        case .ready:
            "Ready"
        case .reset:
            "Reset local credential."
        case .failed(let operation):
            "\(operation) failed. See diagnostics for details."
        }
    }
}

nonisolated enum AppAttestBackendPresentation {
    static let configuredHTTPBackendSummary = "HTTP backend configured"
    static let unavailableBackendSummary = "Backend configuration unavailable"
    static let configuredBackendSummary = "Backend configured"
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
