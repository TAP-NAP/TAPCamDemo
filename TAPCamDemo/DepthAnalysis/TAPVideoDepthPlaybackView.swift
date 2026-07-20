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
    private let deletionContext: DepthAlbumDeletionContext?
    private let onDeletionCompleted: ((String, DepthAlbumDeletionContext.Entry?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var session: TAPVideoPlaybackSession
    @State private var selectedTool = AnalysisViewerTool.raw
    @State private var depthOverlayOpacity = 0.58
    @State private var sharePayload: TAPVideoSystemSharePayload?
    @State private var isPreparingShare = false
    @State private var pendingDeleteRequest: TAPVideoPendingDeleteRequest?
    @State private var deleteAlert: TAPVideoDeleteAlert?
    @State private var removedVideoEntryIDs: Set<String> = []

    init(
        source: TAPVideoPlaybackSource,
        albumContext: TAPVideoAlbumContext? = nil,
        onCurrentAlbumEntryChanged: ((TAPVideoAlbumContext.Entry) -> Void)? = nil,
        deletionContext: DepthAlbumDeletionContext? = nil,
        onDeletionCompleted: ((String, DepthAlbumDeletionContext.Entry?) -> Void)? = nil,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting =
            TAPVideoManifestDepthRegistrationAdapter(),
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()
    ) {
        self.source = source
        self.albumContext = albumContext
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
        self.deletionContext = deletionContext
        self.onDeletionCompleted = onDeletionCompleted
        _session = State(initialValue: TAPVideoPlaybackSession(
            source: source,
            registrationAdapter: registrationAdapter,
            mediaFetcher: mediaFetcher
        ))
    }

    var body: some View {
        TAPVideoPlaybackScreen(
            session: session,
            selectedTool: $selectedTool,
            depthOverlayOpacity: $depthOverlayOpacity,
            isPreparingShare: isPreparingShare,
            onBackTapped: { dismiss() },
            onShareTapped: presentSystemShareSheet,
            onModeTapped: handleModeTapped,
            onDeleteTapped: deleteCurrentVideo,
            onMoveVideo: moveVideo
        )
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(.container, edges: .all)
        .sheet(item: $sharePayload) { payload in
            VerificationExportActivityView(activityItems: [payload.fileURL])
        }
        .alert(item: $pendingDeleteRequest) { request in
            Alert(
                title: Text("Delete unsaved video?"),
                message: Text("This video has not finished exporting to Photos. Deleting it removes the local TAP copy and cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    performDelete(source: request.source)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $deleteAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: session.requestKey) {
            await session.startPlaybackSession()
            if selectedTool == .twoD {
                session.prepareTwoDPlaybackGate()
            }
        }
        .onChange(of: selectedTool) { _, tool in
            if tool == .twoD {
                session.prepareTwoDPlaybackGate()
            } else {
                session.cancelTwoDPlaybackGate()
            }
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
    }

    private func handleModeTapped(_ itemID: String) {
        guard let tool = AnalysisViewerTool(rawValue: itemID),
              tool != .threeD,
              tool == .raw || session.isRegisteredDepthAvailable else {
            return
        }
        selectedTool = tool
    }

    private func presentSystemShareSheet() {
        guard !isPreparingShare, session.player != nil else {
            return
        }
        isPreparingShare = true
        Task { @MainActor in
            defer { isPreparingShare = false }
            do {
                sharePayload = TAPVideoSystemSharePayload(
                    fileURL: try await session.shareableFileURL()
                )
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.appAttest.error("video share export failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
            }
        }
    }

    private func deleteCurrentVideo() {
        if source.requiresUnsavedDeleteConfirmation {
            pendingDeleteRequest = TAPVideoPendingDeleteRequest(source: source)
        } else {
            performDelete(source: source)
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
                    let nextEntry = deletionContext?.entryAfterDeletingCurrent(
                        excluding: removedVideoEntryIDs
                    )
                    session.stopPlayback()
                    onDeletionCompleted(deletedItemID, nextEntry)
                    if nextEntry == nil {
                        dismiss()
                    }
                } else if let nextEntry = albumContext?.entryAfterDeletingCurrent(
                    excluding: removedVideoEntryIDs
                ) {
                    session.stopPlayback()
                    onCurrentAlbumEntryChanged?(nextEntry)
                } else {
                    dismiss()
                }
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.photoLibrary.error("video delete failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
                deleteAlert = TAPVideoDeleteAlert(
                    title: "Unable to delete video",
                    message: "Try again from TAP Library."
                )
            }
        }
    }

    private func moveVideo(offset: Int) {
        guard let entry = albumContext?.adjacentEntry(
            offset: offset,
            excluding: removedVideoEntryIDs
        ) else {
            return
        }
        session.stopPlayback()
        onCurrentAlbumEntryChanged?(entry)
    }
}

private struct TAPVideoSystemSharePayload: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct TAPVideoPendingDeleteRequest: Identifiable {
    let id = UUID()
    let source: TAPVideoPlaybackSource
}

private struct TAPVideoDeleteAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
