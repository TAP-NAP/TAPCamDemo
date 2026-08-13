//
//  LibraryMediaModels.swift
//  TAPCamDemo
//

import Foundation

/// Stable, private identity shared by every TAP Library surface.
///
/// App-owned captures retain the same identity while moving from the pending
/// bundle to Photos. Photos-only items use their Photos local identifier.
nonisolated enum LibraryMediaID: Hashable, Sendable {
    case tapCapture(String)
    case photosAsset(String)

    /// In-memory UI/route identity. Do not use this value as a public log field
    /// or an unhashed cache filename.
    var storageValue: String {
        switch self {
        case .tapCapture(let captureID):
            "capture:\(captureID)"
        case .photosAsset(let assetID):
            "photos:\(assetID)"
        }
    }
}

nonisolated enum LibraryMediaKind: String, Equatable, Hashable, Sendable {
    case photo
    case livePhoto
    case tapVideo
}

nonisolated enum LibraryMediaSource: Equatable, Hashable, Sendable {
    case pending(captureID: String)
    case ownedPhotosAsset(captureID: String, assetID: String)
    case photosOnly(assetID: String)
}

/// Opaque revisions keep content and poster invalidation independent.
nonisolated struct LibraryMediaVersion: Equatable, Hashable, Sendable {
    let contentRevision: String
    let posterRevision: String
}

nonisolated struct LibraryMediaSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: LibraryMediaID
    let capturedAt: Date
    let kind: LibraryMediaKind
    let source: LibraryMediaSource
    let version: LibraryMediaVersion
}

nonisolated struct LibraryMediaSnapshot: Equatable, Sendable {
    let revision: UInt64
    let items: [LibraryMediaSummary]

    static let empty = LibraryMediaSnapshot(revision: 0, items: [])

    var latest: LibraryMediaSummary? {
        items.first
    }
}

/// A Sendable encoded poster value. Presentation code must route these bytes
/// through `DepthAlbumThumbnailDecoder`; keeping UIKit conversion out of this
/// value prevents an innocent computed-property read from decoding on the
/// MainActor or inside a SwiftUI body.
nonisolated struct MediaPoster: Equatable, Sendable {
    let cacheKey: String
    let jpegData: Data
}

nonisolated enum MediaFetchFailure: Error, Equatable, Sendable {
    case permission
    case offline
    case assetRemoved
    case download
    case decode

    var isRetryable: Bool {
        switch self {
        case .offline, .download:
            true
        case .permission, .assetRemoved, .decode:
            false
        }
    }
}

/// One fetch state shared by the camera cover, grid and current-item viewers.
/// A same-item preview remains available while the original is downloaded.
nonisolated enum MediaFetchPhase<Preview: Sendable, Value: Sendable>: Sendable {
    case idle(Preview?)
    case resolving(Preview?)
    case localPreview(Preview)
    case cloudOnly(Preview?)
    case downloadingFromICloud(Preview?, progress: Double?)
    case ready(Value)
    case failed(Preview?, reason: MediaFetchFailure, retryable: Bool)
}

extension MediaFetchPhase: Equatable where Preview: Equatable, Value: Equatable {}

nonisolated extension MediaFetchPhase {
    /// Keeps an already-rendered preview when a network upgrade fails. A
    /// failure from a second request often has no preview of its own, but that
    /// must not erase the local derivative supplied by the preceding probe.
    func preservingFailurePreview(_ fallback: Preview?) -> Self {
        guard let fallback else {
            return self
        }
        switch self {
        case .failed(let preview, let reason, let retryable):
            return .failed(
                preview ?? fallback,
                reason: reason,
                retryable: retryable
            )
        default:
            return self
        }
    }
}

nonisolated extension MediaFetchPhase where Preview == Value {
    var previewOrReadyValue: Value? {
        switch self {
        case .idle(let preview),
             .resolving(let preview),
             .cloudOnly(let preview),
             .downloadingFromICloud(let preview, _),
             .failed(let preview, _, _):
            preview
        case .localPreview(let preview), .ready(let preview):
            preview
        }
    }
}

nonisolated enum MediaFetchPurpose: String, Equatable, Hashable, Sendable {
    case gridPoster
    case recentCover
    case photoDisplay
    case photoOriginal
    case livePhotoPlayback
    case videoOriginal
}

nonisolated enum LibraryMediaFetchPolicy {
    static func allowsNetworkAccess(
        purpose: MediaFetchPurpose,
        item: LibraryMediaSummary,
        currentItemID: LibraryMediaID?
    ) -> Bool {
        guard item.id == currentItemID else {
            return false
        }
        switch purpose {
        case .gridPoster:
            return false
        case .recentCover:
            if case .photosOnly = item.source {
                return true
            }
            return false
        case .photoDisplay, .photoOriginal, .livePhotoPlayback, .videoOriginal:
            return true
        }
    }
}

nonisolated struct MediaFetchRequestKey: Equatable, Hashable, Sendable {
    let itemID: LibraryMediaID
    let generation: UInt64
    let purpose: MediaFetchPurpose
}

nonisolated struct IdentifiedMediaFetchState<Preview: Sendable, Value: Sendable>: Sendable {
    let request: MediaFetchRequestKey
    var phase: MediaFetchPhase<Preview, Value>
}

extension IdentifiedMediaFetchState: Equatable where Preview: Equatable, Value: Equatable {}

/// Identity-bearing camera presentation. A previous poster may remain visible
/// while a newer one is resolving, but an empty or failed result never silently
/// reuses the old item's image.
nonisolated enum RecentLibraryPresentation: Equatable, Sendable {
    case unresolved
    case empty
    case resolving(itemID: LibraryMediaID, kind: LibraryMediaKind)
    case loading(
        itemID: LibraryMediaID,
        kind: LibraryMediaKind,
        preview: MediaPoster?,
        progress: Double?
    )
    case ready(itemID: LibraryMediaID, kind: LibraryMediaKind, poster: MediaPoster)
    case failed(
        itemID: LibraryMediaID,
        kind: LibraryMediaKind,
        preview: MediaPoster?,
        retryable: Bool
    )

    var itemID: LibraryMediaID? {
        switch self {
        case .unresolved, .empty:
            nil
        case .resolving(let itemID, _):
            itemID
        case .loading(let itemID, _, _, _),
             .ready(let itemID, _, _),
             .failed(let itemID, _, _, _):
            itemID
        }
    }

    var kind: LibraryMediaKind? {
        switch self {
        case .unresolved, .empty:
            nil
        case .resolving(_, let kind):
            kind
        case .loading(_, let kind, _, _),
             .ready(_, let kind, _),
             .failed(_, let kind, _, _):
            kind
        }
    }

    var poster: MediaPoster? {
        switch self {
        case .unresolved, .empty, .resolving:
            nil
        case .loading(_, _, let preview, _):
            preview
        case .ready(_, _, let poster):
            poster
        case .failed(_, _, let preview, _):
            preview
        }
    }

    var isLoadingFromICloud: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var showsPlaceholderSymbol: Bool {
        switch self {
        case .unresolved, .empty, .resolving:
            true
        case .loading(_, _, let preview, _),
             .failed(_, _, let preview, _):
            preview == nil
        case .ready:
            false
        }
    }
}
