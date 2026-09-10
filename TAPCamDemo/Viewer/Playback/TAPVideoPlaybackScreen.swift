//
//  TAPVideoPlaybackScreen.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import SwiftUI

struct TAPVideoPlaybackContentSurface: View {
    let session: TAPVideoPlaybackSession
    @Binding var selectedTool: AnalysisViewerTool
    @Binding var overlayOpacity: Double
    let onRetry: () -> Void

    @State private var readyPlayerID: ObjectIdentifier?

    var body: some View {
        ZStack {
            Color.black

            if let player = session.player {
                TAPVideoPlayerSurfaceView(
                    player: player,
                    overlayStore: session.overlayStore,
                    showsRegisteredDepth: selectedTool == .twoD,
                    overlayOpacity: overlayOpacity,
                    onReadyForDisplay: { playerID, isReady in
                        acceptPlayerFrameReadiness(
                            playerID: playerID,
                            isReady: isReady
                        )
                    }
                )
                .contentShape(Rectangle())
                .clipped()
            }

            if selectedTool == .threeD {
                TAPVideoPointCloudView(store: session.pointCloudStore)
                    .background(Color.black)
            }

            // Keep the poster above the warming AVPlayerLayer. AVPlayer creation
            // is not a first-frame guarantee; uncovering it earlier produces a
            // visible black flash when the loading indicator disappears.
            loadingPreview
                .opacity(showsLoadingPreview ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!showsLoadingPreview)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }

            primaryStatusOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var loadingPreview: some View {
        ZStack {
            Color.black
            if let image = session.loadingPreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    @ViewBuilder
    private var primaryStatusOverlay: some View {
        switch session.state {
        case .idle, .loading:
            LibraryMediaViewerFetchOverlay(
                kind: .tapVideo,
                state: LibraryMediaFetchOverlayState(session.mediaFetchPhase),
                onRetry: onRetry
            )
        case .failed(let message):
            if LibraryMediaFetchOverlayState(session.mediaFetchPhase) == .hidden {
                ContentUnavailableView(
                    "Unable to play video",
                    systemImage: "video.slash",
                    description: Text(message)
                )
                .foregroundStyle(.white)
                .padding()
            } else {
                LibraryMediaViewerFetchOverlay(
                    kind: .tapVideo,
                    state: LibraryMediaFetchOverlayState(session.mediaFetchPhase),
                    onRetry: onRetry
                )
            }
        case .ready:
            let isPreparingDepth = selectedTool == .twoD
                ? session.isRegisteredDepthAvailable && !session.isTwoDPlaybackReady
                : selectedTool == .threeD && !session.isThreeDPlaybackReady
            LibraryMediaViewerFetchOverlay(
                kind: .tapVideo,
                state: (!isPlayerFrameReady && !session.isReusingOriginal) || isPreparingDepth ? .loading : .hidden,
                onRetry: onRetry
            )
        }
    }

    private var showsLoadingPreview: Bool {
        TAPVideoFirstFramePresentationPolicy.showsLoadingPreview(
            state: session.state,
            isPlayerFrameReady: isPlayerFrameReady
        )
    }

    private var playerIdentity: ObjectIdentifier? {
        session.player.map(ObjectIdentifier.init)
    }

    private func acceptPlayerFrameReadiness(
        playerID: ObjectIdentifier,
        isReady: Bool
    ) {
        // Readiness is monotonic for one player. A transient false KVO update
        // during seek/buffering must never put the poster back over playback.
        guard isReady else {
            return
        }
        guard playerID == playerIdentity else {
            return
        }
        guard readyPlayerID != playerID else {
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            readyPlayerID = playerID
        }
    }

    private var isPlayerFrameReady: Bool {
        guard let playerIdentity else {
            return false
        }
        return readyPlayerID == playerIdentity
    }
}

nonisolated enum TAPVideoFirstFramePresentationPolicy {
    static func showsLoadingPreview(
        state: TAPVideoPlaybackLoadState,
        isPlayerFrameReady: Bool
    ) -> Bool {
        switch state {
        case .ready:
            !isPlayerFrameReady
        case .idle, .loading, .failed:
            true
        }
    }
}
