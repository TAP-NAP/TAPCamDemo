//
//  TAPCaptureProvenanceTestFixtures.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import TAPCamDemo

enum TAPCaptureProvenanceTestFixtures {
    static func sampleSignedManifest(id: String = "sample-capture") throws -> TAPDepthManifest {
        let capturedAt = "2026-04-25T00:00:00.000Z"
        return TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(id: id, capturedAt: capturedAt, location: nil),
            proofs: [
                try sampleCaptureProof(captureID: id, capturedAt: capturedAt)
            ]
        )
    }

    static func sampleSignedHEICData(
        manifest: TAPDepthManifest
    ) throws -> Data {
        let sourceHEIC = try sampleHEICSourceData()
        let manifestWithoutProofBody = TAPDepthManifest(payload: manifest.payload)
        let unsignedHEIC = try TAPDepthPhotoFileWriter.injectingManifest(manifestWithoutProofBody, into: sourceHEIC)
        var signedHEIC = try TAPProofSlot.ensuringEmptySlot(in: unsignedHEIC, fileContainer: .heic)
        if let proof = manifest.proofs.first {
            let proofEnvelope = try JSONEncoder.tapCaptureCanonical.encode(proof)
            signedHEIC = try TAPProofSlot.writeProofEnvelope(
                proofEnvelope,
                into: signedHEIC,
                fileContainer: .heic
            )
        }
        return signedHEIC
    }

    static func sampleHEICSourceData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
            context.cgContext.setFillColor(UIColor.systemTeal.cgColor)
            context.cgContext.fill(rect)
        }
        guard let cgImage = image.cgImage else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw TAPDepthCaptureError.imageDestinationCreationFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TAPDepthCaptureError.imageDestinationCreationFailed
        }
        return output as Data
    }

    static func sampleCaptureProof(
        captureID: String = "sample-capture",
        capturedAt: String = "2026-04-25T00:00:00.123Z"
    ) throws -> TAPDepthManifest.Proof {
        let digest = sampleContentDigest(captureID: captureID, capturedAt: capturedAt)
        let proofValue = CaptureAssertionProofValue(
            contentDigest: digest,
            keyId: "test-key-id",
            assertionObject: Data([0xA1, 0x01]).appAttestBase64URL,
            signingBinding: try CaptureSigningBinding(contentDigest: digest)
        )
        let proofData = try proofValue.canonicalJSONData()
        return TAPDepthManifest.Proof(
            type: "appAttestAssertion",
            algorithm: "TAPCam.AppAttestCaptureSignature.v1",
            keyID: "test-key-id",
            createdAt: capturedAt,
            value: proofData.appAttestBase64URL
        )
    }

    static func sampleContentDigest(
        captureID: String = "sample-capture",
        capturedAt: String = "2026-04-25T00:00:00.123Z"
    ) -> CaptureContentDigest {
        CaptureContentDigest(
            captureID: captureID,
            capturedAt: capturedAt,
            assetHash: CaptureContentDigest.AssetHash(
                fileContainer: .heic,
                byteCount: 128,
                slot: TAPProofSlot.Location(
                    kind: .bmffUUIDBox,
                    containerRange: 64..<(64 + 16),
                    payloadRange: 72..<(72 + TAPProofSlot.payloadByteCount)
                ),
                value: "asset-digest"
            ),
            metadataHash: CaptureContentDigest.MetadataHash(
                kind: "canonical-json",
                mediaType: "application/vnd.tapnap.still-photo-manifest.payload+json;version=1",
                algorithm: "SHA-256",
                value: "metadata-digest"
            ),
            proofSlot: CaptureContentDigest.ProofSlot(
                TAPProofSlot.Location(
                    kind: .bmffUUIDBox,
                    containerRange: 64..<(64 + 16),
                    payloadRange: 72..<(72 + TAPProofSlot.payloadByteCount)
                )
            ),
            depthResource: CaptureContentDigest.DepthResource(
                presence: "required",
                binding: "covered-by-assetHash",
                interpretation: "not-part-of-base-signature",
                platformPresenceCheck: "AVDepthData-readback"
            )
        )
    }
}
