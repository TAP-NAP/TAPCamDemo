//
//  TAPCaptureProvenanceWriter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import Foundation

/// Writes TAP provenance into embedded photo-depth artifacts.
///
/// This is the code entry for provenance work. It owns the current TAP XMP
/// manifest and App Attest proof write path, while packagers and queue workers
/// keep their focus on orchestration, storage, and retry state.
nonisolated struct TAPCaptureProvenanceWriter: Sendable {
    private static let unsignedFallbackReason = "App Attest proof unavailable during capture."

    func writeManifest(
        _ manifest: TAPDepthManifest,
        into photoData: Data
    ) throws -> TAPDepthPhotoFileWriteResult {
        try TAPDepthPhotoFileWriter.injectingManifestWithMetrics(manifest, into: photoData)
    }

    /// Shutter-time helper: attempts to add an App Attest proof, but returns an
    /// unsigned manifest when signing is unavailable. Use this only where an
    /// unsigned pending artifact is an acceptable output.
    func manifestByApplyingCaptureAssertion(
        to manifest: TAPDepthManifest,
        baseHEICData: Data,
        fileContainer: CapturePhotoFileContainer = .heic,
        depthData: AVDepthData?,
        assertionSigner: (any CaptureAssertionSigning)?
    ) async -> TAPCaptureProvenanceManifestResult {
        var metrics = CapturePackagingMetrics()

        guard let assertionSigner else {
            return TAPCaptureProvenanceManifestResult(
                manifest: manifest,
                status: .unsigned(reason: Self.unsignedFallbackReason),
                metrics: metrics
            )
        }

        do {
            guard let depthData else {
                throw TAPDepthCaptureError.missingDepthData
            }

            let digestResult = try CaptureContentDigest.makeWithMetrics(
                manifest: manifest,
                basePhotoData: baseHEICData,
                fileContainer: fileContainer,
                depthData: depthData
            )
            metrics.rgbDigestDuration = digestResult.metrics.rgbDigestDuration
            metrics.depthDigestDuration = digestResult.metrics.depthDigestDuration
            metrics.metadataDigestDuration = digestResult.metrics.metadataDigestDuration

            let appAttestStart = Date()
            let assertionProof: CaptureAssertionProof
            do {
                assertionProof = try await assertionSigner.sign(contentDigest: digestResult.digest)
                metrics.appAttestDuration = Date().timeIntervalSince(appAttestStart)
            } catch {
                metrics.appAttestDuration = Date().timeIntervalSince(appAttestStart)
                throw error
            }

            return TAPCaptureProvenanceManifestResult(
                manifest: manifest.applying(proof: assertionProof.proof),
                status: .signed(keyID: assertionProof.keyID),
                metrics: metrics
            )
        } catch {
            return TAPCaptureProvenanceManifestResult(
                manifest: manifest,
                status: .unsigned(reason: Self.unsignedFallbackReason),
                metrics: metrics
            )
        }
    }

    /// Pending-queue helper: returns a signed TAP depth photo file or throws.
    /// This path must not silently fall back to unsigned output because export
    /// requires proofed data.
    func signedPhotoData(
        from unsignedPhotoData: Data,
        expectedCaptureID: String,
        expectedProfile: CaptureOutputProfile,
        assertionSigner: any CaptureAssertionSigning
    ) async throws -> TAPCaptureProvenanceSignedPhotoResult {
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: unsignedPhotoData)
        guard fileContainer == expectedProfile.fileContainer else {
            throw TAPDepthCaptureError.invalidHEICContainerType(fileContainer.uniformTypeIdentifier)
        }

        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: unsignedPhotoData)
        try validateManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)

        guard let depthData = try TAPDepthPhotoFileReader.depthData(from: unsignedPhotoData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let digest = try CaptureContentDigest.make(
            manifest: manifest,
            basePhotoData: unsignedPhotoData,
            fileContainer: fileContainer,
            depthData: depthData
        )
        let assertionProof = try await assertionSigner.sign(contentDigest: digest)
        let signedManifest = manifest.applying(proof: assertionProof.proof)
        let writeResult = try writeManifest(signedManifest, into: unsignedPhotoData)
        _ = try validateSignedExportPhoto(
            writeResult.data,
            expectedCaptureID: expectedCaptureID,
            expectedProfile: expectedProfile
        )

        return TAPCaptureProvenanceSignedPhotoResult(
            data: writeResult.data,
            manifest: signedManifest,
            keyID: assertionProof.keyID,
            fileContainer: fileContainer
        )
    }

    /// Backward-compatible pending-queue helper for existing HEIC call sites.
    func signedHEICData(
        from unsignedHEICData: Data,
        expectedCaptureID: String,
        assertionSigner: any CaptureAssertionSigning
    ) async throws -> TAPCaptureProvenanceSignedHEICResult {
        let result = try await signedPhotoData(
            from: unsignedHEICData,
            expectedCaptureID: expectedCaptureID,
            expectedProfile: .releasePhotoDepthHEIC,
            assertionSigner: assertionSigner
        )
        return TAPCaptureProvenanceSignedHEICResult(
            data: result.data,
            manifest: result.manifest,
            keyID: result.keyID
        )
    }

    /// Final fail-closed gate before a signed TAP depth artifact may leave the
    /// app-private pending store.
    ///
    /// This re-reads the bytes that will be exported, not the earlier unsigned
    /// input. It prevents stale or corrupted signed files from reaching Photos
    /// merely because a pending record says a signed filename exists.
    func validateSignedExportPhoto(
        _ signedPhotoData: Data,
        expectedCaptureID: String,
        expectedProfile: CaptureOutputProfile
    ) throws -> ValidatedTAPDepthPhoto {
        try TAPDepthPhotoFileReader.validateContainer(
            signedPhotoData,
            expected: expectedProfile.fileContainer
        )
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: signedPhotoData)
        try validateManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)

        guard let proof = manifest.proofs.first else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }
        guard manifest.proofs.count == 1 else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("expected exactly one capture proof")
        }

        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)

        guard let depthData = try TAPDepthPhotoFileReader.depthData(from: signedPhotoData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let recomputedDigest = try CaptureContentDigest.make(
            manifest: manifest,
            basePhotoData: signedPhotoData,
            fileContainer: expectedProfile.fileContainer,
            depthData: depthData
        )
        try validateCaptureProof(
            proof,
            proofValue: proofValue,
            recomputedDigest: recomputedDigest
        )

        return ValidatedTAPDepthPhoto(
            data: signedPhotoData,
            manifest: manifest,
            fileContainer: expectedProfile.fileContainer
        )
    }

    /// Backward-compatible final gate for existing HEIC call sites.
    func validateSignedExportHEIC(
        _ signedHEICData: Data,
        expectedCaptureID: String
    ) throws -> ValidatedTAPDepthHEIC {
        let validated = try validateSignedExportPhoto(
            signedHEICData,
            expectedCaptureID: expectedCaptureID,
            expectedProfile: .releasePhotoDepthHEIC
        )
        return ValidatedTAPDepthHEIC(data: validated.data, manifest: validated.manifest)
    }

    private func validateManifestSchema(_ manifest: TAPDepthManifest) throws {
        guard manifest.schema == TAPDepthManifest.Schema() else {
            throw TAPDepthCaptureError.invalidTAPManifest("unexpected schema metadata")
        }
    }

    private func decodedCaptureProofValue(
        _ proof: TAPDepthManifest.Proof,
        expectedCaptureID: String
    ) throws -> CaptureAssertionProofValue {
        guard proof.type == "appAttestAssertion" else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("unexpected proof type")
        }
        guard proof.algorithm == "TAPCam.AppAttestCaptureSignature.v1" else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("unexpected proof algorithm")
        }
        guard let keyID = proof.keyID, !keyID.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("missing key id")
        }
        guard let encodedValue = proof.value, !encodedValue.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("missing proof value")
        }

        let proofValueData = try AppAttestBase64URL.decode(encodedValue, field: "proof.value")
        let proofValue = try JSONDecoder().decode(CaptureAssertionProofValue.self, from: proofValueData)
        guard proofValue.keyId == keyID else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof key id mismatch")
        }
        guard !proofValue.assertionObject.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("missing assertion object")
        }
        guard proofValue.contentDigest.captureID == expectedCaptureID,
              proofValue.signingBinding.captureID == expectedCaptureID else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof capture id mismatch")
        }
        return proofValue
    }

    private func validateCaptureProof(
        _ proof: TAPDepthManifest.Proof,
        proofValue: CaptureAssertionProofValue,
        recomputedDigest: CaptureContentDigest
    ) throws {
        guard proof.createdAt == recomputedDigest.capturedAt else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof timestamp does not match capture digest")
        }
        guard proofValue.contentDigest == recomputedDigest else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof digest does not match exported bytes")
        }
        let expectedSigningBinding = try CaptureSigningBinding(contentDigest: recomputedDigest)
        guard proofValue.signingBinding == expectedSigningBinding else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof signing binding does not match exported bytes")
        }
    }

    private func validateManifestID(
        _ manifestID: String,
        expectedCaptureID: String
    ) throws {
        guard manifestID == expectedCaptureID else {
            throw TAPDepthCaptureError.pendingCaptureManifestIDMismatch(
                expected: expectedCaptureID,
                actual: manifestID
            )
        }
    }
}

nonisolated struct TAPCaptureProvenanceManifestResult: Sendable {
    let manifest: TAPDepthManifest
    let status: CaptureSignatureStatus
    let metrics: CapturePackagingMetrics
}

nonisolated struct TAPCaptureProvenanceSignedPhotoResult: Sendable {
    let data: Data
    let manifest: TAPDepthManifest
    let keyID: String
    let fileContainer: CapturePhotoFileContainer
}

nonisolated struct TAPCaptureProvenanceSignedHEICResult: Sendable {
    let data: Data
    let manifest: TAPDepthManifest
    let keyID: String
}

nonisolated struct ValidatedTAPDepthPhoto: Sendable {
    let data: Data
    let manifest: TAPDepthManifest
    let fileContainer: CapturePhotoFileContainer

    init(
        data: Data,
        manifest: TAPDepthManifest,
        fileContainer: CapturePhotoFileContainer
    ) {
        self.data = data
        self.manifest = manifest
        self.fileContainer = fileContainer
    }
}

nonisolated struct ValidatedTAPDepthHEIC: Sendable {
    let data: Data
    let manifest: TAPDepthManifest

    init(data: Data, manifest: TAPDepthManifest) {
        self.data = data
        self.manifest = manifest
    }
}

private extension TAPDepthManifest {
    nonisolated func applying(proof: TAPDepthManifest.Proof) -> TAPDepthManifest {
        TAPDepthManifest(payload: payload, proofs: [proof])
    }
}
