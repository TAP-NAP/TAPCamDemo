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
    @StateObject private var viewModel: TAPVideoDepthPlaybackViewModel
    @State private var selectedLayer = TAPVideoPlaybackLayer.twoD
    @State private var depthOverlayOpacity = 0.58
    @State private var sharePayload: TAPVideoSystemSharePayload?
    @State private var isPreparingShare = false
    @State private var pendingDeleteRequest: TAPVideoPendingDeleteRequest?
    @State private var deleteAlert: TAPVideoDeleteAlert?
    @State private var removedVideoEntryIDs: Set<String> = []

    init(
        source: TAPVideoPlaybackSource,
        albumContext: TAPVideoAlbumContext? = nil,
        onCurrentAlbumEntryChanged: ((TAPVideoAlbumContext.Entry) -> Void)? = nil
    ) {
        self.source = source
        self.albumContext = albumContext
        self.onCurrentAlbumEntryChanged = onCurrentAlbumEntryChanged
        _viewModel = StateObject(wrappedValue: TAPVideoDepthPlaybackViewModel(source: source))
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
        .task {
            await viewModel.loadIfNeeded()
            if selectedLayer.usesDepthFrames {
                viewModel.prepareTwoDPlaybackGate()
            }
        }
        .onChange(of: selectedLayer) { _, layer in
            handleLayerChanged(layer)
        }
        .onDisappear {
            viewModel.stopPlayback()
        }
    }

    private func videoSurface() -> some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            let safeAreaInsets = geometry.safeAreaInsets
            let systemControlsBottomInset = TAPVideoPlaybackContentLayout.systemControlsBottomInset(
                showsOpacityControl: selectedLayer == .twoD
            )

            ZStack(alignment: .bottom) {
                content(systemControlsBottomInset: systemControlsBottomInset)
                    .frame(width: viewportSize.width, height: viewportSize.height)
                    .background(Color.black)

                DepthViewerChromeView(
                    selectedModeID: selectedLayer.rawValue,
                    modeItems: TAPVideoPlaybackLayer.allCases.map(\.modeItem),
                    overlayOpacity: $depthOverlayOpacity,
                    showsOpacityControl: selectedLayer == .twoD,
                    isSharePreparing: isPreparingShare,
                    shareAccessibilityLabel: isPreparingShare ? "Preparing share" : "Share video",
                    deleteAccessibilityLabel: "Delete video",
                    topSafeArea: safeAreaInsets.top,
                    bottomSafeArea: safeAreaInsets.bottom,
                    onBackTapped: {
                        dismiss()
                    },
                    onShareTapped: presentSystemShareSheet,
                    onModeTapped: handleModeTapped,
                    onDeleteTapped: deleteCurrentVideo
                )
                .zIndex(2)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(videoSwipeGesture)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func content(systemControlsBottomInset: CGFloat) -> some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .tint(.white)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to play video",
                systemImage: "video.slash",
                description: Text(message)
            )
            .foregroundStyle(.white)
            .padding()
        case .ready:
            playbackSurface(systemControlsBottomInset: systemControlsBottomInset)
        }
    }

    @ViewBuilder
    private func playbackSurface(systemControlsBottomInset: CGFloat) -> some View {
        ZStack {
            Color.black

            switch selectedLayer {
            case .rgb:
                playerView(systemControlsBottomInset: systemControlsBottomInset)
            case .twoD:
                ZStack {
                    playerView(systemControlsBottomInset: systemControlsBottomInset)
                    if let depthImage = viewModel.depthFrameImage {
                        Image(uiImage: depthImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(depthOverlayOpacity)
                            .allowsHitTesting(false)
                    }
                }
            }

            if selectedLayer == .twoD,
               viewModel.isPreparingTwoDPlayback {
                twoDPreparationOverlay
                    .zIndex(3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func playerView(systemControlsBottomInset: CGFloat) -> some View {
        if let player = viewModel.player {
            TAPSystemVideoPlayerView(
                player: player,
                controlsBottomInset: systemControlsBottomInset
            )
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
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
        guard let layer = TAPVideoPlaybackLayer(rawValue: itemID) else {
            return
        }
        selectedLayer = layer
    }

    private func handleLayerChanged(_ layer: TAPVideoPlaybackLayer) {
        if layer.usesDepthFrames {
            viewModel.prepareTwoDPlaybackGate()
        } else {
            viewModel.cancelTwoDPlaybackGate()
        }
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
        viewModel.stopPlayback()
        onCurrentAlbumEntryChanged?(entry)
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

private enum TAPVideoPlaybackLayer: String, CaseIterable, Identifiable {
    case rgb
    case twoD

    var id: String { rawValue }

    var usesDepthFrames: Bool {
        switch self {
        case .rgb:
            false
        case .twoD:
            true
        }
    }

    var modeItem: DepthViewerModeItem {
        DepthViewerModeItem(
            id: rawValue,
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel
        )
    }

    private var systemImage: String {
        switch self {
        case .rgb:
            "video"
        case .twoD:
            "square.on.square"
        }
    }

    private var accessibilityLabel: String {
        switch self {
        case .rgb:
            "RGB video"
        case .twoD:
            "2D video"
        }
    }
}

nonisolated enum TAPVideoPlaybackContentLayout {
    private static let baseBottomChromeClearance: CGFloat = 84
    private static let opacityControlClearance: CGFloat = 56

    static func systemControlsBottomInset(showsOpacityControl: Bool) -> CGFloat {
        baseBottomChromeClearance
            + (showsOpacityControl ? opacityControlClearance : 0)
    }
}

private struct TAPSystemVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let controlsBottomInset: CGFloat

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.additionalSafeAreaInsets.bottom = max(0, controlsBottomInset)
        controller.view.backgroundColor = .black
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
    @Published private(set) var player: AVPlayer?
    @Published private(set) var depthFrameImage: UIImage?
    @Published private(set) var depthFrameOrientation: CGImagePropertyOrientation = .up
    @Published private(set) var videoAspectRatio: CGFloat?
    @Published private(set) var isPlaying = false
    @Published private(set) var hasReachedEnd = false
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    @Published private(set) var isPreparingTwoDPlayback = false

    private static let depthFrameLeadToleranceSeconds = 0.08
    private static let depthFrameStaleToleranceSeconds = 1.25
    private static let maxDepthFrameCacheCount = 900
    private static let preferredTwoDBufferDurationSeconds: TimeInterval = 3
    private static let twoDPlaybackGateNanoseconds: UInt64 = 2_000_000_000

    private let source: TAPVideoPlaybackSource
    private var metadataOutput: TAPVideoDepthMetadataOutput?
    private var temporaryDirectoryURL: URL?
    private var resolvedFileURL: URL?
    private var playbackEndObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var playerStatusObservation: NSKeyValueObservation?
    private var twoDPlaybackGateTask: Task<Void, Never>?
    private var depthFrameCache: [TAPDecodedDepthVideoFrame] = []
    private var currentDepthFrameTimeSeconds: Double?
    private var depthFrameSelectionMissCount = 0
    private var lastDepthFrameMissLogTimeSeconds: Double?

    init(source: TAPVideoPlaybackSource) {
        self.source = source
    }

    deinit {
        temporaryDirectoryURL.map { try? FileManager.default.removeItem(at: $0) }
    }

    var playbackProgress: Double {
        guard durationSeconds.isFinite,
              durationSeconds > 0 else {
            return 0
        }
        return min(max(currentTimeSeconds / durationSeconds, 0), 1)
    }

    var primaryPlaybackSystemImageName: String {
        if hasReachedEnd {
            return "arrow.counterclockwise"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    var primaryPlaybackAccessibilityLabel: String {
        if hasReachedEnd {
            return "Replay TAP video"
        }
        return isPlaying ? "Pause TAP video" : "Play TAP video"
    }

    var timecodeText: String {
        "\(Self.timecode(currentTimeSeconds)) / \(Self.timecode(durationSeconds))"
    }

    func loadIfNeeded() async {
        guard state == .idle else {
            return
        }
        state = .loading

        do {
            let resource = try await Self.resolveResource(source: source)
            let presentation = await Self.videoPresentation(for: resource.fileURL)
            temporaryDirectoryURL = resource.temporaryDirectoryURL
            resolvedFileURL = resource.fileURL
            self.depthFrameOrientation = presentation.depthFrameOrientation
            self.videoAspectRatio = presentation.aspectRatio
            let item = AVPlayerItem(url: resource.fileURL)
            let metadataOutput = TAPVideoDepthMetadataOutput(
                displayOrientation: presentation.depthFrameOrientation
            ) { [weak self] frame in
                self?.storeDepthFrame(frame)
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                if frame.frameIndex == 0 {
                    LockedCameraDiagnostics.logger.info("tap_video_depth_playback_first_frame width=\(frame.width, privacy: .public) height=\(frame.height, privacy: .public) pixelFormat=\(frame.pixelFormat, privacy: .public) presentationTime=\(frame.presentationTimeSeconds, privacy: .public) orientation=\(String(describing: presentation.depthFrameOrientation), privacy: .public)")
                }
                #endif
            }
            metadataOutput.attach(to: item)
            self.metadataOutput = metadataOutput

            let player = AVPlayer(playerItem: item)
            self.player = player
            installPlaybackObservers(player: player, item: item)
            state = .ready
            warmPlayback(player: player)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.info("tap_video_playback_loaded source=\(Self.sourceLabel(self.source), privacy: .public) fileURL=\(resource.fileURL.lastPathComponent, privacy: .public) autoPlay=false")
            #endif
        } catch {
            state = .failed(DepthAnalysisErrorPresentation.albumLoadErrorMessage(for: error))
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.error("tap_video_playback_load_failed source=\(Self.sourceLabel(self.source), privacy: .public) error=\(Self.describe(error), privacy: .public)")
            #endif
        }
    }

    func stopPlayback() {
        cancelTwoDPlaybackGate()
        pause()
        removePlaybackObservers()
    }

    func shareableFileURL() async throws -> URL {
        if let resolvedFileURL {
            return resolvedFileURL
        }
        let resource = try await Self.resolveResource(source: source)
        temporaryDirectoryURL = resource.temporaryDirectoryURL
        resolvedFileURL = resource.fileURL
        return resource.fileURL
    }

    func prepareTwoDPlaybackGate() {
        guard state == .ready else {
            return
        }
        twoDPlaybackGateTask?.cancel()
        isPreparingTwoDPlayback = true
        pause()
        if let player {
            player.currentItem?.preferredForwardBufferDuration = Self.preferredTwoDBufferDurationSeconds
            prerollIfReady(player: player)
        }

        twoDPlaybackGateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.twoDPlaybackGateNanoseconds)
            guard !Task.isCancelled,
                  let self else {
                return
            }
            self.isPreparingTwoDPlayback = false
            self.twoDPlaybackGateTask = nil
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.info("tap_video_depth_2d_gate_ready source=\(Self.sourceLabel(self.source), privacy: .public)")
            #endif
        }
    }

    func cancelTwoDPlaybackGate() {
        twoDPlaybackGateTask?.cancel()
        twoDPlaybackGateTask = nil
        isPreparingTwoDPlayback = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func play() {
        guard let player else {
            return
        }
        if hasReachedEnd {
            player.seek(to: .zero)
            currentTimeSeconds = 0
            hasReachedEnd = false
            resetDepthFrameClockSelection()
        }
        player.play()
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

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
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.isPlaying = false
                self.hasReachedEnd = true
            }
        }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { time in
            Task { @MainActor [weak self, weak item] in
                guard let self else {
                    return
                }
                let playbackTimeSeconds = max(0, CMTimeGetSeconds(time))
                if playbackTimeSeconds + 1 < self.currentTimeSeconds {
                    self.resetDepthFrameClockSelection()
                }
                self.currentTimeSeconds = playbackTimeSeconds
                if let item {
                    let duration = CMTimeGetSeconds(item.duration)
                    if duration.isFinite, duration > 0 {
                        self.durationSeconds = duration
                    }
                }
                self.updateDepthFrame(for: playbackTimeSeconds)
                self.isPlaying = self.player?.rate != 0
            }
        }
    }

    private func removePlaybackObservers() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
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
        if let index = depthFrameCache.firstIndex(where: { $0.cacheMatches(frame) }) {
            depthFrameCache[index] = frame
        } else {
            depthFrameCache.append(frame)
            depthFrameCache.sort { $0.presentationTimeSeconds < $1.presentationTimeSeconds }
        }
        pruneDepthFrameCache(around: currentTimeSeconds)
        updateDepthFrame(for: currentTimeSeconds)
    }

    private func updateDepthFrame(for playbackTimeSeconds: Double) {
        guard playbackTimeSeconds.isFinite else {
            return
        }
        let earliest = playbackTimeSeconds - Self.depthFrameStaleToleranceSeconds
        let latest = playbackTimeSeconds + Self.depthFrameLeadToleranceSeconds
        let frame = depthFrameCache
            .filter({ frame in
                frame.presentationTimeSeconds >= earliest
                    && frame.presentationTimeSeconds <= latest
            })
            .min(by: { lhs, rhs in
                abs(lhs.presentationTimeSeconds - playbackTimeSeconds)
                    < abs(rhs.presentationTimeSeconds - playbackTimeSeconds)
            })
        guard let frame else {
            logDepthFrameSelectionMiss(playbackTimeSeconds: playbackTimeSeconds)
            return
        }
        guard currentDepthFrameTimeSeconds != frame.presentationTimeSeconds else {
            return
        }
        currentDepthFrameTimeSeconds = frame.presentationTimeSeconds
        depthFrameImage = frame.image
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
        let nearestDelta = depthFrameCache
            .map { abs($0.presentationTimeSeconds - playbackTimeSeconds) }
            .min() ?? -1
        LockedCameraDiagnostics.logger.info("tap_video_depth_pipeline_miss source=\(Self.sourceLabel(self.source), privacy: .public) playbackTime=\(playbackTimeSeconds, privacy: .public) cacheCount=\(self.depthFrameCache.count, privacy: .public) nearestDelta=\(nearestDelta, privacy: .public) missCount=\(self.depthFrameSelectionMissCount, privacy: .public)")
        #endif
    }

    private func pruneDepthFrameCache(around playbackTimeSeconds: Double) {
        guard depthFrameCache.count > Self.maxDepthFrameCacheCount else {
            return
        }
        depthFrameCache.sort { lhs, rhs in
            abs(lhs.presentationTimeSeconds - playbackTimeSeconds)
                < abs(rhs.presentationTimeSeconds - playbackTimeSeconds)
        }
        depthFrameCache = Array(depthFrameCache.prefix(Self.maxDepthFrameCacheCount))
        depthFrameCache.sort { $0.presentationTimeSeconds < $1.presentationTimeSeconds }
    }

    private func resetDepthFrameClockSelection() {
        currentDepthFrameTimeSeconds = nil
        depthFrameImage = nil
    }

    private static func resolveResource(
        source: TAPVideoPlaybackSource
    ) async throws -> TAPVideoPlaybackResolvedResource {
        switch source {
        case .pendingCapture(let captureID):
            let fileURL = try await TAPPendingCaptureStore.shared.bestAvailableVideoURL(captureID: captureID)
            return TAPVideoPlaybackResolvedResource(fileURL: fileURL, temporaryDirectoryURL: nil)
        case .ownedCapture(let captureID, let assetID):
            do {
                let fileURL = try await TAPPendingCaptureStore.shared.bestAvailableVideoURL(captureID: captureID)
                return TAPVideoPlaybackResolvedResource(fileURL: fileURL, temporaryDirectoryURL: nil)
            } catch {
                let fileURL = try await PhotoLibraryWriter.originalVideoFileURL(localIdentifier: assetID)
                return TAPVideoPlaybackResolvedResource(
                    fileURL: fileURL,
                    temporaryDirectoryURL: fileURL.deletingLastPathComponent()
                )
            }
        case .photosAsset(let assetID):
            let fileURL = try await PhotoLibraryWriter.originalVideoFileURL(localIdentifier: assetID)
            return TAPVideoPlaybackResolvedResource(
                fileURL: fileURL,
                temporaryDirectoryURL: fileURL.deletingLastPathComponent()
            )
        }
    }

    private static func videoPresentation(for fileURL: URL) async -> TAPVideoPlaybackPresentation {
        await Task.detached(priority: .utility) {
            do {
                let data = try Data(contentsOf: fileURL)
                let manifest = try TAPVideoManifestBox.decodedManifest(from: data)
                let displaySize = TAPVideoDepthDisplayOrientation.displaySize(
                    width: manifest.payload.rgbTrack.width,
                    height: manifest.payload.rgbTrack.height,
                    transform: manifest.payload.rgbTrack.transform
                )
                return TAPVideoPlaybackPresentation(
                    depthFrameOrientation: TAPVideoDepthDisplayOrientation.cgImageOrientation(
                        from: manifest.payload.rgbTrack.transform
                    ),
                    aspectRatio: Self.aspectRatio(for: displaySize)
                )
            } catch {
                let displaySize = await Self.assetVideoDisplaySize(for: fileURL)
                return TAPVideoPlaybackPresentation(
                    depthFrameOrientation: .up,
                    aspectRatio: Self.aspectRatio(for: displaySize)
                )
            }
        }.value
    }

    private nonisolated static func assetVideoDisplaySize(for fileURL: URL) async -> CGSize? {
        let asset = AVURLAsset(url: fileURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await videoTrack.load(.naturalSize),
              let preferredTransform = try? await videoTrack.load(.preferredTransform) else {
            return nil
        }
        let transformedSize = naturalSize.applying(preferredTransform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }

    private nonisolated static func aspectRatio(for displaySize: CGSize?) -> CGFloat? {
        guard let displaySize,
              displaySize.width.isFinite,
              displaySize.height.isFinite,
              displaySize.width > 0,
              displaySize.height > 0 else {
            return nil
        }
        return displaySize.width / displaySize.height
    }

    private static func sourceLabel(_ source: TAPVideoPlaybackSource) -> String {
        switch source {
        case .pendingCapture:
            "pending"
        case .ownedCapture:
            "owned"
        case .photosAsset:
            "photos"
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }

    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }
        let rounded = Int(seconds.rounded(.down))
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))"
    }
}

private struct TAPVideoPlaybackResolvedResource {
    let fileURL: URL
    let temporaryDirectoryURL: URL?
}

private struct TAPVideoPlaybackPresentation {
    let depthFrameOrientation: CGImagePropertyOrientation
    let aspectRatio: CGFloat?
}

@MainActor
private final class TAPVideoDepthMetadataOutput: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private nonisolated static let depthMetadataIdentifierRawValue = "mdta/com.tapnap.depth.klv"
    private nonisolated static let depthMetadataAdvanceIntervalSeconds: TimeInterval = 2
    private nonisolated static let maxPendingDepthDecodeCount = 90

    private nonisolated let displayOrientation: CGImagePropertyOrientation
    private let metadataQueue = DispatchQueue(label: "com.tapnap.video-depth.metadata", qos: .userInitiated)
    private nonisolated let decodeQueue = DispatchQueue(
        label: "com.tapnap.video-depth.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private nonisolated let decodeBackpressure: TAPVideoDepthDecodeBackpressure
    private let onFrame: (TAPDecodedDepthVideoFrame) -> Void

    init(
        displayOrientation: CGImagePropertyOrientation,
        onFrame: @escaping (TAPDecodedDepthVideoFrame) -> Void
    ) {
        self.displayOrientation = displayOrientation
        self.decodeBackpressure = TAPVideoDepthDecodeBackpressure(
            maxPendingCount: TAPVideoDepthMetadataOutput.maxPendingDepthDecodeCount
        )
        self.onFrame = onFrame
    }

    func attach(to item: AVPlayerItem) {
        let output = AVPlayerItemMetadataOutput(identifiers: [Self.depthMetadataIdentifierRawValue])
        output.advanceIntervalForDelegateInvocation = Self.depthMetadataAdvanceIntervalSeconds
        output.setDelegate(self, queue: metadataQueue)
        item.add(output)
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
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? await item.load(.dataValue) else {
                return
            }
            self?.enqueueDepthPayload(
                data,
                presentationTimeSeconds: presentationTimeSeconds
            )
        }
    }

    private nonisolated func enqueueDepthPayload(
        _ data: Data,
        presentationTimeSeconds: Double
    ) {
        guard decodeBackpressure.begin() else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            LockedCameraDiagnostics.logger.info("tap_video_depth_pipeline_backpressure_drop presentationTime=\(presentationTimeSeconds, privacy: .public) pending=\(self.decodeBackpressure.pendingCount, privacy: .public)")
            #endif
            return
        }

        let frameOrientation = displayOrientation
        decodeQueue.async { [weak self, decodeBackpressure] in
            defer {
                decodeBackpressure.end()
            }
            guard let frame = try? TAPDepthVideoFrameDecoder.decode(
                data,
                presentationTimeSeconds: presentationTimeSeconds,
                displayOrientation: frameOrientation
            ) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.publish(frame)
            }
        }
    }

    private func publish(_ frame: TAPDecodedDepthVideoFrame) {
        onFrame(frame)
    }
}

nonisolated private final class TAPVideoDepthDecodeBackpressure: @unchecked Sendable {
    private let maxPendingCount: Int
    private let lock = NSLock()
    private var pending = 0

    init(maxPendingCount: Int) {
        self.maxPendingCount = maxPendingCount
    }

    var pendingCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return pending
    }

    func begin() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard pending < maxPendingCount else {
            return false
        }
        pending += 1
        return true
    }

    func end() {
        lock.lock()
        pending = max(0, pending - 1)
        lock.unlock()
    }
}

nonisolated private struct TAPDecodedDepthVideoFrame {
    let frameIndex: Int
    let presentationTimeSeconds: Double
    let width: Int
    let height: Int
    let pixelFormat: String
    let depthMap: TAPMetricDepthMap
    let image: UIImage

    func cacheMatches(_ other: TAPDecodedDepthVideoFrame) -> Bool {
        frameIndex == other.frameIndex
            || abs(presentationTimeSeconds - other.presentationTimeSeconds) < 0.000_5
    }
}

nonisolated private enum TAPDepthVideoFrameDecoder {
    static func decode(
        _ data: Data,
        presentationTimeSeconds: Double,
        displayOrientation: CGImagePropertyOrientation
    ) throws -> TAPDecodedDepthVideoFrame {
        let records = try TAPDepthKLV.decode(data)
        let payloadByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0.payload) })

        guard let dimensionsPayload = payloadByKey[.dimensions],
              dimensionsPayload.count == 8 else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth video dimensions")
        }
        let width = Int(dimensionsPayload.tapInt32BE(at: 0))
        let height = Int(dimensionsPayload.tapInt32BE(at: 4))

        guard let rowStridePayload = payloadByKey[.rowStride],
              rowStridePayload.count == 4 else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth video row stride")
        }
        let rowStride = Int(rowStridePayload.tapUInt32BE(at: 0))

        guard let pixelFormatPayload = payloadByKey[.pixelFormat],
              let pixelFormat = String(data: pixelFormatPayload, encoding: .ascii),
              let depthPayload = payloadByKey[.depthPayload] else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth video payload")
        }

        let frameIndex: Int
        if let framePayload = payloadByKey[.frameIndex], framePayload.count == 4 {
            frameIndex = Int(framePayload.tapUInt32BE(at: 0))
        } else {
            frameIndex = 0
        }

        let rendered = try TAPDepthFrameRenderer.render(
            payload: depthPayload,
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            rowStride: rowStride,
            displayOrientation: displayOrientation
        )
        return TAPDecodedDepthVideoFrame(
            frameIndex: frameIndex,
            presentationTimeSeconds: presentationTimeSeconds,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            depthMap: rendered.depthMap,
            image: rendered.image
        )
    }
}

nonisolated private struct TAPDepthFrameRenderResult {
    let depthMap: TAPMetricDepthMap
    let image: UIImage
}

nonisolated private enum TAPDepthFrameRenderer {
    static func render(
        payload: Data,
        pixelFormat: String,
        width: Int,
        height: Int,
        rowStride: Int,
        displayOrientation: CGImagePropertyOrientation
    ) throws -> TAPDepthFrameRenderResult {
        guard width > 0,
              height > 0,
              rowStride > 0,
              payload.count >= rowStride * height else {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid TAP depth video frame shape")
        }

        let values: [Float]
        switch pixelFormat {
        case "fdep", "fdis":
            values = try float32Values(payload: payload, width: width, height: height, rowStride: rowStride)
        case "hdep", "hdis":
            values = try float16Values(payload: payload, width: width, height: height, rowStride: rowStride)
        default:
            throw TAPDepthCaptureError.invalidTAPManifest("unsupported TAP depth video pixel format")
        }

        let depthMap = TAPMetricDepthMap(width: width, height: height, samples: values, calibration: nil)
        let heatmap = try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        return TAPDepthFrameRenderResult(
            depthMap: depthMap,
            image: UIImage(
                cgImage: heatmap.image,
                scale: 1,
                orientation: displayOrientation.uiImageOrientation
            )
        )
    }

    private static func float32Values(
        payload: Data,
        width: Int,
        height: Int,
        rowStride: Int
    ) throws -> [Float] {
        let bytes = [UInt8](payload)
        var values: [Float] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            let rowOffset = y * rowStride
            for x in 0..<width {
                let offset = rowOffset + x * 4
                guard offset + 4 <= bytes.count else {
                    throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth float32 row")
                }
                let bits = UInt32(bytes[offset])
                    | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16
                    | UInt32(bytes[offset + 3]) << 24
                values.append(Float(bitPattern: bits))
            }
        }
        return values
    }

    private static func float16Values(
        payload: Data,
        width: Int,
        height: Int,
        rowStride: Int
    ) throws -> [Float] {
        let bytes = [UInt8](payload)
        var values: [Float] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            let rowOffset = y * rowStride
            for x in 0..<width {
                let offset = rowOffset + x * 2
                guard offset + 2 <= bytes.count else {
                    throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth float16 row")
                }
                let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                values.append(Float(Float16(bitPattern: bits)))
            }
        }
        return values
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
