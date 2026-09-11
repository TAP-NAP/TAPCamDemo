//
//  TAPDepthCaptureError.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import Foundation

/// User-facing errors for the SingleCam photo-depth capture flow.
///
/// These cases are shared by planning, runtime capture, embedded photo output,
/// and Photos writing so the UI can display one coherent status surface.
enum TAPDepthCaptureError: LocalizedError {
    case cameraAccessDenied
    case noDepthCameraAvailable
    case unableToAddCameraInput
    case unableToAddPhotoOutput
    case unableToAddVideoOutput
    case unableToAddAudioOutput
    case unableToAddDepthOutput
    case depthDeliveryUnsupported
    case unsupportedZoomFactor
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
    case pendingCaptureProofExternalMutation
    case captureBackpressureLimitReached
    case incompatibleRGBDepthPairing
    case multicamRequired
    case cameraControlOutsideSessionQueue
    case cameraControlCommandPlanNotExecutable
    case cameraControlTargetDeviceChanged
    case cameraControlTargetSurfaceChanged
    case cameraControlUnsupportedCommand
    case cameraManualFocusAssistTimedOut
    case cameraManualFocusLockTimedOut
    case videoRecordingAlreadyActive
    case videoRecordingNotActive
    case videoRecordingFailed(String)

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
        case .unableToAddVideoOutput:
            "Unable to add AVCaptureVideoDataOutput to the capture session."
        case .unableToAddAudioOutput:
            "Unable to add AVCaptureAudioDataOutput to the capture session."
        case .unableToAddDepthOutput:
            "Unable to add AVCaptureDepthDataOutput to the capture session."
        case .depthDeliveryUnsupported:
            "The current session configuration does not support depth photo delivery."
        case .unsupportedZoomFactor:
            "The selected zoom factor does not support depth delivery on this camera."
        case .invalidCaptureOutputProfile(let reason):
            "The capture output profile is not valid for Release photo-depth output: \(reason)"
        case .captureOutputCodecUnsupported(let reason):
            "The configured photo output does not support the requested capture codec: \(reason)"
        case .unableToCreatePhotoData:
            "AVCapturePhoto could not produce photo data."
        case .invalidUTF8Manifest:
            "The TAP manifest could not be encoded as UTF-8 JSON."
        case .invalidTAPManifest(let reason):
            "The TAP manifest is not valid: \(reason)"
        case .imageSourceCreationFailed:
            "ImageIO could not open the generated photo data."
        case .imageDestinationCreationFailed:
            "ImageIO could not create a photo destination."
        case .xmpNamespaceRegistrationFailed(let reason):
            "ImageIO could not register the TAP XMP namespace: \(reason)"
        case .xmpManifestWriteFailed:
            "ImageIO could not write tapdepth:Manifest into XMP metadata."
        case .imageCopyFailed(let reason):
            "ImageIO could not copy the photo source while injecting metadata: \(reason)"
        case .xmpManifestMissing:
            "The generated photo file does not contain tapdepth:Manifest after writeback."
        case .invalidHEICContainerType(let actual):
            "The pending TAP capture is not a supported TAP depth photo container: \(actual)."
        case .photoLibraryAccessDenied:
            "Photo library access is required to save into the TAPCamDepth album."
        case .albumCreationFailed:
            "Unable to create or fetch the TAPCamDepth album."
        case .assetCreationFailed:
            "Unable to create a Photos asset from the depth photo file."
        case .assetNotFound:
            "The selected Photos asset could not be found."
        case .pendingCaptureDataMissing:
            "The pending TAP capture no longer has its staged photo data."
        case .invalidPendingCaptureBundlePath(let reason):
            "The pending TAP capture bundle path is not valid: \(reason)."
        case .pendingCaptureManifestIDMismatch(let expected, let actual):
            "The pending TAP capture record (\(expected)) does not match the embedded TAP manifest (\(actual))."
        case .pendingCaptureProofMissing:
            "The pending TAP capture does not contain an App Attest proof."
        case .pendingCaptureProofInvalid(let reason):
            "The pending TAP capture App Attest proof is not valid: \(reason)"
        case .pendingCaptureProofExternalMutation:
            "The pending TAP video changed outside its fixed proof slot after signing began."
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
        case .cameraManualFocusAssistTimedOut:
            "The camera did not finish autofocus assist in time."
        case .cameraManualFocusLockTimedOut:
            "The camera did not confirm the manual focus change in time."
        case .videoRecordingAlreadyActive:
            "A TAP video recording is already active."
        case .videoRecordingNotActive:
            "No TAP video recording is active."
        case .videoRecordingFailed(let reason):
            "The TAP video recording failed: \(reason)"
        }
    }
}
