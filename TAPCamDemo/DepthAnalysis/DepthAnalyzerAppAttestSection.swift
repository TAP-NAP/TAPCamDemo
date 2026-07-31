//
//  DepthAnalyzerAppAttestSection.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

struct DepthAnalyzerAppAttestSection: View {
    let readiness: PhotoIntegrityReadiness
    let canPrepare: Bool
    let onPrepare: () async -> Void

    var body: some View {
        Section("Photo Integrity") {
            statusRow
        }
    }

    private var statusRow: some View {
        LabeledContent {
            statusValue
        } label: {
            Text("Protection Readiness")
        }
    }

    @ViewBuilder
    private var statusValue: some View {
        if readiness == .preparing {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(readiness.statusText))
                    .foregroundStyle(.secondary)

                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            }
            .accessibilityElement(children: .combine)
        } else if canPrepare {
            VStack(alignment: .trailing, spacing: 6) {
                Text(LocalizedStringKey(readiness.statusText))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                Button {
                    Task {
                        await onPrepare()
                    }
                } label: {
                    Text(LocalizedStringKey(readiness.preparationActionTitle))
                }
                .buttonStyle(.borderless)
            }
        } else {
            Text(LocalizedStringKey(readiness.statusText))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
