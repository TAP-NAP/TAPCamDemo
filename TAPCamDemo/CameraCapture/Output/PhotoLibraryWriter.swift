//
//  PhotoLibraryWriter.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import CoreLocation
import Foundation
import Photos
import UniformTypeIdentifiers

/// Saves final TAP depth HEIC bytes into the user's Photos library.
///
/// Photos is treated as storage for the finished file, not as the source of
/// metadata truth. To parse a saved asset later, request the original `.photo`
/// resource bytes with `PHAssetResourceManager` and then use `TAPDepthHEICReader`.
nonisolated enum PhotoLibraryWriter {
    static let albumName = "TAPCamDepth"

    /// Saves final embedded HEIC bytes to Photos.
    ///
    /// This writer receives a completed artifact; it does not inspect cameras,
    /// choose packaging policy, or mutate capture session state. Full Photos
    /// access also adds the asset to the TAPCamDepth album; limited access saves
    /// the app-created asset directly and relies on its returned local identifier.
    ///
    /// - Tag: SaveDepthHEICToPhotos
    static func saveDepthHEIC(_ data: Data, capturedAt: Date, location: CLLocation?) async throws -> String {
        let authorizationStatus = try await requestReadWriteAccess()
        let album: PHAssetCollection? = authorizationStatus == .authorized
            ? try await fetchOrCreateAlbum()
            : nil
        return try await createAsset(data: data, capturedAt: capturedAt, location: location, album: album)
    }

    static func originalPhotoData(for asset: PHAsset) async throws -> Data {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
            throw TAPDepthCaptureError.assetCreationFailed
        }

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
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            )
        }
    }

    /// Reads original HEIC bytes by resolving the asset inside a detached task.
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
        return await Task.detached(priority: .userInitiated) {
            guard let album = fetchAlbum() else {
                return []
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
    }

    static func depthAssetIdentifier(captureID: String) async throws -> String? {
        let assets = try await depthAlbumAssets()
        for asset in assets {
            guard let data = try? await originalPhotoData(for: asset),
                  let manifest = try? TAPDepthHEICReader.decodedManifest(from: data),
                  manifest.payload.id == captureID else {
                continue
            }
            return asset.localIdentifier
        }
        return nil
    }

    @discardableResult
    private static func requestReadWriteAccess() async throws -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return current
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
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
            return existing
        }

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

        return album
    }

    private static func createAsset(
        data: Data,
        capturedAt: Date,
        location: CLLocation?,
        album: PHAssetCollection?
    ) async throws -> String {
        var placeholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.creationDate = capturedAt
            creationRequest.location = location

            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.heic.identifier
            creationRequest.addResource(with: .photo, data: data, options: options)

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

        return localIdentifier
    }

    private static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }
}
