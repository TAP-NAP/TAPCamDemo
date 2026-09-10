//
//  CameraCaptureStatusPresentation.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation

/// Public-safe text for camera status surfaces.
///
/// Capture errors can contain internal identifiers, paths, URLs, format
/// descriptions, manifest details, and App Attest proof state. Keep those raw
/// diagnostics in logs and control flow; status labels and Debug metrics should
/// use this fixed vocabulary instead.
nonisolated enum CameraCaptureStatusPresentation {
    enum Context {
        case capture
        case configuration
        case debugConfiguration
        case metrics
    }

    static func message(for error: Error, context: Context) -> String {
        guard let captureError = error as? TAPDepthCaptureError else {
            return context.fallbackMessage
        }

        return message(for: captureError, context: context)
    }

    static func message(for error: TAPDepthCaptureError, context: Context) -> String {
        switch error {
        case .cameraAccessDenied:
            return "Camera access is required to capture depth photos."
        case .noDepthCameraAvailable:
            return "No camera with depth-capable formats is available on this device."
        case .unableToAddCameraInput:
            return "Unable to add the selected camera input to the capture session."
        case .unableToAddPhotoOutput:
            return "Unable to add photo output to the capture session."
        case .unableToAddVideoOutput:
            return "Unable to add video output to the capture session."
        case .unableToAddAudioOutput:
            return "Unable to add audio output to the capture session."
        case .unableToAddDepthOutput:
            return "Unable to add depth output to the capture session."
        case .depthDeliveryUnsupported:
            return "The current session configuration does not support depth photo delivery."
        case .unsupportedZoomFactor:
            return "The selected zoom factor does not support depth delivery on this camera."
        case .missingDepthData:
            return "The captured photo did not include depth data."
        case .photoLibraryAccessDenied:
            return "Photo library access is required to save into the TAPCamDepth album."
        case .albumCreationFailed:
            return "Unable to create or fetch the TAPCamDepth album."
        case .assetCreationFailed:
            return "Unable to create a Photos asset from the depth photo."
        case .assetNotFound:
            return "The selected Photos asset could not be found."
        case .pendingCaptureDataMissing:
            return "The pending TAP capture data is unavailable."
        case .invalidPendingCaptureBundlePath:
            return "The pending TAP capture bundle could not be read safely."
        case .captureBackpressureLimitReached:
            return "Too many capture jobs are already pending."
        case .incompatibleRGBDepthPairing:
            return "The selected RGB source and depth source cannot produce a supported paired capture."
        case .multicamRequired:
            return "This RGB and depth pairing is outside the SingleCam photo-depth pipeline."
        case .cameraControlOutsideSessionQueue,
             .cameraControlCommandPlanNotExecutable,
             .cameraControlTargetDeviceChanged,
             .cameraControlTargetSurfaceChanged,
             .cameraControlUnsupportedCommand,
             .cameraManualFocusAssistTimedOut,
             .cameraManualFocusLockTimedOut:
            return "Camera controls are temporarily unavailable."
        case .invalidCaptureOutputProfile,
             .captureOutputCodecUnsupported,
             .unableToCreatePhotoData,
             .invalidUTF8Manifest,
             .invalidTAPManifest,
             .imageSourceCreationFailed,
             .imageDestinationCreationFailed,
             .xmpNamespaceRegistrationFailed,
             .xmpManifestWriteFailed,
             .imageCopyFailed,
             .xmpManifestMissing,
             .invalidHEICContainerType,
             .pendingCaptureManifestIDMismatch,
             .pendingCaptureProofMissing,
             .pendingCaptureProofInvalid,
             .pendingCaptureProofExternalMutation,
             .videoRecordingAlreadyActive,
             .videoRecordingNotActive,
             .videoRecordingFailed:
            return context.fallbackMessage
        }
    }

    static func failureReason(for error: Error) -> String {
        message(for: error, context: .metrics)
    }
}

private extension CameraCaptureStatusPresentation.Context {
    nonisolated var fallbackMessage: String {
        switch self {
        case .capture:
            return "Capture failed. See diagnostics for details."
        case .configuration:
            return "Camera configuration failed. See diagnostics for details."
        case .debugConfiguration:
            return "Debug camera configuration failed. See diagnostics for details."
        case .metrics:
            return "Capture failed; see diagnostics."
        }
    }
}
