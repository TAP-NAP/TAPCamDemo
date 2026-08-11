//
//  TAPVideoShareArtifactBuilder.swift
//  TAPCamDemo
//

import Foundation

/// Scalar input for on-demand original-video sharing. Durable signature state
/// is carried from the local record; the builder never parses or validates the
/// MP4 while preparing a transport copy.
nonisolated struct TAPVideoShareResourceRequest: Sendable {
    let captureID: String?
    let assetLocalIdentifier: String?
    let prefersPhotoLibraryResource: Bool
    let hasSignatureEvidence: Bool

    init(record: TAPPendingCaptureRecord) {
        captureID = record.captureID
        assetLocalIdentifier = record.assetLocalIdentifier
        prefersPhotoLibraryResource = record.status == .exported
            && record.assetLocalIdentifier != nil
        hasSignatureEvidence = record.artifactKind == .tapVideo
            && record.videoArtifactState == .signed
    }

    init(
        captureID: String?,
        assetLocalIdentifier: String?,
        prefersPhotoLibraryResource: Bool = false,
        hasSignatureEvidence: Bool = false
    ) {
        self.captureID = captureID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.prefersPhotoLibraryResource = prefersPhotoLibraryResource
        self.hasSignatureEvidence = hasSignatureEvidence
    }
}

/// Makes a process-independent copy of the original video only after the user
/// selects Share Video. Outputs are session-temporary and are never cached or
/// pre-generated.
nonisolated struct TAPVideoShareArtifactBuilder: Sendable {
    typealias ProgressHandler = @Sendable (Double?) -> Void
    typealias PendingSnapshotter = @Sendable (
        _ captureID: String,
        _ expectedAssetLocalIdentifier: String?,
        _ destinationDirectoryURL: URL,
        _ requiresSignedVideo: Bool,
        _ progress: @escaping ProgressHandler
    ) async throws -> TAPPendingVideoShareResourceSnapshot
    typealias PhotoLibraryResourceLoader = @Sendable (
        _ assetLocalIdentifier: String,
        _ outputDirectoryURL: URL,
        _ progress: @escaping ProgressHandler
    ) async throws -> PhotoLibraryWriter.OriginalVideoShareResource
    typealias TemporaryDirectoryProvider = @Sendable () throws -> URL

    private static let outputBasename = "TAPNAP-Video"

    private let pendingSnapshotter: PendingSnapshotter
    private let photoLibraryResourceLoader: PhotoLibraryResourceLoader
    private let temporaryDirectoryProvider: TemporaryDirectoryProvider

    init(
        pendingSnapshotter: @escaping PendingSnapshotter = { captureID, assetID, destinationURL, requiresSignedVideo, progress in
            try TAPPendingCaptureStore.shared.snapshotVideoShareResource(
                captureID: captureID,
                expectedAssetLocalIdentifier: assetID,
                to: destinationURL,
                requiresSignedVideo: requiresSignedVideo,
                progressHandler: progress
            )
        },
        photoLibraryResourceLoader: @escaping PhotoLibraryResourceLoader = { assetID, outputURL, progress in
            try await PhotoLibraryWriter.originalVideoShareResource(
                localIdentifier: assetID,
                outputDirectoryURL: outputURL,
                progressHandler: progress
            )
        },
        temporaryDirectoryProvider: @escaping TemporaryDirectoryProvider = Self.defaultTemporaryDirectory
    ) {
        self.pendingSnapshotter = pendingSnapshotter
        self.photoLibraryResourceLoader = photoLibraryResourceLoader
        self.temporaryDirectoryProvider = temporaryDirectoryProvider
    }

    @concurrent
    func prepareVideo(
        request: TAPVideoShareResourceRequest,
        requiresSignedVideo: Bool,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> TAPNAPShareArtifact {
        if requiresSignedVideo, !request.hasSignatureEvidence {
            throw TAPNAPShareArtifactError.packageRequiresSignatureEvidence
        }

        let outputDirectoryURL = try temporaryDirectoryProvider()
        let resourcesDirectoryURL = outputDirectoryURL.appendingPathComponent(
            "resources",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: outputDirectoryURL,
                withIntermediateDirectories: true
            )
            progress(0)
            let sourceURL = try await loadVideoResource(
                request: request,
                requiresSignedVideo: requiresSignedVideo,
                destinationDirectoryURL: resourcesDirectoryURL,
                progress: { value in
                    Self.mapProgress(value, weight: 0.98, handler: progress)
                }
            )
            try Task.checkCancellation()
            _ = try Self.checkedResourceSize(sourceURL)

            let fileExtension = sourceURL.pathExtension.isEmpty
                ? "mp4"
                : sourceURL.pathExtension.lowercased()
            let outputURL = outputDirectoryURL
                .appendingPathComponent(Self.outputBasename)
                .appendingPathExtension(fileExtension)
            try FileManager.default.moveItem(at: sourceURL, to: outputURL)
            try? FileManager.default.removeItem(at: resourcesDirectoryURL)
            try Task.checkCancellation()
            progress(1)
            return TAPNAPShareArtifact(
                id: UUID(),
                kind: .video,
                fileURL: outputURL,
                temporaryDirectoryURL: outputDirectoryURL,
                warnings: []
            )
        } catch {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
            if error is CancellationError {
                throw error
            }
            throw TAPNAPShareArtifactError.shareResourceUnavailable
        }
    }

    private func loadVideoResource(
        request: TAPVideoShareResourceRequest,
        requiresSignedVideo: Bool,
        destinationDirectoryURL: URL,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        if !request.prefersPhotoLibraryResource, let captureID = request.captureID {
            do {
                let snapshot = try await pendingSnapshotter(
                    captureID,
                    request.assetLocalIdentifier,
                    destinationDirectoryURL,
                    requiresSignedVideo,
                    progress
                )
                progress(1)
                return snapshot.videoURL
            } catch TAPPendingVideoShareSnapshotError.sourceUnavailable {
                guard request.assetLocalIdentifier != nil else {
                    throw TAPNAPShareArtifactError.shareResourceUnavailable
                }
            }
        }

        guard let assetLocalIdentifier = request.assetLocalIdentifier else {
            throw TAPNAPShareArtifactError.shareResourceUnavailable
        }
        let resource = try await photoLibraryResourceLoader(
            assetLocalIdentifier,
            destinationDirectoryURL,
            progress
        )
        return resource.videoURL
    }

    private static func checkedResourceSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0 else {
            throw TAPNAPShareArtifactError.shareResourceUnavailable
        }
        return Int64(size)
    }

    private static func mapProgress(
        _ value: Double?,
        weight: Double,
        handler: ProgressHandler
    ) {
        guard let value, value.isFinite else {
            handler(nil)
            return
        }
        handler(min(max(value, 0), 1) * weight)
    }

    private static func defaultTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TAPVideoShare-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
