//
//  EmbeddedPhotoPackager.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Foundation

/// Default Release-safe packager.
///
/// It preserves Apple's HEIC photo-depth output using
/// `AVCapturePhoto.fileDataRepresentation(with:)`, then injects TAP's XMP
/// manifest without creating sidecars. This is the only packaging strategy used
/// by the app in Release.
nonisolated struct EmbeddedPhotoPackager: CapturePackager {
    let strategy: PackagingStrategy = .embeddedPhoto

    /// Converts a logical package into the single Release HEIC artifact.
    ///
    /// Apple auxiliary depth remains in the HEIC, and TAP-specific metadata is
    /// injected into XMP without emitting sidecar files.
    ///
    /// - Tag: PackageEmbeddedDepthHEIC
    func package(_ capturePackage: CapturePackage) async throws -> PackagedCaptureArtifact {
        let manifest = try TAPDepthManifestBuilder.makeManifest(capturePackage: capturePackage)
        let customizer = TAPPhotoFileMetadataCustomizer(
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location,
            device: capturePackage.sourceContext.sessionConfiguration.device
        )

        guard let baseHEICData = capturePackage.photo.fileDataRepresentation(with: customizer) else {
            throw TAPDepthCaptureError.unableToCreatePhotoData
        }

        let finalHEICData = try TAPDepthHEICWriter.injectingManifest(manifest, into: baseHEICData)
        return PackagedCaptureArtifact(
            packageID: capturePackage.job.id,
            strategy: strategy,
            photoData: finalHEICData,
            manifest: manifest,
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location
        )
    }
}
