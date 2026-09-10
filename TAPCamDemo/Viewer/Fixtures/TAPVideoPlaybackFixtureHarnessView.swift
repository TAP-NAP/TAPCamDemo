//
//  TAPVideoPlaybackFixtureHarnessView.swift
//  TAPCamDemo
//

#if DEBUG
import Foundation
import SwiftUI
import UIKit

@MainActor
struct TAPVideoPlaybackFixtureHarnessView: View {
    let configuration: TAPVideoPlaybackFixtureLaunchConfiguration
    private let pendingDeleteKind = ProcessInfo.processInfo.environment[
        "TAPCAM_UI_TEST_PENDING_DELETE"
    ]

    @State private var phase = Phase.generating
    @State private var presentedArtifact: TAPVideoPlaybackFixtureArtifact?
    @State private var readinessDelayGate = TAPVideoPlaybackFixtureReadinessDelayGate()

    var body: some View {
        Group {
            if pendingDeleteKind == "photo" {
                NavigationStack {
                    DepthAnalysisView(source: .pendingCapture("ui-test-missing-photo"))
                }
            } else if pendingDeleteKind == "video" {
                NavigationStack {
                    TAPVideoDepthPlaybackView(source: .pendingCapture("ui-test-missing-video"))
                }
            } else if configuration.showsGallery {
                TAPGalleryFixtureView()
            } else {
                NavigationStack {
                    Group {
                        switch phase {
                        case .generating:
                            ProgressView("Generating \(configuration.scenario.rawValue)")
                                .tint(.white)
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("tap.video.fixture.generating")
                        case .ready(let artifact):
                            VStack(spacing: 18) {
                                Label("Fixture ready", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .accessibilityIdentifier("tap.video.fixture.ready")

                                Text(artifact.scenario.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)

                                Button("Open fixture") {
                                    readinessDelayGate = .fromLaunchEnvironment()
                                    presentedArtifact = artifact
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("tap.video.fixture.open")
                            }
                        case .failed(let message):
                            ContentUnavailableView(
                                "Fixture generation failed",
                                systemImage: "video.slash",
                                description: Text(message)
                            )
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("tap.video.fixture.failed")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                    .navigationDestination(isPresented: isArtifactPresented) {
                        if let presentedArtifact {
                            TAPVideoDepthPlaybackView(
                                source: .fixtureFile(
                                    presentedArtifact.fileURL,
                                    automaticSeekScheduleSeconds: configuration.seekScheduleSeconds
                                        ?? presentedArtifact.specification.automaticSeekSeconds.map { [$0] }
                                        ?? [],
                                    autoPlay: configuration.autoPlay
                                ),
                                registrationAdapter: TAPVideoPlaybackFixtureRegistrationAdapter(
                                    readinessDelayGate: readinessDelayGate
                                )
                            )
                            .onDisappear {
                                readinessDelayGate.cancel()
                            }
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(
            configuration.usesAccessibilityDynamicType ? .accessibility3 : .large
        )
        .task(id: configuration.scenario) {
            // Missing originals exercise production pending confirmation without
            // creating a capture record, accessing Photos, or running a worker.
            guard !configuration.showsGallery,
                  pendingDeleteKind != "photo", pendingDeleteKind != "video" else { return }
            phase = .generating
            do {
                phase = .ready(
                    try await TAPVideoPlaybackFixtureGenerator.generate(
                        scenario: configuration.scenario
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                phase = .failed("\((error as NSError).domain)(\((error as NSError).code))")
            }
        }
    }

    private var isArtifactPresented: Binding<Bool> {
        Binding(
            get: { presentedArtifact != nil },
            set: { isPresented in
                if !isPresented {
                    presentedArtifact = nil
                }
            }
        )
    }

    private enum Phase {
        case generating
        case ready(TAPVideoPlaybackFixtureArtifact)
        case failed(String)
    }
}

/// Synthetic catalog and image bytes exercise the production grid, pager and
/// navigation stack without opening Photos, camera, or backend services.
@MainActor
private struct TAPGalleryFixtureView: View {
    @StateObject private var routeStore = CameraRouteStore(contextStore: CameraRouteFileContextStore(
        directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("TAPGalleryFixture")
    ))
    @State private var libraryStore = LibraryMediaStore(itemProvider: DepthAlbumItemProvider(
        pendingRecordsLoader: { [] },
        exportedRecordsLoader: { [] },
        photoCatalogLoader: { _ in
            DepthAlbumPhotoCatalogSnapshot(albumAssets: (0..<160).map { index in
                DepthAlbumPhotoAsset(localIdentifier: "fixture-\(index)",
                                    creationDate: Date(timeIntervalSince1970: Double(10_000 - index)),
                                    isVideo: index == 1)
            })
        }
    ))
    private let fetcher = TAPGalleryFixtureMediaFetcher()

    var body: some View {
        NavigationStack {
            DepthAlbumPickerView(
                routeStore: routeStore,
                libraryStore: libraryStore,
                mediaFetcher: fetcher,
                photoLoader: DepthAnalysisProgressivePhotoLoader(
                    mediaFetcher: fetcher,
                    inputLoader: { source, _ in try await TAPGalleryFixtureMediaFetcher.analysisInput(for: source) }
                ),
                itemAccessibilityIdentifier: { "tap.gallery.item.\($0.id)" }
            )
        }
        .overlay(alignment: .bottomTrailing) {
            Text(routeStore.albumState.selectedItemID ?? "Gallery ready")
                .font(.caption2).allowsHitTesting(false)
                .accessibilityIdentifier("tap.gallery.selection")
        }
        .task { routeStore.presentDepthAlbum() }
    }
}

nonisolated private struct TAPGalleryFixtureMediaFetcher: LibraryMediaFetching {
    func mediaKind(for request: LibraryMediaAssetRequest) async throws -> LibraryMediaKind {
        request.assetLocalIdentifier == "fixture-1" ? .tapVideo : .photo
    }

    func posterPhase(for request: LibraryMediaPosterRequest, allowsNetworkAccess: Bool,
                     progress: @escaping @Sendable (Double?) -> Void) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> {
        .ready(MediaPoster(cacheKey: request.cacheKey, image: await Self.image(request.assetLocalIdentifier, width: 80)))
    }

    func previewPhase(for request: LibraryMediaAssetRequest, pixelLength: Int, allowsNetworkAccess: Bool,
                      progress: @escaping @Sendable (Double?) -> Void) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> {
        .ready(MediaPoster(cacheKey: request.assetLocalIdentifier, image: await Self.image(request.assetLocalIdentifier, width: 80)))
    }

    func photoDisplayImage(for request: LibraryMediaAssetRequest, pixelLength: Int,
                           progress: @escaping @Sendable (Double?) -> Void) async throws -> UIImage {
        await Self.image(request.assetLocalIdentifier, width: CGFloat(max(pixelLength, 1)))
    }

    func videoOriginalFile(for request: LibraryMediaAssetRequest,
                           progress: @escaping @Sendable (Double?) -> Void) async throws -> LibraryManagedTemporaryFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .rotation0, outputDirectoryURL: directory)
        return LibraryManagedTemporaryFile(fileURL: artifact.fileURL, directoryURL: directory)
    }
    func livePhoto(for request: LibraryMediaAssetRequest, targetSize: CGSize,
                   progress: @escaping @Sendable (Double?) -> Void) async throws -> LibraryLivePhoto { throw MediaFetchFailure.decode }

    @MainActor static func analysisInput(for source: DepthAnalysisSource) throws -> TAPDepthAnalysisInput {
        guard case .photosAsset(let identifier) = source,
              let image = Self.image(identifier, width: 960).cgImage else {
            throw MediaFetchFailure.decode
        }
        let depthMap = TAPMetricDepthMap(
            width: 64, height: 48,
            samples: (0..<(64 * 48)).map { 1 + Float($0 % 64) / 320 },
            calibration: TAPDepthManifest.CameraCalibration(
                intrinsicMatrixReferenceWidth: 64, intrinsicMatrixReferenceHeight: 48,
                pixelSizeMillimeters: 0.001,
                lensDistortionLookupTablePresent: false, inverseLensDistortionLookupTablePresent: false,
                lensDistortionCenterX: 32, lensDistortionCenterY: 24,
                intrinsicMatrix: [100, 0, 0, 0, 100, 0, 32, 24, 1],
                extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
            )
        )
        return TAPDepthAnalysisInput(
            manifest: nil, image: image, imageOrientation: .up, depthMap: depthMap,
            depthAccuracy: "unknown", depthQuality: "unknown",
            heatmap: try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        )
    }

    @MainActor private static func image(_ identifier: String, width: CGFloat) -> UIImage {
        let index = Int(identifier.split(separator: "-").last ?? "0") ?? 0
        let size = CGSize(width: width, height: width * 0.75)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(hue: CGFloat(index % 12) / 12, saturation: 0.7, brightness: 0.65, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            String(index).draw(at: CGPoint(x: width * 0.1, y: width * 0.1), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: width * 0.35), .foregroundColor: UIColor.white
            ])
        }
    }
}

/// DEBUG-only timing seam for UI tests that need to observe Viewer chrome
/// before AVPlayer construction completes. Production playback never reads
/// this environment value.
nonisolated private struct TAPVideoPlaybackFixtureRegistrationAdapter:
    TAPVideoDepthRegistrationAdapting
{
    let readinessDelayGate: TAPVideoPlaybackFixtureReadinessDelayGate

    func registrationDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoDepthRegistrationDescriptor? {
        readinessDelayGate.waitUntilReadyOrCancelled()
        return TAPVideoFixtureIdentityRegistrationAdapter()
            .registrationDescriptor(for: manifest)
    }
}

/// The delay defaults to zero, is available only in DEBUG, and polls a
/// cancellation gate in short slices so leaving the fixture never strands its
/// detached metadata task in a long sleep.
nonisolated private final class TAPVideoPlaybackFixtureReadinessDelayGate:
    @unchecked Sendable
{
    private static let delayEnvironmentKey =
        "TAPCAM_UI_TEST_VIDEO_FIXTURE_PLAYER_READINESS_DELAY_MS"

    private let delaySeconds: TimeInterval
    private let lock = NSLock()
    private var isCancelled = false

    init(delayMilliseconds: Double = 0) {
        delaySeconds = max(0, delayMilliseconds) / 1_000
    }

    static func fromLaunchEnvironment() -> TAPVideoPlaybackFixtureReadinessDelayGate {
        let rawDelay = ProcessInfo.processInfo.environment[delayEnvironmentKey]
        return TAPVideoPlaybackFixtureReadinessDelayGate(
            delayMilliseconds: rawDelay.flatMap(Double.init) ?? 0
        )
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func waitUntilReadyOrCancelled() {
        guard delaySeconds > 0 else {
            return
        }
        let deadline = Date().addingTimeInterval(delaySeconds)
        while Date() < deadline {
            lock.lock()
            let shouldStop = isCancelled
            lock.unlock()
            if shouldStop {
                return
            }
            Thread.sleep(
                forTimeInterval: max(0, min(0.01, deadline.timeIntervalSinceNow))
            )
        }
    }
}
#endif
