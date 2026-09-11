//
//  PreCaptureConfigurationBuilder.swift
//  TAPCamDemo
//

import Foundation

/// Applies last-moment preview state to the already configured capture session.
///
/// Runtime owns `SessionConfigurationResult`: it has already resolved the
/// output profile, selected the AVFoundation device, and recorded the active
/// control capability snapshot. A shutter press only updates the preview crop
/// metadata that should travel with this capture. Keeping that update here
/// prevents `CameraViewModel` from hand-copying Runtime configuration fields or
/// reinterpreting output policy at capture time.
nonisolated enum PreCaptureConfigurationBuilder {
    static func configuration(
        from active: SessionConfigurationResult,
        previewCropRectNormalized: CropRectNormalized
    ) -> SessionConfigurationResult {
        let plan = capturePlan(
            from: active.capturePlan,
            previewCropRectNormalized: previewCropRectNormalized
        )
        let request = SessionConfigurationRequest(
            capturePlan: plan,
            outputProfile: active.outputProfile,
            auxiliaryPreviewPolicy: active.auxiliaryPreviewPolicy
        )

        return SessionConfigurationResult(
            depthDeliverySupported: active.depthDeliverySupported && plan.canCapturePhotoDepth,
            cameraDisplayName: active.cameraDisplayName,
            nativePreviewAspectRatio: active.nativePreviewAspectRatio,
            capturePlan: plan,
            outputProfile: active.outputProfile,
            resolvedOutput: active.resolvedOutput,
            device: active.device,
            livePhotoAudioInputConfigured: active.livePhotoAudioInputConfigured,
            controlCapabilities: active.controlCapabilities,
            selectionContext: request.selectionContext,
            auxiliaryPreviewPolicy: active.auxiliaryPreviewPolicy
        )
    }

    static func capturePlan(
        from activePlan: CaptureSourcePlan,
        previewCropRectNormalized: CropRectNormalized
    ) -> CaptureSourcePlan {
        var plan = activePlan
        plan.cropPolicy = CropPolicy(
            mode: activePlan.cropPolicy.mode,
            cropRectNormalized: previewCropRectNormalized,
            destructiveFinalCropApplied: activePlan.cropPolicy.destructiveFinalCropApplied
        )
        return plan
    }
}
