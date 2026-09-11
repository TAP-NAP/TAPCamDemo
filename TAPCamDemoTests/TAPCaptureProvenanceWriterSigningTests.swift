//
//  TAPCaptureProvenanceWriterSigningTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureProvenanceWriterSigningTests {
    @Test func unsignedCaptureStatusUsesFixedPublicReason() throws {
        guard case .unsigned(let reason) = TAPCaptureProvenanceWriter.unsignedCaptureStatus else {
            Issue.record("Expected shutter-time packaging to remain unsigned.")
            return
        }

        #expect(reason == "App Attest proof unavailable during capture.")
    }

    @Test func pendingSigningRejectsManifestIDMismatchBeforeSignerCall() async throws {
        let embeddedManifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(
            id: "embedded-capture",
            location: nil
        ))
        let unsignedData = try TAPDepthPhotoFileWriter.injectingManifest(
            embeddedManifest,
            into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        )
        let signer = CountingCaptureAssertionSigner()

        do {
            _ = try await TAPCaptureProvenanceWriter().signedPhotoData(
                from: unsignedData,
                expectedCaptureID: "record-capture",
                expectedContainer: .heic,
                assertionSigner: signer
            )
            Issue.record("Expected manifest id mismatch to stop pending signing.")
        } catch TAPDepthCaptureError.pendingCaptureManifestIDMismatch(let expected, let actual) {
            #expect(expected == "record-capture")
            #expect(actual == "embedded-capture")
        } catch {
            Issue.record("Unexpected pending signing error: \(error)")
        }

        #expect(await signer.signCallCount() == 0)
    }
}
