//
//  LibraryMediaFetchOverlay.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

nonisolated enum LibraryMediaFetchOverlayState: Equatable, Sendable {
    case hidden
    case preparing
    case cloudOnly
    case downloading(progress: Double?)
    case failed(reason: MediaFetchFailure, retryable: Bool)

    init<Preview, Value>(_ phase: MediaFetchPhase<Preview, Value>) {
        switch phase {
        case .idle, .localPreview, .ready:
            self = .hidden
        case .resolving:
            self = .preparing
        case .cloudOnly:
            self = .cloudOnly
        case .downloadingFromICloud(_, let progress):
            self = .downloading(progress: progress)
        case .failed(_, let reason, let retryable):
            self = .failed(reason: reason, retryable: retryable)
        }
    }
}

/// Photo and video viewers share one active-loading treatment: keep any
/// lightweight preview visible and place one circular original-download
/// indicator above it. Cancellation remains owned by viewer navigation and
/// lifecycle; only terminal states expose recovery actions here.
struct LibraryMediaViewerFetchOverlay: View {
    let kind: LibraryMediaKind
    let state: LibraryMediaFetchOverlayState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .preparing:
            LibraryMediaProgressBadge(kind: kind, progress: nil)
        case .downloading(let progress):
            LibraryMediaProgressBadge(kind: kind, progress: progress)
        case .hidden:
            EmptyView()
        case .cloudOnly, .failed:
            LibraryMediaFetchOverlay(
                kind: kind,
                state: state,
                onCancel: {},
                onRetry: onRetry
            )
        }
    }
}

private struct LibraryMediaProgressBadge: View {
    let kind: LibraryMediaKind
    let progress: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 4)
                .frame(width: 44, height: 44)

            if let clampedProgress {
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(10)
        .background(.black.opacity(0.44), in: Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var clampedProgress: Double? {
        guard let progress, progress.isFinite else {
            return nil
        }
        return min(max(progress, 0), 1)
    }

    private var accessibilityLabel: String {
        switch kind {
        case .tapVideo:
            "Downloading video"
        case .photo, .livePhoto:
            "Downloading photo"
        }
    }
}

struct LibraryMediaFetchOverlay: View {
    let kind: LibraryMediaKind
    let state: LibraryMediaFetchOverlayState
    let onCancel: () -> Void
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if state != .hidden {
            VStack(spacing: 10) {
                switch state {
                case .hidden:
                    EmptyView()
                case .preparing:
                    ProgressView()
                        .tint(.white)
                    Text(LibraryMediaCopy.preparing(kind))
                case .cloudOnly:
                    Image(systemName: "icloud")
                    Text(LibraryMediaCopy.storedInICloud)
                    actionButton(LibraryMediaCopy.retry, action: onRetry)
                case .downloading(let progress):
                    ProgressView(value: progress)
                        .tint(.white)
                    Text(LibraryMediaCopy.loadingFromICloud(progress: progress))
                    actionButton(LibraryMediaCopy.cancel, action: onCancel)
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
