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
    func package(
        _ capturePackage: CapturePackage,
        assertionSigner: (any CaptureAssertionSigning)?
    ) async throws -> PackagedCaptureArtifact {
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

        let signingResult = await Self.manifestByApplyingCaptureAssertion(
            to: unsignedManifest,
            baseHEICData: baseHEICData,
            depthData: capturePackage.photo.depthData,
            capturedAt: capturePackage.sourceContext.capturedAt,
            assertionSigner: assertionSigner
        )
        packagingMetrics.rgbDigestDuration = signingResult.metrics.rgbDigestDuration
        packagingMetrics.depthDigestDuration = signingResult.metrics.depthDigestDuration
        packagingMetrics.metadataDigestDuration = signingResult.metrics.metadataDigestDuration
        packagingMetrics.appAttestDuration = signingResult.metrics.appAttestDuration

        let writeResult = try TAPDepthHEICWriter.injectingManifestWithMetrics(signingResult.manifest, into: baseHEICData)
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

    static func manifestByApplyingCaptureAssertion(
        to manifest: TAPDepthManifest,
        baseHEICData: Data,
        depthData: AVDepthData?,
        capturedAt: Date,
        assertionSigner: (any CaptureAssertionSigning)?
    ) async -> (manifest: TAPDepthManifest, status: CaptureSignatureStatus, metrics: CapturePackagingMetrics) {
        var metrics = CapturePackagingMetrics()

        guard let assertionSigner else {
            return (manifest, .unsigned(reason: "App Attest signer unavailable."), metrics)
        }

        do {
            guard let depthData else {
                throw TAPDepthCaptureError.missingDepthData
            }

            let digestResult = try CaptureContentDigest.makeWithMetrics(
                manifest: manifest,
                baseHEICData: baseHEICData,
                depthData: depthData,
                capturedAt: capturedAt
            )
            metrics.rgbDigestDuration = digestResult.metrics.rgbDigestDuration
            metrics.depthDigestDuration = digestResult.metrics.depthDigestDuration
            metrics.metadataDigestDuration = digestResult.metrics.metadataDigestDuration

            let appAttestStart = Date()
            let assertionProof: CaptureAssertionProof
            do {
                assertionProof = try await assertionSigner.sign(
                    contentDigest: digestResult.digest,
                    capturedAt: capturedAt
                )
                metrics.appAttestDuration = Date().timeIntervalSince(appAttestStart)
            } catch {
                metrics.appAttestDuration = Date().timeIntervalSince(appAttestStart)
                throw error
            }

            return (
                TAPDepthManifest(payload: manifest.payload, proofs: [assertionProof.proof]),
                .signed(keyID: assertionProof.keyID),
                metrics
            )
        } catch {
            return (manifest, .unsigned(reason: error.localizedDescription), metrics)
        }
    }
}
