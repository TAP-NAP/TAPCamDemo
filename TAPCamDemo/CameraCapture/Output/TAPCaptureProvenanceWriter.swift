//
//  TAPCaptureProvenanceWriter.swift
//  TAPCamDemo
//

import Foundation

/// Writes TAP provenance into embedded photo-depth artifacts.
///
/// This is the code entry for provenance work. It owns the current TAP XMP
/// manifest and App Attest proof write path, while packagers and queue workers
/// keep their focus on orchestration, storage, and retry state.
nonisolated struct TAPCaptureProvenanceWriter: Sendable {
    static let unsignedCaptureStatus: CaptureSignatureStatus = .unsigned(
        reason: "App Attest proof unavailable during capture."
    )

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

    /// Pending-queue helper: returns a signed TAP depth photo file or throws.
    /// This path must not silently fall back to unsigned output because export
    /// requires proofed data.
    func signedPhotoData(
        from unsignedPhotoData: Data,
        expectedCaptureID: String,
        expectedContainer: CapturePhotoFileContainer,
        assertionSigner: any CaptureAssertionSigning,
        pairedVideoURL: URL? = nil
    ) async throws -> TAPCaptureProvenanceSignedPhotoResult {
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: unsignedPhotoData)
        guard fileContainer == expectedContainer else {
            throw TAPDepthCaptureError.invalidHEICContainerType(fileContainer.uniformTypeIdentifier)
        }

        let unsignedPhotoDataWithSlot = try TAPProofSlot.ensuringEmptySlot(
            in: unsignedPhotoData,
            fileContainer: fileContainer
        )
        let input = try TAPPhotoValidationInput(data: unsignedPhotoDataWithSlot)
        let document = input.manifestDocument
        try validateManifestID(document.captureID, expectedCaptureID: expectedCaptureID)
        let digest = try CaptureContentDigest.makePhoto(
            document: document, photoData: unsignedPhotoDataWithSlot,
            fileContainer: fileContainer, pairedVideoURL: pairedVideoURL
        )
        let assertionProof = try await assertionSigner.sign(contentDigest: digest)
        let proofEnvelope = try JSONEncoder.tapCaptureCanonical.encode(assertionProof.proof)
        let signedPhotoData = try TAPProofSlot.writeProofEnvelope(
            proofEnvelope,
            into: unsignedPhotoDataWithSlot,
            fileContainer: fileContainer
        )
        _ = try validateSignedExportPhoto(
            .init(data: signedPhotoData, expectedContainer: expectedContainer),
            expectedCaptureID: expectedCaptureID,
            pairedVideoURL: pairedVideoURL
        )

        return TAPCaptureProvenanceSignedPhotoResult(
            data: signedPhotoData,
            keyID: assertionProof.keyID,
            fileContainer: fileContainer
        )
    }

    /// Pending-queue helper for TAP signed video.
    ///
    /// The unsigned MP4 must already contain a TAP video manifest box and one
    /// empty TAP BMFF proof slot. Signing fills only that proof slot.
    func signedVideoFile(
        at videoFileURL: URL,
        expectedCaptureID: String,
        expectedPackageID: UUID,
        expectedPreSignContentBinding: CaptureContentBinding? = nil,
        contentBindingPrepared: @escaping @Sendable (CaptureContentBinding) async throws -> Void = { _ in },
        assertionSigner: any CaptureAssertionSigning
    ) async throws -> TAPSignedVideoFile {
        _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: videoFileURL)
        let document = try TAPVideoValidationInput(fileURL: videoFileURL).manifestDocument
        try validateManifestID(document.captureID, expectedCaptureID: expectedCaptureID)
        try validateVideoPackageID(document.packageID, expectedPackageID: expectedPackageID)
        try TAPProofSlot.resetBMFFProofSlot(inFileAt: videoFileURL)

        let digest = try makeTracedVideoContentDigest(
            document: document, videoFileURL: videoFileURL, purpose: "pre-sign"
        )
        if let expectedPreSignContentBinding,
           expectedPreSignContentBinding != digest {
            throw TAPDepthCaptureError.pendingCaptureProofExternalMutation
        }
        try await contentBindingPrepared(digest)
        let proofTrace = TAPVideoPerformanceTrace.beginProofGeneration()
        let assertionProof: CaptureAssertionProof
        var assertionFinished = false
        do {
            assertionProof = try await assertionSigner.sign(contentDigest: digest)
            assertionFinished = true
            TAPVideoPerformanceTrace.emitAssertionFinished(succeeded: true)
            try Task.checkCancellation()
            let videoProof = TAPVideoManifest.Proof(
                type: assertionProof.proof.type,
                algorithm: assertionProof.proof.algorithm,
                keyID: assertionProof.proof.keyID,
                createdAt: assertionProof.proof.createdAt,
                value: assertionProof.proof.value
            )
            let proofEnvelope = try JSONEncoder.tapCaptureCanonical.encode(videoProof)
            try TAPProofSlot.writeProofEnvelope(
                proofEnvelope,
                intoBMFFFileAt: videoFileURL
            )
            TAPVideoPerformanceTrace.emitProofWritten(byteCount: proofEnvelope.count)
            TAPVideoPerformanceTrace.endProofGeneration(proofTrace, succeeded: true)
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(stage: "proof-written")
        } catch {
            if !assertionFinished {
                TAPVideoPerformanceTrace.emitAssertionFinished(succeeded: false)
            }
            TAPVideoPerformanceTrace.endProofGeneration(proofTrace, succeeded: false)
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(stage: "proof-failed")
            throw error
        }
        _ = try await validateSignedExportVideoFile(
            .init(fileURL: videoFileURL),
            expectedCaptureID: expectedCaptureID,
            expectedPackageID: expectedPackageID
        )
        try Task.checkCancellation()

        return TAPSignedVideoFile(
            fileURL: videoFileURL,
            keyID: assertionProof.keyID
        )
    }

    /// Final fail-closed gate before a signed TAP depth artifact may leave the
    /// app-private pending store.
    ///
    /// This re-reads the bytes that will be exported, not the earlier unsigned
    /// input. It prevents stale or corrupted signed files from reaching Photos
    /// merely because a pending record says a signed filename exists.
    func validateSignedExportPhoto(
        _ input: TAPPhotoValidationInput,
        expectedCaptureID: String,
        pairedVideoURL: URL? = nil
    ) throws -> ValidatedTAPDepthPhoto {
        try Task<Never, Never>.checkCancellation()
        let document = input.manifestDocument
        try validateManifestID(document.captureID, expectedCaptureID: expectedCaptureID)
        guard (document.schemaID == TAPDepthManifest.livePhotoSchemaIdentifier) == (pairedVideoURL != nil) else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("photo binding resource set is incomplete")
        }
        let proof = try decodedCaptureProof(from: input.data, fileContainer: input.fileContainer)
        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)
        let digest = try CaptureContentDigest.makePhoto(
            document: document, photoData: input.data, fileContainer: input.fileContainer,
            depthResource: proofValue.contentDigest.depthResource, pairedVideoURL: pairedVideoURL
        )
        try validateCaptureProof(proofValue: proofValue, recomputedDigest: digest)
        return ValidatedTAPDepthPhoto(data: input.data, fileContainer: input.fileContainer)
    }

    func validateSignedExportLivePhoto(
        _ input: TAPPhotoValidationInput,
        pairedVideoURL: URL,
        expectedCaptureID: String
    ) throws -> ValidatedTAPLivePhoto {
        ValidatedTAPLivePhoto(
            photo: try validateSignedExportPhoto(
                input, expectedCaptureID: expectedCaptureID, pairedVideoURL: pairedVideoURL
            ),
            pairedVideoURL: pairedVideoURL
        )
    }

    /// Checks only the primary resource of a Live Photo whose MOV is unavailable.
    /// It does not certify that the complete Live Photo resource set is present.
    func validateSignedExportLivePhotoPrimaryPhoto(
        _ signedPhotoData: Data,
        expectedCaptureID: String
    ) throws -> ValidatedTAPDepthPhoto {
        let input = try TAPPhotoValidationInput(data: signedPhotoData)
        let document = input.manifestDocument
        guard document.schemaID == TAPDepthManifest.livePhotoSchemaIdentifier else {
            throw TAPDepthCaptureError.invalidTAPManifest("expected Live Photo binding schema")
        }
        try validateManifestID(document.captureID, expectedCaptureID: expectedCaptureID)
        let proof = try decodedCaptureProof(from: input.data, fileContainer: input.fileContainer)
        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)
        let digest = try CaptureContentDigest.makePhoto(
            document: document, photoData: input.data, fileContainer: input.fileContainer,
            depthResource: proofValue.contentDigest.depthResource
        )
        try validateLivePhotoPrimaryProof(
            proofValue: proofValue, recomputedPrimaryDigest: digest,
            manifestSchemaID: document.schemaID, rawManifestPayloadData: document.rawPayloadData,
            fileContainer: input.fileContainer
        )
        return ValidatedTAPDepthPhoto(data: input.data, fileContainer: input.fileContainer)
    }

    /// Final fail-closed gate before a signed TAP video may leave pending
    /// storage. This recomputes the byte binding from the exact MP4 bytes that
    /// will be exported to Photos. Media and telemetry interpretation belongs
    /// to consumers and does not affect this byte-integrity result.
    func validateSignedExportVideoFile(
        _ readInput: @autoclosure () throws -> TAPVideoValidationInput,
        expectedCaptureID: String,
        expectedPackageID: UUID? = nil
    ) async throws -> ValidatedTAPVideoFile {
        try Task<Never, Never>.checkCancellation()
        let validationPurpose = "post-proof-authentication"
        let validationTrace = TAPVideoPerformanceTrace.beginLocalValidation(
            purpose: validationPurpose
        )
        var validationSucceeded = false
        defer {
            TAPVideoPerformanceTrace.endLocalValidation(
                validationTrace,
                purpose: validationPurpose,
                succeeded: validationSucceeded
            )
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
                stage: validationSucceeded ? "local-validation-finished" : "local-validation-failed"
            )
        }
        let input = try readInput()
        let videoFileURL = input.fileURL
        let document = input.manifestDocument
        try Task<Never, Never>.checkCancellation()
        try validateManifestID(document.captureID, expectedCaptureID: expectedCaptureID)
        if let expectedPackageID {
            try validateVideoPackageID(document.packageID, expectedPackageID: expectedPackageID)
        }
        try Task<Never, Never>.checkCancellation()
        let slot = try TAPProofSlot.locateBMFF(inFileAt: videoFileURL, layout: input.layout)
        let proof = try decodedVideoCaptureProof(fromFileAt: videoFileURL, validatedSlot: slot)
        let proofValue = try decodedCaptureProofValue(
            proof,
            expectedCaptureID: expectedCaptureID
        )
        let recomputedDigest = try makeTracedVideoContentDigest(
            document: document,
            videoFileURL: videoFileURL,
            purpose: "proof-validation",
            validatedSlot: slot,
            depthResource: proofValue.contentDigest.depthResource
        )
        try Task<Never, Never>.checkCancellation()
        try validateCaptureProof(
            proofValue: proofValue,
            recomputedDigest: recomputedDigest
        )

        validationSucceeded = true
        return ValidatedTAPVideoFile(fileURL: videoFileURL)
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
        _ proof: TAPCaptureProof,
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

    private func decodedVideoCaptureProof(
        fromFileAt videoFileURL: URL,
        validatedSlot: TAPProofSlot.FileLocation
    ) throws -> TAPCaptureProof {
        let proofData = try TAPProofSlot.proofEnvelopeData(
            fromBMFFFileAt: videoFileURL, validatedSlot: validatedSlot
        )
        return try JSONDecoder().decode(TAPVideoManifest.Proof.self, from: proofData)
    }

    private func validateCaptureProof(
        proofValue: CaptureAssertionProofValue,
        recomputedDigest: CaptureContentDigest
    ) throws {
        guard proofValue.contentDigest == recomputedDigest else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof digest does not match exported bytes")
        }
        let expectedSigningBinding = try CaptureSigningBinding(contentDigest: recomputedDigest)
        guard proofValue.signingBinding == expectedSigningBinding else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof signing binding does not match exported bytes")
        }
    }

    private func validateLivePhotoPrimaryProof(
        proofValue: CaptureAssertionProofValue,
        recomputedPrimaryDigest: CaptureContentDigest,
        manifestSchemaID: String,
        rawManifestPayloadData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws {
        let digest = proofValue.contentDigest
        guard digest.schemaID == CaptureContentBinding.livePhotoSchemaIdentifier,
              digest.manifestSchemaID == manifestSchemaID,
              digest.captureID == recomputedPrimaryDigest.captureID,
              digest.capturedAt == recomputedPrimaryDigest.capturedAt,
              digest.assetHash == recomputedPrimaryDigest.assetHash,
              digest.metadataHash == recomputedPrimaryDigest.metadataHash,
              digest.proofSlot == recomputedPrimaryDigest.proofSlot,
              digest.depthResource == recomputedPrimaryDigest.depthResource else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof primary photo digest does not match exported bytes")
        }

        let expectedSigningBinding = try CaptureSigningBinding(contentDigest: digest)
        guard proofValue.signingBinding == expectedSigningBinding else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof signing binding does not match exported bytes")
        }

        guard let signedResources = digest.signedResources,
              signedResources.count == 3 else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("missing Live Photo signed resources")
        }

        let expectedPrimaryResource = CaptureContentDigest.SignedResource(
            role: "primaryPhoto",
            kind: recomputedPrimaryDigest.assetHash.kind,
            mediaType: fileContainer.uniformTypeIdentifier,
            algorithm: recomputedPrimaryDigest.assetHash.algorithm,
            byteCount: recomputedPrimaryDigest.assetHash.byteCount,
            value: recomputedPrimaryDigest.assetHash.value,
            binding: "format-native-byte-ranges",
            excludedRanges: recomputedPrimaryDigest.assetHash.excludedRanges
        )
        let expectedManifestResource = CaptureContentDigest.SignedResource(
            role: "tapDepthManifestPayload",
            kind: recomputedPrimaryDigest.metadataHash.kind,
            mediaType: recomputedPrimaryDigest.metadataHash.mediaType,
            algorithm: recomputedPrimaryDigest.metadataHash.algorithm,
            byteCount: rawManifestPayloadData.count,
            value: recomputedPrimaryDigest.metadataHash.value,
            binding: "canonical-json"
        )

        guard signedResources.contains(expectedPrimaryResource),
              signedResources.contains(expectedManifestResource),
              signedResources.contains(where: { resource in
                resource.role == "pairedLivePhotoVideo"
                    && resource.kind == "format-native-full-file"
                    && resource.mediaType == "com.apple.quicktime-movie"
                    && resource.algorithm == "SHA-256"
                    && resource.binding == "full-file"
              }) else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof Live Photo resource descriptors do not match exported bytes")
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

    private func makeTracedVideoContentDigest(
        document: TAPManifestBindingDocument,
        videoFileURL: URL,
        purpose: String,
        validatedSlot: TAPProofSlot.FileLocation? = nil,
        depthResource: CaptureContentBinding.DepthResource? = nil
    ) throws -> CaptureContentDigest {
        let trace = TAPVideoPerformanceTrace.beginContentHash(purpose: purpose)
        do {
            let digest = try CaptureContentDigest.makeVideo(
                document: document,
                mp4FileURL: videoFileURL,
                validatedSlot: validatedSlot,
                depthResource: depthResource
            )
            TAPVideoPerformanceTrace.endContentHash(
                trace,
                purpose: purpose,
                succeeded: true
            )
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
                stage: "content-hash-\(purpose)-finished"
            )
            return digest
        } catch {
            TAPVideoPerformanceTrace.endContentHash(
                trace,
                purpose: purpose,
                succeeded: false
            )
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
                stage: "content-hash-\(purpose)-failed"
            )
            throw error
        }
    }

    private func validateVideoPackageID(
        _ manifestPackageID: String?,
        expectedPackageID: UUID
    ) throws {
        guard manifestPackageID.flatMap(UUID.init(uuidString:)) == expectedPackageID else {
            throw TAPDepthCaptureError.invalidTAPManifest("video package id mismatch")
        }
    }
}

nonisolated struct TAPCaptureProvenanceSignedPhotoResult: Sendable {
    let data: Data
    let keyID: String
    let fileContainer: CapturePhotoFileContainer
}

nonisolated struct TAPSignedVideoFile: Sendable {
    let fileURL: URL
    let keyID: String
}

nonisolated struct ValidatedTAPDepthPhoto: Sendable {
    let data: Data
    let fileContainer: CapturePhotoFileContainer
}

nonisolated struct ValidatedTAPLivePhoto: Sendable {
    let photo: ValidatedTAPDepthPhoto
    let pairedVideoURL: URL
}

nonisolated struct ValidatedTAPVideoFile: Sendable {
    let fileURL: URL
}
