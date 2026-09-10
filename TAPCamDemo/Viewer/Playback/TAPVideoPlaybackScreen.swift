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
    var loadingBottomInset: CGFloat = 0

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

            if selectedTool == .threeD {
                // Mount while projection prepares, but keep RGB/poster visible
                // until this session has a point-cloud frame. Gaps retain that
                // frame and its readiness instead of exposing the fallback again.
                TAPVideoPointCloudView(store: session.pointCloudStore)
                    .opacity(showsPointCloud ? 1 : 0)
                    .allowsHitTesting(showsPointCloud)
                    .accessibilityHidden(!showsPointCloud)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
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

    private var primaryStatusOverlay: some View {
        ZStack {
            LibraryMediaViewerFetchOverlay(
                kind: .tapVideo,
                state: fetchOverlayState,
                onRetry: onRetry,
                loadingBottomInset: loadingBottomInset
            )
            if case .failed(let message) = session.state,
               fetchOverlayState == .hidden {
                ContentUnavailableView(
                    "Unable to play video",
                    systemImage: "video.slash",
                    description: Text(message)
                )
                .foregroundStyle(.white)
                .padding()
            }
        }
    }

    private var fetchOverlayState: LibraryMediaFetchOverlayState {
        guard session.state == .ready else {
            return LibraryMediaFetchOverlayState(session.mediaFetchPhase)
        }
        let isPreparingDepth = selectedTool == .twoD
            ? session.isRegisteredDepthAvailable && !session.isTwoDPlaybackReady
            : selectedTool == .threeD && !session.isThreeDPlaybackReady
        let isPreparingPlayerFrame = !isPlayerFrameReady
            && !session.isReusingOriginal && !showsPointCloud
        return isPreparingPlayerFrame || isPreparingDepth ? .loading : .hidden
    }

    private var showsPointCloud: Bool {
        selectedTool == .threeD && session.isThreeDPlaybackReady
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
