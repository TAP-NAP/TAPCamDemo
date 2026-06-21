//
//  TAPCaptureProvenanceTestFixtures.swift
//  TAPCamDemoTests
//

import AppAttestKit
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
        let digest = sampleContentDigest(captureID: id, capturedAt: capturedAt)
        let proofValue = CaptureAssertionProofValue(
            contentDigest: digest,
            keyId: "test-key-id",
            assertionObject: Data([0xA1, 0x01]).appAttestBase64URL,
            signingBinding: try CaptureSigningBinding(contentDigest: digest)
        )
        let proofData = try proofValue.canonicalJSONData()
        return TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(id: id, capturedAt: capturedAt, location: nil),
            proofs: [
                TAPDepthManifest.Proof(
                    type: "appAttestAssertion",
                    algorithm: "TAPCam.AppAttestCaptureSignature.v1",
                    keyID: "test-key-id",
                    createdAt: capturedAt,
                    value: proofData.appAttestBase64URL
                )
            ]
        )
    }

    static func sampleSignedHEICData(
        manifest: TAPDepthManifest,
        hasDepth: Bool
    ) throws -> Data {
        let sourceHEIC = try sampleHEICSourceData()
        let signedHEIC = try TAPDepthHEICWriter.injectingManifest(manifest, into: sourceHEIC)
        if hasDepth {
            /*
             This fixture intentionally has no Apple auxiliary depth plane.
             Tests that pass `hasDepth: true` only exercise validation checks
             that run before depth readback, such as manifest/proof rejection.
             */
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

    static func sampleContentDigest(
        captureID: String = "sample-capture",
        capturedAt: String = "2026-04-25T00:00:00.123Z"
    ) -> CaptureContentDigest {
        CaptureContentDigest(
            captureID: captureID,
            capturedAt: capturedAt,
            rgb: CaptureContentDigest.Component(
                mediaType: "image/heic-primary-rgba8",
                width: 2,
                height: 2,
                value: "rgb-digest"
            ),
            depth: CaptureContentDigest.Component(
                mediaType: "application/vnd.tapnap.depth-float32",
                width: 2,
                height: 2,
                value: "depth-digest"
            ),
            metadata: CaptureContentDigest.Component(
                mediaType: "application/vnd.tapnap.depth-manifest.payload+json;version=1",
                width: nil,
                height: nil,
                value: "metadata-digest"
            )
        )
    }
}

private extension CaptureSignatureStatus {
    var unsignedReason: String? {
        if case .unsigned(let reason) = self {
            return reason
        }
        return nil
    }
}

extension TAPCaptureProvenanceManifestResult {
    var unsignedReason: String? {
        status.unsignedReason
    }
}
