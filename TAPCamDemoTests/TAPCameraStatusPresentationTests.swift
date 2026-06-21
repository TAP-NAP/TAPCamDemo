//
//  TAPCameraStatusPresentationTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraStatusPresentationTests {
    @Test func cameraCaptureStatusPresentationOmitsRawIdentifiersAndPaths() throws {
        let error = TAPDepthCaptureError.pendingCaptureManifestIDMismatch(
            expected: "expected-capture-id-1",
            actual: "actual-manifest-id-2"
        )
        let statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
        let failureReason = CameraCaptureStatusPresentation.failureReason(for: error)
        let forbiddenTokens = [
            "expected-capture-id-1",
            "actual-manifest-id-2",
            "pending/private-capture-id",
            "asset-private-id",
            "/private/",
            "unsigned.heic",
            "signed.heic",
            "bundle.json",
            "https://secret.tapnap.net",
            "token=secret-token",
            "prepared-key-id",
            "server-registered-key-id"
        ]

        #expect(statusMessage == "Capture failed. See diagnostics for details.")
        #expect(failureReason == "Capture failed; see diagnostics.")
        for text in [statusMessage, failureReason] {
            for token in forbiddenTokens {
                #expect(!text.contains(token))
            }
        }
    }

    @Test func cameraCaptureStatusPresentationRedactsAssociatedReasons() throws {
        let errors: [TAPDepthCaptureError] = [
            .invalidTAPManifest("captureID=pending/private-capture-id proof=secret-proof"),
            .pendingCaptureProofInvalid("keyID=prepared-key-id assertion=secret-assertion"),
            .imageCopyFailed("/private/var/tmp/unsigned.heic"),
            .invalidHEICContainerType("bundle.json"),
            .xmpNamespaceRegistrationFailed("https://secret.tapnap.net/sign?token=secret-token")
        ]
        let forbiddenTokens = [
            "pending/private-capture-id",
            "secret-proof",
            "prepared-key-id",
            "secret-assertion",
            "/private/var/tmp/unsigned.heic",
            "bundle.json",
            "https://secret.tapnap.net",
            "token=secret-token"
        ]

        for error in errors {
            let statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .capture)
            let failureReason = CameraCaptureStatusPresentation.failureReason(for: error)

            #expect(statusMessage == "Capture failed. See diagnostics for details.")
            #expect(failureReason == "Capture failed; see diagnostics.")
            for text in [statusMessage, failureReason] {
                for token in forbiddenTokens {
                    #expect(!text.contains(token))
                }
            }
        }
    }

    @Test func cameraCaptureStatusPresentationRedactsNSErrorDescriptionURLAndPath() throws {
        let error = NSError(
            domain: "SensitiveCameraError",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey: "secret localized /private/var/tmp/unsigned.heic https://secret.tapnap.net/sign?token=secret-token",
                NSURLErrorFailingURLErrorKey: URL(string: "https://secret.tapnap.net/sign?token=secret-token")!
            ]
        )
        let messages = [
            CameraCaptureStatusPresentation.message(for: error, context: .capture),
            CameraCaptureStatusPresentation.message(for: error, context: .configuration),
            CameraCaptureStatusPresentation.message(for: error, context: .debugConfiguration),
            CameraCaptureStatusPresentation.failureReason(for: error)
        ]
        let forbiddenTokens = [
            "secret localized",
            "/private/var/tmp/unsigned.heic",
            "https://secret.tapnap.net",
            "token=secret-token",
            "SensitiveCameraError"
        ]

        #expect(messages == [
            "Capture failed. See diagnostics for details.",
            "Camera configuration failed. See diagnostics for details.",
            "Debug camera configuration failed. See diagnostics for details.",
            "Capture failed; see diagnostics."
        ])
        for message in messages {
            for token in forbiddenTokens {
                #expect(!message.contains(token))
            }
        }
    }

    @Test func cameraCaptureStatusPresentationKeepsGenericRecoverableMessages() throws {
        #expect(
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraAccessDenied,
                context: .configuration
            ) == "Camera access is required to capture depth photos."
        )
        #expect(
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.captureBackpressureLimitReached,
                context: .capture
            ) == "Too many capture jobs are already pending."
        )
        #expect(
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.unsupportedZoomFactor,
                context: .debugConfiguration
            ) == "The selected zoom factor does not support depth delivery on this camera."
        )
        let bundlePathMessage = CameraCaptureStatusPresentation.message(
            for: TAPDepthCaptureError.invalidPendingCaptureBundlePath("/private/var/tmp/unsigned.heic"),
            context: .capture
        )
        #expect(bundlePathMessage == "The pending TAP capture bundle could not be read safely.")
        #expect(!bundlePathMessage.contains("/private/var/tmp/unsigned.heic"))
    }

    @Test func capturePipelineMetricsUsePublicSafeFailureReason() async throws {
        guard let context = Self.sampleCaptureSourceContextForMetrics() else {
            return
        }

        let metricsStore = MetricsStore()
        let error = TAPDepthCaptureError.pendingCaptureManifestIDMismatch(
            expected: "expected-capture-id-1",
            actual: "actual-manifest-id-2"
        )
        let pipeline = CapturePipeline(
            photoDepthProvider: FailingSingleCamPhotoDepthProvider(error: error),
            metricsStore: metricsStore
        )

        let result = await pipeline.runSingleCamJob(
            job: CaptureJob(id: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!),
            context: context,
            assertionSigner: nil,
            pendingJobCount: 1,
            queueWaitDuration: 0.01
        )

        guard case .failure = result else {
            Issue.record("Expected capture pipeline failure.")
            return
        }

        let metric = try #require(await metricsStore.recent().first)
        #expect(metric.failureReason == "Capture failed; see diagnostics.")
        #expect(metric.failureReason?.contains("expected-capture-id-1") == false)
        #expect(metric.failureReason?.contains("actual-manifest-id-2") == false)
    }

    private static func sampleCaptureSourceContextForMetrics() -> CaptureSourceContext? {
        let options = CameraCapabilityResolver.discover().focalLengthOptions()
        guard let option = options.first(where: \.isEnabled) else {
            return nil
        }

        let plan = CaptureSourcePlan.make(
            rgbSource: option.rgbSource,
            depthSource: option.depthSource,
            selectionMode: .automatic,
            selectedZoomID: option.zoom.id,
            selectedZoomFactor: option.zoom.rawVideoZoomFactor,
            cropRectNormalized: .fullFrame
        )
        let request = SessionConfigurationRequest(capturePlan: plan)
        guard let resolvedOutput = try? request.outputProfile.resolvedPhotoOutput(availablePhotoCodecTypes: []) else {
            return nil
        }
        let result = SessionConfigurationResult(
            depthDeliverySupported: plan.canCapturePhotoDepth,
            cameraDisplayName: option.displayName,
            nativePreviewAspectRatio: 3.0 / 4.0,
            capturePlan: plan,
            outputProfile: request.outputProfile,
            resolvedOutput: resolvedOutput,
            device: option.rgbSource.device,
            controlCapabilities: TAPCamDemoTestFixtures.sampleManualControlCapability(),
            selectionContext: request.selectionContext
        )

        return CaptureSourceContext(
            sessionConfiguration: result,
            capturedAt: Date(timeIntervalSince1970: 1_779_897_600),
            location: nil,
            suppressesShutterSound: false
        )
    }
}

private struct FailingSingleCamPhotoDepthProvider: SingleCamPhotoCaptureProvider, @unchecked Sendable {
    let error: Error

    func capturePhotoDepth(job: CaptureJob, context: CaptureSourceContext) async throws -> SingleCamPhotoCaptureResult {
        throw error
    }
}
