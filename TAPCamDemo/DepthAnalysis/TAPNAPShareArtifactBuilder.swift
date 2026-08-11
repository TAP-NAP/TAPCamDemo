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

/// Scalar routing input captured before share preparation begins. A request
/// deliberately carries durable record evidence rather than asking the share
/// path to verify photo bytes again.
nonisolated struct TAPNAPShareResourceRequest: Sendable {
    let captureID: String?
    let assetLocalIdentifier: String?
    let fileContainer: CapturePhotoFileContainer?
    let expectsPairedVideo: Bool
    let hasSignatureEvidence: Bool
    let prefersPhotoLibraryResources: Bool

    init(
        record: TAPPendingCaptureRecord,
        expectsPairedVideo livePhotoHint: Bool = false
    ) {
        captureID = record.captureID
        assetLocalIdentifier = record.assetLocalIdentifier
        fileContainer = record.photoFileContainer
        expectsPairedVideo = livePhotoHint || record.pairedVideoFilename != nil
        hasSignatureEvidence = record.artifactKind == .photoDepth
            && (record.signedPhotoFilename != nil || record.status.tapnapHasSignatureEvidence)
        prefersPhotoLibraryResources = record.status == .exported
            && record.assetLocalIdentifier != nil
    }

    init(assetLocalIdentifier: String) {
        captureID = nil
        self.assetLocalIdentifier = assetLocalIdentifier
        fileContainer = nil
        expectsPairedVideo = false
        hasSignatureEvidence = false
        prefersPhotoLibraryResources = true
    }

    init(
        captureID: String?,
        assetLocalIdentifier: String?,
        fileContainer: CapturePhotoFileContainer?,
        expectsPairedVideo: Bool,
        hasSignatureEvidence: Bool,
        prefersPhotoLibraryResources: Bool = false
    ) {
        self.captureID = captureID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.fileContainer = fileContainer
        self.expectsPairedVideo = expectsPairedVideo
        self.hasSignatureEvidence = hasSignatureEvidence
        self.prefersPhotoLibraryResources = prefersPhotoLibraryResources
    }
}

nonisolated struct TAPNAPShareArtifact: Identifiable, Sendable {
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

    func removeTemporaryDirectory() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
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
/// user explicitly selects the package option in `DepthAnalysisShareSheet`.
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
        guard request.hasSignatureEvidence, request.fileContainer != nil else {
            throw TAPNAPShareArtifactError.packageRequiresSignatureEvidence
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tapnap prepare started livePhoto=\(request.expectsPairedVideo, privacy: .public) pendingRoute=\(request.captureID != nil, privacy: .public) photosRoute=\(request.assetLocalIdentifier != nil, privacy: .public) compression=none bufferBytes=\(Self.archiveBufferSize, privacy: .public)"
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
            progress(0)
            let resourceLoadStartedAt = ProcessInfo.processInfo.systemUptime
            let resources = try await loadResources(
                request: request,
                requiresSignedPhoto: true,
                includesPairedVideo: request.expectsPairedVideo,
                pendingLinkPolicy: .allowReadOnlyHardLink,
                destinationDirectoryURL: resourcesDirectoryURL,
                progress: { value in
                    Self.mapProgress(value, offset: 0, weight: 0.78, handler: progress)
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
            guard !request.expectsPairedVideo || resources.pairedVideoURL != nil else {
                throw TAPNAPShareArtifactError.livePhotoPairedVideoMissing
            }

            let artifact = try await makePackage(
                resources: resources,
                expectsPairedVideo: request.expectsPairedVideo,
                outputDirectoryURL: outputDirectoryURL,
                progress: progress
            )
            try? FileManager.default.removeItem(at: resourcesDirectoryURL)
            progress(1)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tapnap prepare completed durationMs=\(Self.elapsedMilliseconds(since: preparationStartedAt), privacy: .public) packageBytes=\((try? Self.checkedResourceSize(artifact.fileURL)) ?? 0, privacy: .public)"
            )
            #endif
            return artifact
        } catch {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
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
            progress(0)
            let resourceLoadStartedAt = ProcessInfo.processInfo.systemUptime
            let resources = try await loadResources(
                request: request,
                requiresSignedPhoto: requiresSignedPhoto,
                includesPairedVideo: false,
                pendingLinkPolicy: .requireIndependentFile,
                destinationDirectoryURL: resourcesDirectoryURL,
                progress: { value in
                    Self.mapProgress(value, offset: 0, weight: 0.95, handler: progress)
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
            try? FileManager.default.removeItem(at: resourcesDirectoryURL)
            progress(1)
            let artifact = TAPNAPShareArtifact(
                id: UUID(),
                kind: .image,
                fileURL: imageURL,
                temporaryDirectoryURL: outputDirectoryURL,
                warnings: Self.warningMessages(
                    from: resources.presentationAdjustmentResourceLabels
                )
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "image share prepare completed durationMs=\(Self.elapsedMilliseconds(since: preparationStartedAt), privacy: .public) imageBytes=\(photoBytes, privacy: .public)"
            )
            #endif
            return artifact
        } catch {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
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
                    presentationAdjustmentResourceLabels: []
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
            presentationAdjustmentResourceLabels: resources.presentationAdjustmentResourceLabels
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
        let sidecarURL = resources.photoURL.deletingLastPathComponent()
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
                ? TAPVerificationExport.Kind.livePhotoPackage.rawValue
                : TAPVerificationExport.Kind.stillPhoto.rawValue,
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
    }

    nonisolated struct ArchiveSource: Sendable {
        let path: String
        let fileURL: URL
        let uncompressedSize: Int64
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
