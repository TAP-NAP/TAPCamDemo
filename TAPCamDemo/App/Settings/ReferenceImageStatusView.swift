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

                ScrollingStatusTitle(message: "TAPCam Protection")
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
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
            }

            Spacer(minLength: 0)

            Link(destination: URL(string: "https://www.tapnap.net/verify/")!) {
                HStack(spacing: 2) {
                    Text("Online Verifier")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
        }
        .font(.footnote)
        .lineLimit(1)
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

/// Scrolls overflowing text within one line without moving surrounding controls.
private struct ScrollingStatusTitle: View {
    let message: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var textWidth: CGFloat = 0

    var body: some View {
        Text(message)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let overflow = max(0, textWidth - geometry.size.width)
                    if reduceMotion {
                        ScrollView(.horizontal) {
                            fullText
                        }
                        .scrollIndicators(.hidden)
                    } else {
                        fullText
                            .keyframeAnimator(
                                initialValue: CGFloat.zero,
                                repeating: overflow > 0 && scenePhase == .active
                            ) { content, offset in
                                content.offset(x: -offset)
                            } keyframes: { _ in
                                LinearKeyframe(0, duration: 1.5)
                                LinearKeyframe(overflow, duration: max(0.01, overflow / 18))
                                LinearKeyframe(overflow, duration: 1.5)
                                MoveKeyframe(0)
                            }
                            .id(overflow)
                    }
                }
                .clipped()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(message))
    }

    private var fullText: some View {
        Text(message)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }
}
