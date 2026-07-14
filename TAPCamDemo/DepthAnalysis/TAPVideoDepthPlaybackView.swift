//
//  TAPVideoDepthPlaybackView.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AVKit
import Combine
import ImageIO
import OSLog
import SwiftUI
import UIKit

nonisolated enum TAPVideoPlaybackSource: Hashable {
    case pendingCapture(String)
    case ownedCapture(captureID: String, assetLocalIdentifier: String)
    case photosAsset(String)
    #if DEBUG
    case fixtureFile(
        URL,
        automaticSeekScheduleSeconds: [Double],
        autoPlay: Bool
    )
    #endif
}

nonisolated private extension TAPVideoPlaybackSource {
    var libraryMediaID: LibraryMediaID {
        switch self {
        case .pendingCapture(let captureID), .ownedCapture(let captureID, _):
            .tapCapture(captureID)
        case .photosAsset(let assetID):
            .photosAsset(assetID)
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            .photosAsset("fixture:\(fileURL.lastPathComponent)")
        #endif
        }
    }
}

nonisolated struct TAPVideoPlaybackRoute: Hashable {
    let itemID: String
    let source: TAPVideoPlaybackSource

    nonisolated init(entry: TAPVideoAlbumContext.Entry) {
        itemID = entry.id
        source = entry.source
    }

    nonisolated init?(item: TAPLibraryItem) {
        itemID = item.id
        switch item.source {
        case .pending(let record):
            guard record.artifactKind == .tapVideo else {
                return nil
            }
            source = .pendingCapture(record.captureID)
        case .ownedPhoto(let record, let asset):
            guard record.artifactKind == .tapVideo || asset.isVideo else {
                return nil
            }
            source = .ownedCapture(
                captureID: record.captureID,
                assetLocalIdentifier: asset.localIdentifier
            )
        case .photos(let asset):
            guard asset.isVideo else {
                return nil
            }
            source = .photosAsset(asset.localIdentifier)
        }
    }
}

struct TAPVideoDepthPlaybackView: View {
    private let source: TAPVideoPlaybackSource
    private let albumContext: TAPVideoAlbumContext?
    private let onCurrentAlbumEntryChanged: ((TAPVideoAlbumContext.Entry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("tap.video.playback.didExplainSystemRGBFallback")
    private var didExplainSystemRGBFallback = false
    @StateObject private var viewModel: TAPVideoDepthPlaybackViewModel
    @State private var selectedTool = AnalysisViewerTool.raw
    @State private var depthOverlayOpacity = 0.58
    @State private var sharePayload: TAPVideoSystemSharePayload?
    @State private var isPreparingShare = false
    @State private var pendingDeleteRequest: TAPVideoPendingDeleteRequest?
    @State private var deleteAlert: TAPVideoDeleteAlert?
    @State private var removedVideoEntryIDs: Set<String> = []
    @State private var systemPlaybackNotice: String?
    @State private var mediaFetchRequestKey: MediaFetchRequestKey?
    @State private var mediaFetchGeneration: UInt64 = 1
    @State private var shouldResumeFetchAfterBackground = false

    init(
        source: TAPVideoPlaybackSource,
        albumContext: TAPVideoAlbumContext? = nil,
        onCurrentAlbumEntryChanged: ((TAPVideoAlbumContext.Entry) -> Void)? = nil,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting = TAPVideoManifestDepthRegistrationAdapter(),
        mediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher()
    ) {
        self.source = source
        self.albumContext = albumContext
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
        _viewModel = StateObject(
            wrappedValue: TAPVideoDepthPlaybackViewModel(
                source: source,
                registrationAdapter: registrationAdapter,
                mediaFetcher: mediaFetcher
            )
        )
        _mediaFetchRequestKey = State(
            initialValue: MediaFetchRequestKey(
                itemID: source.libraryMediaID,
                generation: 1,
                purpose: .videoOriginal
            )
        )
    }

    var body: some View {
        videoSurface()
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
        .task(id: mediaFetchRequestKey) {
            guard let mediaFetchRequestKey else {
                return
            }
            await viewModel.startPlaybackSession(requestKey: mediaFetchRequestKey)
            if selectedTool == .twoD {
                viewModel.prepareTwoDPlaybackGate()
            }
        }
        .task(id: systemPlaybackNotice) {
            guard systemPlaybackNotice != nil else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            systemPlaybackNotice = nil
        }
        .onChange(of: selectedTool) { _, tool in
            handleToolChanged(tool)
        }
        .onDisappear {
            shouldResumeFetchAfterBackground = false
            if let mediaFetchRequestKey {
                viewModel.cancelFetch(requestKey: mediaFetchRequestKey)
            }
            viewModel.stopPlayback()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            cancelActiveFetchForBackground()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            resumeCanceledFetchAfterBackground()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            viewModel.handleMemoryWarning()
        }
    }

    private func videoSurface() -> some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            let safeAreaInsets = geometry.safeAreaInsets

            ZStack {
                content
                    .frame(width: viewportSize.width, height: viewportSize.height)
                    .background(Color.black)

                videoChrome(
                    topSafeArea: safeAreaInsets.top,
                    bottomSafeArea: safeAreaInsets.bottom
                )
                .frame(width: viewportSize.width, height: viewportSize.height)
                .zIndex(5)

                playbackNoticeOverlay(
                    topSafeArea: safeAreaInsets.top,
                    availableWidth: viewportSize.width
                )
                .frame(width: viewportSize.width, height: viewportSize.height)
                .zIndex(6)
            }
            .animation(.snappy(duration: 0.2), value: systemPlaybackNotice)
        }
        .background(Color.black)
    }

    private func playbackNoticeOverlay(
        topSafeArea: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let noticeContentMaxWidth = TAPVideoViewerChromeLayout
            .noticeContentMaxWidth(availableWidth: availableWidth)

        return VStack(spacing: 10) {
            if let systemPlaybackNotice {
                Text(systemPlaybackNotice)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(maxWidth: noticeContentMaxWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isStaticText)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if selectedTool == .twoD,
               let depthGapNotice = viewModel.depthGapNotice {
                Label(depthGapNotice, systemImage: "waveform.path.ecg.rectangle")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(maxWidth: noticeContentMaxWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("tap.video.playback.depthGapNotice")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, TAPVideoViewerChromeLayout.noticeTopPadding(topSafeArea: topSafeArea))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func videoChrome(
        topSafeArea: CGFloat,
        bottomSafeArea: CGFloat
    ) -> some View {
        if let player = viewModel.player {
            DepthViewerChromeView(
                selectedModeID: selectedTool.rawValue,
                modeItems: TAPVideoViewerModePolicy.items(
                    availability: viewModel.registeredDepthAvailability,
                    selectedTool: selectedTool,
                    isTwoDPlaybackReady: viewModel.isTwoDPlaybackReady
                ),
                overlayOpacity: $depthOverlayOpacity,
                showsOpacityControl: selectedTool == .twoD
                    && viewModel.isRegisteredDepthAvailable,
                isSharePreparing: isPreparingShare,
                shareAccessibilityLabel: isPreparingShare
                    ? "Preparing share"
                    : "Share video",
                deleteAccessibilityLabel: "Delete video",
                topSafeArea: topSafeArea,
                bottomSafeArea: bottomSafeArea,
                bottomAccessory: TAPVideoPlaybackTransportView(player: player),
                onBackTapped: {
                    dismiss()
                },
                onShareTapped: presentSystemShareSheet,
                onModeTapped: handleModeTapped,
                onDeleteTapped: deleteCurrentVideo
            )
        } else {
            DepthViewerChromeView(
                selectedModeID: selectedTool.rawValue,
                modeItems: TAPVideoViewerModePolicy.items(
                    availability: viewModel.registeredDepthAvailability,
                    selectedTool: selectedTool,
                    isTwoDPlaybackReady: false
                ),
                overlayOpacity: $depthOverlayOpacity,
                showsOpacityControl: false,
                isSharePreparing: true,
                shareAccessibilityLabel: "Preparing video",
                deleteAccessibilityLabel: "Delete video",
                topSafeArea: topSafeArea,
                bottomSafeArea: bottomSafeArea,
                bottomAccessory: EmptyView(),
                onBackTapped: {
                    dismiss()
                },
                onShareTapped: {},
                onModeTapped: handleModeTapped,
                onDeleteTapped: deleteCurrentVideo
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                Color.black
                LibraryMediaFetchOverlay(
                    kind: .tapVideo,
                    state: LibraryMediaFetchOverlayState(viewModel.mediaFetchPhase),
                    onCancel: cancelCurrentFetch,
                    onRetry: retryCurrentFetch
                )
            }
        case .failed(let message):
            ZStack {
                Color.black
                if LibraryMediaFetchOverlayState(viewModel.mediaFetchPhase) == .hidden {
                    ContentUnavailableView(
                        "Unable to play video",
                        systemImage: "video.slash",
                        description: Text(message)
                    )
                    .foregroundStyle(.white)
                    .padding()
                } else {
                    LibraryMediaFetchOverlay(
                        kind: .tapVideo,
                        state: LibraryMediaFetchOverlayState(viewModel.mediaFetchPhase),
                        onCancel: cancelCurrentFetch,
                        onRetry: retryCurrentFetch
                    )
                }
            }
        case .ready:
            playbackSurface
        }
    }

    @ViewBuilder
    private var playbackSurface: some View {
        ZStack {
            Color.black
            playerView

            if selectedTool == .twoD,
               viewModel.isPreparingTwoDPlayback {
                twoDPreparationOverlay
                    .zIndex(3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var playerView: some View {
        if let player = viewModel.player {
            TAPVideoPlayerSurfaceView(
                player: player,
                overlayStore: viewModel.overlayStore,
                showsRegisteredDepth: selectedTool == .twoD,
                overlayOpacity: depthOverlayOpacity,
                onSystemPlaybackRequiresRGB: forceRawForSystemPlayback
            )
            .contentShape(Rectangle())
            .gesture(videoSwipeGesture)
            .clipped()
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var twoDPreparationOverlay: some View {
        ZStack {
            Color.black.opacity(0.62)
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .accessibilityLabel("Preparing 2D playback")
                .accessibilityIdentifier("tap.video.playback.2d.preparing")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var videoSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.predictedEndTranslation.width
                let vertical = value.predictedEndTranslation.height
                guard abs(horizontal) > abs(vertical),
                      abs(horizontal) > 80 else {
                    return
                }
                moveVideo(offset: horizontal < 0 ? 1 : -1)
            }
    }

    private func handleModeTapped(_ itemID: String) {
        guard let tool = AnalysisViewerTool(rawValue: itemID),
              tool != .threeD else {
            return
        }
        guard tool == .raw || viewModel.isRegisteredDepthAvailable else {
            return
        }
        selectedTool = tool
    }

    private func handleToolChanged(_ tool: AnalysisViewerTool) {
        if tool == .twoD {
            viewModel.prepareTwoDPlaybackGate()
        } else {
            viewModel.cancelTwoDPlaybackGate()
        }
    }

    private func forceRawForSystemPlayback() {
        guard selectedTool != .raw else {
            return
        }
        selectedTool = .raw
        guard !didExplainSystemRGBFallback else {
            return
        }
        didExplainSystemRGBFallback = true
        systemPlaybackNotice = "Picture in Picture and AirPlay show RAW video because the 2D overlay stays on this device."
    }

    private func presentSystemShareSheet() {
        guard !isPreparingShare else {
            return
        }
        isPreparingShare = true

        Task { @MainActor in
            defer {
                isPreparingShare = false
            }
            do {
                let fileURL = try await viewModel.shareableFileURL()
                sharePayload = TAPVideoSystemSharePayload(fileURL: fileURL)
            } catch {
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.appAttest.error("video share export failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
                #endif
            }
        }
    }

    private func deleteCurrentVideo() {
        if case .pendingCapture = source {
            pendingDeleteRequest = TAPVideoPendingDeleteRequest(source: source)
            return
        }

        performDelete(source: source)
    }

    private func performDelete(source: TAPVideoPlaybackSource) {
        Task { @MainActor in
            do {
                try await TAPVideoDeletionService.delete(source: source)
                if let currentItemID = albumContext?.currentItemID {
                    removedVideoEntryIDs.insert(currentItemID)
                }
                if let nextEntry = nextVideoEntryAfterDeletingCurrent() {
                    viewModel.stopPlayback()
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
        guard let entry = adjacentVideoEntry(offset: offset) else {
            return
        }
        cancelCurrentFetch()
        viewModel.stopPlayback()
        onCurrentAlbumEntryChanged?(entry)
    }

    private func cancelCurrentFetch() {
        guard let requestKey = mediaFetchRequestKey else {
            return
        }
        viewModel.cancelFetch(requestKey: requestKey)
        mediaFetchRequestKey = nil
    }

    private func cancelActiveFetchForBackground() {
        // A ready player must survive backgrounding so automatic PiP can take
        // ownership. Only an unresolved/local-or-iCloud fetch is cancellable
        // here; dismiss and item replacement still stop the full session.
        guard viewModel.hasActiveMediaFetch else {
            return
        }
        shouldResumeFetchAfterBackground = true
        cancelCurrentFetch()
    }

    private func resumeCanceledFetchAfterBackground() {
        guard shouldResumeFetchAfterBackground,
              mediaFetchRequestKey == nil else {
            return
        }
        shouldResumeFetchAfterBackground = false
        retryCurrentFetch()
    }

    private func retryCurrentFetch() {
        shouldResumeFetchAfterBackground = false
        viewModel.prepareForRetry()
        mediaFetchGeneration &+= 1
        mediaFetchRequestKey = MediaFetchRequestKey(
            itemID: source.libraryMediaID,
            generation: mediaFetchGeneration,
            purpose: .videoOriginal
        )
    }

    private func adjacentVideoEntry(offset: Int) -> TAPVideoAlbumContext.Entry? {
        guard abs(offset) == 1,
              let albumContext else {
            return nil
        }
        let entries = albumContext.entries.filter { !removedVideoEntryIDs.contains($0.id) }
        guard let currentIndex = entries.firstIndex(where: { $0.id == albumContext.currentItemID }) else {
            return nil
        }
        let targetIndex = currentIndex + offset
        guard entries.indices.contains(targetIndex) else {
            return nil
        }
        return entries[targetIndex]
    }

    private func nextVideoEntryAfterDeletingCurrent() -> TAPVideoAlbumContext.Entry? {
        guard let albumContext else {
            return nil
        }
        let deletedIndex = albumContext.entries.firstIndex { $0.id == albumContext.currentItemID } ?? 0
        let remainingEntries = albumContext.entries.filter { !removedVideoEntryIDs.contains($0.id) }
        guard !remainingEntries.isEmpty else {
            return nil
        }
        let nextIndex = min(deletedIndex, remainingEntries.count - 1)
        return remainingEntries[nextIndex]
    }
}

nonisolated private enum TAPVideoViewerChromeLayout {
    /// Full-screen GeometryReader can report a zero safe-area inset after the
    /// root ignores the container safe area. Keep status notices below the
    /// shared 42-point Back control in that path as well.
    static func noticeTopPadding(topSafeArea: CGFloat) -> CGFloat {
        max(topSafeArea + 66, 116)
    }

    /// Leaves 24 points outside and 14 points inside the notice on each side,
    /// so accessibility-sized localized copy cannot widen the full-screen root.
    static func noticeContentMaxWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - 76)
    }
}

nonisolated enum TAPVideoViewerModePolicy {
    static func items(
        availability: TAPVideoRegisteredDepthAvailability,
        selectedTool: AnalysisViewerTool,
        isTwoDPlaybackReady: Bool
    ) -> [DepthViewerModeItem] {
        AnalysisViewerTool.allCases.map { tool in
            let isEnabled: Bool
            let accessibilityValue: String?
            switch tool {
            case .raw:
                isEnabled = true
                accessibilityValue = selectedTool == .raw ? "Selected" : nil
            case .twoD:
                isEnabled = availability.isAvailable
                switch availability {
                case .checking:
                    accessibilityValue = "Preparing registered depth"
                case .unavailable:
                    accessibilityValue = "Registered depth unavailable"
                case .available:
                    if selectedTool == .twoD {
                        accessibilityValue = isTwoDPlaybackReady
                            ? "Selected, Ready"
                            : "Selected, Preparing"
                    } else {
                        accessibilityValue = "Available"
                    }
                }
            case .threeD:
                isEnabled = false
                accessibilityValue = "Unavailable for video"
            }
            return DepthViewerModeItem(
                id: tool.rawValue,
                systemImage: tool.systemImage,
                accessibilityLabel: accessibilityLabel(for: tool),
                accessibilityIdentifier: accessibilityIdentifier(for: tool),
                isEnabled: isEnabled,
                accessibilityValue: accessibilityValue
            )
        }
    }

    private static func accessibilityLabel(for tool: AnalysisViewerTool) -> String {
        switch tool {
        case .raw:
            "Raw video"
        case .twoD:
            "2D analysis"
        case .threeD:
            "3D projection"
        }
    }

    private static func accessibilityIdentifier(for tool: AnalysisViewerTool) -> String {
        switch tool {
        case .raw:
            "tap.viewer.mode.raw"
        case .twoD:
            "tap.viewer.mode.2d"
        case .threeD:
            "tap.viewer.mode.3d"
        }
    }
}

nonisolated enum TAPVideoPlaybackTransportPolicy {
    static func hasActivePlaybackIntent(
        status: AVPlayer.TimeControlStatus
    ) -> Bool {
        status != .paused
    }
}

@MainActor
enum TAPVideoPlaybackAudioSession {
    @discardableResult
    static func activate() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

@MainActor
final class TAPVideoPlaybackTransportModel: ObservableObject {
    @Published private(set) var hasActivePlaybackIntent = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var confirmedElapsedSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0

    private let player: AVPlayer
    private var periodicTimeObserver: Any?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var seekTask: Task<Void, Never>?
    private var seekGeneration: UInt64 = 0
    private var isScrubbing = false
    private var shouldResumeAfterScrubbing = false
    private var ownsPlaybackAudioSession = false
    private var isInvalidated = false

    init(player: AVPlayer) {
        self.player = player
        installObservers()
    }

    deinit {
        seekTask?.cancel()
        player.currentItem?.cancelPendingSeeks()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        timeControlStatusObservation?.invalidate()
        durationObservation?.invalidate()
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        if ownsPlaybackAudioSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    func togglePlayback() {
        guard !isInvalidated else {
            return
        }
        if hasActivePlaybackIntent {
            cancelPendingSeek()
            shouldResumeAfterScrubbing = false
            player.pause()
            return
        }
        if durationSeconds > 0,
           elapsedSeconds >= durationSeconds - 0.05 {
            performSeek(to: .zero, resumeAfterSeek: true)
            return
        }
        cancelPendingSeek()
        activatePlaybackAudioSessionIfNeeded()
        player.play()
    }

    func previewSeek(to seconds: Double) {
        guard seconds.isFinite else {
            return
        }
        elapsedSeconds = min(max(seconds, 0), max(durationSeconds, 0))
    }

    func setScrubbing(_ scrubbing: Bool) {
        guard !isInvalidated else {
            return
        }
        guard scrubbing != isScrubbing else {
            return
        }
        if scrubbing {
            shouldResumeAfterScrubbing = TAPVideoPlaybackTransportPolicy
                .hasActivePlaybackIntent(status: player.timeControlStatus)
            cancelPendingSeek()
            isScrubbing = true
            player.pause()
            return
        }
        isScrubbing = false
        let target = CMTime(seconds: elapsedSeconds, preferredTimescale: 600)
        let shouldResume = shouldResumeAfterScrubbing
        shouldResumeAfterScrubbing = false
        performSeek(to: target, resumeAfterSeek: shouldResume)
    }

    private func performSeek(to target: CMTime, resumeAfterSeek: Bool) {
        cancelPendingSeek()
        guard let expectedItem = player.currentItem else {
            elapsedSeconds = confirmedElapsedSeconds
            return
        }
        seekGeneration &+= 1
        let generation = seekGeneration
        let player = player
        seekTask = Task { @MainActor [weak self] in
            let didFinish = await player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard let self,
                  !isInvalidated,
                  generation == seekGeneration else {
                return
            }
            seekTask = nil
            guard !Task.isCancelled,
                  didFinish,
                  !isScrubbing,
                  player.currentItem === expectedItem else {
                elapsedSeconds = confirmedElapsedSeconds
                return
            }
            updateConfirmedElapsedTime(player.currentTime())
            if resumeAfterSeek {
                activatePlaybackAudioSessionIfNeeded()
                player.play()
            }
        }
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        player.pause()
        tearDown()
    }

    private func cancelPendingSeek() {
        seekGeneration &+= 1
        seekTask?.cancel()
        seekTask = nil
        player.currentItem?.cancelPendingSeeks()
    }

    private func installObservers() {
        updateDuration(player.currentItem?.duration ?? .invalid)
        updateConfirmedElapsedTime(player.currentTime())
        timeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.hasActivePlaybackIntent = TAPVideoPlaybackTransportPolicy
                    .hasActivePlaybackIntent(status: player.timeControlStatus)
            }
        }
        if let item = player.currentItem {
            durationObservation = item.observe(\.duration, options: [.initial, .new]) {
                [weak self] item, _ in
                Task { @MainActor [weak self] in
                    self?.updateDuration(item.duration)
                }
            }
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    cancelPendingSeek()
                    hasActivePlaybackIntent = false
                    elapsedSeconds = durationSeconds
                    confirmedElapsedSeconds = durationSeconds
                }
            }
        }
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self,
                      !isScrubbing else {
                    return
                }
                updateConfirmedElapsedTime(time)
            }
        }
    }

    private func updateConfirmedElapsedTime(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else {
            return
        }
        let bounded = min(max(seconds, 0), max(durationSeconds, 0))
        confirmedElapsedSeconds = bounded
        elapsedSeconds = bounded
    }

    private func updateDuration(_ duration: CMTime) {
        let seconds = CMTimeGetSeconds(duration)
        durationSeconds = seconds.isFinite && seconds > 0 ? seconds : 0
        confirmedElapsedSeconds = min(confirmedElapsedSeconds, durationSeconds)
        elapsedSeconds = min(elapsedSeconds, durationSeconds)
    }

    private func activatePlaybackAudioSessionIfNeeded() {
        guard !ownsPlaybackAudioSession else {
            return
        }
        ownsPlaybackAudioSession = TAPVideoPlaybackAudioSession.activate()
    }

    private func tearDown() {
        cancelPendingSeek()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if ownsPlaybackAudioSession {
            TAPVideoPlaybackAudioSession.deactivate()
            ownsPlaybackAudioSession = false
        }
    }
}

private struct TAPVideoPlaybackTransportView: View {
    @StateObject private var model: TAPVideoPlaybackTransportModel

    init(player: AVPlayer) {
        _model = StateObject(
            wrappedValue: TAPVideoPlaybackTransportModel(player: player)
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            transportRow(showsTimeLabels: true)
            transportRow(showsTimeLabels: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 460)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .onDisappear {
            model.invalidate()
        }
    }

    private func transportRow(showsTimeLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Button(action: model.togglePlayback) {
                Image(
                    systemName: model.hasActivePlaybackIntent
                        ? "pause.fill"
                        : "play.fill"
                )
                    .font(.callout.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                    .dynamicTypeSize(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.hasActivePlaybackIntent ? "Pause video" : "Play video"
            )
            .accessibilityIdentifier("tap.video.playback.transport.playPause")

            if showsTimeLabels {
                timeLabel(
                    model.elapsedSeconds,
                    confirmedSeconds: model.confirmedElapsedSeconds,
                    identifier: "tap.video.playback.transport.elapsed",
                    accessibilityLabel: "Elapsed time"
                )
            }

            Slider(
                value: Binding(
                    get: { model.elapsedSeconds },
                    set: model.previewSeek(to:)
                ),
                in: 0...max(model.durationSeconds, 0.01),
                onEditingChanged: model.setScrubbing
            )
            .tint(.primary)
            .accessibilityLabel("Video position")
            .accessibilityValue(
                "\(Self.timecode(model.elapsedSeconds)) of "
                    + Self.timecode(model.durationSeconds)
            )
            .accessibilityIdentifier("tap.video.playback.transport.scrubber")

            if showsTimeLabels {
                timeLabel(
                    model.durationSeconds,
                    confirmedSeconds: model.durationSeconds,
                    identifier: "tap.video.playback.transport.duration",
                    accessibilityLabel: "Video duration"
                )
            }
        }
    }

    private func timeLabel(
        _ seconds: Double,
        confirmedSeconds: Double,
        identifier: String,
        accessibilityLabel: String
    ) -> some View {
        Text(Self.timecode(seconds))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.primary)
            .frame(minWidth: 34)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(Self.timecode(confirmedSeconds))
            .accessibilityIdentifier(identifier)
    }

    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }
        let wholeSeconds = Int(seconds.rounded(.down))
        return "\(wholeSeconds / 60):\(String(format: "%02d", wholeSeconds % 60))"
    }
}

nonisolated struct TAPVideoAlbumContext: Equatable {
    nonisolated struct Entry: Identifiable, Equatable {
        let id: String
        let source: TAPVideoPlaybackSource
        let routeAnchor: CameraRouteAlbumAnchor
    }

    let currentItemID: String
    let entries: [Entry]

    init(currentItemID: String, entries: [Entry]) {
        self.currentItemID = currentItemID
        self.entries = entries
    }

    init(currentItemID: String, items: [TAPLibraryItem]) {
        self.init(
            currentItemID: currentItemID,
            entries: items.compactMap(Entry.init(item:))
        )
    }
}

private extension TAPVideoAlbumContext.Entry {
    nonisolated init?(item: TAPLibraryItem) {
        guard let route = TAPVideoPlaybackRoute(item: item) else {
            return nil
        }
        id = route.itemID
        source = route.source
        routeAnchor = item.routeAnchor
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

nonisolated private enum TAPVideoDeletionService {
    static func delete(source: TAPVideoPlaybackSource) async throws {
        switch source {
        case .pendingCapture(let captureID):
            try await TAPPendingCaptureStore.shared.removeRecord(captureID: captureID)
        case .ownedCapture(_, let assetID), .photosAsset(let assetID):
            try await PhotoLibraryWriter.deleteAsset(localIdentifier: assetID)
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        #if DEBUG
        case .fixtureFile:
            return
        #endif
        }
    }
}

nonisolated enum TAPVideoDepthDisplayOrientation {
    static func cgImageOrientation(from transform: String?) -> CGImagePropertyOrientation {
        guard let transform,
              transform != "identity" else {
            return .up
        }

        let components = transform.split(separator: ";").map(String.init)
        let isMirrored = components.contains("mirrored")
        let rotation = components
            .first { $0.hasPrefix("rotation:") }
            .flatMap { Double($0.dropFirst("rotation:".count)) }
            .map { normalizedDegrees($0) } ?? 0

        switch (rotation, isMirrored) {
        case (0, false):
            return .up
        case (90, false):
            return .right
        case (180, false):
            return .down
        case (270, false):
            return .left
        case (0, true):
            return .upMirrored
        case (90, true):
            return .rightMirrored
        case (180, true):
            return .downMirrored
        case (270, true):
            return .leftMirrored
        default:
            return .up
        }
    }

    static func displaySize(width: Int32, height: Int32, transform: String?) -> CGSize? {
        guard width > 0,
              height > 0 else {
            return nil
        }
        let rotation = rotationDegrees(from: transform)
        let isSideways = rotation == 90 || rotation == 270
        return isSideways
            ? CGSize(width: CGFloat(height), height: CGFloat(width))
            : CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    private static func normalizedDegrees(_ degrees: Double) -> Int {
        let rounded = Int(degrees.rounded())
        return ((rounded % 360) + 360) % 360
    }

    private static func rotationDegrees(from transform: String?) -> Int {
        guard let transform else {
            return 0
        }
        return transform.split(separator: ";")
            .map(String.init)
            .first { $0.hasPrefix("rotation:") }
            .flatMap { Double($0.dropFirst("rotation:".count)) }
            .map { normalizedDegrees($0) } ?? 0
    }
}

@MainActor
private final class TAPVideoDepthPlaybackViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var mediaFetchPhase: MediaFetchPhase<Bool, Bool> = .idle(false)
    @Published private(set) var player: AVPlayer?
    @Published private(set) var registeredDepthAvailability: TAPVideoRegisteredDepthAvailability = .checking
    @Published private(set) var isPreparingTwoDPlayback = false
    @Published private(set) var depthGapNotice: String?
    private var currentTimeSeconds: Double = 0

    private static let preferredTwoDBufferDurationSeconds: TimeInterval = 3

    private let source: TAPVideoPlaybackSource
    private let registrationAdapter: any TAPVideoDepthRegistrationAdapting
    private let mediaFetcher: any LibraryMediaFetching
    let overlayStore = TAPVideoDepthOverlayStore()
    private var metadataOutput: TAPVideoDepthMetadataOutput?
    private var temporaryDirectoryURL: URL?
    private var managedTemporaryFile: LibraryManagedTemporaryFile?
    private var resolvedFileURL: URL?
    private var currentRequestKey: MediaFetchRequestKey?
    private var playbackTimeJumpObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var playerStatusObservation: NSKeyValueObservation?
    private let depthFrameCache = TAPVideoDepthFrameCache()
    private var currentDepthFrameTimeSeconds: Double?
    private var depthFrameStaleToleranceSeconds = TAPVideoDepthPlaybackBudget
        .failSafeFrameStaleToleranceSeconds
    private var depthFrameSelectionMissCount = 0
    private var lastDepthFrameMissLogTimeSeconds: Double?
    private var isTwoDPresentationRequested = false
    private var twoDReadinessTrace: OSSignpostIntervalState?
    private var depthPipelineGeneration: UInt64 = 0
    #if DEBUG
    private var fixtureSeekTask: Task<Void, Never>?
    #endif

    init(
        source: TAPVideoPlaybackSource,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting,
        mediaFetcher: any LibraryMediaFetching
    ) {
        self.source = source
        self.registrationAdapter = registrationAdapter
        self.mediaFetcher = mediaFetcher
    }

    deinit {
        temporaryDirectoryURL.map { try? FileManager.default.removeItem(at: $0) }
    }

    var isRegisteredDepthAvailable: Bool {
        registeredDepthAvailability.isAvailable
    }

    var hasActiveMediaFetch: Bool {
        state == .loading
    }

    var isTwoDPlaybackReady: Bool {
        isTwoDPresentationRequested
            && !isPreparingTwoDPlayback
            && currentDepthFrameTimeSeconds != nil
    }

    func startPlaybackSession(requestKey: MediaFetchRequestKey) async {
        currentRequestKey = requestKey
        await loadIfNeeded(requestKey: requestKey)
        guard currentRequestKey == requestKey else {
            return
        }
        guard state == .ready,
              let player,
              let item = player.currentItem else {
            return
        }
        installPlaybackObservers(player: player, item: item)
        if let metadataOutput {
            depthPipelineGeneration = metadataOutput.beginNewGeneration()
        }
        warmPlayback(player: player)
        #if DEBUG
        if case .fixtureFile(_, _, let autoPlay) = source,
           autoPlay {
            player.play()
        }
        scheduleFixtureSeekIfNeeded(player: player)
        #endif
    }

    private func loadIfNeeded(requestKey: MediaFetchRequestKey) async {
        guard state == .idle else {
            return
        }
        let playerOpenTrace = TAPVideoPerformanceTrace.beginPlayerOpen(
            source: Self.sourceLabel(source)
        )
        var didOpenPlayer = false
        defer {
            TAPVideoPerformanceTrace.endPlayerOpen(
                playerOpenTrace,
                succeeded: didOpenPlayer
            )
        }
        state = .loading
        mediaFetchPhase = .resolving(false)
        var uncommittedResource: TAPVideoPlaybackResolvedResource?

        do {
            let resource = try await Self.resolveResource(
                source: source,
                requestKey: requestKey,
                mediaFetcher: mediaFetcher
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.currentRequestKey == requestKey else {
                        return
                    }
                    self.mediaFetchPhase = .downloadingFromICloud(
                        false,
                        progress: progress
                    )
                }
            }
            uncommittedResource = resource
            guard currentRequestKey == requestKey else {
                Self.cleanup(resource)
                return
            }
            try Task.checkCancellation()
            let presentation = await Self.videoPresentation(
                for: resource.fileURL,
                registrationAdapter: registrationAdapter
            )
            try Task.checkCancellation()
            guard currentRequestKey == requestKey else {
                Self.cleanup(resource)
                return
            }
            if let descriptor = presentation.registrationDescriptor,
               descriptor.supportsRegisteredOverlay,
               presentation.depthFormat != nil {
                registeredDepthAvailability = .available(descriptor)
                depthFrameStaleToleranceSeconds = TAPVideoDepthGapPolicy.staleToleranceSeconds(
                    nominalDepthFrameIntervalSeconds: descriptor.nominalDepthFrameIntervalSeconds
                )
            } else {
                registeredDepthAvailability = .unavailable
                depthFrameStaleToleranceSeconds = TAPVideoDepthPlaybackBudget
                    .failSafeFrameStaleToleranceSeconds
            }
            let item = AVPlayerItem(url: resource.fileURL)
            if isRegisteredDepthAvailable,
               let depthFormat = presentation.depthFormat {
                let metadataOutput = TAPVideoDepthMetadataOutput(
                    displayOrientation: presentation.depthFrameOrientation,
                    depthFormat: depthFormat,
                    depthTrackID: presentation.depthTrackID
                ) { [weak self] event in
                    self?.handleDepthPipelineEvent(event)
                }
                self.metadataOutput = metadataOutput
            } else {
                self.metadataOutput = nil
            }

            let player = AVPlayer(playerItem: item)
            #if DEBUG
            if case .fixtureFile = source {
                // Simulator evidence must stay on-device. Otherwise an
                // external playback route can immediately invoke the product
                // RGB fallback and make 2D performance runs nondeterministic.
                player.allowsExternalPlayback = false
            }
            #endif
            temporaryDirectoryURL = resource.temporaryDirectoryURL
            managedTemporaryFile = resource.managedTemporaryFile
            resolvedFileURL = resource.fileURL
            uncommittedResource = nil
            self.player = player
            state = .ready
            mediaFetchPhase = .ready(true)
            didOpenPlayer = true
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.info("tap_video_playback_loaded source=\(Self.sourceLabel(self.source), privacy: .public) fileURL=\(resource.fileURL.lastPathComponent, privacy: .public) autoPlay=false")
            #endif
        } catch is CancellationError {
            guard currentRequestKey == requestKey else {
                uncommittedResource.map(Self.cleanup)
                return
            }
            uncommittedResource.map(Self.cleanup)
            releasePlaybackResources()
            state = .idle
            if case .downloadingFromICloud = mediaFetchPhase {
                mediaFetchPhase = .cloudOnly(false)
            } else {
                mediaFetchPhase = .idle(false)
            }
        } catch {
            guard currentRequestKey == requestKey else {
                uncommittedResource.map(Self.cleanup)
                return
            }
            uncommittedResource.map(Self.cleanup)
            releasePlaybackResources()
            state = .failed(DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error))
            let failure = (error as? MediaFetchFailure) ?? .decode
            mediaFetchPhase = .failed(
                false,
                reason: failure,
                retryable: failure.isRetryable
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.error("tap_video_playback_load_failed source=\(Self.sourceLabel(self.source), privacy: .public) error=\(Self.describe(error), privacy: .public)")
            #endif
        }
    }

    func stopPlayback() {
        cancelTwoDPlaybackGate()
        releasePlaybackResources()
        registeredDepthAvailability = .checking
        state = .idle
        currentRequestKey = nil
        if case .cloudOnly = mediaFetchPhase {
            // Cancellation intentionally leaves an explicit cloud-only state.
        } else {
            mediaFetchPhase = .idle(false)
        }
    }

    func cancelFetch(requestKey: MediaFetchRequestKey) {
        guard currentRequestKey == requestKey else {
            return
        }
        let wasCloudFetch: Bool
        switch mediaFetchPhase {
        case .cloudOnly, .downloadingFromICloud:
            wasCloudFetch = true
        default:
            wasCloudFetch = false
        }
        currentRequestKey = nil
        releasePlaybackResources()
        state = .idle
        mediaFetchPhase = wasCloudFetch ? .cloudOnly(false) : .idle(false)
    }

    func prepareForRetry() {
        currentRequestKey = nil
        releasePlaybackResources()
        state = .idle
        mediaFetchPhase = .idle(false)
    }

    func handleMemoryWarning() {
        finishTwoDReadiness(outcome: "memory-warning")
        resetDepthFrameClockSelection(beginNewGeneration: true)
        guard isTwoDPresentationRequested,
              state == .ready,
              isRegisteredDepthAvailable,
              metadataOutput != nil,
              resolvedFileURL != nil else {
            isPreparingTwoDPlayback = false
            return
        }
        beginTwoDReadiness(outcomeForPreviousAttempt: "memory-warning")
        requestCurrentDepthProbe(playbackTimeSeconds: currentTimeSeconds)
    }

    func shareableFileURL() async throws -> URL {
        if let resolvedFileURL {
            return resolvedFileURL
        }
        throw MediaFetchFailure.download
    }

    func prepareTwoDPlaybackGate() {
        guard state == .ready,
              isRegisteredDepthAvailable,
              metadataOutput != nil,
              resolvedFileURL != nil else {
            isPreparingTwoDPlayback = false
            isTwoDPresentationRequested = false
            return
        }
        isTwoDPresentationRequested = true
        beginTwoDReadiness(outcomeForPreviousAttempt: "restarted")
        if let player {
            if let item = player.currentItem,
               let metadataOutput {
                metadataOutput.attach(to: item)
                depthPipelineGeneration = metadataOutput.beginNewGeneration()
            }
            player.currentItem?.preferredForwardBufferDuration = Self.preferredTwoDBufferDurationSeconds
            prerollIfReady(player: player)
        }

        updateDepthFrame(for: currentTimeSeconds)
        guard isPreparingTwoDPlayback else {
            return
        }
        requestCurrentDepthProbe(playbackTimeSeconds: currentTimeSeconds)
    }

    func cancelTwoDPlaybackGate() {
        finishTwoDReadiness(outcome: "cancelled")
        isTwoDPresentationRequested = false
        isPreparingTwoDPlayback = false
        depthGapNotice = nil
        if let metadataOutput {
            depthPipelineGeneration = metadataOutput.beginNewGeneration()
            metadataOutput.detach()
        } else {
            depthPipelineGeneration &+= 1
        }
        depthFrameCache.clear()
        currentDepthFrameTimeSeconds = nil
        overlayStore.clear()
    }

    private func beginTwoDReadiness(outcomeForPreviousAttempt: String) {
        finishTwoDReadiness(outcome: outcomeForPreviousAttempt)
        twoDReadinessTrace = TAPVideoPerformanceTrace.beginTwoDReadiness()
        isPreparingTwoDPlayback = true
    }

    private func requestCurrentDepthProbe(playbackTimeSeconds: Double) {
        guard isTwoDPresentationRequested,
              isPreparingTwoDPlayback,
              let metadataOutput,
              let resolvedFileURL else {
            return
        }
        metadataOutput.probe(
            fileURL: resolvedFileURL,
            playbackTimeSeconds: max(0, playbackTimeSeconds),
            staleToleranceSeconds: depthFrameStaleToleranceSeconds,
            leadToleranceSeconds: TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds
        )
    }

    private func restartTwoDReadinessAfterDiscontinuity(
        playbackTimeSeconds: Double
    ) {
        guard isTwoDPresentationRequested,
              state == .ready,
              isRegisteredDepthAvailable else {
            return
        }
        beginTwoDReadiness(outcomeForPreviousAttempt: "discontinuity")
        requestCurrentDepthProbe(playbackTimeSeconds: playbackTimeSeconds)
    }

    private func handleDepthPipelineEvent(_ event: TAPVideoDepthPipelineEvent) {
        guard isTwoDPresentationRequested,
              TAPVideoDepthPipelineGenerationPolicy.accepts(
            eventGeneration: event.generation,
            currentGeneration: depthPipelineGeneration
        ) else {
            return
        }
        switch event.payload {
        case .frame(let frame):
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            if frame.frameIndex == 0 {
                LockedCameraDiagnostics.logger.info("tap_video_depth_playback_first_frame width=\(frame.width, privacy: .public) height=\(frame.height, privacy: .public) pixelFormat=\(frame.pixelFormat, privacy: .public) presentationTime=\(frame.presentationTimeSeconds, privacy: .public)")
            }
            #endif
            storeDepthFrame(frame)
        case .noSample:
            finishDepthPipelineUnavailable(outcome: "no-sample")
        case .decodeFailed(let reason, _):
            finishDepthPipelineUnavailable(outcome: "decode-failed-\(reason.rawValue)")
        }
    }

    private func finishDepthPipelineUnavailable(outcome: String) {
        currentDepthFrameTimeSeconds = nil
        overlayStore.clear()
        guard isTwoDPresentationRequested else {
            return
        }
        isPreparingTwoDPlayback = false
        if depthGapNotice == nil {
            depthGapNotice = String(
                localized: "video.depth.gap",
                defaultValue: "Depth data is unavailable at this moment."
            )
        }
        finishTwoDReadiness(outcome: outcome)
    }

    private func releasePlaybackResources() {
        #if DEBUG
        fixtureSeekTask?.cancel()
        fixtureSeekTask = nil
        #endif
        removePlaybackObservers()
        if let metadataOutput {
            depthPipelineGeneration = metadataOutput.beginNewGeneration()
        } else {
            depthPipelineGeneration &+= 1
        }
        metadataOutput?.detach()
        metadataOutput = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        depthFrameCache.clear()
        overlayStore.clear()
        depthGapNotice = nil
        currentDepthFrameTimeSeconds = nil
        currentTimeSeconds = 0
        depthFrameStaleToleranceSeconds = TAPVideoDepthPlaybackBudget
            .failSafeFrameStaleToleranceSeconds
        depthFrameSelectionMissCount = 0
        lastDepthFrameMissLogTimeSeconds = nil
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        managedTemporaryFile?.cleanup()
        managedTemporaryFile = nil
        temporaryDirectoryURL = nil
        resolvedFileURL = nil
    }

    #if DEBUG
    private func scheduleFixtureSeekIfNeeded(player: AVPlayer) {
        guard case .fixtureFile(_, let seekScheduleSeconds, let autoPlay) = source,
              !seekScheduleSeconds.isEmpty else {
            return
        }
        fixtureSeekTask?.cancel()
        fixtureSeekTask = Task { @MainActor [weak self, weak player] in
            for (index, seekSeconds) in seekScheduleSeconds.enumerated() {
                do {
                    try await Task.sleep(
                        nanoseconds: index == 0 ? 900_000_000 : 500_000_000
                    )
                } catch {
                    return
                }
                guard let self,
                      let player,
                      self.player === player else {
                    return
                }
                _ = await player.seek(
                    to: CMTime(seconds: seekSeconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                if autoPlay {
                    player.play()
                }
            }
            self?.fixtureSeekTask = nil
        }
    }
    #endif

    private func warmPlayback(player: AVPlayer) {
        player.currentItem?.preferredForwardBufferDuration = Self.preferredTwoDBufferDurationSeconds
        guard player.status == .readyToPlay else {
            playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self, weak player] observedPlayer, _ in
                guard observedPlayer.status == .readyToPlay else {
                    return
                }
                Task { @MainActor [weak self, weak player] in
                    guard let self,
                          let player else {
                        return
                    }
                    self.playerStatusObservation?.invalidate()
                    self.playerStatusObservation = nil
                    self.prerollIfReady(player: player)
                }
            }
            if player.status == .readyToPlay {
                playerStatusObservation?.invalidate()
                playerStatusObservation = nil
                prerollIfReady(player: player)
            }
            return
        }
        prerollIfReady(player: player)
    }

    private func prerollIfReady(player: AVPlayer) {
        guard player.status == .readyToPlay else {
            return
        }
        player.preroll(atRate: 1) { _ in }
    }

    private func installPlaybackObservers(player: AVPlayer, item: AVPlayerItem) {
        removePlaybackObservers()
        playbackTimeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak player] _ in
            Task { @MainActor [weak self, weak player] in
                guard let self else {
                    return
                }
                let jumpedTime = player.map { CMTimeGetSeconds($0.currentTime()) }
                    .flatMap { $0.isFinite ? max(0, $0) : nil }
                    ?? self.currentTimeSeconds
                self.currentTimeSeconds = jumpedTime
                self.resetDepthFrameClockSelection(beginNewGeneration: true)
                self.restartTwoDReadinessAfterDiscontinuity(
                    playbackTimeSeconds: jumpedTime
                )
            }
        }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { time in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let playbackTimeSeconds = max(0, CMTimeGetSeconds(time))
                if abs(playbackTimeSeconds - self.currentTimeSeconds) > 1 {
                    self.resetDepthFrameClockSelection(beginNewGeneration: true)
                    self.restartTwoDReadinessAfterDiscontinuity(
                        playbackTimeSeconds: playbackTimeSeconds
                    )
                }
                self.currentTimeSeconds = playbackTimeSeconds
                self.updateDepthFrame(for: playbackTimeSeconds)
            }
        }
    }

    private func removePlaybackObservers() {
        if let playbackTimeJumpObserver {
            NotificationCenter.default.removeObserver(playbackTimeJumpObserver)
            self.playbackTimeJumpObserver = nil
        }
        if let timeObserverToken,
           let player {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
    }

    private func storeDepthFrame(_ frame: TAPDecodedDepthVideoFrame) {
        guard isTwoDPresentationRequested,
              depthFrameCache.insert(frame, around: currentTimeSeconds) else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.info("tap_video_depth_cache_reject frameIndex=\(frame.frameIndex, privacy: .public) bytes=\(frame.retainedByteCount, privacy: .public) retained=\(self.depthFrameCache.retainedByteCount, privacy: .public) budget=\(self.depthFrameCache.maximumRetainedBytes, privacy: .public)")
            #endif
            return
        }
        updateDepthFrame(for: currentTimeSeconds)
    }

    private func updateDepthFrame(for playbackTimeSeconds: Double) {
        guard isTwoDPresentationRequested,
              playbackTimeSeconds.isFinite else {
            return
        }
        depthFrameCache.prune(around: playbackTimeSeconds)
        let frame = depthFrameCache.nearestFrame(
            to: playbackTimeSeconds,
            staleToleranceSeconds: depthFrameStaleToleranceSeconds
        )
        guard let frame else {
            logDepthFrameSelectionMiss(playbackTimeSeconds: playbackTimeSeconds)
            let clearedDisplayedFrame = currentDepthFrameTimeSeconds != nil
            currentDepthFrameTimeSeconds = nil
            overlayStore.clear()
            if clearedDisplayedFrame {
                TAPVideoPerformanceTrace.emitPlaybackGapCleared()
            }
            if isTwoDPresentationRequested,
               !isPreparingTwoDPlayback,
               playbackTimeSeconds >= depthFrameStaleToleranceSeconds {
                if depthGapNotice == nil {
                    depthGapNotice = String(
                        localized: "video.depth.gap",
                        defaultValue: "Depth data is unavailable at this moment."
                    )
                }
            }
            return
        }
        guard currentDepthFrameTimeSeconds != frame.presentationTimeSeconds else {
            return
        }
        currentDepthFrameTimeSeconds = frame.presentationTimeSeconds
        if depthGapNotice != nil {
            depthGapNotice = nil
        }
        guard case .available(let registrationDescriptor) = registeredDepthAvailability else {
            overlayStore.clear()
            return
        }
        overlayStore.present(
            frame.image,
            registrationDescriptor: registrationDescriptor
        )
        if isTwoDPresentationRequested {
            isPreparingTwoDPlayback = false
            finishTwoDReadiness(outcome: "frame")
        }
    }

    private func finishTwoDReadiness(outcome: String) {
        guard let twoDReadinessTrace else {
            return
        }
        self.twoDReadinessTrace = nil
        TAPVideoPerformanceTrace.endTwoDReadiness(
            twoDReadinessTrace,
            outcome: outcome
        )
    }

    private func logDepthFrameSelectionMiss(playbackTimeSeconds: Double) {
        depthFrameSelectionMissCount += 1
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        let shouldLog: Bool
        if let lastDepthFrameMissLogTimeSeconds {
            shouldLog = playbackTimeSeconds - lastDepthFrameMissLogTimeSeconds >= 1
        } else {
            shouldLog = true
        }
        guard shouldLog else {
            return
        }
        lastDepthFrameMissLogTimeSeconds = playbackTimeSeconds
        let nearestDelta = depthFrameCache.frames
            .map { abs($0.presentationTimeSeconds - playbackTimeSeconds) }
            .min() ?? -1
        LockedCameraDiagnostics.logger.info("tap_video_depth_pipeline_miss source=\(Self.sourceLabel(self.source), privacy: .public) playbackTime=\(playbackTimeSeconds, privacy: .public) cacheCount=\(self.depthFrameCache.frames.count, privacy: .public) cacheBytes=\(self.depthFrameCache.retainedByteCount, privacy: .public) nearestDelta=\(nearestDelta, privacy: .public) missCount=\(self.depthFrameSelectionMissCount, privacy: .public)")
        #endif
    }

    private func resetDepthFrameClockSelection(beginNewGeneration: Bool = false) {
        currentDepthFrameTimeSeconds = nil
        depthFrameCache.clear()
        overlayStore.clear()
        if beginNewGeneration {
            if let metadataOutput {
                depthPipelineGeneration = metadataOutput.beginNewGeneration()
            } else {
                depthPipelineGeneration &+= 1
            }
        }
    }

    private static func resolveResource(
        source: TAPVideoPlaybackSource,
        requestKey: MediaFetchRequestKey,
        mediaFetcher: any LibraryMediaFetching,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TAPVideoPlaybackResolvedResource {
        switch source {
        case .pendingCapture(let captureID):
            let fileURL = try await TAPPendingCaptureStore.shared.bestAvailableVideoURL(captureID: captureID)
            return TAPVideoPlaybackResolvedResource(
                fileURL: fileURL,
                temporaryDirectoryURL: nil,
                managedTemporaryFile: nil
            )
        case .ownedCapture(let captureID, let assetID):
            do {
                let fileURL = try await TAPPendingCaptureStore.shared.bestAvailableVideoURL(captureID: captureID)
                return TAPVideoPlaybackResolvedResource(
                    fileURL: fileURL,
                    temporaryDirectoryURL: nil,
                    managedTemporaryFile: nil
                )
            } catch {
                let request = LibraryMediaAssetRequest(
                    key: requestKey,
                    assetLocalIdentifier: assetID
                )
                let file = try await mediaFetcher.videoOriginalFile(
                    for: request,
                    progress: progress
                )
                return TAPVideoPlaybackResolvedResource(
                    fileURL: file.fileURL,
                    temporaryDirectoryURL: nil,
                    managedTemporaryFile: file
                )
            }
        case .photosAsset(let assetID):
            let request = LibraryMediaAssetRequest(
                key: requestKey,
                assetLocalIdentifier: assetID
            )
            let file = try await mediaFetcher.videoOriginalFile(
                for: request,
                progress: progress
            )
            return TAPVideoPlaybackResolvedResource(
                fileURL: file.fileURL,
                temporaryDirectoryURL: nil,
                managedTemporaryFile: file
            )
        #if DEBUG
        case .fixtureFile(let fileURL, _, _):
            return TAPVideoPlaybackResolvedResource(
                fileURL: fileURL,
                // The harness owns this reusable artifact. Dismissing one
                // player must not delete the source needed by later lifecycle
                // cycles in the same process.
                temporaryDirectoryURL: nil,
                managedTemporaryFile: nil
            )
        #endif
        }
    }

    private static func cleanup(_ resource: TAPVideoPlaybackResolvedResource) {
        resource.managedTemporaryFile?.cleanup()
        if let temporaryDirectoryURL = resource.temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    private static func videoPresentation(
        for fileURL: URL,
        registrationAdapter: any TAPVideoDepthRegistrationAdapting
    ) async -> TAPVideoPlaybackPresentation {
        await Task.detached(priority: .utility) {
            do {
                let manifest = try TAPVideoManifestBox.decodedManifest(fromFileAt: fileURL)
                return TAPVideoPlaybackPresentation(
                    depthFrameOrientation: TAPVideoDepthDisplayOrientation.cgImageOrientation(
                        from: manifest.payload.rgbTrack.transform
                    ),
                    registrationDescriptor: registrationAdapter.registrationDescriptor(for: manifest),
                    depthFormat: manifest.payload.depthCoverage.format,
                    depthTrackID: manifest.payload.depthCoverage.trackID
                )
            } catch {
                return TAPVideoPlaybackPresentation(
                    depthFrameOrientation: .up,
                    registrationDescriptor: nil,
                    depthFormat: nil,
                    depthTrackID: nil
                )
            }
        }.value
    }

    private static func sourceLabel(_ source: TAPVideoPlaybackSource) -> String {
        switch source {
        case .pendingCapture:
            "pending"
        case .ownedCapture:
            "owned"
        case .photosAsset:
            "photos"
        #if DEBUG
        case .fixtureFile:
            "fixture"
        #endif
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }

}

private struct TAPVideoPlaybackResolvedResource {
    let fileURL: URL
    let temporaryDirectoryURL: URL?
    let managedTemporaryFile: LibraryManagedTemporaryFile?
}

private struct TAPVideoPlaybackPresentation {
    let depthFrameOrientation: CGImagePropertyOrientation
    let registrationDescriptor: TAPVideoDepthRegistrationDescriptor?
    let depthFormat: TAPVideoManifest.DepthFormat?
    let depthTrackID: CMPersistentTrackID?
}

nonisolated enum TAPVideoDepthPipelineDecodeFailureReason: String, Sendable {
    case metadataRead
    case decode
    case backpressure
}

nonisolated struct TAPVideoDepthPipelineEvent {
    nonisolated enum Payload {
        case frame(TAPDecodedDepthVideoFrame)
        case noSample(playbackTimeSeconds: Double)
        case decodeFailed(
            reason: TAPVideoDepthPipelineDecodeFailureReason,
            presentationTimeSeconds: Double
        )
    }

    let generation: UInt64
    let payload: Payload
}

nonisolated private enum TAPVideoDepthMetadataProbeResult {
    case frame(TAPDecodedDepthVideoFrame)
    case noSample
}

nonisolated private struct TAPVideoDepthMetadataProbeFailure: Error {
    let reason: TAPVideoDepthPipelineDecodeFailureReason
}

nonisolated private enum TAPVideoDepthMetadataProbe {
    private static let metadataIdentifier = AVMetadataIdentifier(
        rawValue: "mdta/com.tapnap.depth.klv"
    )

    static func readNearestFrame(
        fileURL: URL,
        trackID: CMPersistentTrackID,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        shouldContinue: @escaping @Sendable () -> Bool
    ) async throws -> TAPVideoDepthMetadataProbeResult {
        guard shouldContinue() else {
            throw CancellationError()
        }
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard let window = TAPVideoDepthMetadataProbePolicy.window(
            playbackTimeSeconds: playbackTimeSeconds,
            staleToleranceSeconds: staleToleranceSeconds,
            leadToleranceSeconds: leadToleranceSeconds,
            assetDurationSeconds: durationSeconds
        ) else {
            return .noSample
        }
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        guard shouldContinue() else {
            throw CancellationError()
        }
        guard let metadataTrack = metadataTracks.first(where: { $0.trackID == trackID }) else {
            return .noSample
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
        }
        let output = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
        }
        reader.add(output)
        let preferredTimeScale: CMTimeScale = 600
        reader.timeRange = CMTimeRange(
            start: CMTime(
                seconds: window.startSeconds,
                preferredTimescale: preferredTimeScale
            ),
            end: CMTime(
                seconds: window.endSeconds,
                preferredTimescale: preferredTimeScale
            )
        )
        let adaptor = AVAssetReaderOutputMetadataAdaptor(
            assetReaderTrackOutput: output
        )
        guard reader.startReading() else {
            throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
        }
        defer {
            if reader.status == .reading {
                reader.cancelReading()
            }
        }

        var candidateItems: [AVMetadataItem] = []
        var candidateTimestamps: [Double] = []
        candidateItems.reserveCapacity(16)
        candidateTimestamps.reserveCapacity(16)
        var groupCount = 0
        while let group = adaptor.nextTimedMetadataGroup() {
            guard shouldContinue() else {
                throw CancellationError()
            }
            groupCount += 1
            guard groupCount <= TAPVideoDepthMetadataProbePolicy.maximumMetadataGroupCount else {
                throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
            }
            let timestamp = CMTimeGetSeconds(group.timeRange.start)
            guard timestamp.isFinite,
                  timestamp >= window.startSeconds,
                  timestamp <= window.endSeconds,
                  let item = group.items.first(where: {
                      $0.identifier == metadataIdentifier
                  }) else {
                continue
            }
            candidateTimestamps.append(timestamp)
            candidateItems.append(item)
        }
        if reader.status == .failed {
            throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
        }
        guard shouldContinue() else {
            throw CancellationError()
        }
        guard let nearestIndex = TAPVideoDepthMetadataProbePolicy.nearestCandidateIndex(
            timestamps: candidateTimestamps,
            playbackTimeSeconds: playbackTimeSeconds,
            window: window
        ) else {
            return .noSample
        }
        let nearestItem = candidateItems[nearestIndex]
        let nearestTimestamp = candidateTimestamps[nearestIndex]

        let data: Data
        do {
            guard let loadedData = try await nearestItem.load(.dataValue) else {
                throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
            }
            data = loadedData
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as TAPVideoDepthMetadataProbeFailure {
            throw failure
        } catch {
            throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
        }
        do {
            return .frame(try TAPDepthVideoFrameDecoder.decode(
                data,
                presentationTimeSeconds: nearestTimestamp,
                depthFormat: depthFormat,
                displayOrientation: displayOrientation,
                shouldContinue: shouldContinue
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TAPVideoDepthMetadataProbeFailure(reason: .decode)
        }
    }
}

@MainActor
private final class TAPVideoDepthMetadataOutput: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private nonisolated static let depthMetadataIdentifierRawValue = "mdta/com.tapnap.depth.klv"
    private nonisolated static let decodeAdmission = TAPVideoDepthDecodeAdmission()

    private nonisolated let displayOrientation: CGImagePropertyOrientation
    private nonisolated let depthFormat: TAPVideoManifest.DepthFormat
    private nonisolated let depthTrackID: CMPersistentTrackID?
    private nonisolated let decodeOwner: TAPVideoDepthDecodeAdmission.Owner
    private let metadataQueue = DispatchQueue(label: "com.tapnap.video-depth.metadata", qos: .userInitiated)
    private let onEvent: (TAPVideoDepthPipelineEvent) -> Void
    private weak var attachedItem: AVPlayerItem?
    private var attachedOutput: AVPlayerItemMetadataOutput?
    private var activeGeneration: UInt64 = 0
    private var probeTask: Task<Void, Never>?
    private var probeSequence: UInt64 = 0

    init(
        displayOrientation: CGImagePropertyOrientation,
        depthFormat: TAPVideoManifest.DepthFormat,
        depthTrackID: CMPersistentTrackID?,
        onEvent: @escaping (TAPVideoDepthPipelineEvent) -> Void
    ) {
        self.displayOrientation = displayOrientation
        self.depthFormat = depthFormat
        self.depthTrackID = depthTrackID
        self.decodeOwner = Self.decodeAdmission.makeOwner()
        self.onEvent = onEvent
    }

    deinit {
        Self.decodeAdmission.invalidate(decodeOwner)
    }

    func attach(to item: AVPlayerItem) {
        detach()
        let output = AVPlayerItemMetadataOutput(identifiers: [Self.depthMetadataIdentifierRawValue])
        output.advanceIntervalForDelegateInvocation = TAPVideoDepthPlaybackBudget.metadataAdvanceIntervalSeconds
        output.setDelegate(self, queue: metadataQueue)
        item.add(output)
        attachedItem = item
        attachedOutput = output
    }

    func detach() {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        guard let attachedOutput else {
            attachedItem = nil
            return
        }
        attachedOutput.setDelegate(nil, queue: nil)
        attachedItem?.remove(attachedOutput)
        self.attachedOutput = nil
        attachedItem = nil
    }

    @discardableResult
    func beginNewGeneration() -> UInt64 {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        let generation = Self.decodeAdmission.beginNewGeneration(for: decodeOwner)
        activeGeneration = generation
        return generation
    }

    func probe(
        fileURL: URL,
        playbackTimeSeconds: Double,
        staleToleranceSeconds: Double,
        leadToleranceSeconds: Double
    ) {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        let probeID = probeSequence
        guard let depthTrackID else {
            publish(
                .noSample(playbackTimeSeconds: playbackTimeSeconds),
                generation: activeGeneration
            )
            return
        }
        let decodeAdmission = Self.decodeAdmission
        let decodeOwner = self.decodeOwner
        let expectedGeneration = activeGeneration
        let task = Task.detached(priority: .userInitiated) {
            [weak output = self, decodeAdmission, depthFormat = self.depthFormat,
             displayOrientation = self.displayOrientation] in
            guard let token = await decodeAdmission.admitWhenAvailable(
                for: decodeOwner,
                expectedGeneration: expectedGeneration
            ) else {
                return
            }
            defer {
                decodeAdmission.finish(token)
            }
            do {
                let result = try await TAPVideoDepthMetadataProbe.readNearestFrame(
                    fileURL: fileURL,
                    trackID: depthTrackID,
                    playbackTimeSeconds: playbackTimeSeconds,
                    staleToleranceSeconds: staleToleranceSeconds,
                    leadToleranceSeconds: leadToleranceSeconds,
                    depthFormat: depthFormat,
                    displayOrientation: displayOrientation,
                    shouldContinue: {
                        !Task.isCancelled && decodeAdmission.isCurrent(token)
                    }
                )
                guard decodeAdmission.isCurrent(token) else {
                    return
                }
                await MainActor.run { [weak output] in
                    guard decodeAdmission.isCurrent(token) else {
                        return
                    }
                    switch result {
                    case .frame(let frame):
                        output?.publishProbe(
                            .frame(frame),
                            generation: token.generation,
                            probeID: probeID
                        )
                    case .noSample:
                        output?.publishProbe(
                            .noSample(playbackTimeSeconds: playbackTimeSeconds),
                            generation: token.generation,
                            probeID: probeID
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch let failure as TAPVideoDepthMetadataProbeFailure {
                await MainActor.run { [weak output] in
                    guard decodeAdmission.isCurrent(token) else {
                        return
                    }
                    output?.publishProbe(
                        .decodeFailed(
                            reason: failure.reason,
                            presentationTimeSeconds: playbackTimeSeconds
                        ),
                        generation: token.generation,
                        probeID: probeID
                    )
                }
            } catch {
                await MainActor.run { [weak output] in
                    guard decodeAdmission.isCurrent(token) else {
                        return
                    }
                    output?.publishProbe(
                        .decodeFailed(
                            reason: .metadataRead,
                            presentationTimeSeconds: playbackTimeSeconds
                        ),
                        generation: token.generation,
                        probeID: probeID
                    )
                }
            }
        }
        probeTask = task
    }

    nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            let presentationTimeSeconds = CMTimeGetSeconds(group.timeRange.start)
            guard presentationTimeSeconds.isFinite else {
                continue
            }
            for item in group.items where item.identifier?.rawValue == Self.depthMetadataIdentifierRawValue {
                enqueueDepthMetadataItem(
                    item,
                    presentationTimeSeconds: max(0, presentationTimeSeconds)
                )
            }
        }
    }

    private nonisolated func enqueueDepthMetadataItem(
        _ item: AVMetadataItem,
        presentationTimeSeconds: Double
    ) {
        let decodeAdmission = Self.decodeAdmission
        let decodeOwner = self.decodeOwner
        guard let token = decodeAdmission.admit(for: decodeOwner) else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.info("tap_video_depth_pipeline_backpressure_drop presentationTime=\(presentationTimeSeconds, privacy: .public) pending=\(decodeAdmission.activeDecodeCount, privacy: .public)")
            #endif
            let generation = decodeAdmission.currentGeneration(for: decodeOwner) ?? 0
            Task { @MainActor [weak self] in
                self?.publish(
                    .decodeFailed(
                        reason: .backpressure,
                        presentationTimeSeconds: presentationTimeSeconds
                    ),
                    generation: generation
                )
            }
            return
        }

        let frameOrientation = displayOrientation
        Task.detached(priority: .userInitiated) {
            [weak output = self, decodeAdmission, depthFormat = self.depthFormat] in
            defer {
                decodeAdmission.finish(token)
            }
            guard decodeAdmission.isCurrent(token) else {
                return
            }
            let data: Data
            do {
                guard let loadedData = try await item.load(.dataValue) else {
                    throw TAPVideoDepthMetadataProbeFailure(reason: .metadataRead)
                }
                data = loadedData
            } catch {
                await MainActor.run { [weak output] in
                    guard decodeAdmission.isCurrent(token) else {
                        return
                    }
                    output?.publish(
                        .decodeFailed(
                            reason: .metadataRead,
                            presentationTimeSeconds: presentationTimeSeconds
                        ),
                        generation: token.generation
                    )
                }
                return
            }
            guard decodeAdmission.isCurrent(token) else {
                return
            }
            let frame: TAPDecodedDepthVideoFrame
            do {
                frame = try TAPDepthVideoFrameDecoder.decode(
                    data,
                    presentationTimeSeconds: presentationTimeSeconds,
                    depthFormat: depthFormat,
                    displayOrientation: frameOrientation,
                    shouldContinue: {
                        decodeAdmission.isCurrent(token)
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak output] in
                    guard decodeAdmission.isCurrent(token) else {
                        return
                    }
                    output?.publish(
                        .decodeFailed(
                            reason: .decode,
                            presentationTimeSeconds: presentationTimeSeconds
                        ),
                        generation: token.generation
                    )
                }
                return
            }
            guard decodeAdmission.isCurrent(token) else {
                return
            }
            await MainActor.run { [weak output] in
                guard decodeAdmission.isCurrent(token) else {
                    return
                }
                output?.publishFrameFromPush(
                    frame,
                    generation: token.generation
                )
            }
        }
    }

    private func publishFrameFromPush(
        _ frame: TAPDecodedDepthVideoFrame,
        generation: UInt64
    ) {
        probeTask?.cancel()
        probeTask = nil
        probeSequence &+= 1
        publish(.frame(frame), generation: generation)
    }

    private func publishProbe(
        _ payload: TAPVideoDepthPipelineEvent.Payload,
        generation: UInt64,
        probeID: UInt64
    ) {
        guard probeID == probeSequence else {
            return
        }
        probeTask = nil
        publish(payload, generation: generation)
    }

    private func publish(
        _ payload: TAPVideoDepthPipelineEvent.Payload,
        generation: UInt64
    ) {
        guard generation == activeGeneration else {
            return
        }
        onEvent(TAPVideoDepthPipelineEvent(
            generation: generation,
            payload: payload
        ))
    }
}

nonisolated struct TAPDecodedDepthVideoFrame {
    let frameIndex: Int
    let presentationTimeSeconds: Double
    let width: Int
    let height: Int
    let pixelFormat: String
    let image: UIImage
    let retainedByteCount: Int

    func cacheMatches(_ other: TAPDecodedDepthVideoFrame) -> Bool {
        frameIndex == other.frameIndex
            || abs(presentationTimeSeconds - other.presentationTimeSeconds) < 0.000_5
    }
}

nonisolated enum TAPDepthVideoFrameDecoder {
    static func decode(
        _ data: Data,
        presentationTimeSeconds: Double,
        depthFormat: TAPVideoManifest.DepthFormat,
        displayOrientation: CGImagePropertyOrientation,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) throws -> TAPDecodedDepthVideoFrame {
        guard shouldContinue() else {
            throw CancellationError()
        }
        let encodedFrame = try TAPDepthKLVFrame.decode(data)
        let decodeTrace = TAPVideoPerformanceTrace.beginDepthDecode(
            frameIndex: Int(encodedFrame.frameIndex)
        )
        var didDecode = false
        var decodedOutputByteCount = 0
        defer {
            TAPVideoPerformanceTrace.endDepthDecode(
                decodeTrace,
                succeeded: didDecode,
                outputByteCount: decodedOutputByteCount
            )
        }
        guard shouldContinue() else {
            throw CancellationError()
        }
        let width = Int(depthFormat.width)
        let height = Int(depthFormat.height)
        let rowStride = depthFormat.packedRowStride
        let pixelFormat = depthFormat.pixelFormat
        let expectedBytesPerSample: Int
        switch pixelFormat {
        case "fdep", "fdis":
            expectedBytesPerSample = 4
        case "hdep", "hdis":
            expectedBytesPerSample = 2
        default:
            throw TAPDepthCaptureError.invalidTAPManifest(
                "unsupported TAP depth video pixel format"
            )
        }
        let (expectedRowStride, rowStrideOverflow) = width.multipliedReportingOverflow(
            by: expectedBytesPerSample
        )
        let (expectedFrameByteCount, frameByteCountOverflow) = rowStride.multipliedReportingOverflow(
            by: height
        )
        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(by: height)
        let (renderedByteCount, renderedByteCountOverflow) = pixelCount.multipliedReportingOverflow(
            by: 4
        )
        guard width > 0,
              height > 0,
              !rowStrideOverflow,
              !frameByteCountOverflow,
              !pixelCountOverflow,
              !renderedByteCountOverflow,
              depthFormat.bytesPerSample == expectedBytesPerSample,
              rowStride == expectedRowStride,
              expectedFrameByteCount == depthFormat.uncompressedFrameByteCount,
              renderedByteCount <= TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes,
              depthFormat.byteOrder == "little-endian",
              encodedFrame.uncompressedByteCount == depthFormat.uncompressedFrameByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("depth frame does not match manifest format")
        }
        let depthPayload = try encodedFrame.decodedPackedBytes()
        guard depthPayload.count == depthFormat.uncompressedFrameByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("depth frame does not match manifest format")
        }

        let rendered = try TAPDepthFrameRenderer.render(
            payload: depthPayload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            displayOrientation: displayOrientation,
            shouldContinue: shouldContinue
        )
        decodedOutputByteCount = rendered.retainedByteCount
        didDecode = true
        return TAPDecodedDepthVideoFrame(
            frameIndex: Int(encodedFrame.frameIndex),
            presentationTimeSeconds: presentationTimeSeconds,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            image: rendered.image,
            retainedByteCount: rendered.retainedByteCount
        )
    }
}

nonisolated private struct TAPDepthFrameRenderResult {
    let image: UIImage
    let retainedByteCount: Int
}

nonisolated private enum TAPDepthFrameRenderer {
    static func render(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        displayOrientation: CGImagePropertyOrientation,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> TAPDepthFrameRenderResult {
        guard width > 0,
              height > 0,
              rowStride > 0,
              payload.count >= rowStride * height else {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid TAP depth video frame shape")
        }

        let bytesPerSample = try bytesPerSample(pixelFormat: pixelFormat)
        guard rowStride >= width * bytesPerSample else {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid TAP depth video row stride")
        }
        let range = try depthRange(
            payload: payload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            bytesPerSample: bytesPerSample,
            shouldContinue: shouldContinue
        )
        let pixels = try heatmapPixels(
            payload: payload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            bytesPerSample: bytesPerSample,
            range: range,
            shouldContinue: shouldContinue
        )
        let heatmap = try TAPDepthRGBAImageRenderer.image(
            pixels: pixels,
            width: width,
            height: height
        )
        return TAPDepthFrameRenderResult(
            image: UIImage(
                cgImage: heatmap,
                scale: 1,
                orientation: displayOrientation.uiImageOrientation
            ),
            retainedByteCount: heatmap.bytesPerRow * heatmap.height
        )
    }

    private static func depthRange(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        bytesPerSample: Int,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> ClosedRange<Float> {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var hasValidValue = false
        try payload.withUnsafeBytes { bytes in
            for y in 0..<height {
                guard shouldContinue() else {
                    throw CancellationError()
                }
                let rowOffset = y * rowStride
                for x in 0..<width {
                    let value = try sampleValue(
                        bytes: bytes,
                        offset: rowOffset + x * bytesPerSample,
                        pixelFormat: pixelFormat
                    )
                    guard value.isFinite, value > 0 else {
                        continue
                    }
                    minimum = min(minimum, value)
                    maximum = max(maximum, value)
                    hasValidValue = true
                }
            }
        }
        guard hasValidValue else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }
        return minimum...maximum
    }

    private static func heatmapPixels(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        bytesPerSample: Int,
        range: ClosedRange<Float>,
        shouldContinue: @escaping @Sendable () -> Bool
    ) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let span = max(range.upperBound - range.lowerBound, 0.001)
        try pixels.withUnsafeMutableBytes { output in
            try payload.withUnsafeBytes { input in
                for y in 0..<height {
                    guard shouldContinue() else {
                        throw CancellationError()
                    }
                    let rowOffset = y * rowStride
                    for x in 0..<width {
                        let value = try sampleValue(
                            bytes: input,
                            offset: rowOffset + x * bytesPerSample,
                            pixelFormat: pixelFormat
                        )
                        guard value.isFinite, value > 0 else {
                            continue
                        }
                        let normalized = min(max((value - range.lowerBound) / span, 0), 1)
                        let color = TAPDepthHeatmapRenderer.viridisColor(normalized: normalized)
                        let outputOffset = (y * width + x) * 4
                        output[outputOffset] = color.red
                        output[outputOffset + 1] = color.green
                        output[outputOffset + 2] = color.blue
                        output[outputOffset + 3] = color.alpha
                    }
                }
            }
        }
        return pixels
    }

    private static func bytesPerSample(pixelFormat: String) throws -> Int {
        switch pixelFormat {
        case "fdep", "fdis":
            4
        case "hdep", "hdis":
            2
        default:
            throw TAPDepthCaptureError.invalidTAPManifest("unsupported TAP depth video pixel format")
        }
    }

    private static func sampleValue(
        bytes: UnsafeRawBufferPointer,
        offset: Int,
        pixelFormat: String
    ) throws -> Float {
        switch pixelFormat {
        case "fdep", "fdis":
            guard offset >= 0,
                  offset + 4 <= bytes.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth float32 row")
            }
            let bits = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            return Float(bitPattern: bits)
        case "hdep", "hdis":
            guard offset >= 0,
                  offset + 2 <= bytes.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth float16 row")
            }
            let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            return Float(Float16(bitPattern: bits))
        default:
            throw TAPDepthCaptureError.invalidTAPManifest("unsupported TAP depth video pixel format")
        }
    }
}

private extension Data {
    nonisolated func tapUInt32BE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }

    nonisolated func tapInt32BE(at offset: Int) -> Int32 {
        Int32(bitPattern: tapUInt32BE(at: offset))
    }
}

private extension CGImagePropertyOrientation {
    nonisolated var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        }
    }
}
