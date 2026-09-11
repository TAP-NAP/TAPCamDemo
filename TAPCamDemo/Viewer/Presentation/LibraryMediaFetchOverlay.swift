//
//  LibraryMediaFetchOverlay.swift
//  TAPCamDemo
//

import ImageIO
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

/// Local preparation and cloud downloads share a quiet corner indicator.
/// The resource owner retains progress and cancellation; only terminal states
/// expose recovery actions in the Viewer.
struct LibraryMediaViewerFetchOverlay: View {
    let kind: LibraryMediaKind
    let state: LibraryMediaFetchOverlayState
    let onRetry: () -> Void
    var imageSize: CGSize? = nil
    var imageOrientation: CGImagePropertyOrientation = .up

    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geometry in
            let imageRect = DepthAnalysisViewerInteractionPolicy.aspectFitRect(
                imageSize: imageSize, orientation: imageOrientation, containerSize: geometry.size
            )
            let inset = DepthAnalysisLivePhotoBadge.Size.viewer.edgeInset
            ZStack {
                LibraryMediaLoadingRing(isLoading: state == .loading)
                    .accessibilityLabel(Text(LibraryMediaCopy.preparing(kind)))
                    .position(x: imageRect.maxX - inset, y: imageRect.maxY - inset)

                recoveryContent
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private var recoveryContent: some View {
        switch state {
        case .hidden, .loading:
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

/// Animation state belongs to this small indicator, never to the image or pager.
struct LibraryMediaLoadingRing: View {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.5), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // Only the arc rotates; initial layout must not repeat with it.
                .transaction { transaction in
                    transaction.disablesAnimations = false
                    transaction.animation = animating && !reduceMotion
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : nil
                } body: { arc in
                    arc.rotationEffect(.degrees(animating && !reduceMotion ? 360 : 0))
                }
        }
        .frame(width: 18, height: 18)
        .padding(4)
        .background(.black.opacity(0.32), in: Circle())
        .transaction { transaction in
            transaction.disablesAnimations = false
            transaction.animation = .easeInOut(duration: 0.18)
        } body: { ring in
            ring.opacity(animating ? 1 : 0)
        }
        .onChange(of: isLoading, initial: true) { _, loading in animating = loading }
        .allowsHitTesting(false)
        .accessibilityHidden(!isLoading)
    }
}
