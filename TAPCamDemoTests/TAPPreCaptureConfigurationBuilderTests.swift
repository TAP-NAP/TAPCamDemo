//
//  TAPPreCaptureConfigurationBuilderTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPPreCaptureConfigurationBuilderTests {
    @Test func preCaptureSnapshotUpdatesPlanAndSelectionContextCrop() throws {
        guard let option = Self.enabledFocalLengthOption() else {
            return
        }
        let activePlan = Self.capturePlan(option: option, crop: .fullFrame)
        let activeConfiguration = try Self.sessionConfigurationResult(
            plan: activePlan,
            cameraDisplayName: option.displayName,
            device: option.rgbSource.device
        )
        let captureCrop = CropRectNormalized(x: 0.125, y: 0.25, width: 0.5, height: 0.625)

        let snapshot = PreCaptureConfigurationBuilder.configuration(
            from: activeConfiguration,
            previewCropRectNormalized: captureCrop
        )

        #expect(activeConfiguration.capturePlan.cropPolicy.cropRectNormalized == .fullFrame)
        #expect(snapshot.capturePlan.cropPolicy.cropRectNormalized == captureCrop)
        #expect(snapshot.selectionContext.cropRectNormalized == captureCrop)
    }

    @Test func preCaptureSnapshotPreservesRuntimeExecutionFacts() throws {
        guard let option = Self.enabledFocalLengthOption() else {
            return
        }
        let activePlan = Self.capturePlan(option: option, crop: .fullFrame)
        let activeConfiguration = try Self.sessionConfigurationResult(
            plan: activePlan,
            cameraDisplayName: option.displayName,
            device: option.rgbSource.device,
            nativePreviewAspectRatio: 1.25
        )

        let snapshot = PreCaptureConfigurationBuilder.configuration(
            from: activeConfiguration,
            previewCropRectNormalized: CropRectNormalized(x: 0.05, y: 0.1, width: 0.8, height: 0.7)
        )

        #expect(snapshot.outputProfile == activeConfiguration.outputProfile)
        #expect(snapshot.resolvedOutput == activeConfiguration.resolvedOutput)
        #expect(snapshot.device.uniqueID == activeConfiguration.device.uniqueID)
        #expect(snapshot.controlCapabilities == activeConfiguration.controlCapabilities)
        #expect(snapshot.cameraDisplayName == activeConfiguration.cameraDisplayName)
        #expect(snapshot.nativePreviewAspectRatio == activeConfiguration.nativePreviewAspectRatio)
        #expect(snapshot.depthDeliverySupported == (
            activeConfiguration.depthDeliverySupported && snapshot.capturePlan.canCapturePhotoDepth
        ))
    }

    @Test func preCaptureSnapshotPreservesFixedZoomID() throws {
        guard let option = Self.enabledFocalLengthOption(matching: { option in
            CameraCapabilityResolver.candidateZoomFactors.contains {
                abs($0 - option.zoom.rawVideoZoomFactor) < 0.001
            }
        }) else {
            return
        }
        let activePlan = Self.capturePlan(option: option, crop: .fullFrame)

        let snapshotPlan = PreCaptureConfigurationBuilder.capturePlan(
            from: activePlan,
            previewCropRectNormalized: CropRectNormalized(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        )

        #expect(snapshotPlan.captureConfig.requestedZoomID == option.zoom.id)
        #expect(snapshotPlan.captureConfig.requestedZoomFactor == option.zoom.rawVideoZoomFactor)
        #expect(snapshotPlan.zoom?.id == activePlan.zoom?.id)
    }

    @Test func preCaptureSnapshotPreservesCustomRawReleaseZoom() throws {
        let options = CameraCapabilityResolver.discover().focalLengthOptions()
        guard let option = options.first(where: { option in
            option.isEnabled
                && !CameraCapabilityResolver.candidateZoomFactors.contains {
                    abs($0 - option.zoom.rawVideoZoomFactor) < 0.001
                }
        }) else {
            return
        }
        let activePlan = CaptureSourcePlan.make(
            rgbSource: option.rgbSource,
            depthSource: option.depthSource,
            selectionMode: .automatic,
            selectedZoomID: nil,
            selectedZoomFactor: option.zoom.rawVideoZoomFactor,
            cropRectNormalized: .fullFrame
        )
        let captureCrop = CropRectNormalized(x: 0.2, y: 0.1, width: 0.6, height: 0.7)

        let snapshotPlan = PreCaptureConfigurationBuilder.capturePlan(
            from: activePlan,
            previewCropRectNormalized: captureCrop
        )

        #expect(snapshotPlan.cropPolicy.cropRectNormalized == captureCrop)
        #expect(abs((snapshotPlan.zoom?.rawVideoZoomFactor ?? 0) - option.zoom.rawVideoZoomFactor) < 0.001)
        #expect(abs((snapshotPlan.captureConfig.requestedZoomFactor ?? 0) - option.zoom.rawVideoZoomFactor) < 0.001)
    }

    @Test func preCaptureSnapshotBoundaryOwnsSessionConfigurationResultCopy() throws {
        let selectionSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift")
        let captureSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift")
        let builderSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/Planning/PreCaptureConfigurationBuilder.swift")

        #expect(!selectionSource.contains("SessionConfigurationResult("))
        #expect(!captureSource.contains("SessionConfigurationResult("))
        #expect(captureSource.contains("PreCaptureConfigurationBuilder.configuration"))
        #expect(captureSource.contains("captureConfiguration.depthDeliverySupported"))
        #expect(builderSource.contains("SessionConfigurationResult("))
        #expect(builderSource.contains("depthDeliverySupported: active.depthDeliverySupported && plan.canCapturePhotoDepth"))
        #expect(builderSource.contains("cameraDisplayName: active.cameraDisplayName"))
        #expect(builderSource.contains("nativePreviewAspectRatio: active.nativePreviewAspectRatio"))
        #expect(builderSource.contains("outputProfile: active.outputProfile"))
        #expect(builderSource.contains("resolvedOutput: active.resolvedOutput"))
        #expect(builderSource.contains("device: active.device"))
        #expect(builderSource.contains("controlCapabilities: active.controlCapabilities"))
        #expect(builderSource.contains("selectionContext: request.selectionContext"))
        #expect(!builderSource.contains("SingleCamPhotoSettingsFactory.resolvedOutput"))
        #expect(!builderSource.contains("resolvedPhotoOutput"))
    }

    private static func enabledFocalLengthOption(
        matching predicate: (FocalLengthOption) -> Bool = { _ in true }
    ) -> FocalLengthOption? {
        CameraCapabilityResolver.discover()
            .focalLengthOptions()
            .first { $0.isEnabled && predicate($0) }
    }

    private static func capturePlan(
        option: FocalLengthOption,
        crop: CropRectNormalized
    ) -> CaptureSourcePlan {
        CaptureSourcePlan.make(
            rgbSource: option.rgbSource,
            depthSource: option.depthSource,
            selectionMode: .automatic,
            selectedZoomID: option.zoom.id,
            selectedZoomFactor: option.zoom.rawVideoZoomFactor,
            cropRectNormalized: crop
        )
    }

    private static func sessionConfigurationResult(
        plan: CaptureSourcePlan,
        cameraDisplayName: String,
        device: AVCaptureDevice,
        nativePreviewAspectRatio: Double = 3.0 / 4.0
    ) throws -> SessionConfigurationResult {
        let request = SessionConfigurationRequest(capturePlan: plan)
        let resolvedOutput = try request.outputProfile.resolvedPhotoOutput(availablePhotoCodecTypes: [])
        return SessionConfigurationResult(
            depthDeliverySupported: plan.canCapturePhotoDepth,
            cameraDisplayName: cameraDisplayName,
            nativePreviewAspectRatio: nativePreviewAspectRatio,
            capturePlan: plan,
            outputProfile: request.outputProfile,
            resolvedOutput: resolvedOutput,
            device: device,
            livePhotoAudioInputConfigured: false,
            controlCapabilities: Self.controlCapabilities(),
            selectionContext: request.selectionContext
        )
    }

    private static func controlCapabilities() -> CameraControlCapabilitySnapshot {
        CameraControlCapabilitySnapshot(
            deviceID: "pre-capture-test-device",
            deviceDisplayName: "Pre-capture Test Camera",
            deviceTypeRawValue: AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue,
            exposure: CameraControlCapabilitySnapshot.Exposure(
                supportsContinuousAutoExposure: true,
                supportsLockedExposure: true,
                supportsCustomExposure: true,
                exposureBiasRange: .init(minimum: -2, maximum: 2),
                isoRange: .init(minimum: 32, maximum: 1_600),
                shutterDurationRangeSeconds: .init(minimum: 1.0 / 12_000.0, maximum: 1),
                currentISO: 100,
                currentShutterDurationSeconds: 1.0 / 120.0,
                currentExposureTargetOffset: 0
            ),
            focus: CameraControlCapabilitySnapshot.Focus(
                supportsAutoFocus: true,
                supportsContinuousAutoFocus: true,
                supportsLockedFocus: true,
                supportsCustomLensPosition: true,
                supportsFocusPointOfInterest: true,
                supportsSmoothAutoFocus: true,
                minimumFocusDistanceMillimeters: 120,
                currentLensPosition: 0.5
            ),
            whiteBalance: CameraControlCapabilitySnapshot.WhiteBalance(
                supportsContinuousAutoWhiteBalance: true,
                supportsLockedWhiteBalance: true,
                maximumGain: 4
            ),
            aperture: CameraControlCapabilitySnapshot.Aperture(fixedLensAperture: 1.78),
            zoom: CameraControlCapabilitySnapshot.Zoom(range: .init(minimum: 1, maximum: 15))
        )
    }

    private static func source(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
