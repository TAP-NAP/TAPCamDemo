//
//  AppAttestPendingCaptureSigner.swift
//  TAPCamDemo
//

import Foundation

struct AppAttestPendingCaptureSigner: TAPPendingCaptureSigning {
    private let signer: any CaptureAssertionSigning
    private let provenanceWriter: TAPCaptureProvenanceWriter

    init(appAttestClient: any AppAttestClient) {
        self.signer = AppAttestCaptureAssertionSigner(client: appAttestClient)
        self.provenanceWriter = TAPCaptureProvenanceWriter()
    }

    init(
        signer: any CaptureAssertionSigning,
        provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()
    ) {
        self.signer = signer
        self.provenanceWriter = provenanceWriter
    }

    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)

        switch record.artifactKind {
        case .photoDepth:
            let unsignedData = try await store.unsignedPhotoData(captureID: record.captureID)
            let pairedVideoURL = try await store.pairedVideoURL(captureID: record.captureID)
            let signedPhoto = try await provenanceWriter.signedPhotoData(
                from: unsignedData,
                expectedCaptureID: record.captureID,
                expectedContainer: record.outputProfile.fileContainer,
                assertionSigner: signer,
                pairedVideoURL: pairedVideoURL
            )
            let signedRecord = try await store.storeSignedPhoto(signedPhoto.data, captureID: record.captureID)
            return signedRecord

        case .tapVideo:
            let signingArtifact = try await store.beginVideoSigningArtifact(
                captureID: record.captureID
            )
            do {
                let signedVideo = try await provenanceWriter.signedVideoFile(
                    at: signingArtifact.fileURL,
                    expectedCaptureID: signingArtifact.captureID,
                    expectedPackageID: signingArtifact.packageID,
                    expectedPreSignContentBinding: signingArtifact.expectedPreSignContentBinding,
                    contentBindingPrepared: { binding in
                        _ = try await store.persistVideoPreSignContentBinding(
                            binding,
                            captureID: signingArtifact.captureID
                        )
                    },
                    assertionSigner: signer
                )
                guard signedVideo.fileURL.standardizedFileURL
                        == signingArtifact.fileURL.standardizedFileURL else {
                    throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                        "signed video result must match its working generation"
                    )
                }
                try Task.checkCancellation()
                let signedRecord = try await store.publishVideoSigningArtifact(
                    signingArtifact
                )
                return signedRecord
            } catch {
                try? await store.discardVideoSigningArtifact(signingArtifact)
                throw error
            }
        }
    }
}
