//
//  TAPCaptureProvenanceWriter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import Foundation

/// Writes TAP provenance into embedded HEIC artifacts.
///
/// This is the code entry for provenance work. It owns the current TAP XMP
/// manifest and App Attest proof write path, while packagers and queue workers
/// keep their focus on orchestration, storage, and retry state.
nonisolated struct TAPCaptureProvenanceWriter: Sendable {
    private static let unsignedFallbackReason = "App Attest proof unavailable during capture."

    func writeManifest(
        _ manifest: TAPDepthManifest,
        into heicData: Data
    ) throws -> TAPDepthHEICWriteResult {
        try TAPDepthHEICWriter.injectingManifestWithMetrics(manifest, into: heicData)
    }

    /// Shutter-time helper: attempts to add an App Attest proof, but returns an
    /// unsigned manifest when signing is unavailable. Use this only where an
    /// unsigned pending artifact is an acceptable output.
    func manifestByApplyingCaptureAssertion(
        to manifest: TAPDepthManifest,
        baseHEICData: Data,
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
                baseHEICData: baseHEICData,
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

    /// Pending-queue helper: returns a signed HEIC or throws. This path must not
    /// silently fall back to unsigned output because export requires proofed data.
    func signedHEICData(
        from unsignedHEICData: Data,
        expectedCaptureID: String,
        assertionSigner: any CaptureAssertionSigning
    ) async throws -> TAPCaptureProvenanceSignedHEICResult {
        let manifest = try TAPDepthHEICReader.decodedManifest(from: unsignedHEICData)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)

        guard let depthData = try TAPDepthHEICReader.depthData(from: unsignedHEICData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let digest = try CaptureContentDigest.make(
            manifest: manifest,
            baseHEICData: unsignedHEICData,
            depthData: depthData
        )
        let assertionProof = try await assertionSigner.sign(contentDigest: digest)
        let signedManifest = manifest.applying(proof: assertionProof.proof)
        let writeResult = try writeManifest(signedManifest, into: unsignedHEICData)
        _ = try validateSignedExportHEIC(
            writeResult.data,
            expectedCaptureID: expectedCaptureID
        )

        return TAPCaptureProvenanceSignedHEICResult(
            data: writeResult.data,
            manifest: signedManifest,
            keyID: assertionProof.keyID
        )
    }

    /// Final fail-closed gate before a signed TAP depth artifact may leave the
    /// app-private pending store.
    ///
    /// This re-reads the bytes that will be exported, not the earlier unsigned
    /// input. It prevents stale or corrupted `signed.heic` files from reaching
    /// Photos merely because a pending record says a signed filename exists.
    func validateSignedExportHEIC(
        _ signedHEICData: Data,
        expectedCaptureID: String
    ) throws -> ValidatedTAPDepthHEIC {
        try TAPDepthHEICReader.validateHEICContainer(signedHEICData)
        let manifest = try TAPDepthHEICReader.decodedManifest(from: signedHEICData)
        try validateManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy.releasePhotoDepthHEIC.validate(manifest.payload.capture)

        guard let proof = manifest.proofs.first else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }
        guard manifest.proofs.count == 1 else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("expected exactly one capture proof")
        }

        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)

        guard let depthData = try TAPDepthHEICReader.depthData(from: signedHEICData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let recomputedDigest = try CaptureContentDigest.make(
            manifest: manifest,
            baseHEICData: signedHEICData,
            depthData: depthData
        )
        try validateCaptureProof(
            proof,
            proofValue: proofValue,
            recomputedDigest: recomputedDigest
        )

        return ValidatedTAPDepthHEIC(data: signedHEICData, manifest: manifest)
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

nonisolated struct TAPCaptureProvenanceSignedHEICResult: Sendable {
    let data: Data
    let manifest: TAPDepthManifest
    let keyID: String
}

nonisolated struct ValidatedTAPDepthHEIC: Sendable {
    let data: Data
    let manifest: TAPDepthManifest

    fileprivate init(data: Data, manifest: TAPDepthManifest) {
        self.data = data
        self.manifest = manifest
    }
}

private extension TAPDepthManifest {
    nonisolated func applying(proof: TAPDepthManifest.Proof) -> TAPDepthManifest {
        TAPDepthManifest(payload: payload, proofs: [proof])
    }
}
