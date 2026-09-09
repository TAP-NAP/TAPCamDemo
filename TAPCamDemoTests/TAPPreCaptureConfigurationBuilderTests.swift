//
//  TAPPreCaptureConfigurationBuilderTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPPreCaptureConfigurationBuilderTests {
    @Test(.enabled(
        if: TAPPreCaptureConfigurationBuilderTests.enabledFocalLengthOption() != nil,
        "Requires a supported physical camera."
    ))
    func preCaptureSnapshotUpdatesPlanAndSelectionContextCrop() throws {
        let option = try #require(Self.enabledFocalLengthOption())
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

    @Test(.enabled(
        if: TAPPreCaptureConfigurationBuilderTests.enabledFocalLengthOption() != nil,
        "Requires a supported physical camera."
    ))
    func preCaptureSnapshotPreservesRuntimeExecutionFacts() throws {
        let option = try #require(Self.enabledFocalLengthOption())
        let activePlan = Self.capturePlan(option: option, crop: .fullFrame)
        let activeConfiguration = try Self.sessionConfigurationResult(
            plan: activePlan,
            cameraDisplayName: option.displayName,
            device: option.rgbSource.device,
            nativePreviewAspectRatio: 1.25,
            livePhotoAudioInputConfigured: true,
            auxiliaryPreviewPolicy: .manualFocusLoupe
        )

        let snapshot = PreCaptureConfigurationBuilder.configuration(
            from: activeConfiguration,
            previewCropRectNormalized: CropRectNormalized(x: 0.05, y: 0.1, width: 0.8, height: 0.7)
        )

        #expect(snapshot.outputProfile == activeConfiguration.outputProfile)
        #expect(snapshot.resolvedOutput == activeConfiguration.resolvedOutput)
        #expect(snapshot.device.uniqueID == activeConfiguration.device.uniqueID)
        #expect(snapshot.controlCapabilities == activeConfiguration.controlCapabilities)
        #expect(snapshot.livePhotoAudioInputConfigured)
        #expect(snapshot.auxiliaryPreviewPolicy == .manualFocusLoupe)
        #expect(snapshot.cameraDisplayName == activeConfiguration.cameraDisplayName)
        #expect(snapshot.nativePreviewAspectRatio == activeConfiguration.nativePreviewAspectRatio)
        #expect(snapshot.depthDeliverySupported == (
            activeConfiguration.depthDeliverySupported && snapshot.capturePlan.canCapturePhotoDepth
        ))
    }

    @Test(.enabled(
        if: TAPPreCaptureConfigurationBuilderTests.enabledFocalLengthOption(fixedZoom: true) != nil,
        "Requires a supported physical camera with fixed zoom."
    ))
    func preCaptureSnapshotPreservesFixedZoomID() throws {
        let option = try #require(Self.enabledFocalLengthOption(fixedZoom: true))
        let activePlan = Self.capturePlan(option: option, crop: .fullFrame)

        let snapshotPlan = PreCaptureConfigurationBuilder.capturePlan(
            from: activePlan,
            previewCropRectNormalized: CropRectNormalized(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        )

        #expect(snapshotPlan.captureConfig.requestedZoomID == option.zoom.id)
        #expect(snapshotPlan.captureConfig.requestedZoomFactor == option.zoom.rawVideoZoomFactor)
        #expect(snapshotPlan.zoom?.id == activePlan.zoom?.id)
    }

    @Test(.enabled(
        if: TAPPreCaptureConfigurationBuilderTests.enabledFocalLengthOption(fixedZoom: false) != nil,
        "Requires a supported physical camera with custom zoom."
    ))
    func preCaptureSnapshotPreservesCustomRawReleaseZoom() throws {
        let option = try #require(Self.enabledFocalLengthOption(fixedZoom: false))
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

    private static func enabledFocalLengthOption(fixedZoom: Bool? = nil) -> FocalLengthOption? {
        CameraCapabilityResolver.discover().focalLengthOptions().first { option in
            guard option.isEnabled else { return false }
            guard let fixedZoom else { return true }
            return CameraCapabilityResolver.candidateZoomFactors.contains {
                abs($0 - option.zoom.rawVideoZoomFactor) < 0.001
            } == fixedZoom
        }
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
        nativePreviewAspectRatio: Double = 3.0 / 4.0,
        livePhotoAudioInputConfigured: Bool = false,
        auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy = .none
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
            livePhotoAudioInputConfigured: livePhotoAudioInputConfigured,
            controlCapabilities: Self.controlCapabilities(),
            selectionContext: request.selectionContext,
            auxiliaryPreviewPolicy: auxiliaryPreviewPolicy
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
}
