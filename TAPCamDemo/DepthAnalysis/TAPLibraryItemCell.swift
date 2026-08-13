//
//  TAPLibraryItemCell.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

/// Square Library grid cell that owns poster loading and media-state badges.
struct TAPLibraryItemCell: View {
    let item: TAPLibraryItem
    let thumbnailPixelLength: Int
    let mediaFetcher: any LibraryMediaFetching
    @State private var fetchPhase: MediaFetchPhase<MediaPoster, MediaPoster> = .idle(nil)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color(uiColor: .secondarySystemBackground))

                if let posterImage = displayedPosterImage {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    Image(systemName: item.isVideo ? "video" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                thumbnailBadges
            }
            .frame(width: geometry.size.width, height: geometry.size.width)
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(isCloudOnly ? LibraryMediaCopy.storedInICloud : "")
    }

    @ViewBuilder
    private var thumbnailBadges: some View {
        if item.isLivePhoto {
            VStack {
                HStack {
                    Spacer()
                    DepthAnalysisLivePhotoBadge(size: .thumbnail)
                }
                Spacer()
            }
            .padding(5)
            .allowsHitTesting(false)
        }

        if item.isVideo {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 18)
                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Spacer()
            }
            .padding(5)
            .allowsHitTesting(false)
        }

        if isCloudOnly {
            VStack {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 18)
                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .accessibilityLabel(LibraryMediaCopy.storedInICloud)
                    Spacer()
                }
                Spacer()
            }
            .padding(5)
            .allowsHitTesting(false)
        } else if isResolving {
            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
                .allowsHitTesting(false)
        } else if hasFailure {
            VStack {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 18)
                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Spacer()
                }
                Spacer()
            }
            .padding(5)
            .allowsHitTesting(false)
        }

        if let badge = item.pendingBadge {
            VStack {
                Spacer()
                HStack {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.yellow, in: Capsule())
                    Spacer()
                }
            }
            .padding(5)
            .allowsHitTesting(false)
        }
    }

    private var thumbnailTaskID: String {
        // Stable media identity deliberately survives pending -> exported. The
        // revision-bearing cache key still changes when the poster/source does.
        item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
    }

    private func loadThumbnail() async {
        let cacheKey = item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
        guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
            return
        }
        fetchPhase = .resolving(nil)
        if let cachedPoster = DepthAlbumThumbnailMemoryCache.shared.poster(for: cacheKey) {
            guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
                return
            }
            fetchPhase = .ready(cachedPoster)
            return
        }

        do {
            var phase = try await thumbnailPhase(cacheKey: cacheKey)
            guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
                return
            }
            if let poster = phase.previewOrReadyValue {
                if let decodedThumbnail = await DepthAlbumThumbnailDecoder.shared
                    .decodedThumbnail(for: poster) {
                    guard !Task.isCancelled,
                          thumbnailTaskID == cacheKey,
                          decodedThumbnail.poster.cacheKey == cacheKey else {
                        return
                    }
                } else if phase.requiresRenderablePoster {
                    phase = .failed(nil, reason: .decode, retryable: false)
                }
            }
            guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
                return
            }
            fetchPhase = phase
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
                return
            }
            fetchPhase = .failed(nil, reason: .decode, retryable: false)
        }
    }

    private func thumbnailPhase(
        cacheKey: String
    ) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> {
        switch item.source {
        case .photos:
            guard let request = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: thumbnailPixelLength
            ) else {
                return .failed(nil, reason: .assetRemoved, retryable: false)
            }
            let phase = try await mediaFetcher.posterPhase(
                for: request,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
            return posterPhase(from: phase, cacheKey: cacheKey)
        case .ownedPhoto(let record, _):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID) {
                return .ready(MediaPoster(cacheKey: cacheKey, jpegData: data))
            }
            guard let request = LibraryMediaPosterRequest(
                summary: item.summary,
                pixelLength: thumbnailPixelLength
            ) else {
                return .failed(nil, reason: .assetRemoved, retryable: false)
            }
            let phase = try await mediaFetcher.posterPhase(
                for: request,
                allowsNetworkAccess: false,
                progress: { _ in }
            )
            return posterPhase(from: phase, cacheKey: cacheKey)
        case .pending(let record):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(captureID: record.captureID) {
                return .ready(MediaPoster(cacheKey: cacheKey, jpegData: data))
            }
            guard item.isVideo,
                  let videoURL = try? await TAPPendingCaptureStore.shared.bestAvailableVideoURL(
                    captureID: record.captureID
                  ),
                  let data = await DepthAlbumThumbnailLoader.shared.videoData(
                    for: videoURL,
                    cacheKey: cacheKey,
                    pixelLength: thumbnailPixelLength
                  ) else {
                return .failed(nil, reason: .decode, retryable: false)
            }
            return .ready(MediaPoster(cacheKey: cacheKey, jpegData: data))
        }
    }

    private func posterPhase(
        from phase: MediaFetchPhase<Data, Data>,
        cacheKey: String
    ) -> MediaFetchPhase<MediaPoster, MediaPoster> {
        switch phase {
        case .idle(let preview):
            return .idle(preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) })
        case .resolving(let preview):
            return .resolving(preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) })
        case .localPreview(let preview):
            return .localPreview(MediaPoster(cacheKey: cacheKey, jpegData: preview))
        case .cloudOnly(let preview):
            return .cloudOnly(preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) })
        case .downloadingFromICloud(let preview, let progress):
            return .downloadingFromICloud(
                preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) },
                progress: progress
            )
        case .ready(let value):
            return .ready(MediaPoster(cacheKey: cacheKey, jpegData: value))
        case .failed(let preview, let reason, let retryable):
            return .failed(
                preview.map { MediaPoster(cacheKey: cacheKey, jpegData: $0) },
                reason: reason,
                retryable: retryable
            )
        }
    }

    private var displayedPoster: MediaPoster? {
        switch fetchPhase {
        case .idle(let preview),
             .resolving(let preview),
             .cloudOnly(let preview),
             .downloadingFromICloud(let preview, _),
             .failed(let preview, _, _):
            return preview
        case .localPreview(let preview), .ready(let preview):
            return preview
        }
    }

    private var displayedPosterImage: UIImage? {
        guard let poster = displayedPoster else {
            return nil
        }
        return DepthAlbumThumbnailMemoryCache.shared.image(for: poster.cacheKey)
    }

    private var isCloudOnly: Bool {
        if case .cloudOnly = fetchPhase {
            return true
        }
        return false
    }

    private var isResolving: Bool {
        if case .resolving = fetchPhase {
            return true
        }
        return false
    }

    private var hasFailure: Bool {
        if case .failed = fetchPhase {
            return true
        }
        return false
    }
}

private extension MediaFetchPhase where Preview == MediaPoster, Value == MediaPoster {
    var requiresRenderablePoster: Bool {
        switch self {
        case .localPreview, .ready:
            true
        case .idle, .resolving, .cloudOnly, .downloadingFromICloud, .failed:
            false
        }
    }
}
