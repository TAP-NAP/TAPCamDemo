//
//  TAPAppAttestSignatureVerificationTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPAppAttestSignatureVerificationTests {
    @Test func signatureVerificationContextUsesPublicBackendSummary() throws {
        let context = AppAttestSignatureVerificationContext(
            backendURL: try Self.url("https://secret.example.com"),
            backendPublicSummary: AppAttestBackendPresentation.configuredHTTPBackendSummary
        )
        let step = context.verificationContextStep

        #expect(step.status == .success)
        #expect(step.detail == "HTTP backend configured.")
        #expect(!step.detail.contains("secret.example.com"))
        #expect(!step.detail.contains("/tapcam/capture-signatures/verify"))
    }

    @Test func signatureVerificationSuccessReportKeepsRawVerificationMaterialOutOfVisibleText() async throws {
        let material = AppAttestSignatureVerificationRequestMaterial(
            steps: [
                AppAttestSignatureVerificationStep(
                    status: .success,
                    title: "Local signed HEIC gate",
                    detail: "Container, Release manifest policy, App Attest proof, digest binding, and auxiliary depth passed local validation."
                )
            ],
            request: CaptureSignatureVerificationRequest(
                keyId: "raw-key-id-secret",
                assertionObject: "raw-assertion-object-secret",
                signingBinding: CaptureSigningBinding(
                    bodySHA256: "raw-body-hash-secret",
                    captureID: "raw-capture-id-secret"
                )
            )
        )
        let verifier = AppAttestCaptureSignatureVerifier(
            photoDataLoader: { _ in Data([0x01, 0x02]) },
            requestMaterialBuilder: { _ in material },
            verificationSubmitter: { _, _ in
                CaptureSignatureVerificationHTTPResponse(
                    payload: CaptureSignatureVerificationResponse(
                        status: "valid",
                        keyId: "raw-key-id-secret",
                        signingBindingSHA256: "raw-signing-binding-hash-secret",
                        reason: nil
                    )
                )
            }
        )
        let report = await verifier.verify(
            assetID: "photos-local-id-secret",
            context: AppAttestSignatureVerificationContext(
                backendURL: try Self.url("https://secret.example.com"),
                backendPublicSummary: AppAttestBackendPresentation.configuredHTTPBackendSummary
            )
        )
        let visibleText = Self.visibleText(in: report)

        #expect(report.summary.state == .success)
        #expect(!visibleText.contains("raw-key-id-secret"))
        #expect(!visibleText.contains("raw-assertion-object-secret"))
        #expect(!visibleText.contains("raw-body-hash-secret"))
        #expect(!visibleText.contains("raw-capture-id-secret"))
        #expect(!visibleText.contains("raw-signing-binding-hash-secret"))
        #expect(!visibleText.contains("photos-local-id-secret"))
        #expect(!visibleText.contains("secret.example.com"))
    }

    @Test func signatureVerificationFailureReportUsesGenericVisibleErrorText() async throws {
        let failingURL = try Self.url("https://secret.example.com/private/path")
        let loaderError = NSError(
            domain: NSURLErrorDomain,
            code: -1200,
            userInfo: [
                NSURLErrorFailingURLErrorKey: failingURL,
                NSLocalizedDescriptionKey: "TLS failed for https://secret.example.com/private/path"
            ]
        )
        let verifier = AppAttestCaptureSignatureVerifier(
            photoDataLoader: { _ in throw loaderError },
            requestMaterialBuilder: { _ in
                throw AppAttestSignatureVerificationFailure(
                    title: "Unexpected",
                    detail: "Unexpected"
                )
            },
            verificationSubmitter: { _, _ in
                CaptureSignatureVerificationHTTPResponse(
                    payload: CaptureSignatureVerificationResponse(
                        status: "valid",
                        keyId: nil,
                        signingBindingSHA256: nil,
                        reason: nil
                    )
                )
            }
        )
        let report = await verifier.verify(
            assetID: "photos-local-id-secret",
            context: AppAttestSignatureVerificationContext(
                backendURL: try Self.url("https://backend.example"),
                backendPublicSummary: AppAttestBackendPresentation.configuredHTTPBackendSummary
            )
        )
        let visibleText = Self.visibleText(in: report)

        #expect(report.summary.state == .failure)
        #expect(visibleText.contains("Verification could not complete. See diagnostics for details."))
        #expect(!visibleText.contains("photos-local-id-secret"))
        #expect(!visibleText.contains("secret.example.com"))
        #expect(!visibleText.contains("/private/path"))
        #expect(!visibleText.localizedCaseInsensitiveContains("tls failed"))
    }

    @Test func signatureVerificationPanelDoesNotRenderRawVerificationSections() throws {
        let panelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift"
        )

        #expect(!panelSource.contains("rawSections"))
        #expect(!panelSource.contains("textSelection"))
        #expect(!panelSource.contains("assertionObject"))
        #expect(!panelSource.contains("endpoint"))
        #expect(!panelSource.contains("keyId"))
    }

    private static func visibleText(in report: AppAttestSignatureVerificationReport) -> String {
        ([report.summary.title] + report.steps.flatMap { [$0.title, $0.detail] })
            .joined(separator: "\n")
    }

    private static func url(_ value: String) throws -> URL {
        try #require(URL(string: value))
    }
}
