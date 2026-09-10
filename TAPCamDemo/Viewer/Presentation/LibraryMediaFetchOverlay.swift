//
//  LibraryMediaFetchOverlay.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

nonisolated enum LibraryMediaFetchOverlayState: Equatable, Sendable {
    case hidden
    case loading
    case cloudOnly
    case failed(reason: MediaFetchFailure, retryable: Bool)

    init<Preview, Value>(_ phase: MediaFetchPhase<Preview, Value>) {
        switch phase {
        case .idle, .localPreview, .ready:
            self = .hidden
        case .resolving, .downloadingFromICloud:
            self = .loading
        case .cloudOnly:
            self = .cloudOnly
        case .failed(_, let reason, let retryable):
            self = .failed(reason: reason, retryable: retryable)
        }
    }
}

/// Local preparation and cloud downloads use the same stable native spinner.
/// The resource owner retains progress and cancellation; only terminal states
/// expose recovery actions in the Viewer.
struct LibraryMediaViewerFetchOverlay: View {
    let kind: LibraryMediaKind
    let state: LibraryMediaFetchOverlayState
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .frame(width: 64, height: 64)
                .background(.black.opacity(0.44), in: Circle())
                .accessibilityLabel(Text(LibraryMediaCopy.preparing(kind)))
                .allowsHitTesting(false)
        case .hidden:
            EmptyView()
        case .cloudOnly, .failed:
            VStack(spacing: 10) {
                switch state {
                case .hidden, .loading:
                    EmptyView()
                case .cloudOnly:
                    Image(systemName: "icloud")
                    Text(LibraryMediaCopy.storedInICloud)
                    actionButton(LibraryMediaCopy.retry, action: onRetry)
                case .failed(let reason, let retryable):
                    Image(systemName: failureSystemImage(reason))
                    Text(LibraryMediaCopy.failureTitle(reason))
                        .font(.footnote.weight(.semibold))
                    Text(LibraryMediaCopy.failureMessage(reason))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                    if reason == .permission {
                        actionButton(LibraryMediaCopy.goToSettings) {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            openURL(url)
                        }
                    } else if retryable {
                        actionButton(LibraryMediaCopy.retry, action: onRetry)
                    }
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(24)
            .accessibilityElement(children: .combine)
        }
    }

    private func actionButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
    }

    private func failureSystemImage(_ failure: MediaFetchFailure) -> String {
        switch failure {
        case .permission:
            "photo.badge.exclamationmark"
        case .offline:
            "wifi.slash"
        case .assetRemoved:
            "photo.slash"
        case .download:
            "icloud.slash"
        case .decode:
            "exclamationmark.triangle"
        }
    }
}
