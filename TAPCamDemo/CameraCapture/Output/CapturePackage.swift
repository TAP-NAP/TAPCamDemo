//
//  CapturePackage.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreLocation
import Foundation

/// Logical result of one SingleCam shutter press.
///
/// This package owns normalized capture facts only: job identity, selected
/// source context, the resolved Runtime output, and the `AVCapturePhoto`. It
/// does not decide how bytes are physically written or where the result is
/// persisted. Camera device facts are copied before the next configuration is
/// allowed to change the live device.
nonisolated struct CapturePackage: @unchecked Sendable {
    let job: CaptureJob
    let sourceContext: CaptureSourceContext
    let camera: TAPDepthManifest.Camera
    let rgbSource: CameraProfile
    let depthSource: DepthProfile?
    let pairingMode: RGBDepthPairingMode
    let pairingStatus: RGBDepthCompatibilityStatus
    let zoomCapabilitySnapshot: ZoomCapability
    let cropRectNormalized: CropRectNormalized
    let resolvedOutput: ResolvedCaptureOutputProfile
    let depthAvailability: CaptureDepthAvailability
    let photo: AVCapturePhoto
    let livePhotoMovie: CapturedLivePhotoMovie?
    let livePhotoFailureReason: String?
}

/// Builds `CapturePackage` from SingleCam photo output.
///
/// Validation happens here before physical packaging. Runtime still requests a
/// depth-capable photo path, but the individual shutter result may come back
/// without `AVCapturePhoto.depthData`; that is recorded as No Depth instead of
/// failing the foreground capture.
nonisolated enum CapturePackageBuilder {
    /// Normalizes one `AVCapturePhoto` result into the app's logical package.
    ///
    /// Packaging and writing are deliberately outside this step, so manifest
    /// construction can read stable source, zoom, crop, and capture facts.
    ///
    /// - Tag: BuildCapturePackage
    static func makePackage(
        job: CaptureJob,
        context: CaptureSourceContext,
        captureResult: SingleCamPhotoCaptureResult
    ) throws -> CapturePackage {
        let resolvedOutput = context.sessionConfiguration.resolvedOutput
        try resolvedOutput.validateForEmbeddedPhotoDepthPackaging()
        try resolvedOutput.validateCapturePlanDepthConfiguration(
            depthDataDeliveryEnabled: context.sessionConfiguration.capturePlan.captureConfig.depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: context.sessionConfiguration.capturePlan.captureConfig.embedsDepthDataInPhoto
        )

        let plan = context.sessionConfiguration.capturePlan
        return CapturePackage(
            job: job,
            sourceContext: context,
            camera: TAPDepthManifestBuilder.makeCamera(device: context.sessionConfiguration.device),
            rgbSource: plan.rgbSource,
            depthSource: plan.depthSource,
            pairingMode: plan.pairingMode,
            pairingStatus: plan.compatibilityStatus,
            zoomCapabilitySnapshot: plan.zoomCapability,
            cropRectNormalized: plan.cropPolicy.cropRectNormalized,
            resolvedOutput: resolvedOutput,
            depthAvailability: captureResult.photo.depthData == nil ? .unavailable : .available,
            photo: captureResult.photo,
            livePhotoMovie: captureResult.livePhotoMovie,
            livePhotoFailureReason: captureResult.livePhotoFailureReason
        )
    }
}
