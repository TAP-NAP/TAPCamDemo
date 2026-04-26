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
enum PhotoLibraryWriter {
    static let albumName = "TAPCamDepth"

    static func saveDepthHEIC(_ data: Data, capturedAt: Date, location: CLLocation?) async throws -> String {
        try await requestReadWriteAccess()
        let album = try await fetchOrCreateAlbum()
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

    private static func requestReadWriteAccess() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if requested == .authorized || requested == .limited {
                return
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
        album: PHAssetCollection
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

            if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
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
