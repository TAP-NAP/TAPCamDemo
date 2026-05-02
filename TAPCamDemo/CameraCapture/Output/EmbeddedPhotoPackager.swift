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
        let unsignedManifest = try TAPDepthManifestBuilder.makeManifest(capturePackage: capturePackage)
        let customizer = TAPPhotoFileMetadataCustomizer(
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location,
            device: capturePackage.sourceContext.sessionConfiguration.device
        )

        guard let baseHEICData = capturePackage.photo.fileDataRepresentation(with: customizer) else {
            throw TAPDepthCaptureError.unableToCreatePhotoData
        }

        let signingResult = await Self.manifestByApplyingCaptureAssertion(
            to: unsignedManifest,
            baseHEICData: baseHEICData,
            depthData: capturePackage.photo.depthData,
            capturedAt: capturePackage.sourceContext.capturedAt,
            assertionSigner: assertionSigner
        )
        let finalHEICData = try TAPDepthHEICWriter.injectingManifest(signingResult.manifest, into: baseHEICData)

        return PackagedCaptureArtifact(
            packageID: capturePackage.job.id,
            strategy: strategy,
            photoData: finalHEICData,
            manifest: signingResult.manifest,
            signatureStatus: signingResult.status,
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
    ) async -> (manifest: TAPDepthManifest, status: CaptureSignatureStatus) {
        guard let assertionSigner else {
            return (manifest, .unsigned(reason: "App Attest signer unavailable."))
        }

        do {
            guard let depthData else {
                throw TAPDepthCaptureError.missingDepthData
            }

            let contentDigest = try CaptureContentDigest.make(
                manifest: manifest,
                baseHEICData: baseHEICData,
                depthData: depthData,
                capturedAt: capturedAt
            )
            let assertionProof = try await assertionSigner.sign(
                contentDigest: contentDigest,
                capturedAt: capturedAt
            )

            return (
                TAPDepthManifest(payload: manifest.payload, proofs: [assertionProof.proof]),
                .signed(keyID: assertionProof.keyID)
            )
        } catch {
            return (manifest, .unsigned(reason: error.localizedDescription))
        }
    }
}
