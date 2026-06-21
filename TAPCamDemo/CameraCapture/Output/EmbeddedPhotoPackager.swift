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
    private let provenanceWriter: TAPCaptureProvenanceWriter

    init(provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()) {
        self.provenanceWriter = provenanceWriter
    }

    /// Converts a logical package into the single Release HEIC artifact.
    ///
    /// Apple auxiliary depth remains in the HEIC, and TAP-specific metadata is
    /// injected into XMP without emitting sidecar files.
    ///
    /// - Tag: PackageEmbeddedDepthHEIC
    func package(
        _ capturePackage: CapturePackage,
        assertionSigner: (any CaptureAssertionSigning)?
    ) async throws -> PackagedCaptureArtifact {
        try capturePackage.resolvedOutput.validateForEmbeddedPhotoDepthPackaging()

        var packagingMetrics = CapturePackagingMetrics()

        let manifestBuildStart = Date()
        let unsignedManifest = try TAPDepthManifestBuilder.makeManifest(capturePackage: capturePackage)
        packagingMetrics.manifestBuildDuration = Date().timeIntervalSince(manifestBuildStart)

        let customizer = TAPPhotoFileMetadataCustomizer(
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location,
            device: capturePackage.sourceContext.sessionConfiguration.device
        )

        let baseHEICStart = Date()
        guard let baseHEICData = capturePackage.photo.fileDataRepresentation(with: customizer) else {
            throw TAPDepthCaptureError.unableToCreatePhotoData
        }
        packagingMetrics.baseHEICDuration = Date().timeIntervalSince(baseHEICStart)

        let signingResult = await provenanceWriter.manifestByApplyingCaptureAssertion(
            to: unsignedManifest,
            baseHEICData: baseHEICData,
            depthData: capturePackage.photo.depthData,
            assertionSigner: assertionSigner
        )
        packagingMetrics.rgbDigestDuration = signingResult.metrics.rgbDigestDuration
        packagingMetrics.depthDigestDuration = signingResult.metrics.depthDigestDuration
        packagingMetrics.metadataDigestDuration = signingResult.metrics.metadataDigestDuration
        packagingMetrics.appAttestDuration = signingResult.metrics.appAttestDuration

        let writeResult = try provenanceWriter.writeManifest(signingResult.manifest, into: baseHEICData)
        packagingMetrics.xmpInjectDuration = writeResult.xmpInjectDuration
        packagingMetrics.xmpVerifyDuration = writeResult.xmpVerifyDuration

        return PackagedCaptureArtifact(
            packageID: capturePackage.job.id,
            strategy: strategy,
            photoData: writeResult.data,
            manifest: signingResult.manifest,
            signatureStatus: signingResult.status,
            packagingMetrics: packagingMetrics,
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location
        )
    }
}
