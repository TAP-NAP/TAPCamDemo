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
    @State private var loadGeneration: UInt64 = 0

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
        .onDisappear {
            loadGeneration &+= 1
            fetchPhase = .idle(nil)
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
        let generation = loadGeneration
        let cacheKey = item.thumbnailCacheKey(pixelLength: thumbnailPixelLength)
        guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
            return
        }
        let preview = fetchPhase.previewOrReadyValue.flatMap {
            $0.cacheKey == cacheKey ? $0 : nil
        }
        if preview != nil {
            switch fetchPhase {
            case .ready, .localPreview: return
            default: break
            }
        }
        fetchPhase = .resolving(preview)
        if let cachedPoster = DepthAlbumThumbnailMemoryCache.shared.poster(for: cacheKey) {
            guard !Task.isCancelled, thumbnailTaskID == cacheKey else {
                return
            }
            fetchPhase = .ready(cachedPoster)
            return
        }

        do {
            let phase = try await thumbnailPhase(cacheKey: cacheKey)
            guard !Task.isCancelled, loadGeneration == generation,
                  thumbnailTaskID == cacheKey else { return }
            fetchPhase = phase
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadGeneration == generation,
                  thumbnailTaskID == cacheKey else {
                return
            }
            fetchPhase = .failed(nil, reason: .decode, retryable: false)
        }
    }

    private func thumbnailPhase(
        cacheKey: String
    ) async throws -> MediaFetchPhase<MediaPoster, MediaPoster> {
        switch item.source {
        case .pending(let record), .ownedPhoto(let record, _):
            if let data = try? await TAPPendingCaptureStore.shared.thumbnailData(
                captureID: record.captureID
            ) {
                return await decodedPosterPhase(data: data, cacheKey: cacheKey)
            }
        case .photos:
            break
        }
        if case .pending(let record) = item.source {
            guard item.isVideo,
                  let videoURL = try? await TAPPendingCaptureStore.shared.bestAvailableVideoURL(
                    captureID: record.captureID
                  ),
                  let data = await DepthAlbumThumbnailLoader.shared.videoData(
                    for: videoURL, cacheKey: cacheKey, pixelLength: thumbnailPixelLength
                  ) else {
                return .failed(nil, reason: .decode, retryable: false)
            }
            return await decodedPosterPhase(data: data, cacheKey: cacheKey)
        }
        guard let request = LibraryMediaPosterRequest(
            summary: item.summary, pixelLength: thumbnailPixelLength
        ) else {
            return .failed(nil, reason: .assetRemoved, retryable: false)
        }
        return try await mediaFetcher.posterPhase(
            for: request, allowsNetworkAccess: false, progress: { _ in }
        )
    }

    private func decodedPosterPhase(data: Data, cacheKey: String) async -> MediaFetchPhase<MediaPoster, MediaPoster> {
        guard let poster = await DepthAlbumThumbnailDecoder.shared.decodedThumbnail(
            data: data, cacheKey: cacheKey
        ) else {
            return .failed(nil, reason: .decode, retryable: false)
        }
        return .ready(poster)
    }

    private var displayedPosterImage: UIImage? {
        fetchPhase.previewOrReadyValue?.image
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
