//
//  TAPVideoPlaybackScreen.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import SwiftUI

struct TAPVideoPlaybackScreen: View {
    let session: TAPVideoPlaybackSession
    let pagingEntries: [TAPLibraryViewerPagingEntry]
    let currentItemID: String
    let pageContentRevision: UInt64
    let mediaFetcher: any LibraryMediaFetching
    @Binding var selectedTool: AnalysisViewerTool
    @Binding var depthOverlayOpacity: Double
    let shareSubject: DepthAnalysisShareSubject?
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void
    let onCurrentPagingEntryChanged: (TAPLibraryViewerPagingEntry) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let insets = geometry.safeAreaInsets
            ZStack {
                TAPLibraryNativePagingView(
                    entries: pagingEntries,
                    currentItemID: currentItemID,
                    pageContentRevision: pageContentRevision,
                    pageBuilder: { entry, isCurrent, pageSize in
                        if isCurrent {
                            return AnyView(
                                TAPVideoPlaybackContentSurface(
                                    session: session,
                                    selectedTool: $selectedTool,
                                    overlayOpacity: $depthOverlayOpacity,
                                    onRetry: session.retryCurrentFetch
                                )
                                .frame(width: pageSize.width, height: pageSize.height)
                            )
                        }
                        return AnyView(
                            TAPLibraryAdjacentMediaPreview(
                                entry: entry,
                                viewportSize: pageSize,
                                mediaFetcher: mediaFetcher
                            )
                        )
                    },
                    onCurrentEntryChanged: onCurrentPagingEntryChanged,
                    onPagingInteractionChanged: { isInteracting in
                        if isInteracting {
                            session.beginInteractivePaging()
                        } else {
                            session.endInteractivePaging()
                        }
                    }
                )
                .frame(width: size.width, height: size.height)
                .background(Color.black)

                TAPVideoPlaybackSessionChrome(
                    session: session,
                    selectedTool: selectedTool,
                    overlayOpacity: $depthOverlayOpacity,
                    shareSubject: shareSubject,
                    topSafeArea: insets.top,
                    bottomSafeArea: insets.bottom,
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
                if !session.isThreeDPlaybackReady {
                    ProgressView().tint(.white).accessibilityLabel("Preparing 3D")
                }
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
            LibraryMediaViewerFetchOverlay(
                kind: .tapVideo,
                state: isPlayerFrameReady ? .hidden : .preparing,
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

/// Keeps session observation below the screen root. Player readiness and depth
/// availability must update only the chrome leaf, not rebuild the native pager.
private struct TAPVideoPlaybackSessionChrome: View {
    let session: TAPVideoPlaybackSession
    let selectedTool: AnalysisViewerTool
    @Binding var overlayOpacity: Double
    let shareSubject: DepthAnalysisShareSubject?
    let topSafeArea: CGFloat
    let bottomSafeArea: CGFloat
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        TAPVideoViewerChrome(
            transportModel: session.transportModel,
            selectedTool: selectedTool,
            availability: session.registeredDepthAvailability,
            isTwoDPlaybackReady: session.isTwoDPlaybackReady,
            isThreeDDepthAvailable: session.isThreeDDepthAvailable,
            isThreeDPlaybackReady: session.isThreeDPlaybackReady,
            overlayOpacity: $overlayOpacity,
            shareSubject: shareSubject,
            shareResourceAccess: DepthAnalysisShareResourceAccess(
                isReady: session.isOriginalResourceReady,
                acquire: {
                    guard let lease = try? session.acquireOriginalResourceLease() else {
                        return nil
                    }
                    return .video(lease)
                }
            ),
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea,
            onModeTapped: onModeTapped,
            onDeleteTapped: onDeleteTapped
        )
    }
}
