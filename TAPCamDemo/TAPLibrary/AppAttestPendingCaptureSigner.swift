//
//  AppAttestPendingCaptureSigner.swift
//  TAPCamDemo
//

import Foundation
import OSLog

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
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign start captureID=\(record.captureID, privacy: .private)")
        #endif
        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.pendingCapture.info("sign status updated captureID=\(record.captureID, privacy: .private) status=\(TAPPendingCaptureStatus.signing.rawValue, privacy: .public)")
        #endif

        switch record.artifactKind {
        case .photoDepth:
            let unsignedData = try await store.unsignedPhotoData(captureID: record.captureID)
            let pairedVideoURL = try await store.pairedVideoURL(captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign unsigned photo data loaded captureID=\(record.captureID, privacy: .private) bytes=\(unsignedData.count, privacy: .public) hasPairedVideo=\(pairedVideoURL != nil, privacy: .public)")
            #endif
            let signedPhoto = try await provenanceWriter.signedPhotoData(
                from: unsignedData,
                expectedCaptureID: record.captureID,
                expectedProfile: record.outputProfile,
                assertionSigner: signer,
                pairedVideoURL: pairedVideoURL
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign photo provenance ready captureID=\(record.captureID, privacy: .private) container=\(signedPhoto.fileContainer.rawValue, privacy: .public) manifestID=\(signedPhoto.manifest.payload.id, privacy: .private) keyID=\(signedPhoto.keyID, privacy: .private)")
            #endif
            let signedRecord = try await store.storeSignedPhoto(signedPhoto.data, captureID: record.captureID)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.pendingCapture.info("sign photo success captureID=\(record.captureID, privacy: .private) signedBytes=\(signedPhoto.data.count, privacy: .public)")
            #endif
            return signedRecord

        case .tapVideo:
            let signingArtifact = try await store.beginVideoSigningArtifact(
                captureID: record.captureID
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            let byteCount = (
                try? signingArtifact.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            ) ?? 0
            TAPDiagnostics.pendingCapture.info("sign video file loaded captureID=\(record.captureID, privacy: .private) bytes=\(byteCount, privacy: .public)")
            #endif
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
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("sign video provenance ready captureID=\(record.captureID, privacy: .private) manifestID=\(signedVideo.manifest.payload.id, privacy: .private) keyID=\(signedVideo.keyID, privacy: .private) depthSamples=\(signedVideo.manifest.payload.depthCoverage.sampleCount, privacy: .public)")
                #endif
                let signedRecord = try await store.publishVideoSigningArtifact(
                    signingArtifact
                )
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                TAPDiagnostics.pendingCapture.info("sign video success captureID=\(record.captureID, privacy: .private) file=\(TAPPendingCaptureBundlePathPolicy.videoArtifactFilename, privacy: .public)")
                #endif
                return signedRecord
            } catch {
                try? await store.discardVideoSigningArtifact(signingArtifact)
                throw error
            }
        }
    }
}
