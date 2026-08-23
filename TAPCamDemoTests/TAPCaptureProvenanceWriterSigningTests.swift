//
//  TAPCaptureProvenanceWriterSigningTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureProvenanceWriterSigningTests {
    @Test func unsignedCaptureManifestKeepsProofsEmptyWhenSignerIsMissing() async throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(location: nil))
        let result = await TAPCaptureProvenanceWriter().manifestByApplyingCaptureAssertion(
            to: manifest,
            baseHEICData: Data(),
            depthData: nil,
            assertionSigner: nil
        )

        #expect(result.manifest.proofs.isEmpty)
        #expect(result.status == .unsigned(reason: "App Attest proof unavailable during capture."))
    }

    @Test func unsignedCaptureManifestUsesFixedReasonWhenProofCannotBeCreated() async throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(location: nil))
        let signer = CountingCaptureAssertionSigner()
        let result = await TAPCaptureProvenanceWriter().manifestByApplyingCaptureAssertion(
            to: manifest,
            baseHEICData: Data("not-heic".utf8),
            depthData: nil,
            assertionSigner: signer
        )
        let reason = try #require(result.unsignedReason)

        #expect(result.manifest.proofs.isEmpty)
        #expect(reason == "App Attest proof unavailable during capture.")
        #expect(!reason.contains("AVDepthData"))
        #expect(!reason.localizedCaseInsensitiveContains("localizedDescription"))
        #expect(await signer.signCallCount() == 0)
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
                expectedProfile: .releasePhotoDepthHEIC,
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
