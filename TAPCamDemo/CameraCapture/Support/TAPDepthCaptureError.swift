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
    case invalidCaptureOutputProfile(String)
    case captureOutputCodecUnsupported(String)
    case unableToCreatePhotoData
    case invalidUTF8Manifest
    case invalidTAPManifest(String)
    case imageSourceCreationFailed
    case imageDestinationCreationFailed
    case xmpNamespaceRegistrationFailed(String)
    case xmpManifestWriteFailed
    case imageCopyFailed(String)
    case xmpManifestMissing
    case invalidHEICContainerType(String)
    case photoLibraryAccessDenied
    case albumCreationFailed
    case assetCreationFailed
    case assetNotFound
    case pendingCaptureDataMissing
    case invalidPendingCaptureBundlePath(String)
    case pendingCaptureManifestIDMismatch(expected: String, actual: String)
    case pendingCaptureProofMissing
    case pendingCaptureProofInvalid(String)
    case releasePackagingStrategyRejected
    case captureBackpressureLimitReached
    case incompatibleRGBDepthPairing
    case multicamRequired
    case cameraControlOutsideSessionQueue
    case cameraControlCommandPlanNotExecutable
    case cameraControlTargetDeviceChanged
    case cameraControlTargetSurfaceChanged
    case cameraControlUnsupportedCommand

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
        case .invalidCaptureOutputProfile(let reason):
            "The capture output profile is not valid for Release photo-depth output: \(reason)"
        case .captureOutputCodecUnsupported(let reason):
            "The configured photo output does not support the requested capture codec: \(reason)"
        case .unableToCreatePhotoData:
            "AVCapturePhoto could not produce HEIC data."
        case .invalidUTF8Manifest:
            "The TAP manifest could not be encoded as UTF-8 JSON."
        case .invalidTAPManifest(let reason):
            "The TAP manifest is not valid: \(reason)"
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
        case .invalidHEICContainerType(let actual):
            "The pending TAP capture is not an HEIC container: \(actual)."
        case .photoLibraryAccessDenied:
            "Photo library access is required to save into the TAPCamDepth album."
        case .albumCreationFailed:
            "Unable to create or fetch the TAPCamDepth album."
        case .assetCreationFailed:
            "Unable to create a Photos asset from the depth HEIC."
        case .assetNotFound:
            "The selected Photos asset could not be found."
        case .pendingCaptureDataMissing:
            "The pending TAP capture no longer has its staged HEIC data."
        case .invalidPendingCaptureBundlePath(let reason):
            "The pending TAP capture bundle path is not valid: \(reason)."
        case .pendingCaptureManifestIDMismatch(let expected, let actual):
            "The pending TAP capture record (\(expected)) does not match the embedded TAP manifest (\(actual))."
        case .pendingCaptureProofMissing:
            "The pending TAP capture does not contain an App Attest proof."
        case .pendingCaptureProofInvalid(let reason):
            "The pending TAP capture App Attest proof is not valid: \(reason)"
        case .releasePackagingStrategyRejected:
            "Release builds only support embedded single-photo artifacts."
        case .captureBackpressureLimitReached:
            "Too many capture jobs are already pending."
        case .incompatibleRGBDepthPairing:
            "The selected RGB source and depth source cannot produce a supported paired capture."
        case .multicamRequired:
            "This RGB and depth pairing is outside the SingleCam photo-depth pipeline."
        case .cameraControlOutsideSessionQueue:
            "Camera controls must run on the camera session queue."
        case .cameraControlCommandPlanNotExecutable:
            "The manual camera control request is not executable."
        case .cameraControlTargetDeviceChanged:
            "The active camera changed before manual controls could be applied."
        case .cameraControlTargetSurfaceChanged:
            "The active camera controls changed before manual controls could be applied."
        case .cameraControlUnsupportedCommand:
            "The manual camera control request includes an unsupported command."
        }
    }
}
