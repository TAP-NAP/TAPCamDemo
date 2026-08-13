//
//  TAPNAPShareArtifactBuilder.swift
//  TAPCamDemo
//

import Foundation
import OSLog
import UniformTypeIdentifiers
import ZIPFoundation

nonisolated extension UTType {
    static let tapnapCapturePackage = UTType(
        exportedAs: "net.tapnap.capture-package",
        conformingTo: .zip
    )
}

nonisolated extension CapturePhotoFileContainer {
    var tapnapFileExtension: String {
        switch self {
        case .heic:
            "heic"
        case .jpeg:
            "jpg"
        }
    }
}

/// Frozen input captured before Share payload preparation begins.
///
/// When `originalResourceLease` is present it is the exact Viewer-ready
/// resource set evaluated by the caller's local-integrity decision. The
/// builder retains that lease for the whole request and must not re-fetch the
/// same media from Photos or the Pending Capture Queue.
nonisolated struct TAPNAPShareResourceRequest: Sendable {
    let captureID: String?
    let assetLocalIdentifier: String?
    let fileContainer: CapturePhotoFileContainer?
    let expectsPairedVideo: Bool
    let hasSignatureEvidence: Bool
    let prefersPhotoLibraryResources: Bool
    let originalResourceLease: TAPPhotoOriginalResourceLease?
    let directShareVerifiabilityWarning: String?

    init(
        record: TAPPendingCaptureRecord,
        expectsPairedVideo livePhotoHint: Bool = false,
        originalResourceLease: TAPPhotoOriginalResourceLease? = nil,
        directShareVerifiabilityWarning: String? = nil
    ) {
        captureID = record.captureID
        assetLocalIdentifier = record.assetLocalIdentifier
        fileContainer = record.photoFileContainer
        expectsPairedVideo = livePhotoHint || record.pairedVideoFilename != nil
        hasSignatureEvidence = record.artifactKind == .photoDepth
            && (record.signedPhotoFilename != nil || record.status.tapnapHasSignatureEvidence)
        prefersPhotoLibraryResources = record.status == .exported
            && record.assetLocalIdentifier != nil
        self.originalResourceLease = originalResourceLease?.retaining()
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
    }

    init(
        assetLocalIdentifier: String,
        originalResourceLease: TAPPhotoOriginalResourceLease? = nil,
        directShareVerifiabilityWarning: String? = nil
    ) {
        captureID = nil
        self.assetLocalIdentifier = assetLocalIdentifier
        fileContainer = nil
        expectsPairedVideo = false
        hasSignatureEvidence = false
        prefersPhotoLibraryResources = true
        self.originalResourceLease = originalResourceLease?.retaining()
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
    }

    init(
        captureID: String?,
        assetLocalIdentifier: String?,
        fileContainer: CapturePhotoFileContainer?,
        expectsPairedVideo: Bool,
        hasSignatureEvidence: Bool,
        prefersPhotoLibraryResources: Bool = false,
        originalResourceLease: TAPPhotoOriginalResourceLease? = nil,
        directShareVerifiabilityWarning: String? = nil
    ) {
        self.captureID = captureID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.fileContainer = fileContainer
        self.expectsPairedVideo = expectsPairedVideo
        self.hasSignatureEvidence = hasSignatureEvidence
        self.prefersPhotoLibraryResources = prefersPhotoLibraryResources
        self.originalResourceLease = originalResourceLease?.retaining()
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
    }

    /// Preferred constructor after the Viewer has resolved and locally checked
    /// one complete original-resource set.
    init(
        originalResourceLease: TAPPhotoOriginalResourceLease,
        hasSignatureEvidence: Bool,
        directShareVerifiabilityWarning: String? = nil
    ) {
        switch originalResourceLease.origin {
        case .photosAsset(let assetID):
            captureID = nil
            assetLocalIdentifier = assetID
            prefersPhotoLibraryResources = true
        case .pendingCapture(let pendingCaptureID, _):
            captureID = pendingCaptureID
            assetLocalIdentifier = nil
            prefersPhotoLibraryResources = false
        }
        fileContainer = originalResourceLease.fileContainerHint
        expectsPairedVideo = originalResourceLease.expectsPairedVideo
        self.hasSignatureEvidence = hasSignatureEvidence
        self.originalResourceLease = originalResourceLease.retaining()
        self.directShareVerifiabilityWarning = directShareVerifiabilityWarning
    }
}

nonisolated final class TAPNAPShareArtifact: Identifiable, @unchecked Sendable {
    typealias TemporaryDirectoryRemover = @Sendable (URL) throws -> Void

    enum Kind: String, Sendable {
        case tapnapPackage
        case image
        case video
    }

    let id: UUID
    let kind: Kind
    let fileURL: URL
    let temporaryDirectoryURL: URL
    let warnings: [String]
    private let temporaryDirectoryLease: TAPNAPShareTemporaryDirectoryLease

    init(
        id: UUID,
        kind: Kind,
        fileURL: URL,
        temporaryDirectoryURL: URL,
        warnings: [String],
        temporaryDirectoryRemover: @escaping TemporaryDirectoryRemover = {
            try FileManager.default.removeItem(at: $0)
        }
    ) {
        self.id = id
        self.kind = kind
        self.fileURL = fileURL
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.warnings = warnings
        temporaryDirectoryLease = TAPNAPShareTemporaryDirectoryLease(
            directoryURL: temporaryDirectoryURL,
            remover: temporaryDirectoryRemover
        )
    }

    func removeTemporaryDirectory() {
        temporaryDirectoryLease.remove()
    }
}

/// Shared by every value-copy of one artifact. Explicit cleanup remains the
/// normal path; deinit is the abnormal-presentation fallback that prevents a
/// temporary package from leaking if its SwiftUI owner disappears mid-handoff.
private nonisolated final class TAPNAPShareTemporaryDirectoryLease: @unchecked Sendable {
    private let directoryURL: URL
    private let remover: TAPNAPShareArtifact.TemporaryDirectoryRemover
    private let lock = NSLock()
    private var hasRemovedDirectory = false
    private var isRemovalInProgress = false

    init(
        directoryURL: URL,
        remover: @escaping TAPNAPShareArtifact.TemporaryDirectoryRemover
    ) {
        self.directoryURL = directoryURL
        self.remover = remover
    }

    deinit {
        remove()
    }

    func remove() {
        let shouldAttempt = lock.withLock {
            guard !hasRemovedDirectory,
                  !isRemovalInProgress else {
                return false
            }
            isRemovalInProgress = true
            return true
        }
        guard shouldAttempt else {
            return
        }

        let didRemove = TAPShareTemporaryDirectoryCleanup.removeIfPresent(
            at: directoryURL,
            scope: "artifactLease",
            remover: remover
        )
        lock.withLock {
            hasRemovedDirectory = didRemove
            isRemovalInProgress = false
        }
    }
}

nonisolated enum TAPShareTemporaryDirectoryCleanup {
    private static let removalAttemptLimit = 3

    @discardableResult
    static func removeIfPresent(
        at directoryURL: URL,
        scope: String,
        remover: @escaping TAPNAPShareArtifact.TemporaryDirectoryRemover = {
            try FileManager.default.removeItem(at: $0)
        }
    ) -> Bool {
        for attempt in 1...removalAttemptLimit {
            do {
                if FileManager.default.fileExists(atPath: directoryURL.path) {
                    try remover(directoryURL)
                }
                return true
            } catch {
                let nsError = error as NSError
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.sharePackaging.error(
                    "tap_share_temp_cleanup_failed scope=\(scope, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) attempt=\(attempt, privacy: .public) willRetry=\(attempt < removalAttemptLimit, privacy: .public)"
                )
                #endif
            }
        }
        return false
    }
}

nonisolated enum TAPNAPShareArtifactError: LocalizedError, Equatable, Sendable {
    case packageRequiresSignatureEvidence
    case shareResourceUnavailable
    case livePhotoPairedVideoMissing
    case emptyResource(String)
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .packageRequiresSignatureEvidence:
            "The TAPNAP package is available after this photo has been signed."
        case .shareResourceUnavailable:
            "The original share resource is currently unavailable."
        case .livePhotoPairedVideoMissing:
            "The complete Live Photo is currently unavailable. You can still share its image."
        case .emptyResource:
            "One of the original share resources is empty."
        case .invalidPackage:
            "The TAPNAP package could not be prepared."
        }
    }
}

/// Builds transport artifacts only. This type never parses a manifest or
/// proof, computes a digest, or invokes a signature validator.
///
/// Lifecycle constraint: a `.tapnap` may be generated only on demand after the
/// user explicitly selects the package option in the anchored TAP Share popover.
/// Background pre-generation and persistent package caching are prohibited.
/// Every output lives in a per-share temporary directory that the presentation
/// owner removes after completion, cancellation, or dismissal.
nonisolated struct TAPNAPShareArtifactBuilder: Sendable {
    typealias ProgressHandler = @Sendable (Double?) -> Void
    typealias PendingSnapshotter = @Sendable (
        _ captureID: String,
        _ destinationDirectoryURL: URL,
        _ requiresSignedPhoto: Bool,
        _ includesPairedVideo: Bool,
        _ linkPolicy: TAPPendingCaptureShareResourceLinkPolicy,
        _ progress: @escaping ProgressHandler
    ) async throws -> TAPPendingCaptureShareResourceSnapshot
    typealias PhotoLibraryResourceLoader = @Sendable (
        _ assetLocalIdentifier: String,
        _ preferredFileContainer: CapturePhotoFileContainer?,
        _ includesPairedVideo: Bool,
        _ outputDirectoryURL: URL,
        _ progress: @escaping ProgressHandler
    ) async throws -> PhotoLibraryWriter.OriginalShareResources
    typealias TemporaryDirectoryProvider = @Sendable () throws -> URL

    private static let packageFilename = "TAPNAP-Capture.tapnap"
    private static let imageBasename = "TAPNAP-Photo"
    private static let primaryPhotoBasename = "primary-photo"
    private static let pairedVideoFilename = "paired-video.mov"
    private static let sidecarFilename = "tapcam-export.json"
    private static let archiveBufferSize = 512 * 1024
    static let archiveProgressOffsetForPresentation = 0.8
    private static let archiveProgressOffset = archiveProgressOffsetForPresentation
    private static let archiveProgressWeight = 0.16

    private let pendingSnapshotter: PendingSnapshotter
    private let photoLibraryResourceLoader: PhotoLibraryResourceLoader
    private let temporaryDirectoryProvider: TemporaryDirectoryProvider

    init(
        pendingSnapshotter: @escaping PendingSnapshotter = { captureID, destinationURL, requiresSignedPhoto, includesPairedVideo, linkPolicy, progress in
            try TAPPendingCaptureStore.shared.snapshotPhotoShareResources(
                captureID: captureID,
                to: destinationURL,
                requiresSignedPhoto: requiresSignedPhoto,
                includesPairedVideo: includesPairedVideo,
                linkPolicy: linkPolicy,
                progressHandler: progress
            )
        },
        photoLibraryResourceLoader: @escaping PhotoLibraryResourceLoader = { assetID, fileContainer, includesPairedVideo, outputURL, progress in
            try await PhotoLibraryWriter.originalShareResources(
                localIdentifier: assetID,
                preferredFileContainer: fileContainer,
                includesPairedVideo: includesPairedVideo,
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
    func prepareTapnapPackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> TAPNAPShareArtifact {
        let preparationStartedAt = ProcessInfo.processInfo.systemUptime
        guard request.hasSignatureEvidence,
              request.fileContainer != nil || request.originalResourceLease != nil else {
            throw TAPNAPShareArtifactError.packageRequiresSignatureEvidence
        }
        let expectsPairedVideo = request.originalResourceLease?.expectsPairedVideo
            ?? request.expectsPairedVideo
        let progressCoalescer = TAPShareProgressCoalescer(delivery: progress)
        let coalescedProgress: ProgressHandler = { value in
            progressCoalescer.submit(value)
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tapnap prepare started livePhoto=\(expectsPairedVideo, privacy: .public) pendingRoute=\(request.captureID != nil, privacy: .public) photosRoute=\(request.assetLocalIdentifier != nil, privacy: .public) viewerLease=\(request.originalResourceLease != nil, privacy: .public) compression=none bufferBytes=\(Self.archiveBufferSize, privacy: .public)"
        )
        #endif

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
            let resourceLoadStartedAt = ProcessInfo.processInfo.systemUptime
            let resources = try await loadResources(
                request: request,
                requiresSignedPhoto: true,
                includesPairedVideo: expectsPairedVideo,
                pendingLinkPolicy: .allowReadOnlyHardLink,
                destinationDirectoryURL: resourcesDirectoryURL,
                progress: { value in
                    Self.mapProgress(
                        value,
                        offset: 0,
                        weight: 0.78,
                        handler: coalescedProgress
                    )
                }
            )
            let photoBytes = try Self.checkedResourceSize(resources.photoURL)
            let pairedVideoBytes = try resources.pairedVideoURL.map(Self.checkedResourceSize) ?? 0
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tapnap resources ready durationMs=\(Self.elapsedMilliseconds(since: resourceLoadStartedAt), privacy: .public) photoBytes=\(photoBytes, privacy: .public) pairedVideoBytes=\(pairedVideoBytes, privacy: .public)"
            )
            #endif
            try Task.checkCancellation()
            guard !expectsPairedVideo || resources.pairedVideoURL != nil else {
                throw TAPNAPShareArtifactError.livePhotoPairedVideoMissing
            }

            let artifact = try await makePackage(
                resources: resources,
                expectsPairedVideo: expectsPairedVideo,
                outputDirectoryURL: outputDirectoryURL,
                progress: coalescedProgress
            )
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: resourcesDirectoryURL,
                scope: "tapnapResources"
            )
            coalescedProgress(1)
            await progressCoalescer.finish()
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tapnap prepare completed durationMs=\(Self.elapsedMilliseconds(since: preparationStartedAt), privacy: .public) packageBytes=\((try? Self.checkedResourceSize(artifact.fileURL)) ?? 0, privacy: .public)"
            )
            #endif
            return artifact
        } catch {
            progressCoalescer.cancel()
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: outputDirectoryURL,
                scope: "tapnapFailure"
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.error(
                "tapnap prepare failed durationMs=\(Self.elapsedMilliseconds(since: preparationStartedAt), privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)"
            )
            #endif
            throw Self.publicError(from: error)
        }
    }

    @concurrent
    func prepareImage(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> TAPNAPShareArtifact {
        let preparationStartedAt = ProcessInfo.processInfo.systemUptime
        if requiresSignedPhoto, !request.hasSignatureEvidence {
            throw TAPNAPShareArtifactError.packageRequiresSignatureEvidence
        }
        let progressCoalescer = TAPShareProgressCoalescer(delivery: progress)
        let coalescedProgress: ProgressHandler = { value in
            progressCoalescer.submit(value)
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "image share prepare started signedOnly=\(requiresSignedPhoto, privacy: .public) pendingRoute=\(request.captureID != nil, privacy: .public) photosRoute=\(request.assetLocalIdentifier != nil, privacy: .public)"
        )
        #endif

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
            let resourceLoadStartedAt = ProcessInfo.processInfo.systemUptime
            let resources = try await loadResources(
                request: request,
                requiresSignedPhoto: requiresSignedPhoto,
                includesPairedVideo: false,
                pendingLinkPolicy: .requireIndependentFile,
                destinationDirectoryURL: resourcesDirectoryURL,
                progress: { value in
                    Self.mapProgress(
                        value,
                        offset: 0,
                        weight: 0.95,
                        handler: coalescedProgress
                    )
                }
            )
            try Task.checkCancellation()
            let photoBytes = try Self.checkedResourceSize(resources.photoURL)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "image share resources ready durationMs=\(Self.elapsedMilliseconds(since: resourceLoadStartedAt), privacy: .public) photoBytes=\(photoBytes, privacy: .public)"
            )
            #endif

            let imageURL = outputDirectoryURL
                .appendingPathComponent(Self.imageBasename)
                .appendingPathExtension(resources.photoFileExtension)
            try FileManager.default.moveItem(at: resources.photoURL, to: imageURL)
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: resourcesDirectoryURL,
                scope: "imageResources"
            )
            coalescedProgress(1)
            let artifact = TAPNAPShareArtifact(
                id: UUID(),
                kind: .image,
                fileURL: imageURL,
                temporaryDirectoryURL: outputDirectoryURL,
                warnings: Self.warningMessages(
                    from: resources.presentationAdjustmentResourceLabels
                ) + Self.verifiabilityWarning(
                    request.directShareVerifiabilityWarning
                )
            )
            await progressCoalescer.finish()
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "image share prepare completed durationMs=\(Self.elapsedMilliseconds(since: preparationStartedAt), privacy: .public) imageBytes=\(photoBytes, privacy: .public)"
            )
            #endif
            return artifact
        } catch {
            progressCoalescer.cancel()
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: outputDirectoryURL,
                scope: "imageFailure"
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.error(
                "image share prepare failed durationMs=\(Self.elapsedMilliseconds(since: preparationStartedAt), privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)"
            )
            #endif
            throw Self.publicError(from: error)
        }
    }

    private func loadResources(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        includesPairedVideo: Bool,
        pendingLinkPolicy: TAPPendingCaptureShareResourceLinkPolicy,
        destinationDirectoryURL: URL,
        progress: @escaping ProgressHandler
    ) async throws -> SourceResources {
        if let originalResourceLease = request.originalResourceLease {
            return try await resources(
                from: originalResourceLease,
                includesPairedVideo: includesPairedVideo,
                requiresIndependentCopy: pendingLinkPolicy == .requireIndependentFile,
                destinationDirectoryURL: destinationDirectoryURL,
                progress: progress
            )
        }

        if !request.prefersPhotoLibraryResources, let captureID = request.captureID {
            do {
                let snapshot = try await pendingSnapshotter(
                    captureID,
                    destinationDirectoryURL,
                    requiresSignedPhoto,
                    includesPairedVideo,
                    pendingLinkPolicy,
                    progress
                )
                progress(1)
                return SourceResources(
                    photoURL: snapshot.photoURL,
                    photoFileExtension: snapshot.fileContainer.tapnapFileExtension,
                    photoMediaType: snapshot.fileContainer.uniformTypeIdentifier,
                    pairedVideoURL: snapshot.pairedVideoURL,
                    presentationAdjustmentResourceLabels: [],
                    retainedOriginalResourceLease: nil
                )
            } catch TAPDepthCaptureError.pendingCaptureDataMissing {
                guard request.assetLocalIdentifier != nil else {
                    throw TAPNAPShareArtifactError.shareResourceUnavailable
                }
            }
        }

        guard let assetLocalIdentifier = request.assetLocalIdentifier else {
            throw TAPNAPShareArtifactError.shareResourceUnavailable
        }
        let resources = try await photoLibraryResourceLoader(
            assetLocalIdentifier,
            request.fileContainer,
            includesPairedVideo,
            destinationDirectoryURL,
            progress
        )
        return SourceResources(
            photoURL: resources.photoURL,
            photoFileExtension: resources.photoFileExtension,
            photoMediaType: resources.photoMediaType,
            pairedVideoURL: resources.pairedVideoURL,
            presentationAdjustmentResourceLabels: resources.presentationAdjustmentResourceLabels,
            retainedOriginalResourceLease: nil
        )
    }

    private func resources(
        from originalResourceLease: TAPPhotoOriginalResourceLease,
        includesPairedVideo: Bool,
        requiresIndependentCopy: Bool,
        destinationDirectoryURL: URL,
        progress: @escaping ProgressHandler
    ) async throws -> SourceResources {
        try Task.checkCancellation()
        if includesPairedVideo, originalResourceLease.pairedVideoURL == nil {
            throw TAPNAPShareArtifactError.livePhotoPairedVideoMissing
        }

        guard requiresIndependentCopy else {
            progress(1)
            return SourceResources(
                photoURL: originalResourceLease.photoURL,
                photoFileExtension: originalResourceLease.photoFileExtension,
                photoMediaType: originalResourceLease.photoMediaType,
                pairedVideoURL: includesPairedVideo
                    ? originalResourceLease.pairedVideoURL
                    : nil,
                presentationAdjustmentResourceLabels:
                    originalResourceLease.presentationAdjustmentResourceLabels,
                retainedOriginalResourceLease: originalResourceLease.retaining()
            )
        }

        try FileManager.default.createDirectory(
            at: destinationDirectoryURL,
            withIntermediateDirectories: true
        )
        let photoURL = destinationDirectoryURL
            .appendingPathComponent("viewer-original-photo")
            .appendingPathExtension(originalResourceLease.photoFileExtension)
        try TAPShareResourceFileCopier.copy(
            from: originalResourceLease.photoURL,
            to: photoURL,
            progress: progress
        )
        try Task.checkCancellation()
        return SourceResources(
            photoURL: photoURL,
            photoFileExtension: originalResourceLease.photoFileExtension,
            photoMediaType: originalResourceLease.photoMediaType,
            pairedVideoURL: nil,
            presentationAdjustmentResourceLabels:
                originalResourceLease.presentationAdjustmentResourceLabels,
            retainedOriginalResourceLease: nil
        )
    }

    private func makePackage(
        resources: SourceResources,
        expectsPairedVideo: Bool,
        outputDirectoryURL: URL,
        progress: @escaping ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        let photoFilename = Self.primaryPhotoBasename
            + "."
            + resources.photoFileExtension
        let sidecarDirectoryURL = outputDirectoryURL.appendingPathComponent(
            "resources",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sidecarDirectoryURL,
            withIntermediateDirectories: true
        )
        let sidecarURL = sidecarDirectoryURL
            .appendingPathComponent(Self.sidecarFilename)
        let packageURL = outputDirectoryURL.appendingPathComponent(Self.packageFilename)
        let partialPackageURL = outputDirectoryURL.appendingPathComponent(
            ".\(Self.packageFilename).partial"
        )
        let warningLabels = resources.presentationAdjustmentResourceLabels
        let warnings = Self.warningMessages(from: warningLabels)
        var sidecarResources = [
            TAPVerificationExportSidecar.Resource(
                role: "primaryPhoto",
                filename: photoFilename,
                mediaType: resources.photoMediaType
            )
        ]
        if expectsPairedVideo {
            sidecarResources.append(TAPVerificationExportSidecar.Resource(
                role: "pairedLivePhotoVideo",
                filename: Self.pairedVideoFilename,
                mediaType: UTType.quickTimeMovie.identifier
            ))
        }
        let sidecar = TAPVerificationExportSidecar(
            packageKind: expectsPairedVideo
                ? TAPVerificationPackageKind.livePhotoPackage.rawValue
                : TAPVerificationPackageKind.stillPhoto.rawValue,
            resources: sidecarResources,
            warningLabels: warningLabels,
            warnings: warnings
        )
        try JSONEncoder.tapCaptureCanonical.encode(sidecar).write(
            to: sidecarURL,
            options: .atomic
        )

        var entries = [
            ArchiveSource(
                path: photoFilename,
                fileURL: resources.photoURL,
                uncompressedSize: try Self.checkedResourceSize(resources.photoURL)
            )
        ]
        if expectsPairedVideo {
            guard let pairedVideoURL = resources.pairedVideoURL else {
                throw TAPNAPShareArtifactError.livePhotoPairedVideoMissing
            }
            entries.append(ArchiveSource(
                path: Self.pairedVideoFilename,
                fileURL: pairedVideoURL,
                uncompressedSize: try Self.checkedResourceSize(pairedVideoURL)
            ))
        }
        entries.append(ArchiveSource(
            path: Self.sidecarFilename,
            fileURL: sidecarURL,
            uncompressedSize: try Self.checkedResourceSize(sidecarURL)
        ))

        progress(Self.archiveProgressOffset)
        let archiveByteCount = entries.reduce(Int64(0)) { $0 + $1.uncompressedSize }
        let archiveProgress = Progress(totalUnitCount: archiveByteCount)
        let archiveStartedAt = ProcessInfo.processInfo.systemUptime
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tapnap zip started entries=\(entries.count, privacy: .public) inputBytes=\(archiveByteCount, privacy: .public)"
        )
        #endif
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try Self.writeArchive(
                entries: entries,
                to: partialPackageURL,
                archiveProgress: archiveProgress,
                progress: { archiveFraction in
                    Self.mapProgress(
                        archiveFraction,
                        offset: Self.archiveProgressOffset,
                        weight: Self.archiveProgressWeight,
                        handler: progress
                    )
                }
            )
            try Task.checkCancellation()
        } onCancel: {
            archiveProgress.cancel()
        }
        progress(Self.archiveProgressOffset + Self.archiveProgressWeight)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tapnap zip completed durationMs=\(Self.elapsedMilliseconds(since: archiveStartedAt), privacy: .public) outputBytes=\((try? Self.checkedResourceSize(partialPackageURL)) ?? 0, privacy: .public)"
        )
        #endif

        let validationStartedAt = ProcessInfo.processInfo.systemUptime
        try Self.validateArchive(at: partialPackageURL, expectedEntries: entries)
        progress(0.99)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tapnap zip validation completed durationMs=\(Self.elapsedMilliseconds(since: validationStartedAt), privacy: .public)"
        )
        #endif
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: partialPackageURL, to: packageURL)

        return TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: packageURL,
            temporaryDirectoryURL: outputDirectoryURL,
            warnings: warnings
        )
    }

    private static func writeArchive(
        entries: [ArchiveSource],
        to url: URL,
        archiveProgress: Progress,
        progress: @escaping ProgressHandler
    ) throws {
        let archive = try Archive(url: url, accessMode: .create)
        let observation = archiveProgress.observe(
            \.fractionCompleted,
            options: [.initial, .new]
        ) { observedProgress, _ in
            progress(observedProgress.fractionCompleted)
        }
        defer { observation.invalidate() }

        for entry in entries {
            if archiveProgress.isCancelled {
                throw CancellationError()
            }
            let entryProgress = Progress(totalUnitCount: entry.uncompressedSize)
            archiveProgress.addChild(
                entryProgress,
                withPendingUnitCount: entry.uncompressedSize
            )
            try archive.addEntry(
                with: entry.path,
                fileURL: entry.fileURL,
                compressionMethod: .none,
                bufferSize: Self.archiveBufferSize,
                progress: entryProgress
            )
        }
    }

    private static func validateArchive(
        at url: URL,
        expectedEntries: [ArchiveSource]
    ) throws {
        let archive = try Archive(url: url, accessMode: .read)
        let entries = Array(archive)
        let expectedByPath = Dictionary(
            uniqueKeysWithValues: expectedEntries.map { ($0.path, $0.uncompressedSize) }
        )
        guard entries.count == expectedEntries.count,
              Set(entries.map(\.path)) == Set(expectedByPath.keys),
              entries.allSatisfy({ entry in
                !entry.isCompressed
                    && expectedByPath[entry.path] == Int64(entry.uncompressedSize)
              }) else {
            throw TAPNAPShareArtifactError.invalidPackage
        }
    }

    private static func checkedResourceSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: url.path),
              let size = values.fileSize,
              size > 0 else {
            throw TAPNAPShareArtifactError.emptyResource(url.lastPathComponent)
        }
        return Int64(size)
    }

    private static func warningMessages(from labels: [String]) -> [String] {
        guard !labels.isEmpty else {
            return []
        }
        return [
            "Photos presentation resources detected: \(labels.joined(separator: ", ")). Sharing uses original resources only."
        ]
    }

    private static func verifiabilityWarning(_ warning: String?) -> [String] {
        guard let warning = warning?.trimmingCharacters(in: .whitespacesAndNewlines),
              !warning.isEmpty else {
            return []
        }
        return [warning]
    }

    private static func mapProgress(
        _ value: Double?,
        offset: Double,
        weight: Double,
        handler: ProgressHandler
    ) {
        guard let value, value.isFinite else {
            handler(nil)
            return
        }
        handler(offset + min(max(value, 0), 1) * weight)
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        max(0, (ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }

    private static func publicError(from error: any Error) -> any Error {
        if error is CancellationError || Task.isCancelled {
            return CancellationError()
        }
        if let error = error as? TAPNAPShareArtifactError {
            return error
        }
        return TAPNAPShareArtifactError.shareResourceUnavailable
    }

    private static func defaultTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TAPNAPShare-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension TAPNAPShareArtifactBuilder {
    nonisolated struct SourceResources: Sendable {
        let photoURL: URL
        let photoFileExtension: String
        let photoMediaType: String
        let pairedVideoURL: URL?
        let presentationAdjustmentResourceLabels: [String]
        /// Keeps Viewer-owned source URLs valid while an on-demand package is
        /// reading them directly. Independent image copies intentionally do not
        /// retain the Viewer resource after copying.
        let retainedOriginalResourceLease: TAPPhotoOriginalResourceLease?
    }

    nonisolated struct ArchiveSource: Sendable {
        let path: String
        let fileURL: URL
        let uncompressedSize: Int64
    }
}

/// Cancellable byte-for-byte copy used when the system activity controller
/// needs ownership independent from the Viewer resource lease.
nonisolated enum TAPShareResourceFileCopier {
    private static let bufferSize = 512 * 1_024

    static func copy(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) throws {
        let values = try sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: sourceURL.path),
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw TAPNAPShareArtifactError.emptyResource(sourceURL.lastPathComponent)
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw TAPNAPShareArtifactError.shareResourceUnavailable
        }

        let source = try FileHandle(forReadingFrom: sourceURL)
        let destination = try FileHandle(forWritingTo: destinationURL)
        var copiedBytes = 0
        do {
            while let chunk = try source.read(upToCount: bufferSize), !chunk.isEmpty {
                try Task.checkCancellation()
                try destination.write(contentsOf: chunk)
                copiedBytes += chunk.count
                progress(Double(copiedBytes) / Double(fileSize))
            }
            try destination.synchronize()
            try source.close()
            try destination.close()
            guard copiedBytes == fileSize else {
                throw TAPNAPShareArtifactError.shareResourceUnavailable
            }
        } catch {
            try? source.close()
            try? destination.close()
            TAPShareTemporaryDirectoryCleanup.removeIfPresent(
                at: destinationURL,
                scope: "partialCopyFile"
            )
            throw error
        }
    }
}

nonisolated private extension TAPPendingCaptureStatus {
    var tapnapHasSignatureEvidence: Bool {
        switch self {
        case .signed, .exporting, .exported:
            true
        case .pending, .waitingNetwork, .signing, .failedRetryable, .failedTerminal:
            false
        }
    }
}
