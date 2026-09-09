//
//  PhotoLibraryWriter.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import CoreLocation
import Foundation
import OSLog
import Photos
import UniformTypeIdentifiers

/// Saves final TAP depth photo bytes into the user's Photos library.
///
/// Photos is treated as storage for the finished file, not as the source of
/// metadata truth. To parse a saved asset later, request the original `.photo`
/// resource bytes with `PHAssetResourceManager` and then use
/// `TAPDepthPhotoFileReader`.
nonisolated enum PhotoLibraryWriter {
    static let albumName = "TAPCamDepth"
    typealias ResourceProgressHandler = @Sendable (Double?) -> Void

    nonisolated static func tapVideoResourceFilename(packageID: UUID) -> String {
        "tap-\(packageID.uuidString.lowercased()).mp4"
    }

    /// File-backed original resources for share preparation. The caller owns
    /// `temporaryDirectoryURL`; no photo or movie bytes are accumulated into a
    /// whole-file `Data` value on this path.
    nonisolated struct OriginalShareResources: Sendable {
        let photoURL: URL
        let photoFileExtension: String
        let photoMediaType: String
        let pairedVideoURL: URL?
        let temporaryDirectoryURL: URL
        let presentationAdjustmentResourceLabels: [String]
    }

    /// Caller-owned original video resource for direct sharing. Photos streams
    /// into the supplied staging directory; no transcoding or whole-file
    /// `Data` allocation occurs on this path.
    nonisolated struct OriginalVideoShareResource: Sendable {
        let videoURL: URL
        let fileExtension: String
        let mediaType: String
        let temporaryDirectoryURL: URL
    }

    /// Saves a validated TAP depth photo file to Photos.
    ///
    /// This writer receives a completed, provenance-checked artifact; it does
    /// not inspect cameras, choose packaging policy, or mutate capture session
    /// state. Full Photos access also adds the asset to the TAPCamDepth album;
    /// limited access saves the app-created asset directly and relies on its
    /// returned local identifier.
    ///
    /// - Tag: SaveDepthPhotoToPhotos
    static func saveDepthPhoto(
        _ validatedPhoto: ValidatedTAPDepthPhoto,
        capturedAt: Date,
        location: CLLocation?
    ) async throws -> String {
        let data = validatedPhoto.data
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveDepthPhoto start container=\(validatedPhoto.fileContainer.rawValue, privacy: .public) bytes=\(data.count, privacy: .public) hasLocation=\(location != nil, privacy: .public)")
        #endif
        let authorizationStatus = try requireReadWriteAccess()
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveDepthPhoto authorization status=\(String(describing: authorizationStatus), privacy: .public)")
        #endif
        let album: PHAssetCollection? = authorizationStatus == .authorized
            ? try await fetchOrCreateAlbum()
            : nil
        let assetID = try await createAsset(
            data: data,
            fileContainer: validatedPhoto.fileContainer,
            capturedAt: capturedAt,
            location: location,
            album: album
        )
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveDepthPhoto success assetID=\(assetID, privacy: .private)")
        #endif
        return assetID
    }

    /// Saves a validated TAP depth Live Photo to Photos.
    static func saveDepthLivePhoto(
        _ validatedLivePhoto: ValidatedTAPLivePhoto,
        capturedAt: Date,
        location: CLLocation?
    ) async throws -> String {
        let data = validatedLivePhoto.photo.data
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveDepthLivePhoto start container=\(validatedLivePhoto.photo.fileContainer.rawValue, privacy: .public) bytes=\(data.count, privacy: .public) hasLocation=\(location != nil, privacy: .public)")
        #endif
        let authorizationStatus = try requireReadWriteAccess()
        let album: PHAssetCollection? = authorizationStatus == .authorized
            ? try await fetchOrCreateAlbum()
            : nil
        let assetID = try await createAsset(
            data: data,
            fileContainer: validatedLivePhoto.photo.fileContainer,
            capturedAt: capturedAt,
            location: location,
            album: album,
            pairedVideoURL: validatedLivePhoto.pairedVideoURL
        )
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveDepthLivePhoto success assetID=\(assetID, privacy: .private)")
        #endif
        return assetID
    }

    /// Saves a validated TAP video without materializing the complete MP4 in
    /// memory or creating a second app-owned staging copy.
    static func saveTAPVideoFile(
        at fileURL: URL,
        packageID: UUID,
        manifest: TAPVideoManifest,
        capturedAt: Date,
        location: CLLocation?,
        commitWillBegin: @Sendable () async throws -> Void
    ) async throws -> String {
        let byteCount = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveTAPVideoFile start bytes=\(byteCount, privacy: .public) hasLocation=\(location != nil, privacy: .public) depthSamples=\(manifest.payload.depthCoverage.sampleCount, privacy: .public)")
        #endif
        let authorizationStatus = try requireReadWriteAccess()
        let album: PHAssetCollection? = authorizationStatus == .authorized
            ? try await fetchOrCreateAlbum()
            : nil
        let assetID = try await createVideoAsset(
            fileURL: fileURL,
            resourceFilename: tapVideoResourceFilename(packageID: packageID),
            capturedAt: capturedAt,
            location: location,
            album: album,
            commitWillBegin: commitWillBegin
        )
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("saveTAPVideoFile success assetID=\(assetID, privacy: .private)")
        #endif
        return assetID
    }

    private static func originalPhotoData(for asset: PHAsset) async throws -> Data {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.error("originalPhotoData missing photo resource assetID=\(asset.localIdentifier, privacy: .private)")
            #endif
            throw TAPDepthCaptureError.assetCreationFailed
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("originalPhotoData request start assetID=\(asset.localIdentifier, privacy: .private)")
        #endif
        return try await withCheckedThrowingContinuation { continuation in
            var result = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    result.append(chunk)
                },
                completionHandler: { error in
                    if let error {
                        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                        TAPDiagnostics.photoLibrary.error("originalPhotoData request failed assetID=\(asset.localIdentifier, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
                        #endif
                        continuation.resume(throwing: error)
                    } else {
                        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                        TAPDiagnostics.photoLibrary.info("originalPhotoData request success assetID=\(asset.localIdentifier, privacy: .private) bytes=\(result.count, privacy: .public)")
                        #endif
                        continuation.resume(returning: result)
                    }
                }
            )
        }
    }

    /// Streams the original Photos video resource through a cancellable
    /// request. This is the readback seam used by the video byte-binding
    /// validator so Photos does not need to be copied into a whole-file Data.
    static func readOriginalVideoResource(
        localIdentifier: String,
        progressHandler: @escaping ResourceProgressHandler = { _ in },
        dataReceivedHandler: @escaping @Sendable (Data) throws -> Void
    ) async throws {
        try requireReadWriteAccess()
        guard let asset = asset(localIdentifier: localIdentifier) else {
            throw TAPDepthCaptureError.assetNotFound
        }
        guard let resource = PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == .video }) else {
            throw TAPDepthCaptureError.assetCreationFailed
        }
        let request = PhotoResourceDataRequest(
            assetLocalIdentifier: localIdentifier,
            label: "originalVideoReadback",
            progressHandler: progressHandler,
            dataReceivedHandler: dataReceivedHandler
        )
        try await withTaskCancellationHandler {
            try await request.start(resource: resource)
        } onCancel: {
            request.cancel()
        }
    }

    /// Reads original photo bytes by resolving the asset inside a detached task.
    ///
    /// `PHAssetResource.assetResources(for:)` can force Photos to fetch
    /// original-metadata properties. Running that lookup on the main actor
    /// produces the runtime warning:
    /// "Missing prefetched properties for PHAssetOriginalMetadataProperties...
    /// Fetching on demand on the main queue". The public Photos API does not
    /// expose a `PHFetchOptions` property-set prefetch knob for this private
    /// property set, so the practical fix is to keep original-resource
    /// resolution off the main queue and hand the UI only the final bytes.
    static func originalPhotoData(localIdentifier: String) async throws -> Data {
        try requireReadWriteAccess()
        return try await Task.detached(priority: .userInitiated) {
            guard let asset = asset(localIdentifier: localIdentifier) else {
                throw TAPDepthCaptureError.assetNotFound
            }

            return try await originalPhotoData(for: asset)
        }.value
    }

    /// Streams the selected asset's original `.photo` and optional
    /// `.pairedVideo` resources into caller-owned temporary storage. The
    /// detached Photos lookup avoids original-metadata work on the main actor;
    /// cancellation is forwarded to both the detached task and the active
    /// `PHAssetResourceManager` request.
    static func originalShareResources(
        localIdentifier: String,
        preferredFileContainer: CapturePhotoFileContainer?,
        includesPairedVideo: Bool,
        outputDirectoryURL: URL,
        progressHandler: @escaping ResourceProgressHandler = { _ in }
    ) async throws -> OriginalShareResources {
        try requireReadWriteAccess()
        let task = Task.detached(priority: .userInitiated) {
            guard let asset = asset(localIdentifier: localIdentifier) else {
                throw TAPDepthCaptureError.assetNotFound
            }
            return try await originalShareResources(
                for: asset,
                preferredFileContainer: preferredFileContainer,
                includesPairedVideo: includesPairedVideo,
                outputDirectoryURL: outputDirectoryURL,
                progressHandler: progressHandler
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Streams the selected asset's original video resource into
    /// caller-owned temporary storage. The original container and bytes are
    /// preserved so sharing never silently converts MOV and MP4 resources.
    static func originalVideoShareResource(
        localIdentifier: String,
        outputDirectoryURL: URL,
        progressHandler: @escaping ResourceProgressHandler = { _ in }
    ) async throws -> OriginalVideoShareResource {
        try requireReadWriteAccess()
        let task = Task.detached(priority: .userInitiated) {
            guard let asset = asset(localIdentifier: localIdentifier) else {
                throw TAPDepthCaptureError.assetNotFound
            }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let preferredType = LibraryVideoResourceSelectionPolicy.preferredType(
                in: resources.map(\.type)
            ),
                  let resource = resources.first(where: { $0.type == preferredType }) else {
                throw TAPDepthCaptureError.assetCreationFailed
            }

            let originalExtension = URL(
                fileURLWithPath: resource.originalFilename
            ).pathExtension.lowercased()
            let fileExtension = originalExtension.isEmpty
                ? (UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "mp4")
                : originalExtension
            let videoURL = outputDirectoryURL.appendingPathComponent(
                "source-video.\(fileExtension)"
            )

            do {
                try FileManager.default.createDirectory(
                    at: outputDirectoryURL,
                    withIntermediateDirectories: true
                )
                try await writeResourceCancellable(
                    resource,
                    to: videoURL,
                    assetLocalIdentifier: asset.localIdentifier,
                    label: "originalShareVideo",
                    progressHandler: progressHandler
                )
                try Task.checkCancellation()
                progressHandler(1)
                return OriginalVideoShareResource(
                    videoURL: videoURL,
                    fileExtension: fileExtension,
                    mediaType: resource.uniformTypeIdentifier,
                    temporaryDirectoryURL: outputDirectoryURL
                )
            } catch {
                try? FileManager.default.removeItem(at: outputDirectoryURL)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func originalShareResources(
        for asset: PHAsset,
        preferredFileContainer: CapturePhotoFileContainer?,
        includesPairedVideo: Bool,
        outputDirectoryURL: URL,
        progressHandler: @escaping ResourceProgressHandler
    ) async throws -> OriginalShareResources {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let photoResource = resources.first(where: { $0.type == .photo }) else {
            throw TAPDepthCaptureError.assetCreationFailed
        }
        let pairedVideoResource = includesPairedVideo
            ? resources.first(where: { $0.type == .pairedVideo })
            : nil

        let photoFileExtension = try sharePhotoFileExtension(
            resource: photoResource,
            preferredFileContainer: preferredFileContainer
        )
        let photoMediaType = preferredFileContainer?.uniformTypeIdentifier
            ?? photoResource.uniformTypeIdentifier
        let photoURL = outputDirectoryURL.appendingPathComponent(
            "source-photo.\(photoFileExtension)"
        )
        let pairedVideoURL = pairedVideoResource.map { _ in
            outputDirectoryURL.appendingPathComponent("source-paired-video.mov")
        }
        let photoProgressWeight = pairedVideoResource == nil ? 1.0 : 0.35

        do {
            try FileManager.default.createDirectory(
                at: outputDirectoryURL,
                withIntermediateDirectories: true
            )
            try await writeResourceCancellable(
                photoResource,
                to: photoURL,
                assetLocalIdentifier: asset.localIdentifier,
                label: "originalSharePhoto",
                progressHandler: { value in
                    mappedShareProgress(
                        value,
                        offset: 0,
                        weight: photoProgressWeight,
                        handler: progressHandler
                    )
                }
            )
            try Task.checkCancellation()

            if let pairedVideoResource, let pairedVideoURL {
                try await writeResourceCancellable(
                    pairedVideoResource,
                    to: pairedVideoURL,
                    assetLocalIdentifier: asset.localIdentifier,
                    label: "originalSharePairedVideo",
                    progressHandler: { value in
                        mappedShareProgress(
                            value,
                            offset: photoProgressWeight,
                            weight: 1 - photoProgressWeight,
                            handler: progressHandler
                        )
                    }
                )
            }
            progressHandler(1)
            return OriginalShareResources(
                photoURL: photoURL,
                photoFileExtension: photoFileExtension,
                photoMediaType: photoMediaType,
                pairedVideoURL: pairedVideoURL,
                temporaryDirectoryURL: outputDirectoryURL,
                presentationAdjustmentResourceLabels: presentationAdjustmentResourceLabels(
                    in: resources
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
            throw error
        }
    }

    private static func sharePhotoFileExtension(
        resource: PHAssetResource,
        preferredFileContainer: CapturePhotoFileContainer?
    ) throws -> String {
        if let preferredFileContainer {
            return preferredFileContainer.tapnapFileExtension
        }
        if let fileContainer = CapturePhotoFileContainer(
            imageTypeIdentifier: resource.uniformTypeIdentifier
        ) {
            return fileContainer.tapnapFileExtension
        }

        let typeExtension = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension
        let originalExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
        for candidate in [typeExtension, originalExtension].compactMap({ $0 }) {
            let normalized = candidate.lowercased()
            guard (1...12).contains(normalized.count),
                  normalized.unicodeScalars.allSatisfy({
                    CharacterSet.alphanumerics.contains($0)
                  }) else {
                continue
            }
            return normalized == "jpeg" ? "jpg" : normalized
        }
        throw TAPDepthCaptureError.invalidHEICContainerType(
            resource.uniformTypeIdentifier
        )
    }

    private static func mappedShareProgress(
        _ value: Double?,
        offset: Double,
        weight: Double,
        handler: ResourceProgressHandler
    ) {
        guard let value, value.isFinite else {
            handler(nil)
            return
        }
        handler(offset + min(max(value, 0), 1) * weight)
    }

    private static func asset(localIdentifier: String) -> PHAsset? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return nil
        }
        return PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        ).firstObject
    }

    static func deleteAsset(localIdentifier: String) async throws {
        try requireReadWriteAccess()
        guard let asset = asset(localIdentifier: localIdentifier) else {
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
        } catch {
            throw normalizedDeletionError(error)
        }
    }

    /// Cancelling Photos' confirmation must still stop downstream local cleanup.
    static func normalizedDeletionError(_ error: Error) -> Error {
        let photosError = error as NSError
        if photosError.domain == PHPhotosErrorDomain,
           photosError.code == PHPhotosError.userCancelled.rawValue {
            return CancellationError()
        }
        return error
    }

    static func depthAssetIdentifier(captureID: String) async throws -> String? {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("depthAssetIdentifier lookup start captureID=\(captureID, privacy: .private)")
        #endif
        try requireReadWriteAccess()
        return await Task.detached(priority: .userInitiated) {
            guard let album = fetchAlbum() else {
                return nil
            }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(in: album, options: options)
            let provenanceWriter = TAPCaptureProvenanceWriter()
            for index in 0..<result.count {
                let asset = result.object(at: index)
                guard let data = try? await originalPhotoData(for: asset),
                      let input = try? TAPPhotoValidationInput(data: data),
                      (try? provenanceWriter.validateSignedExportPhoto(
                        input,
                        expectedCaptureID: captureID,
                        expectedProfile: input.inferredProfile
                      )) != nil else {
                    continue
                }
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.photoLibrary.info("depthAssetIdentifier found captureID=\(captureID, privacy: .private) assetID=\(asset.localIdentifier, privacy: .private)")
                #endif
                return asset.localIdentifier
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info("depthAssetIdentifier not found captureID=\(captureID, privacy: .private) scannedCount=\(result.count, privacy: .public)")
            #endif
            return nil
        }.value
    }

    /// Returns deterministic, oldest-first recovery candidates. The resource
    /// filename is only an index hint; callers must still validate the signed
    /// manifest and byte binding before accepting any candidate.
    static func tapVideoAssetCandidateIdentifiers(packageID: UUID) async throws -> [String] {
        try requireReadWriteAccess()
        let expectedFilename = tapVideoResourceFilename(packageID: packageID)
        return await Task.detached(priority: .utility) {
            let result = PHAsset.fetchAssets(with: .video, options: nil)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            return assets
                .filter { asset in
                    PHAssetResource.assetResources(for: asset).contains { resource in
                        resource.type == .video && resource.originalFilename == expectedFilename
                    }
                }
                .sorted { lhs, rhs in
                    // TAP preserves capturedAt as Photos creationDate, so that
                    // field cannot distinguish duplicate export attempts. Photos'
                    // modificationDate is the closest available import-order
                    // signal; the opaque identifier remains a deterministic tie.
                    let lhsDate = lhs.modificationDate ?? lhs.creationDate ?? .distantFuture
                    let rhsDate = rhs.modificationDate ?? rhs.creationDate ?? .distantFuture
                    if lhsDate != rhsDate {
                        return lhsDate < rhsDate
                    }
                    return lhs.localIdentifier < rhs.localIdentifier
                }
                .map(\.localIdentifier)
        }.value
    }

    private static func writeResourceCancellable(
        _ resource: PHAssetResource,
        to fileURL: URL,
        assetLocalIdentifier: String,
        label: String,
        progressHandler: @escaping ResourceProgressHandler
    ) async throws {
        try Data().write(to: fileURL, options: .atomic)
        let request = try PhotoResourceFileRequest(
            fileURL: fileURL,
            assetLocalIdentifier: assetLocalIdentifier,
            label: label,
            progressHandler: progressHandler
        )
        try await withTaskCancellationHandler {
            try await request.start(resource: resource)
        } onCancel: {
            request.cancel()
        }
    }

    private static func presentationAdjustmentResourceLabels(
        in resources: [PHAssetResource]
    ) -> [String] {
        resources.compactMap { resource in
            switch resource.type {
            case .adjustmentData:
                "adjustmentData"
            case .adjustmentBasePhoto:
                "adjustmentBasePhoto"
            case .fullSizePairedVideo:
                "fullSizePairedVideo"
            case .adjustmentBasePairedVideo:
                "adjustmentBasePairedVideo"
            case .adjustmentBaseVideo:
                "adjustmentBaseVideo"
            default:
                nil
            }
        }
    }

    @discardableResult
    /// Photos writes and lookups consume authorization granted by the explicit
    /// setup action. Background retries must report denial instead of owning a
    /// system permission prompt.
    private static func requireReadWriteAccess() throws -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("requireReadWriteAccess current=\(String(describing: current), privacy: .public)")
        #endif
        switch current {
        case .authorized, .limited:
            return current
        case .notDetermined, .denied, .restricted:
            throw TAPDepthCaptureError.photoLibraryAccessDenied
        @unknown default:
            throw TAPDepthCaptureError.photoLibraryAccessDenied
        }
    }

    private static func fetchOrCreateAlbum() async throws -> PHAssetCollection {
        if let existing = fetchAlbum() {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info("fetchOrCreateAlbum existing name=\(albumName, privacy: .public)")
            #endif
            return existing
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("fetchOrCreateAlbum create name=\(albumName, privacy: .public)")
        #endif
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            placeholder = request.placeholderForCreatedAssetCollection
        }

        guard let localIdentifier = placeholder?.localIdentifier else {
            throw TAPDepthCaptureError.albumCreationFailed
        }

        let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let album = created.firstObject else {
            throw TAPDepthCaptureError.albumCreationFailed
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("fetchOrCreateAlbum created name=\(albumName, privacy: .public)")
        #endif
        return album
    }

    private static func createAsset(
        data: Data,
        fileContainer: CapturePhotoFileContainer,
        capturedAt: Date,
        location: CLLocation?,
        album: PHAssetCollection?,
        pairedVideoURL: URL? = nil
    ) async throws -> String {
        var placeholder: PHObjectPlaceholder?
        let resourceFilename = "tap-depth-photo.\(fileContainer.fileExtension)"
        let resourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPPhotoLibraryWriter-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(resourceFilename)

        try FileManager.default.createDirectory(
            at: resourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: resourceURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: resourceURL.deletingLastPathComponent())
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("createAsset start bytes=\(data.count, privacy: .public) album=\(album != nil, privacy: .public)")
        #endif
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.creationDate = capturedAt
            creationRequest.location = location

            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = fileContainer.uniformTypeIdentifier
            options.originalFilename = resourceFilename
            options.shouldMoveFile = false
            creationRequest.addResource(with: .photo, fileURL: resourceURL, options: options)

            if let pairedVideoURL {
                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
                videoOptions.originalFilename = TAPPendingCaptureBundlePathPolicy.pairedVideoFilename
                videoOptions.shouldMoveFile = false
                creationRequest.addResource(with: .pairedVideo, fileURL: pairedVideoURL, options: videoOptions)
            }

            placeholder = creationRequest.placeholderForCreatedAsset

            if let album,
               let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
               let placeholder {
                albumChangeRequest.addAssets([placeholder] as NSArray)
            }
        }

        guard let localIdentifier = placeholder?.localIdentifier else {
            throw TAPDepthCaptureError.assetCreationFailed
        }

        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("createAsset success assetID=\(localIdentifier, privacy: .private)")
        #endif
        return localIdentifier
    }

    private static func createVideoAsset(
        fileURL: URL,
        resourceFilename: String,
        capturedAt: Date,
        location: CLLocation?,
        album: PHAssetCollection?,
        commitWillBegin: @Sendable () async throws -> Void
    ) async throws -> String {
        guard fileURL.isFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TAPDepthCaptureError.assetCreationFailed
        }

        var placeholder: PHObjectPlaceholder?
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        let byteCount = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        TAPDiagnostics.photoLibrary.info("createVideoAsset file start bytes=\(byteCount, privacy: .public) album=\(album != nil, privacy: .public)")
        #endif
        try Task.checkCancellation()
        try await commitWillBegin()
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.creationDate = capturedAt
            creationRequest.location = location

            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.mpeg4Movie.identifier
            options.originalFilename = resourceFilename
            options.shouldMoveFile = false
            creationRequest.addResource(with: .video, fileURL: fileURL, options: options)

            placeholder = creationRequest.placeholderForCreatedAsset
            if let album,
               let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
               let placeholder {
                albumChangeRequest.addAssets([placeholder] as NSArray)
            }
        }

        guard let localIdentifier = placeholder?.localIdentifier else {
            throw TAPDepthCaptureError.assetCreationFailed
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("createVideoAsset file success assetID=\(localIdentifier, privacy: .private)")
        #endif
        return localIdentifier
    }

    private static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }
}

/// Bridges cancellation/finish state across PhotoKit APIs that return their
/// request identifier only after callbacks may already have fired.
///
/// The injected cancellation closure keeps the race logic independently
/// testable without issuing a real PhotoKit request.
nonisolated final class PhotoLibraryRequestIDCancellationBridge<RequestID: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelRequest: @Sendable (RequestID) -> Void
    private var installedRequestID: RequestID?
    private var cancellationRequested = false
    private var finishedBeforeInstall = false
    private var cancellationDelivered = false

    init(cancelRequest: @escaping @Sendable (RequestID) -> Void) {
        self.cancelRequest = cancelRequest
    }

    func install(requestID: RequestID) {
        let requestIDToCancel: RequestID?
        lock.lock()
        if installedRequestID == nil {
            installedRequestID = requestID
        }
        if !cancellationDelivered,
           cancellationRequested || finishedBeforeInstall {
            cancellationDelivered = true
            requestIDToCancel = installedRequestID
        } else {
            requestIDToCancel = nil
        }
        lock.unlock()

        if let requestIDToCancel {
            cancelRequest(requestIDToCancel)
        }
    }

    func requestCancellation() {
        let requestIDToCancel: RequestID?
        lock.lock()
        cancellationRequested = true
        if !cancellationDelivered,
           let installedRequestID {
            cancellationDelivered = true
            requestIDToCancel = installedRequestID
        } else {
            requestIDToCancel = nil
        }
        lock.unlock()

        if let requestIDToCancel {
            cancelRequest(requestIDToCancel)
        }
    }

    func markFinished() {
        lock.lock()
        if installedRequestID == nil {
            finishedBeforeInstall = true
        }
        lock.unlock()
    }
}

nonisolated private final class PhotoResourceFileRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let manager = PHAssetResourceManager.default()
    private let requestIDBridge = PhotoLibraryRequestIDCancellationBridge<PHAssetResourceDataRequestID>(
        cancelRequest: { requestID in
            PHAssetResourceManager.default().cancelDataRequest(requestID)
        }
    )
    private let fileURL: URL
    private let assetLocalIdentifier: String
    private let label: String
    private let progressHandler: PhotoLibraryWriter.ResourceProgressHandler
    private let requestStartedAt = ProcessInfo.processInfo.systemUptime
    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var cancellationRequested = false
    private var finished = false
    private var receivedByteCount = Int64(0)

    init(
        fileURL: URL,
        assetLocalIdentifier: String,
        label: String,
        progressHandler: @escaping PhotoLibraryWriter.ResourceProgressHandler
    ) throws {
        self.fileURL = fileURL
        self.assetLocalIdentifier = assetLocalIdentifier
        self.label = label
        self.progressHandler = progressHandler
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
    }

    func start(resource: PHAssetResource) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let shouldCancelBeforeStart = cancellationRequested
            lock.unlock()

            guard !shouldCancelBeforeStart else {
                finish(throwing: CancellationError())
                return
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { [weak self] progress in
                self?.progressHandler(progress.isFinite ? progress : nil)
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info(
                "\(self.label, privacy: .public) request started assetID=\(self.assetLocalIdentifier, privacy: .private) networkAccess=true"
            )
            #endif
            let requestID = manager.requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { [weak self] data in
                    self?.receive(data)
                },
                completionHandler: { [weak self] error in
                    self?.finish(throwing: error)
                }
            )
            install(requestID: requestID)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        requestIDBridge.requestCancellation()
        finish(throwing: CancellationError())
    }

    private func install(requestID: PHAssetResourceDataRequestID) {
        requestIDBridge.install(requestID: requestID)
    }

    private func receive(_ data: Data) {
        var writeError: (any Error)?
        lock.lock()
        if !finished, !cancellationRequested {
            do {
                try fileHandle?.write(contentsOf: data)
                receivedByteCount += Int64(data.count)
            } catch {
                writeError = error
            }
        }
        lock.unlock()
        if let writeError {
            requestIDBridge.requestCancellation()
            finish(throwing: writeError)
        }
    }

    private func finish(throwing error: (any Error)?) {
        requestIDBridge.markFinished()
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let fileHandle = self.fileHandle
        self.fileHandle = nil
        let receivedByteCount = self.receivedByteCount
        lock.unlock()

        try? fileHandle?.close()
        let durationMilliseconds = max(
            0,
            (ProcessInfo.processInfo.systemUptime - requestStartedAt) * 1_000
        )
        if let error {
            try? FileManager.default.removeItem(at: fileURL)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.error(
                "\(self.label, privacy: .public) request failed assetID=\(self.assetLocalIdentifier, privacy: .private) durationMs=\(durationMilliseconds, privacy: .public) receivedBytes=\(receivedByteCount, privacy: .public) error=\(TAPDiagnostics.describe(error), privacy: .public)"
            )
            #endif
            continuation?.resume(throwing: error)
        } else {
            progressHandler(1)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info(
                "\(self.label, privacy: .public) request success assetID=\(self.assetLocalIdentifier, privacy: .private) durationMs=\(durationMilliseconds, privacy: .public) receivedBytes=\(receivedByteCount, privacy: .public)"
            )
            #endif
            continuation?.resume(returning: ())
        }
    }
}

nonisolated private final class PhotoResourceDataRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let manager = PHAssetResourceManager.default()
    private let requestIDBridge = PhotoLibraryRequestIDCancellationBridge<PHAssetResourceDataRequestID>(
        cancelRequest: { requestID in
            PHAssetResourceManager.default().cancelDataRequest(requestID)
        }
    )
    private let assetLocalIdentifier: String
    private let label: String
    private let progressHandler: PhotoLibraryWriter.ResourceProgressHandler
    private let dataReceivedHandler: @Sendable (Data) throws -> Void
    private var continuation: CheckedContinuation<Void, any Error>?
    private var cancellationRequested = false
    private var finished = false

    init(
        assetLocalIdentifier: String,
        label: String,
        progressHandler: @escaping PhotoLibraryWriter.ResourceProgressHandler,
        dataReceivedHandler: @escaping @Sendable (Data) throws -> Void
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.label = label
        self.progressHandler = progressHandler
        self.dataReceivedHandler = dataReceivedHandler
    }

    func start(resource: PHAssetResource) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let shouldCancelBeforeStart = cancellationRequested
            lock.unlock()
            guard !shouldCancelBeforeStart else {
                finish(throwing: CancellationError())
                return
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { [weak self] progress in
                self?.progressHandler(progress.isFinite ? progress : nil)
            }
            let requestID = manager.requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { [weak self] data in
                    self?.receive(data)
                },
                completionHandler: { [weak self] error in
                    self?.finish(throwing: error)
                }
            )
            install(requestID: requestID)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        requestIDBridge.requestCancellation()
        finish(throwing: CancellationError())
    }

    private func install(requestID: PHAssetResourceDataRequestID) {
        requestIDBridge.install(requestID: requestID)
    }

    private func receive(_ data: Data) {
        lock.lock()
        let shouldReceive = !finished && !cancellationRequested
        lock.unlock()
        guard shouldReceive else {
            return
        }
        do {
            try dataReceivedHandler(data)
        } catch {
            requestIDBridge.requestCancellation()
            finish(throwing: error)
        }
    }

    private func finish(throwing error: (any Error)?) {
        requestIDBridge.markFinished()
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if let error {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.error("\(self.label, privacy: .public) request failed assetID=\(self.assetLocalIdentifier, privacy: .private) error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            continuation?.resume(throwing: error)
        } else {
            progressHandler(1)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info("\(self.label, privacy: .public) request success assetID=\(self.assetLocalIdentifier, privacy: .private)")
            #endif
            continuation?.resume(returning: ())
        }
    }
}

private extension CapturePhotoFileContainer {
    nonisolated var fileExtension: String {
        switch self {
        case .heic:
            "heic"
        case .jpeg:
            "jpg"
        }
    }
}
