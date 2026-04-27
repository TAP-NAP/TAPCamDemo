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
/// source context, the `AVCapturePhoto`, location, and capture settings. It
/// does not decide how bytes are physically written or where the result is
/// persisted.
nonisolated struct CapturePackage: @unchecked Sendable {
    let job: CaptureJob
    let sourceContext: CaptureSourceContext
    let rgbSource: CameraProfile
    let depthSource: DepthProfile?
    let pairingMode: RGBDepthPairingMode
    let pairingStatus: RGBDepthCompatibilityStatus
    let zoomCapabilitySnapshot: ZoomCapability
    let cropRectNormalized: CropRectNormalized
    let photo: AVCapturePhoto
    let requestedCodec: AVVideoCodecType
    let depthDataFiltered: Bool
    let photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
}

/// Builds `CapturePackage` from SingleCam photo output.
///
/// Validation happens here before physical packaging. A package without
/// `AVCapturePhoto.depthData` is invalid because output must remain a single
/// photo artifact with embedded auxiliary depth.
nonisolated enum CapturePackageBuilder {
    static func makePackage(
        job: CaptureJob,
        context: CaptureSourceContext,
        captureResult: SingleCamPhotoCaptureResult
    ) throws -> CapturePackage {
        guard captureResult.photo.depthData != nil else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let plan = context.sessionConfiguration.capturePlan
        return CapturePackage(
            job: job,
            sourceContext: context,
            rgbSource: plan.rgbSource,
            depthSource: plan.depthSource,
            pairingMode: plan.pairingMode,
            pairingStatus: plan.compatibilityStatus,
            zoomCapabilitySnapshot: plan.zoomCapability,
            cropRectNormalized: plan.cropPolicy.cropRectNormalized,
            photo: captureResult.photo,
            requestedCodec: captureResult.requestedCodec,
            depthDataFiltered: captureResult.depthDataFiltered,
            photoQualityPrioritization: captureResult.photoQualityPrioritization
        )
    }
}
