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
        let writeResult = try TAPDepthPhotoFileWriter.injectingManifestWithMetrics(manifest, into: photoData)
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: writeResult.data)
        let slottedData = try TAPProofSlot.ensuringEmptySlot(
            in: writeResult.data,
            fileContainer: fileContainer
        )
        return TAPDepthPhotoFileWriteResult(
            data: slottedData,
            xmpInjectDuration: writeResult.xmpInjectDuration,
            xmpVerifyDuration: writeResult.xmpVerifyDuration
        )
    }

    /// Shutter-time helper: returns an unsigned manifest for pending storage.
    ///
    /// The fixed proof slot is reserved when the manifest is written into the
    /// photo. Actual App Attest proof creation and slot filling happen only in
    /// `signedPhotoData`, after the pending worker re-opens the saved bytes.
    func manifestByApplyingCaptureAssertion(
        to manifest: TAPDepthManifest,
        baseHEICData: Data,
        fileContainer: CapturePhotoFileContainer = .heic,
        depthData: AVDepthData?,
        assertionSigner: (any CaptureAssertionSigning)?
    ) async -> TAPCaptureProvenanceManifestResult {
        _ = baseHEICData
        _ = fileContainer
        _ = depthData
        _ = assertionSigner

        return TAPCaptureProvenanceManifestResult(
            manifest: manifest,
            status: .unsigned(reason: Self.unsignedFallbackReason),
            metrics: CapturePackagingMetrics()
        )
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

        let unsignedPhotoDataWithSlot = try TAPProofSlot.ensuringEmptySlot(
            in: unsignedPhotoData,
            fileContainer: fileContainer
        )
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: unsignedPhotoDataWithSlot)
        try validateManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)
        try validateManifestCarriesNoProofBody(manifest)

        guard let depthData = try TAPDepthPhotoFileReader.depthData(from: unsignedPhotoDataWithSlot) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let digest = try CaptureContentDigest.make(
            manifest: manifest,
            basePhotoData: unsignedPhotoDataWithSlot,
            fileContainer: fileContainer,
            depthData: depthData
        )
        let assertionProof = try await assertionSigner.sign(contentDigest: digest)
        let proofEnvelope = try JSONEncoder.tapCaptureCanonical.encode(assertionProof.proof)
        let signedPhotoData = try TAPProofSlot.writeProofEnvelope(
            proofEnvelope,
            into: unsignedPhotoDataWithSlot,
            fileContainer: fileContainer
        )
        _ = try validateSignedExportPhoto(
            signedPhotoData,
            expectedCaptureID: expectedCaptureID,
            expectedProfile: expectedProfile
        )

        return TAPCaptureProvenanceSignedPhotoResult(
            data: signedPhotoData,
            manifest: manifest,
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
        try validateManifestCarriesNoProofBody(manifest)

        let proof = try decodedCaptureProof(
            from: signedPhotoData,
            fileContainer: expectedProfile.fileContainer
        )
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

    private func validateManifestCarriesNoProofBody(_ manifest: TAPDepthManifest) throws {
        guard manifest.proofs.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("manifest proofs must not carry capture proof bodies")
        }
    }

    private func decodedCaptureProof(
        from photoData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws -> TAPDepthManifest.Proof {
        let proofData = try TAPProofSlot.proofEnvelopeData(
            from: photoData,
            fileContainer: fileContainer
        )
        return try JSONDecoder().decode(TAPDepthManifest.Proof.self, from: proofData)
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
