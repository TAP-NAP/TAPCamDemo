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
                    title: "Local signed photo gate",
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

    @Test func signatureVerificationWarningReportKeepsRawVerificationMaterialOutOfVisibleText() async throws {
        let warningStep = AppAttestSignatureVerificationStep(
            status: .warning,
            title: "Photos presentation warning",
            detail: "Photos has presentation resources: adjustmentData. Verification covers original .photo and .pairedVideo only."
        )
        let material = AppAttestSignatureVerificationRequestMaterial(
            steps: [warningStep],
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
            photoDataLoader: { _ in Data([0x03, 0x04]) },
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

        #expect(report.summary.state == .warning)
        #expect(report.summary.title == "Warnings")
        #expect(report.firstAttentionStepID == warningStep.id)
        #expect(!visibleText.contains("raw-key-id-secret"))
        #expect(!visibleText.contains("raw-assertion-object-secret"))
        #expect(!visibleText.contains("raw-body-hash-secret"))
        #expect(!visibleText.contains("raw-capture-id-secret"))
        #expect(!visibleText.contains("raw-signing-binding-hash-secret"))
        #expect(!visibleText.contains("photos-local-id-secret"))
        #expect(!visibleText.contains("secret.example.com"))
    }

    @Test func signatureVerificationFailureReportPrioritizesFailureOverWarning() async throws {
        let warningStep = AppAttestSignatureVerificationStep(
            status: .warning,
            title: "Photos presentation warning",
            detail: "Photos has presentation resources: fullSizePairedVideo."
        )
        let material = AppAttestSignatureVerificationRequestMaterial(
            steps: [warningStep],
            request: CaptureSignatureVerificationRequest(
                keyId: "key",
                assertionObject: "assertion",
                signingBinding: CaptureSigningBinding(
                    bodySHA256: "body",
                    captureID: "capture"
                )
            )
        )
        let verifier = AppAttestCaptureSignatureVerifier(
            photoDataLoader: { _ in Data([0x05, 0x06]) },
            requestMaterialBuilder: { _ in material },
            verificationSubmitter: { _, _ in
                CaptureSignatureVerificationHTTPResponse(
                    payload: CaptureSignatureVerificationResponse(
                        status: "invalid",
                        keyId: nil,
                        signingBindingSHA256: nil,
                        reason: "rejected"
                    )
                )
            }
        )
        let report = await verifier.verify(
            assetID: "asset-id",
            context: AppAttestSignatureVerificationContext(
                backendURL: try Self.url("https://backend.example"),
                backendPublicSummary: AppAttestBackendPresentation.configuredHTTPBackendSummary
            )
        )

        #expect(report.summary.state == .failure)
        #expect(report.summary.title == "Failed")
        #expect(report.firstAttentionStepID == report.steps.first(where: { $0.status == .failure })?.id)
        #expect(report.firstAttentionStepID != warningStep.id)
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

    @Test func signatureVerificationPanelSupportsWarningStateAndAttentionJump() throws {
        let panelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift"
        )

        #expect(panelSource.contains("ScrollViewReader"))
        #expect(panelSource.contains("firstAttentionStepID"))
        #expect(panelSource.contains("exclamationmark.triangle.fill"))
        #expect(panelSource.contains("proxy.scrollTo(stepID, anchor: .center)"))
    }

    @Test func signatureVerificationSeparatesStillPhotoAndLivePhotoLocalGates() throws {
        let verifierSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AppAttestSignatureVerification.swift"
        )
        let writerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift"
        )

        #expect(verifierSource.contains("validateSignedExportPhoto"))
        #expect(verifierSource.contains("validateSignedExportLivePhoto"))
        #expect(verifierSource.contains("TAPDepthManifest.Schema.livePhotoV2"))
        #expect(verifierSource.contains("Saved Live Photo is missing its original paired video resource."))
        #expect(writerSource.contains("resources.first(where: { $0.type == .pairedVideo })"))
        #expect(writerSource.contains("presentationAdjustmentResourceLabels"))
        #expect(writerSource.contains("fullSizePairedVideo"))
        #expect(writerSource.contains("adjustmentBasePairedVideo"))
        #expect(writerSource.contains("adjustmentData"))
    }

    private static func visibleText(in report: AppAttestSignatureVerificationReport) -> String {
        ([report.summary.title] + report.steps.flatMap { [$0.title, $0.detail] })
            .joined(separator: "\n")
    }

    private static func url(_ value: String) throws -> URL {
        try #require(URL(string: value))
    }
}
