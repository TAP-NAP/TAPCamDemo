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
        let authorizationStatus = try await requestReadWriteAccess()
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

    /// Backward-compatible HEIC save wrapper.
    static func saveDepthHEIC(
        _ validatedHEIC: ValidatedTAPDepthHEIC,
        capturedAt: Date,
        location: CLLocation?
    ) async throws -> String {
        try await saveDepthPhoto(
            ValidatedTAPDepthPhoto(
                data: validatedHEIC.data,
                manifest: validatedHEIC.manifest,
                fileContainer: .heic
            ),
            capturedAt: capturedAt,
            location: location
        )
    }

    static func originalPhotoData(for asset: PHAsset) async throws -> Data {
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
        try await Task.detached(priority: .userInitiated) {
            guard let asset = asset(localIdentifier: localIdentifier) else {
                throw TAPDepthCaptureError.assetNotFound
            }

            return try await originalPhotoData(for: asset)
        }.value
    }

    static func asset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    static func latestDepthAssetIfAuthorized() -> PHAsset? {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .authorized || current == .limited,
              let album = fetchAlbum() else {
            return nil
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(in: album, options: options).firstObject
    }

    static func depthAlbumAssets() async throws -> [PHAsset] {
        try await requestReadWriteAccess()
        let assets: [PHAsset] = await Task.detached(priority: .userInitiated) {
            guard let album = fetchAlbum() else {
                return [PHAsset]()
            }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(in: album, options: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            return assets
        }.value
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("depthAlbumAssets fetched count=\(assets.count, privacy: .public)")
        #endif
        return assets
    }

    static func depthAssetIdentifier(captureID: String) async throws -> String? {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("depthAssetIdentifier lookup start captureID=\(captureID, privacy: .private)")
        #endif
        let assets = try await depthAlbumAssets()
        let provenanceWriter = TAPCaptureProvenanceWriter()
        for asset in assets {
            guard let data = try? await originalPhotoData(for: asset),
                  (try? provenanceWriter.validateSignedExportPhoto(
                    data,
                    expectedCaptureID: captureID,
                    expectedProfile: .releasePhotoDepthHEIC
                  )) != nil || (try? provenanceWriter.validateSignedExportPhoto(
                    data,
                    expectedCaptureID: captureID,
                    expectedProfile: .releasePhotoDepthJPEG
                  )) != nil else {
                continue
            }
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info("depthAssetIdentifier found captureID=\(captureID, privacy: .private) assetID=\(asset.localIdentifier, privacy: .private)")
            #endif
            return asset.localIdentifier
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("depthAssetIdentifier not found captureID=\(captureID, privacy: .private) scannedCount=\(assets.count, privacy: .public)")
        #endif
        return nil
    }

    @discardableResult
    private static func requestReadWriteAccess() async throws -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.photoLibrary.info("requestReadWriteAccess current=\(String(describing: current), privacy: .public)")
        #endif
        switch current {
        case .authorized, .limited:
            return current
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.photoLibrary.info("requestReadWriteAccess requested=\(String(describing: requested), privacy: .public)")
            #endif
            if requested == .authorized || requested == .limited {
                return requested
            }
            throw TAPDepthCaptureError.photoLibraryAccessDenied
        case .denied, .restricted:
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
        album: PHAssetCollection?
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

    private static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
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
