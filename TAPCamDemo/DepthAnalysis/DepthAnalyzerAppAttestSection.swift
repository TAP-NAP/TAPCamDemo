//
//  DepthAnalyzerAppAttestSection.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

struct DepthAnalyzerAppAttestSection: View {
    let statusText: String
    let keyID: AppAttestCredentialKeyIDPresentation?
    let isPreparingCredential: Bool
    let canResetAndPrepareCredential: Bool
    let actionTitle: String
    let showsHelp: Bool
    let onPrepare: () async -> Void

    var body: some View {
        Section("App Attest") {
            statusRow
            if showsHelp {
                AppAttestKeyIDHelpView(message: Self.keyIDHelpText)
            }
            if let keyID {
                AppAttestKeyIDInfoView(keyID: keyID)
            }
        }
    }

    private var statusRow: some View {
        LabeledContent {
            statusValue
        } label: {
            Text("Status")
        }
    }

    @ViewBuilder
    private var statusValue: some View {
        if isPreparingCredential {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Preparing App Attest credential")
        } else if canResetAndPrepareCredential {
            VStack(alignment: .trailing, spacing: 6) {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                Button {
                    Task {
                        await onPrepare()
                    }
                } label: {
                    Text(actionTitle)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Resets and prepares the App Attest credential.")
            }
        } else {
            Text(statusText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let keyIDHelpText = "KeyID identifies the App Attest key that this app prepared on this device. " +
        "The app uses that key to generate request assertions, and the backend uses the KeyID to find the registered credential for verification. " +
        "Settings show only a redacted KeyID summary."
}

// Help stays inline under Status so Release users can read it in context.
private struct AppAttestKeyIDHelpView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("KeyID help. \(message)")
    }
}

private struct AppAttestKeyIDInfoView: View {
    let keyID: AppAttestCredentialKeyIDPresentation

    var body: some View {
        Text(keyID.displayText)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .accessibilityLabel(keyID.accessibilityText)
    }
}
