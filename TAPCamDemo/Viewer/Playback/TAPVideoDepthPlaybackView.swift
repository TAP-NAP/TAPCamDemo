//
//  TAPVideoDepthPlaybackView.swift
//  TAPCamDemo
//

import Combine
import OSLog
import SwiftUI
import UIKit

struct TAPVideoDepthPlaybackView: View {
    private let source: TAPVideoPlaybackSource
    private let albumContext: TAPVideoAlbumContext?
    private let onCurrentAlbumEntryChanged: ((TAPVideoAlbumContext.Entry) -> Void)?
    private let onMixedMediaEntryChanged: ((DepthAlbumDeletionContext.Entry) -> Void)?
    private let deletionContext: DepthAlbumDeletionContext?
    private let onDeletionCompleted: ((String, DepthAlbumDeletionContext.Entry?) -> Void)?
    private let registrationAdapter: any TAPVideoDepthRegistrationAdapting
    private let mediaFetcher: any LibraryMediaFetching

    @Environment(\.dismiss) private var dismiss
    @State private var session: TAPVideoPlaybackSession
    @State private var selectedTool = AnalysisViewerTool.raw
    @State private var depthOverlayOpacity = 0.58
    @State private var deleteAlert: TAPVideoDeleteAlert?
    @State private var removedVideoEntryIDs: Set<String> = []
    @State private var sessionGeneration: UInt64 = 0
    @State private var sessionSource: TAPVideoPlaybackSource

    init(
        source: TAPVideoPlaybackSource,
        albumContext: TAPVideoAlbumContext? = nil,
        onCurrentAlbumEntryChanged: ((TAPVideoAlbumContext.Entry) -> Void)? = nil,
        onMixedMediaEntryChanged: ((DepthAlbumDeletionContext.Entry) -> Void)? = nil,
        deletionContext: DepthAlbumDeletionContext? = nil,
        onDeletionCompleted: ((String, DepthAlbumDeletionContext.Entry?) -> Void)? = nil,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting =
            TAPVideoManifestDepthRegistrationAdapter(),
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()
    ) {
        self.source = source
        self.albumContext = albumContext
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
        self.onMixedMediaEntryChanged = onMixedMediaEntryChanged
        self.deletionContext = deletionContext
        self.onDeletionCompleted = onDeletionCompleted
        self.registrationAdapter = registrationAdapter
        self.mediaFetcher = mediaFetcher
        let currentItemID = albumContext?.currentItemID
            ?? source.libraryMediaID.storageValue
        _session = State(initialValue: TAPVideoPlaybackSession(
            source: source,
            registrationAdapter: registrationAdapter,
            mediaFetcher: mediaFetcher,
            initialLoadingPreviewImage: TAPLibraryPagingPreviewCache.shared.image(
                for: currentItemID
            )
        ))
        _sessionSource = State(initialValue: source)
    }

    var body: some View {
        TAPVideoPlaybackScreen(
            session: session,
            pagingEntries: pagingEntries,
            currentItemID: currentItemID,
            pageContentRevision: sessionGeneration,
            mediaFetcher: mediaFetcher,
            selectedTool: $selectedTool,
            depthOverlayOpacity: $depthOverlayOpacity,
            shareSubject: DepthAnalysisShareSubject(
                videoSource: sessionSource,
                itemID: currentItemID
            ),
            onModeTapped: handleModeTapped,
            onDeleteTapped: deleteCurrentVideo,
            onCurrentPagingEntryChanged: moveToPagingEntry
        )
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarRole(.editor)
        .navigationTitle(Text(verbatim: ""))
        .ignoresSafeArea(.container, edges: .all)
        .alert(item: $deleteAlert) { alert in
            switch alert {
            case .confirmPending(let source):
                Alert(
                    title: Text("Delete unsaved video?"),
                    message: Text("This video has not finished exporting to Photos. Deleting it removes the local TAP copy and cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        performDelete(source: source)
                    },
                    secondaryButton: .cancel()
                )
            case .failure:
                Alert(
                    title: Text("Unable to delete video"),
                    message: Text("Try again from TAP Library."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .task(id: playbackTaskIdentity) {
            let activeSession = session
            await activeSession.startPlaybackSession()
            guard !Task.isCancelled else {
                return
            }
            prepareSelectedTool(on: activeSession)
        }
        .onChange(of: source) { _, updatedSource in
            replacePlaybackSessionIfNeeded(
                to: updatedSource,
                itemID: currentItemID
            )
        }
        .onChange(of: selectedTool) { _, _ in
            prepareSelectedTool(on: session)
        }
        .onDisappear(perform: session.stopPlayback)
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            session.handleDidEnterBackground()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            session.resumeCanceledFetchAfterBackground()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            session.handleMemoryWarning()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .tapLibraryDidChange)
        ) { notification in
            guard case .pendingCapture(let captureID) = sessionSource,
                  let change = notification.object as? TAPLibraryPendingCaptureChange,
                  change.captureID == captureID else {
                return
            }
            let refreshSession = session
            let refreshSource = sessionSource
            guard let refreshID = refreshSession.claimPendingSignedOriginalRefresh() else {
                return
            }
            Task { @MainActor in
                guard session === refreshSession,
                      sessionSource == refreshSource else {
                    refreshSession.cancelPendingSignedOriginalRefreshClaim(refreshID)
                    return
                }
                guard let record = try? await TAPPendingCaptureStore.shared
                    .readRecord(captureID: captureID),
                      record.videoArtifactState == .signed else {
                    refreshSession.cancelPendingSignedOriginalRefreshClaim(refreshID)
                    return
                }
                guard session === refreshSession,
                      sessionSource == refreshSource else {
                    refreshSession.cancelPendingSignedOriginalRefreshClaim(refreshID)
                    return
                }
                _ = refreshSession.startClaimedPendingSignedOriginalRefresh(refreshID)
            }
        }
    }

    private func handleModeTapped(_ itemID: String) {
        guard let tool = AnalysisViewerTool(rawValue: itemID) else { return }
        switch tool {
        case .raw: break
        case .twoD:
            guard session.isRegisteredDepthAvailable else { return }
        case .threeD:
            guard session.isThreeDDepthAvailable else { return }
        }
        selectedTool = tool
    }

    private func prepareSelectedTool(on activeSession: TAPVideoPlaybackSession) {
        switch selectedTool {
        case .raw:
            activeSession.cancelTwoDPlaybackGate()
            activeSession.cancelThreeDPlaybackGate()
        case .twoD:
            activeSession.prepareTwoDPlaybackGate()
        case .threeD:
            activeSession.prepareThreeDPlaybackGate()
        }
    }

    private func deleteCurrentVideo() {
        if sessionSource.requiresUnsavedDeleteConfirmation {
            deleteAlert = .confirmPending(sessionSource)
        } else {
            performDelete(source: sessionSource)
        }
    }

    private func performDelete(source: TAPVideoPlaybackSource) {
        Task { @MainActor in
            do {
                try await TAPVideoDeletionService.delete(source: source)
                let deletedItemID = albumContext?.currentItemID
                    ?? source.libraryMediaID.storageValue
                removedVideoEntryIDs.insert(deletedItemID)

                if let onDeletionCompleted {
                    let nextEntry = deletionContext?.entryAfterDeleting(
                        deletedItemID,
                        excluding: removedVideoEntryIDs
                    )
                    if let nextEntry {
                        preparePlaybackForPagingTarget(
                            TAPLibraryViewerPagingEntry(nextEntry)
                        )
                    } else {
                        session.stopPlayback()
                    }
                    onDeletionCompleted(deletedItemID, nextEntry)
                    if nextEntry == nil {
                        dismiss()
                    }
                } else if let nextEntry = albumContext?.entryAfterDeletingCurrent(
                    excluding: removedVideoEntryIDs
                ) {
                    let route = DepthAlbumRouteAdapter.videoRoute(for: nextEntry)
                    replacePlaybackSessionIfNeeded(
                        to: route.source,
                        itemID: nextEntry.id
                    )
                    onCurrentAlbumEntryChanged?(nextEntry)
                } else {
                    session.stopPlayback()
                    dismiss()
                }
            } catch is CancellationError {
                return
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.photoLibrary.error("video delete failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                deleteAlert = .failure
            }
        }
    }

    private var currentItemID: String {
        albumContext?.currentItemID ?? source.libraryMediaID.storageValue
    }

    private var playbackTaskIdentity: TAPVideoPlaybackTaskIdentity {
        TAPVideoPlaybackTaskIdentity(
            session: ObjectIdentifier(session),
            requestKey: session.requestKey
        )
    }

    /// A video/source change replaces only playback ownership. The stable
    /// viewer, pager, chrome, and target poster remain on screen.
    private func replacePlaybackSessionIfNeeded(
        to updatedSource: TAPVideoPlaybackSource,
        itemID: String
    ) {
        guard sessionSource != updatedSource else {
            return
        }
        let isSameMedia = sessionSource.libraryMediaID == updatedSource.libraryMediaID
        let targetPreview = TAPLibraryPagingPreviewCache.shared.image(for: itemID)
        let handoffPreview = targetPreview
            ?? (isSameMedia ? session.loadingPreviewImage : nil)
        let replacement = TAPVideoPlaybackSession(
            source: updatedSource,
            registrationAdapter: registrationAdapter,
            mediaFetcher: mediaFetcher,
            initialLoadingPreviewImage: handoffPreview
        )
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            session.stopPlayback()
            if !isSameMedia {
                selectedTool = .raw
            }
            session = replacement
            sessionSource = updatedSource
            sessionGeneration &+= 1
        }
    }

    private func preparePlaybackForPagingTarget(
        _ target: TAPLibraryViewerPagingEntry
    ) {
        guard case .video(let route) = target.destination else {
            session.stopPlayback()
            return
        }
        replacePlaybackSessionIfNeeded(
            to: route.source,
            itemID: target.id
        )
    }

    private var pagingEntries: [TAPLibraryViewerPagingEntry] {
        if let deletionContext {
            return deletionContext.pagingEntries(
                from: currentItemID,
                excluding: removedVideoEntryIDs
            ).map(TAPLibraryViewerPagingEntry.init)
        }

        guard let albumContext,
              albumContext.entries.contains(where: {
                  $0.id == currentItemID
              }) else {
            return [TAPLibraryViewerPagingEntry(
                id: currentItemID,
                destination: .video(TAPVideoPlaybackRoute(
                    itemID: currentItemID,
                    source: source
                ))
            )]
        }

        let visibleEntries = albumContext.entries.filter {
            !removedVideoEntryIDs.contains($0.id)
        }
        guard let visibleCurrentIndex = visibleEntries.firstIndex(where: {
            $0.id == currentItemID
        }) else {
            return []
        }
        let lowerBound = max(visibleCurrentIndex - 1, visibleEntries.startIndex)
        let upperBound = min(
            visibleCurrentIndex + 1,
            visibleEntries.index(before: visibleEntries.endIndex)
        )
        return visibleEntries[lowerBound...upperBound].map { entry in
            TAPLibraryViewerPagingEntry(
                id: entry.id,
                destination: .video(DepthAlbumRouteAdapter.videoRoute(for: entry))
            )
        }
    }

    private func moveToPagingEntry(_ target: TAPLibraryViewerPagingEntry) {
        if let entry = deletionContext?.entries.first(where: {
            $0.id == target.id && !removedVideoEntryIDs.contains($0.id)
        }) {
            preparePlaybackForPagingTarget(target)
            onMixedMediaEntryChanged?(entry)
            return
        }

        guard let entry = albumContext?.entries.first(where: {
            $0.id == target.id && !removedVideoEntryIDs.contains($0.id)
        }) else {
            return
        }
        preparePlaybackForPagingTarget(target)
        onCurrentAlbumEntryChanged?(entry)
    }
}

private enum TAPVideoDeleteAlert: Hashable, Identifiable {
    case confirmPending(TAPVideoPlaybackSource)
    case failure

    var id: Self { self }
}

private struct TAPVideoPlaybackTaskIdentity: Hashable {
    let session: ObjectIdentifier
    let requestKey: MediaFetchRequestKey?
}
