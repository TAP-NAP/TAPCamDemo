//
//  TAPVideoShareArtifactBuilder.swift
//  TAPCamDemo
//

import Foundation

/// Frozen input for on-demand original-video sharing. When a Viewer resource
/// lease is supplied, it remains the sole media source for this attempt; the
/// builder never re-fetches the same file from Photos or the pending queue.
nonisolated struct TAPVideoShareResourceRequest: Sendable {
    let captureID: String?
    let assetLocalIdentifier: String?
    let prefersPhotoLibraryResource: Bool
    let hasSignatureEvidence: Bool
    let originalResourceLease: TAPVideoOriginalResourceLease?
    let directShareVerifiabilityWarning: String?

    init(
        record: TAPPendingCaptureRecord,
        originalResourceLease: TAPVideoOriginalResourceLease? = nil,
        directShareVerifiabilityWarning: String? = nil
    ) {
        captureID = record.captureID
        assetLocalIdentifier = record.assetLocalIdentifier
        prefersPhotoLibraryResource = record.status == .exported
            && record.assetLocalIdentifier != nil
        hasSignatureEvidence = record.artifactKind == .tapVideo
            && record.videoArtifactState == .signed
        self.originalResourceLease = originalResourceLease
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
    }

    init(
        captureID: String?,
        assetLocalIdentifier: String?,
        prefersPhotoLibraryResource: Bool = false,
        hasSignatureEvidence: Bool = false,
        originalResourceLease: TAPVideoOriginalResourceLease? = nil,
        directShareVerifiabilityWarning: String? = nil
    ) {
        self.captureID = captureID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.prefersPhotoLibraryResource = prefersPhotoLibraryResource
        self.hasSignatureEvidence = hasSignatureEvidence
        self.originalResourceLease = originalResourceLease
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
    }

    /// Preferred constructor after the Viewer has resolved and locally checked
    /// one complete original video.
    init(
        originalResourceLease: TAPVideoOriginalResourceLease,
        hasSignatureEvidence: Bool,
        directShareVerifiabilityWarning: String? = nil
    ) {
        captureID = nil
        assetLocalIdentifier = nil
        prefersPhotoLibraryResource = false
        self.hasSignatureEvidence = hasSignatureEvidence
        self.originalResourceLease = originalResourceLease
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
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
        let progressCoalescer = TAPShareProgressCoalescer(delivery: progress)
        let coalescedProgress: ProgressHandler = { value in
            progressCoalescer.submit(value)
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
            coalescedProgress(0)
            let sourceURL = try await loadVideoResource(
                request: request,
                requiresSignedVideo: requiresSignedVideo,
                destinationDirectoryURL: resourcesDirectoryURL,
                progress: { value in
                    Self.mapProgress(
                        value,
                        weight: 0.98,
                        handler: coalescedProgress
                    )
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
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: resourcesDirectoryURL,
                scope: "videoResources"
            )
            try Task.checkCancellation()
            coalescedProgress(1)
            let artifact = TAPNAPShareArtifact(
                id: UUID(),
                kind: .video,
                fileURL: outputURL,
                temporaryDirectoryURL: outputDirectoryURL,
                warnings: Self.verifiabilityWarning(
                    request.directShareVerifiabilityWarning
                )
            )
            await progressCoalescer.finish()
            return artifact
        } catch {
            progressCoalescer.cancel()
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: outputDirectoryURL,
                scope: "videoFailure"
            )
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
        if let originalResourceLease = request.originalResourceLease {
            try Task.checkCancellation()
            let fileExtension = originalResourceLease.fileURL.pathExtension.isEmpty
                ? "mp4"
                : originalResourceLease.fileURL.pathExtension.lowercased()
            let copiedURL = destinationDirectoryURL
                .appendingPathComponent("viewer-original-video")
                .appendingPathExtension(fileExtension)
            try TAPShareResourceFileCopier.copy(
                from: originalResourceLease.fileURL,
                to: copiedURL,
                progress: progress
            )
            try Task.checkCancellation()
            return copiedURL
        }

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

    private static func verifiabilityWarning(_ warning: String?) -> [String] {
        guard let warning = warning?.trimmingCharacters(in: .whitespacesAndNewlines),
              !warning.isEmpty else {
            return []
        }
        return [warning]
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
