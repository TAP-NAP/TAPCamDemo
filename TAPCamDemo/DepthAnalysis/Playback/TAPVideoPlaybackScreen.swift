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
    let systemPlaybackNotice: String?
    let onBackTapped: () -> Void
    let onShareTapped: () -> Void
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void
    let onSystemPlaybackRequiresRGB: () -> Void
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
                    onSystemPlaybackRequiresRGB: onSystemPlaybackRequiresRGB,
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

                TAPVideoPlaybackNoticeOverlay(
                    systemNotice: systemPlaybackNotice,
                    depthGapNotice: selectedTool == .twoD
                        ? session.depthGapNotice
                        : nil,
                    topSafeArea: insets.top,
                    availableWidth: size.width
                )
                .frame(width: size.width, height: size.height)
                .zIndex(6)
            }
            .animation(.snappy(duration: 0.2), value: systemPlaybackNotice)
        }
        .background(Color.black)
    }
}

private struct TAPVideoPlaybackContentSurface: View {
    let session: TAPVideoPlaybackSession
    let selectedTool: AnalysisViewerTool
    let overlayOpacity: Double
    let onRetry: () -> Void
    let onSystemPlaybackRequiresRGB: () -> Void
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
                    overlayOpacity: overlayOpacity,
                    onSystemPlaybackRequiresRGB: onSystemPlaybackRequiresRGB
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

private struct TAPVideoPlaybackNoticeOverlay: View {
    let systemNotice: String?
    let depthGapNotice: String?
    let topSafeArea: CGFloat
    let availableWidth: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            if let systemNotice {
                notice(systemNotice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let depthGapNotice {
                Label(depthGapNotice, systemImage: "waveform.path.ecg.rectangle")
                    .modifier(TAPVideoNoticeStyle(availableWidth: availableWidth))
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("tap.video.playback.depthGapNotice")
            }
            Spacer(minLength: 0)
        }
        .padding(
            .top,
            TAPVideoViewerChromeLayout.noticeTopPadding(topSafeArea: topSafeArea)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .modifier(TAPVideoNoticeStyle(availableWidth: availableWidth))
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct TAPVideoNoticeStyle: ViewModifier {
    let availableWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(
                maxWidth: TAPVideoViewerChromeLayout.noticeContentMaxWidth(
                    availableWidth: availableWidth
                )
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 24)
    }
}
