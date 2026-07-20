//
//  TAPVideoPlaybackScreen.swift
//  TAPCamDemo
//

import SwiftUI

struct TAPVideoPlaybackScreen: View {
    let session: TAPVideoPlaybackSession
    @Binding var selectedTool: AnalysisViewerTool
    @Binding var depthOverlayOpacity: Double
    let isPreparingShare: Bool
    let onBackTapped: () -> Void
    let onShareTapped: () -> Void
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void
    let onMoveVideo: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let insets = geometry.safeAreaInsets
            ZStack {
                TAPVideoPlaybackContentSurface(
                    session: session,
                    selectedTool: selectedTool,
                    overlayOpacity: depthOverlayOpacity,
                    onRetry: session.retryCurrentFetch,
                    onMoveVideo: onMoveVideo
                )
                .frame(width: size.width, height: size.height)
                .background(Color.black)

                TAPVideoViewerChrome(
                    player: session.player,
                    selectedTool: selectedTool,
                    availability: session.registeredDepthAvailability,
                    isTwoDPlaybackReady: session.isTwoDPlaybackReady,
                    overlayOpacity: $depthOverlayOpacity,
                    isSharePreparing: isPreparingShare,
                    topSafeArea: insets.top,
                    bottomSafeArea: insets.bottom,
                    onBackTapped: onBackTapped,
                    onShareTapped: onShareTapped,
                    onModeTapped: onModeTapped,
                    onDeleteTapped: onDeleteTapped
                )
                .frame(width: size.width, height: size.height)
                .zIndex(5)

            }
        }
        .background(Color.black)
    }
}

private struct TAPVideoPlaybackContentSurface: View {
    let session: TAPVideoPlaybackSession
    let selectedTool: AnalysisViewerTool
    let overlayOpacity: Double
    let onRetry: () -> Void
    let onMoveVideo: (Int) -> Void

    @ViewBuilder
    var body: some View {
        switch session.state {
        case .idle, .loading:
            ZStack {
                loadingPreview
                LibraryMediaViewerFetchOverlay(
                    kind: .tapVideo,
                    state: LibraryMediaFetchOverlayState(session.mediaFetchPhase),
                    onRetry: onRetry
                )
            }
            .contentShape(Rectangle())
            .gesture(swipeGesture)
        case .failed(let message):
            ZStack {
                loadingPreview
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
            }
        case .ready:
            playbackSurface
        }
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
    private var playbackSurface: some View {
        ZStack {
            Color.black
            if let player = session.player {
                TAPVideoPlayerSurfaceView(
                    player: player,
                    overlayStore: session.overlayStore,
                    showsRegisteredDepth: selectedTool == .twoD,
                    overlayOpacity: overlayOpacity
                )
                .contentShape(Rectangle())
                .gesture(swipeGesture)
                .clipped()
            } else {
                ProgressView().tint(.white)
            }

            if selectedTool == .twoD, session.isPreparingTwoDPlayback {
                ZStack {
                    Color.black.opacity(0.62)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .accessibilityLabel("Preparing 2D playback")
                        .accessibilityIdentifier("tap.video.playback.2d.preparing")
                }
                .allowsHitTesting(false)
                .zIndex(3)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.predictedEndTranslation.width
                let vertical = value.predictedEndTranslation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 80 else {
                    return
                }
                onMoveVideo(horizontal < 0 ? 1 : -1)
            }
    }
}
