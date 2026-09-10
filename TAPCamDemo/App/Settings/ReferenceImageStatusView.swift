//
//  ReferenceImageStatusView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

struct ReferenceImageStatusView: View {
    let readiness: PhotoIntegrityReadiness
    let canPrepare: Bool
    let onPrepare: () async -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    if readiness == .preparing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

                Text("Reference Image status")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(LocalizedStringKey(readiness.statusText)))

            if canPrepare && readiness != .preparing {
                Button {
                    Task {
                        await onPrepare()
                    }
                } label: {
                    Text(LocalizedStringKey(readiness.preparationActionTitle))
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
            }

            Spacer(minLength: 0)

            Link(destination: URL(string: "https://verifier.tapnap.net/verify/")!) {
                HStack(spacing: 2) {
                    Text("Online Verifier")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
        .font(.footnote)
        .frame(minHeight: 44)
    }

    private var statusColor: Color {
        switch readiness {
        case .ready: .green
        case .preparationFailed: .red
        case .notReady, .preparing: .secondary
        }
    }
}
