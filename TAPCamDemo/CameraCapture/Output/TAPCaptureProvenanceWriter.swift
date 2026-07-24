//
//  TAPCaptureProvenanceWriter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import Foundation

/// Makes the trust boundary explicit for an already-signed file: authenticate
/// the bounded manifest/proof and streaming content hash before AVFoundation is
/// allowed to parse timed metadata from a Photos or recovery candidate.
nonisolated enum TAPVideoSignedFileValidationOrder {
    enum Phase: Equatable, Sendable {
        case authenticateProofAndContentBinding
        case validateActualTracks
    }

    static func phases(validatesDepthTrack: Bool) -> [Phase] {
        validatesDepthTrack
            ? [.authenticateProofAndContentBinding, .validateActualTracks]
            : [.authenticateProofAndContentBinding]
    }

    static func run(
        validatesDepthTrack: Bool,
        authenticate: () throws -> Void,
        validateActualTracks: () async throws -> Void
    ) async throws {
        for phase in phases(validatesDepthTrack: validatesDepthTrack) {
            switch phase {
            case .authenticateProofAndContentBinding:
                try authenticate()
            case .validateActualTracks:
                try await validateActualTracks()
            }
        }
    }
}

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
        assertionSigner: any CaptureAssertionSigning,
        pairedVideoURL: URL? = nil
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
        if pairedVideoURL == nil {
            try validateStillPhotoManifestSchema(manifest)
        } else {
            try validateLivePhotoManifestSchema(manifest)
        }
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)
        try validateManifestCarriesNoProofBody(manifest)

        let depthData = try TAPDepthPhotoFileReader.depthData(from: unsignedPhotoDataWithSlot)
        try validateDepthReadback(depthData, manifest: manifest)

        let digest = try CaptureContentDigest.make(
            manifest: manifest,
            basePhotoData: unsignedPhotoDataWithSlot,
            fileContainer: fileContainer,
            depthData: depthData,
            pairedVideoURL: pairedVideoURL
        )
        let assertionProof = try await assertionSigner.sign(contentDigest: digest)
        let proofEnvelope = try JSONEncoder.tapCaptureCanonical.encode(assertionProof.proof)
        let signedPhotoData = try TAPProofSlot.writeProofEnvelope(
            proofEnvelope,
            into: unsignedPhotoDataWithSlot,
            fileContainer: fileContainer
        )
        if let pairedVideoURL {
            _ = try validateSignedExportLivePhoto(
                signedPhotoData,
                pairedVideoURL: pairedVideoURL,
                expectedCaptureID: expectedCaptureID,
                expectedProfile: expectedProfile
            )
        } else {
            _ = try validateSignedExportPhoto(
                signedPhotoData,
                expectedCaptureID: expectedCaptureID,
                expectedProfile: expectedProfile
            )
        }

        return TAPCaptureProvenanceSignedPhotoResult(
            data: signedPhotoData,
            manifest: manifest,
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
        let manifest = try TAPVideoManifestBox.decodedManifest(fromFileAt: videoFileURL)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try validateVideoPackageID(manifest.payload.packageID, expectedPackageID: expectedPackageID)
        try validateVideoManifestCarriesNoProofBody(manifest)
        try TAPProofSlot.resetBMFFProofSlot(inFileAt: videoFileURL)

        let digest = try makeTracedVideoContentDigest(
            manifest: manifest,
            videoFileURL: videoFileURL,
            purpose: "pre-sign"
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
            at: videoFileURL,
            expectedCaptureID: expectedCaptureID,
            expectedPackageID: expectedPackageID,
            validatesDepthTrack: false
        )

        return TAPSignedVideoFile(
            fileURL: videoFileURL,
            manifest: manifest,
            keyID: assertionProof.keyID
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
        try validateStillPhotoManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)
        try validateManifestCarriesNoProofBody(manifest)

        let proof = try decodedCaptureProof(
            from: signedPhotoData,
            fileContainer: expectedProfile.fileContainer
        )
        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)

        let depthData = try TAPDepthPhotoFileReader.depthData(from: signedPhotoData)
        try validateDepthReadback(depthData, manifest: manifest)

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

    /// Final fail-closed gate for a signed TAP Live Photo export.
    func validateSignedExportLivePhoto(
        _ signedPhotoData: Data,
        pairedVideoURL: URL,
        expectedCaptureID: String,
        expectedProfile: CaptureOutputProfile
    ) throws -> ValidatedTAPLivePhoto {
        try TAPDepthPhotoFileReader.validateContainer(
            signedPhotoData,
            expected: expectedProfile.fileContainer
        )
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: signedPhotoData)
        try validateLivePhotoManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)
        try validateManifestCarriesNoProofBody(manifest)
        try validateManifestLivePhotoPayload(manifest)

        let proof = try decodedCaptureProof(
            from: signedPhotoData,
            fileContainer: expectedProfile.fileContainer
        )
        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)

        let depthData = try TAPDepthPhotoFileReader.depthData(from: signedPhotoData)
        try validateDepthReadback(depthData, manifest: manifest)

        let recomputedDigest = try CaptureContentDigest.make(
            manifest: manifest,
            basePhotoData: signedPhotoData,
            fileContainer: expectedProfile.fileContainer,
            depthData: depthData,
            pairedVideoURL: pairedVideoURL
        )
        try validateCaptureProof(
            proof,
            proofValue: proofValue,
            recomputedDigest: recomputedDigest
        )

        return ValidatedTAPLivePhoto(
            photo: ValidatedTAPDepthPhoto(
                data: signedPhotoData,
                manifest: manifest,
                fileContainer: expectedProfile.fileContainer
            ),
            pairedVideoURL: pairedVideoURL
        )
    }

    /// Partial gate for exporting the primary photo from an incomplete saved
    /// Live Photo. This validates the signed still resource and the proof's
    /// internal Live Photo binding, but it deliberately does not mark the Live
    /// Photo as complete when the paired MOV is unavailable.
    func validateSignedExportLivePhotoPrimaryPhoto(
        _ signedPhotoData: Data,
        expectedCaptureID: String,
        expectedProfile: CaptureOutputProfile
    ) throws -> ValidatedTAPDepthPhoto {
        try TAPDepthPhotoFileReader.validateContainer(
            signedPhotoData,
            expected: expectedProfile.fileContainer
        )
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: signedPhotoData)
        try validateLivePhotoManifestSchema(manifest)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try CaptureOutputManifestPolicy(profile: expectedProfile).validate(manifest.payload.capture)
        try validateManifestCarriesNoProofBody(manifest)
        try validateManifestLivePhotoPayload(manifest)

        let proof = try decodedCaptureProof(
            from: signedPhotoData,
            fileContainer: expectedProfile.fileContainer
        )
        let proofValue = try decodedCaptureProofValue(proof, expectedCaptureID: expectedCaptureID)

        let depthData = try TAPDepthPhotoFileReader.depthData(from: signedPhotoData)
        try validateDepthReadback(depthData, manifest: manifest)

        let recomputedPrimaryDigest = try CaptureContentDigest.make(
            manifest: manifest,
            basePhotoData: signedPhotoData,
            fileContainer: expectedProfile.fileContainer,
            depthData: depthData
        )
        try validateLivePhotoPrimaryProof(
            proof,
            proofValue: proofValue,
            recomputedPrimaryDigest: recomputedPrimaryDigest,
            manifest: manifest,
            fileContainer: expectedProfile.fileContainer
        )

        return ValidatedTAPDepthPhoto(
            data: signedPhotoData,
            manifest: manifest,
            fileContainer: expectedProfile.fileContainer
        )
    }

    /// Final fail-closed gate before a signed TAP video may leave pending
    /// storage. This recomputes the byte binding from the exact MP4 bytes that
    /// will be exported to Photos. Timed-track semantic validation is an
    /// explicitly requested health check; it is not part of signing or export
    /// authenticity.
    func validateSignedExportVideoFile(
        at videoFileURL: URL,
        expectedCaptureID: String,
        expectedPackageID: UUID,
        validatesDepthTrack: Bool = false
    ) async throws -> ValidatedTAPVideoFile {
        let validationPurpose = validatesDepthTrack
            ? "signed-export-full"
            : "post-proof-authentication"
        let validationTrace = TAPVideoPerformanceTrace.beginLocalValidation(
            purpose: validationPurpose,
            validatesDepthTrack: validatesDepthTrack
        )
        var validationSucceeded = false
        defer {
            TAPVideoPerformanceTrace.endLocalValidation(
                validationTrace,
                purpose: validationPurpose,
                validatesDepthTrack: validatesDepthTrack,
                succeeded: validationSucceeded
            )
            TAPVideoPerformanceTrace.emitRuntimeCheckpoint(
                stage: validationSucceeded ? "local-validation-finished" : "local-validation-failed"
            )
        }
        let manifest = try TAPVideoManifestBox.decodedManifest(fromFileAt: videoFileURL)
        try validateManifestID(manifest.payload.id, expectedCaptureID: expectedCaptureID)
        try validateVideoPackageID(manifest.payload.packageID, expectedPackageID: expectedPackageID)
        try validateVideoManifestCarriesNoProofBody(manifest)
        try await TAPVideoSignedFileValidationOrder.run(
            validatesDepthTrack: validatesDepthTrack,
            authenticate: {
                let proof = try decodedVideoCaptureProof(fromFileAt: videoFileURL)
                let proofValue = try decodedVideoCaptureProofValue(
                    proof,
                    expectedCaptureID: expectedCaptureID
                )
                let recomputedDigest = try makeTracedVideoContentDigest(
                    manifest: manifest,
                    videoFileURL: videoFileURL,
                    purpose: "proof-validation"
                )
                try validateVideoCaptureProof(
                    proof,
                    proofValue: proofValue,
                    recomputedDigest: recomputedDigest
                )
            },
            validateActualTracks: {
                try validateVideoManifestSchema(manifest)
                try await TAPVideoDepthTrackValidator.validate(
                    fileURL: videoFileURL,
                    manifest: manifest
                )
            }
        )

        validationSucceeded = true
        return ValidatedTAPVideoFile(fileURL: videoFileURL, manifest: manifest)
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

    private func validateStillPhotoManifestSchema(_ manifest: TAPDepthManifest) throws {
        guard manifest.schema == TAPDepthManifest.Schema() else {
            throw TAPDepthCaptureError.invalidTAPManifest("unexpected schema metadata")
        }
    }

    private func validateLivePhotoManifestSchema(_ manifest: TAPDepthManifest) throws {
        guard manifest.schema == TAPDepthManifest.Schema.livePhotoV2 else {
            throw TAPDepthCaptureError.invalidTAPManifest("unexpected Live Photo schema metadata")
        }
    }

    private func validateVideoManifestSchema(_ manifest: TAPVideoManifest) throws {
        guard manifest.schema == TAPVideoManifest.Schema() else {
            throw TAPDepthCaptureError.invalidTAPManifest("unexpected video schema metadata")
        }
        let rgbTrack = manifest.payload.rgbTrack
        guard rgbTrack.trackID != nil,
              !rgbTrack.codec.isEmpty,
              rgbTrack.width > 0,
              rgbTrack.height > 0,
              rgbTrack.durationSeconds.isFinite,
              rgbTrack.durationSeconds >= 0,
              rgbTrack.timeScale > 0 else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "video manifest RGB track facts are incomplete"
            )
        }

        let audioTrack = manifest.payload.audioTrack
        if audioTrack.status == .captured {
            guard audioTrack.trackID != nil,
                  audioTrack.codec?.isEmpty == false,
                  let audioDurationSeconds = audioTrack.durationSeconds,
                  audioDurationSeconds.isFinite,
                  audioDurationSeconds >= 0,
                  let audioTimeScale = audioTrack.timeScale,
                  audioTimeScale > 0 else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "video manifest audio track facts are incomplete"
                )
            }
        }

        let depthCoverage = manifest.payload.depthCoverage
        guard depthCoverage.sampleCount > 0,
              depthCoverage.trackID != nil,
              depthCoverage.trackCodec?.isEmpty == false,
              let depthDurationSeconds = depthCoverage.trackDurationSeconds,
              depthDurationSeconds.isFinite,
              depthDurationSeconds >= 0,
              let depthTimeScale = depthCoverage.trackTimeScale,
              depthTimeScale > 0,
              depthCoverage.format != nil else {
            throw TAPDepthCaptureError.missingDepthData
        }
        guard Set([
            rgbTrack.trackID,
            audioTrack.trackID,
            depthCoverage.trackID
        ].compactMap { $0 }).count == [
            rgbTrack.trackID,
            audioTrack.trackID,
            depthCoverage.trackID
        ].compactMap({ $0 }).count,
              manifest.payload.container.trackCount >= 2,
              manifest.payload.container.durationSeconds.isFinite,
              manifest.payload.container.durationSeconds >= 0,
              manifest.payload.container.timeScale > 0,
              depthCoverage.deliveredSampleCount >= depthCoverage.sampleCount,
              depthCoverage.outputDropCount >= 0,
              depthCoverage.encodingDropCount >= 0,
              depthCoverage.metadataDropCount >= 0,
              depthCoverage.gapCount == depthCoverage.gaps.count,
              depthCoverage.gaps.count <= TAPVideoManifest.DepthCoverage.maximumGapCount,
              depthCoverage.gaps.allSatisfy({
                  Self.isValidDepthGap(
                      $0,
                      durationSeconds: manifest.payload.container.durationSeconds
                  )
              }) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "video manifest track, counter, or depth-gap facts are inconsistent"
            )
        }

        let registration = manifest.payload.spatialRegistration
        let calibrationCoverage = registration.calibrationCoverage
        guard registration.calibrationTable.count
                <= TAPVideoManifest.SpatialRegistration.maximumCalibrationCount,
              calibrationCoverage.indexedSampleCount >= 0,
              calibrationCoverage.missingCalibrationSampleCount >= 0,
              calibrationCoverage.overflowUnindexedSampleCount >= 0,
              calibrationCoverage.accountedSampleCount == depthCoverage.sampleCount,
              calibrationCoverage.indexedSampleCount == 0
                || !registration.calibrationTable.isEmpty,
              calibrationCoverage.tableOverflowed
                || calibrationCoverage.overflowUnindexedSampleCount == 0,
              !calibrationCoverage.tableOverflowed
                || registration.calibrationTable.count
                    == TAPVideoManifest.SpatialRegistration.maximumCalibrationCount,
              registration.status != .approximate,
              registration.status != .registered
                || registration.descriptor != nil,
              registration.status != .unavailable || registration.descriptor == nil else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "video registration descriptor is inconsistent"
            )
        }
    }

    private static func isValidDepthGap(
        _ gap: TAPVideoManifest.DepthGap,
        durationSeconds: Double
    ) -> Bool {
        guard gap.startPTS.timescale > 0,
              gap.endPTS.timescale > 0 else {
            return false
        }
        let start = Double(gap.startPTS.value) / Double(gap.startPTS.timescale)
        let end = Double(gap.endPTS.value) / Double(gap.endPTS.timescale)
        return start.isFinite
            && end.isFinite
            && start >= 0
            && end >= start
            && end <= durationSeconds + 0.1
    }

    private func validateManifestLivePhotoPayload(_ manifest: TAPDepthManifest) throws {
        guard let livePhoto = manifest.payload.livePhoto,
              livePhoto.presence == "paired-video",
              livePhoto.pairedVideoFilename == "paired-video.mov" else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing Live Photo paired video metadata")
        }
    }

    private func validateManifestCarriesNoProofBody(_ manifest: TAPDepthManifest) throws {
        guard manifest.proofs.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("manifest proofs must not carry capture proof bodies")
        }
    }

    private func validateVideoManifestCarriesNoProofBody(_ manifest: TAPVideoManifest) throws {
        guard manifest.proofs.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("video manifest proofs must not carry capture proof bodies")
        }
    }

    private func validateDepthReadback(
        _ depthData: AVDepthData?,
        manifest: TAPDepthManifest
    ) throws {
        guard manifest.payload.capture.depthAvailability == manifest.payload.depth.availability else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "manifest capture and depth availability disagree"
            )
        }

        switch manifest.payload.depth.availability {
        case .available:
            guard depthData != nil else {
                throw TAPDepthCaptureError.missingDepthData
            }
        case .unavailable:
            guard depthData == nil else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "manifest marks depth unavailable but the photo contains auxiliary depth"
                )
            }
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

    private func decodedVideoCaptureProof(
        fromFileAt videoFileURL: URL
    ) throws -> TAPVideoManifest.Proof {
        let proofData = try TAPProofSlot.proofEnvelopeData(fromBMFFFileAt: videoFileURL)
        return try JSONDecoder().decode(TAPVideoManifest.Proof.self, from: proofData)
    }

    private func decodedVideoCaptureProofValue(
        _ proof: TAPVideoManifest.Proof,
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

    private func validateVideoCaptureProof(
        _ proof: TAPVideoManifest.Proof,
        proofValue: CaptureAssertionProofValue,
        recomputedDigest: CaptureContentDigest
    ) throws {
        guard proof.createdAt == recomputedDigest.capturedAt else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof timestamp does not match capture digest")
        }
        guard proofValue.contentDigest == recomputedDigest else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof digest does not match exported video bytes")
        }
        let expectedSigningBinding = try CaptureSigningBinding(contentDigest: recomputedDigest)
        guard proofValue.signingBinding == expectedSigningBinding else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof signing binding does not match exported video bytes")
        }
    }

    private func validateLivePhotoPrimaryProof(
        _ proof: TAPDepthManifest.Proof,
        proofValue: CaptureAssertionProofValue,
        recomputedPrimaryDigest: CaptureContentDigest,
        manifest: TAPDepthManifest,
        fileContainer: CapturePhotoFileContainer
    ) throws {
        let digest = proofValue.contentDigest
        guard proof.createdAt == recomputedPrimaryDigest.capturedAt else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof timestamp does not match capture digest")
        }
        guard digest.schemaID == CaptureContentBinding.livePhotoSchemaIdentifier,
              digest.manifestSchemaID == manifest.schema.id,
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

        let payloadData = try TAPDepthManifestEncoder.payloadDataExcludingProofs(manifest.payload)
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
            byteCount: payloadData.count,
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
        manifest: TAPVideoManifest,
        videoFileURL: URL,
        purpose: String
    ) throws -> CaptureContentDigest {
        let trace = TAPVideoPerformanceTrace.beginContentHash(purpose: purpose)
        do {
            let digest = try CaptureContentDigest.makeVideo(
                manifest: manifest,
                mp4FileURL: videoFileURL
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
        _ manifestPackageID: String,
        expectedPackageID: UUID
    ) throws {
        guard UUID(uuidString: manifestPackageID) == expectedPackageID else {
            throw TAPDepthCaptureError.invalidTAPManifest("video package id mismatch")
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

nonisolated struct TAPSignedVideoFile: Sendable {
    let fileURL: URL
    let manifest: TAPVideoManifest
    let keyID: String
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

nonisolated struct ValidatedTAPLivePhoto: Sendable {
    let photo: ValidatedTAPDepthPhoto
    let pairedVideoURL: URL
}

nonisolated struct ValidatedTAPVideoFile: Sendable {
    let fileURL: URL
    let manifest: TAPVideoManifest
}

nonisolated struct ValidatedTAPDepthHEIC: Sendable {
    let data: Data
    let manifest: TAPDepthManifest

    init(data: Data, manifest: TAPDepthManifest) {
        self.data = data
        self.manifest = manifest
    }
}
