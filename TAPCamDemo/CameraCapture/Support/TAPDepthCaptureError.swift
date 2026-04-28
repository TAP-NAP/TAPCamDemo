//
//  TAPDepthCaptureError.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import Foundation

/// User-facing errors for the SingleCam photo-depth capture flow.
///
/// These cases are shared by planning, runtime capture, embedded HEIC output,
/// and Photos writing so the UI can display one coherent status surface.
enum TAPDepthCaptureError: LocalizedError {
    case cameraAccessDenied
    case noDepthCameraAvailable
    case unableToAddCameraInput
    case unableToAddPhotoOutput
    case depthDeliveryUnsupported
    case unsupportedZoomFactor
    case missingDepthData
    case unableToCreatePhotoData
    case invalidUTF8Manifest
    case imageSourceCreationFailed
    case imageDestinationCreationFailed
    case xmpNamespaceRegistrationFailed(String)
    case xmpManifestWriteFailed
    case imageCopyFailed(String)
    case xmpManifestMissing
    case photoLibraryAccessDenied
    case albumCreationFailed
    case assetCreationFailed
    case assetNotFound
    case releasePackagingStrategyRejected
    case captureBackpressureLimitReached
    case incompatibleRGBDepthPairing
    case multicamRequired

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied:
            "Camera access is required to capture depth photos."
        case .noDepthCameraAvailable:
            "No camera with depth-capable formats is available on this device."
        case .unableToAddCameraInput:
            "Unable to add the selected camera input to the capture session."
        case .unableToAddPhotoOutput:
            "Unable to add AVCapturePhotoOutput to the capture session."
        case .depthDeliveryUnsupported:
            "The current session configuration does not support depth photo delivery."
        case .unsupportedZoomFactor:
            "The selected zoom factor does not support depth delivery on this camera."
        case .missingDepthData:
            "The captured photo did not include AVDepthData."
        case .unableToCreatePhotoData:
            "AVCapturePhoto could not produce HEIC data."
        case .invalidUTF8Manifest:
            "The TAP manifest could not be encoded as UTF-8 JSON."
        case .imageSourceCreationFailed:
            "ImageIO could not open the generated HEIC data."
        case .imageDestinationCreationFailed:
            "ImageIO could not create a HEIC destination."
        case .xmpNamespaceRegistrationFailed(let reason):
            "ImageIO could not register the TAP XMP namespace: \(reason)"
        case .xmpManifestWriteFailed:
            "ImageIO could not write tapdepth:Manifest into XMP metadata."
        case .imageCopyFailed(let reason):
            "ImageIO could not copy the HEIC source while injecting metadata: \(reason)"
        case .xmpManifestMissing:
            "The generated HEIC does not contain tapdepth:Manifest after writeback."
        case .photoLibraryAccessDenied:
            "Photo library access is required to save into the TAPCamDepth album."
        case .albumCreationFailed:
            "Unable to create or fetch the TAPCamDepth album."
        case .assetCreationFailed:
            "Unable to create a Photos asset from the depth HEIC."
        case .assetNotFound:
            "The selected Photos asset could not be found."
        case .releasePackagingStrategyRejected:
            "Release builds only support embedded single-photo artifacts."
        case .captureBackpressureLimitReached:
            "Too many capture jobs are already pending."
        case .incompatibleRGBDepthPairing:
            "The selected RGB source and depth source cannot produce a supported paired capture."
        case .multicamRequired:
            "This RGB and depth pairing is outside the SingleCam photo-depth pipeline."
        }
    }
}
