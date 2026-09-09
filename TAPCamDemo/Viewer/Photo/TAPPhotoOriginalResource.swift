//
//  TAPPhotoOriginalResource.swift
//  TAPCamDemo
//

import Combine
import Foundation

/// Identifies how the exact file-backed Viewer original was obtained.
///
/// This is an in-memory routing value only. Capture and Photos identifiers must
/// remain private in diagnostics and must never be copied into a package
/// sidecar or public error message.
nonisolated enum TAPPhotoOriginalResourceOrigin: Equatable, Sendable {
    case photosAsset(assetID: String)
    case pendingCapture(captureID: String, selectedSignedPhoto: Bool)
}

nonisolated enum TAPPhotoOriginalResourceError: Error, Equatable, Sendable {
    case resourceUnavailable
    case emptyPhoto
    case livePhotoPairedVideoMissing
    case emptyPairedVideo
    case invalidOwnedDirectory
}

/// Immutable file-backed original shared by the Viewer and an active Share
/// attempt. The directory is deleted only after the final lease is released.
///
/// This is deliberately not a package cache: it contains only the current
/// Viewer's original media resources, never a generated `.tapnap` or a payload
/// prepared for the system activity controller.
nonisolated final class TAPPhotoOriginalResourceLease: @unchecked Sendable {
    private let storage: TAPPhotoOriginalResourceStorage

    var mediaID: LibraryMediaID { storage.mediaID }
    var origin: TAPPhotoOriginalResourceOrigin { storage.origin }
    var photoURL: URL { storage.photoURL }
    var pairedVideoURL: URL? { storage.pairedVideoURL }
    var photoFileExtension: String { storage.photoFileExtension }
    var photoMediaType: String { storage.photoMediaType }
    var fileContainerHint: CapturePhotoFileContainer? { storage.fileContainerHint }
    var expectsPairedVideo: Bool { storage.expectsPairedVideo }
    var presentationAdjustmentResourceLabels: [String] {
        storage.presentationAdjustmentResourceLabels
    }

    init(
        mediaID: LibraryMediaID,
        origin: TAPPhotoOriginalResourceOrigin,
        photoURL: URL,
        pairedVideoURL: URL?,
        photoFileExtension: String,
        photoMediaType: String,
        fileContainerHint: CapturePhotoFileContainer?,
        expectsPairedVideo: Bool,
        ownedTemporaryDirectoryURL: URL,
        presentationAdjustmentResourceLabels: [String] = []
    ) throws {
        storage = try TAPPhotoOriginalResourceStorage(
            mediaID: mediaID,
            origin: origin,
            photoURL: photoURL,
            pairedVideoURL: pairedVideoURL,
            photoFileExtension: photoFileExtension,
            photoMediaType: photoMediaType,
            fileContainerHint: fileContainerHint,
            expectsPairedVideo: expectsPairedVideo,
            ownedTemporaryDirectoryURL: ownedTemporaryDirectoryURL,
            presentationAdjustmentResourceLabels: presentationAdjustmentResourceLabels
        )
    }

    private init(storage: TAPPhotoOriginalResourceStorage) {
        self.storage = storage
    }

    func retaining() -> TAPPhotoOriginalResourceLease {
        TAPPhotoOriginalResourceLease(storage: storage)
    }
}

/// Stable, Viewer-owned reference to one current original resource set.
///
/// A slot may clear or replace this owner during paging without invalidating a
/// lease already acquired by the Share coordinator. Conversely, a bare
/// `ready` Boolean is never treated as proof that its backing URLs still exist.
@MainActor
final class TAPPhotoOriginalResourceOwner: ObservableObject {
    @Published private(set) var isReady = false

    private var retainedLease: TAPPhotoOriginalResourceLease?

    func install(_ lease: TAPPhotoOriginalResourceLease) {
        retainedLease = lease.retaining()
        isReady = true
    }

    func acquireLease() -> TAPPhotoOriginalResourceLease? {
        retainedLease?.retaining()
    }

    func clear() {
        retainedLease = nil
        isReady = false
    }
}

/// Owns cleanup for one original-resource directory. ARC supplies the
/// reference count across the Viewer owner and every acquired Share lease.
private nonisolated final class TAPPhotoOriginalResourceStorage: @unchecked Sendable {
    let mediaID: LibraryMediaID
    let origin: TAPPhotoOriginalResourceOrigin
    let photoURL: URL
    let pairedVideoURL: URL?
    let photoFileExtension: String
    let photoMediaType: String
    let fileContainerHint: CapturePhotoFileContainer?
    let expectsPairedVideo: Bool
    let presentationAdjustmentResourceLabels: [String]

    private let ownedTemporaryDirectoryURL: URL
    private let cleanupLock = NSLock()
    private var didCleanUp = false

    init(
        mediaID: LibraryMediaID,
        origin: TAPPhotoOriginalResourceOrigin,
        photoURL: URL,
        pairedVideoURL: URL?,
        photoFileExtension: String,
        photoMediaType: String,
        fileContainerHint: CapturePhotoFileContainer?,
        expectsPairedVideo: Bool,
        ownedTemporaryDirectoryURL: URL,
        presentationAdjustmentResourceLabels: [String]
    ) throws {
        guard Self.isOwnedResource(photoURL, by: ownedTemporaryDirectoryURL),
              pairedVideoURL.map({ Self.isOwnedResource($0, by: ownedTemporaryDirectoryURL) }) ?? true else {
            throw TAPPhotoOriginalResourceError.invalidOwnedDirectory
        }
        guard try Self.nonemptyRegularFile(at: photoURL) else {
            throw TAPPhotoOriginalResourceError.emptyPhoto
        }
        if expectsPairedVideo, pairedVideoURL == nil {
            throw TAPPhotoOriginalResourceError.livePhotoPairedVideoMissing
        }
        if let pairedVideoURL,
           try !Self.nonemptyRegularFile(at: pairedVideoURL) {
            throw TAPPhotoOriginalResourceError.emptyPairedVideo
        }

        self.mediaID = mediaID
        self.origin = origin
        self.photoURL = photoURL
        self.pairedVideoURL = pairedVideoURL
        self.photoFileExtension = photoFileExtension
        self.photoMediaType = photoMediaType
        self.fileContainerHint = fileContainerHint
        self.expectsPairedVideo = expectsPairedVideo
        self.ownedTemporaryDirectoryURL = ownedTemporaryDirectoryURL
        self.presentationAdjustmentResourceLabels = presentationAdjustmentResourceLabels
    }

    deinit {
        cleanup()
    }

    private func cleanup() {
        let shouldRemove = cleanupLock.withLock {
            guard !didCleanUp else {
                return false
            }
            didCleanUp = true
            return true
        }
        if shouldRemove {
            try? FileManager.default.removeItem(at: ownedTemporaryDirectoryURL)
        }
    }

    private static func isOwnedResource(_ resourceURL: URL, by directoryURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let resourcePath = resourceURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        guard directoryPath != "/", !directoryPath.isEmpty else {
            return false
        }
        return resourcePath.hasPrefix(directoryPath + "/")
    }

    private static func nonemptyRegularFile(at url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return values.isRegularFile == true
            && (values.fileSize ?? 0) > 0
            && FileManager.default.isReadableFile(atPath: url.path)
    }
}

nonisolated struct TAPPhotoOriginalResourceRequest: Equatable, Sendable {
    let mediaID: LibraryMediaID
    let source: DepthAnalysisSource
    let expectsPairedVideo: Bool

    init(
        mediaID: LibraryMediaID,
        source: DepthAnalysisSource,
        expectsPairedVideo: Bool
    ) {
        self.mediaID = mediaID
        self.source = source
        self.expectsPairedVideo = expectsPairedVideo
    }
}

/// Resolves the complete original photo resource set for the current Viewer
/// item. Photos may use iCloud, while pending resources are snapshotted under
/// the queue actor so its export worker cannot remove a source midway.
///
/// No package is generated and no backend verifier is reachable from this
/// service. Loading a Live Photo succeeds only when both its photo and paired
/// MOV are present and nonempty.
nonisolated struct TAPPhotoOriginalResourceLoader: Sendable {
    typealias ProgressHandler = @Sendable (Double?) -> Void
    typealias PhotoLibraryLoader = @Sendable (
        _ assetID: String,
        _ includesPairedVideo: Bool,
        _ outputDirectoryURL: URL,
        _ progress: @escaping ProgressHandler
    ) async throws -> PhotoLibraryWriter.OriginalShareResources
    typealias PendingLoader = @Sendable (
        _ captureID: String,
        _ includesPairedVideo: Bool,
        _ outputDirectoryURL: URL,
        _ progress: @escaping ProgressHandler
    ) async throws -> TAPPendingCaptureShareResourceSnapshot
    typealias DirectoryProvider = @Sendable () throws -> URL
    typealias ResourceProtector = @Sendable (URL) throws -> Void

    private let photoLibraryLoader: PhotoLibraryLoader
    private let pendingLoader: PendingLoader
    private let directoryProvider: DirectoryProvider
    private let resourceProtector: ResourceProtector

    init(
        photoLibraryLoader: @escaping PhotoLibraryLoader = { assetID, includesPairedVideo, outputDirectoryURL, progress in
            try await PhotoLibraryWriter.originalShareResources(
                localIdentifier: assetID,
                preferredFileContainer: nil,
                includesPairedVideo: includesPairedVideo,
                outputDirectoryURL: outputDirectoryURL,
                progressHandler: progress
            )
        },
        pendingLoader: @escaping PendingLoader = { captureID, includesPairedVideo, outputDirectoryURL, progress in
            try TAPPendingCaptureStore.shared.snapshotPhotoShareResources(
                captureID: captureID,
                to: outputDirectoryURL,
                requiresSignedPhoto: false,
                includesPairedVideo: includesPairedVideo,
                linkPolicy: .allowReadOnlyHardLink,
                progressHandler: progress
            )
        },
        directoryProvider: @escaping DirectoryProvider = Self.defaultDirectory,
        resourceProtector: @escaping ResourceProtector = {
            try TAPLocalArtifactStoragePolicy.privatePhotoArtifact.protectDirectoryTree(at: $0)
        }
    ) {
        self.photoLibraryLoader = photoLibraryLoader
        self.pendingLoader = pendingLoader
        self.directoryProvider = directoryProvider
        self.resourceProtector = resourceProtector
    }

    @concurrent
    func load(
        _ request: TAPPhotoOriginalResourceRequest,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> TAPPhotoOriginalResourceLease {
        let outputDirectoryURL = try directoryProvider()
        do {
            try FileManager.default.createDirectory(
                at: outputDirectoryURL,
                withIntermediateDirectories: true
            )
            progress(0)

            let lease: TAPPhotoOriginalResourceLease
            switch request.source {
            case .photosAsset(let assetID):
                let resources = try await photoLibraryLoader(
                    assetID,
                    request.expectsPairedVideo,
                    outputDirectoryURL,
                    progress
                )
                guard resources.temporaryDirectoryURL.standardizedFileURL
                    == outputDirectoryURL.standardizedFileURL else {
                    throw TAPPhotoOriginalResourceError.invalidOwnedDirectory
                }
                let containerHint = CapturePhotoFileContainer(
                    imageTypeIdentifier: resources.photoMediaType
                )
                lease = try TAPPhotoOriginalResourceLease(
                    mediaID: request.mediaID,
                    origin: .photosAsset(assetID: assetID),
                    photoURL: resources.photoURL,
                    pairedVideoURL: resources.pairedVideoURL,
                    photoFileExtension: resources.photoFileExtension,
                    photoMediaType: resources.photoMediaType,
                    fileContainerHint: containerHint,
                    expectsPairedVideo: request.expectsPairedVideo,
                    ownedTemporaryDirectoryURL: outputDirectoryURL,
                    presentationAdjustmentResourceLabels: resources.presentationAdjustmentResourceLabels
                )

            case .pendingCapture(let captureID):
                let snapshot = try await pendingLoader(
                    captureID,
                    request.expectsPairedVideo,
                    outputDirectoryURL,
                    progress
                )
                lease = try TAPPhotoOriginalResourceLease(
                    mediaID: request.mediaID,
                    origin: .pendingCapture(
                        captureID: captureID,
                        selectedSignedPhoto: snapshot.selectedSignedPhoto
                    ),
                    photoURL: snapshot.photoURL,
                    pairedVideoURL: snapshot.pairedVideoURL,
                    photoFileExtension: Self.fileExtension(for: snapshot.fileContainer),
                    photoMediaType: snapshot.fileContainer.uniformTypeIdentifier,
                    fileContainerHint: snapshot.fileContainer,
                    expectsPairedVideo: request.expectsPairedVideo,
                    ownedTemporaryDirectoryURL: outputDirectoryURL
                )
            }

            try Task.checkCancellation()
            try resourceProtector(outputDirectoryURL)
            progress(1)
            return lease
        } catch {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            if let resourceError = error as? TAPPhotoOriginalResourceError {
                throw resourceError
            }
            throw TAPPhotoOriginalResourceError.resourceUnavailable
        }
    }

    private static func fileExtension(
        for container: CapturePhotoFileContainer
    ) -> String {
        switch container {
        case .heic:
            "heic"
        case .jpeg:
            "jpg"
        }
    }

    private static func defaultDirectory() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "TAPViewerPhotoOriginal-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

nonisolated struct TAPPhotoLocalIntegrityResult: Equatable, Sendable {
    let captureID: String
    let mediaKind: LibraryMediaKind
    let fileContainer: CapturePhotoFileContainer
}

nonisolated enum TAPPhotoLocalIntegrityError: Error, Equatable, Sendable {
    case expectedCaptureIDMismatch
    case unsupportedManifestSchema
    case mediaKindMismatch
    case livePhotoPairedVideoMissing
}

/// Recomputes the embedded TAP proof/content binding against the exact ready
/// original held by a Viewer lease. This is a synchronous, local-only gate: it
/// neither re-signs the capture nor submits an App Attest verification request.
nonisolated struct TAPPhotoLocalIntegrityValidator: Sendable {
    private let localValidator: TAPSignedPhotoResourceValidator

    init(localValidator: TAPSignedPhotoResourceValidator = .production) {
        self.localValidator = localValidator
    }

    func validate(
        _ resource: TAPPhotoOriginalResourceLease,
        expectedCaptureID: String? = nil
    ) throws -> TAPPhotoLocalIntegrityResult {
        try Task<Never, Never>.checkCancellation()
        let photoData = try Data(
            contentsOf: resource.photoURL,
            options: [.mappedIfSafe]
        )
        try Task<Never, Never>.checkCancellation()
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: photoData)
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: photoData)
        try Task<Never, Never>.checkCancellation()
        if let expectedCaptureID,
           manifest.payload.id != expectedCaptureID {
            throw TAPPhotoLocalIntegrityError.expectedCaptureIDMismatch
        }
        let expectedProfile = Self.expectedProfile(
            fileContainer: fileContainer,
            manifest: manifest
        )

        if manifest.schema == TAPDepthManifest.Schema.livePhoto {
            guard let pairedVideoURL = resource.pairedVideoURL else {
                throw TAPPhotoLocalIntegrityError.livePhotoPairedVideoMissing
            }
            _ = try localValidator.validateLivePhoto(
                photoData,
                pairedVideoURL,
                manifest.payload.id,
                expectedProfile
            )
            try Task<Never, Never>.checkCancellation()
            return TAPPhotoLocalIntegrityResult(
                captureID: manifest.payload.id,
                mediaKind: .livePhoto,
                fileContainer: fileContainer
            )
        }

        guard manifest.schema == TAPDepthManifest.Schema() else {
            throw TAPPhotoLocalIntegrityError.unsupportedManifestSchema
        }
        guard !resource.expectsPairedVideo else {
            throw TAPPhotoLocalIntegrityError.mediaKindMismatch
        }
        _ = try localValidator.validateStillPhoto(
            photoData,
            manifest.payload.id,
            expectedProfile
        )
        try Task<Never, Never>.checkCancellation()
        return TAPPhotoLocalIntegrityResult(
            captureID: manifest.payload.id,
            mediaKind: .photo,
            fileContainer: fileContainer
        )
    }

    private static func expectedProfile(
        fileContainer: CapturePhotoFileContainer,
        manifest: TAPDepthManifest
    ) -> CaptureOutputProfile {
        let qualityLevel = CapturePhotoQualityLevel(
            rawValue: manifest.payload.capture.photoQualityPrioritization
        ) ?? .quality
        return CaptureOutputProfile.releasePhotoDepthProfile(
            fileContainer: fileContainer,
            photoQualityLevel: qualityLevel
        )
    }
}

/// Queue-only classification used before local validation of a pending photo.
/// Photos/iCloud assets do not use this policy and cannot fail merely because a
/// matching queue record no longer exists.
nonisolated enum TAPPendingPhotoShareDisposition: Equatable, Sendable {
    case validateSignedOriginal
    case needsRetry
    case failed
}

nonisolated enum TAPPendingPhotoSharePolicy {
    static func disposition(
        for record: TAPPendingCaptureRecord?,
        selectedSignedPhoto: Bool
    ) -> TAPPendingPhotoShareDisposition {
        guard let record, record.artifactKind == .photoDepth else {
            return .failed
        }
        // The actor-owned snapshot is the authority for which bytes are held
        // by this Share attempt. A stale filename or status must never promote
        // an unsigned fallback to Verified.
        if selectedSignedPhoto {
            return .validateSignedOriginal
        }
        switch record.status {
        case .pending, .waitingNetwork, .signing, .failedRetryable:
            return .needsRetry
        case .signed, .exporting, .exported, .failedTerminal:
            return .failed
        }
    }
}
