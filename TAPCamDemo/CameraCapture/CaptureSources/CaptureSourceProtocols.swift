//
//  CaptureSourceProtocols.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreLocation
import Foundation

/// Context passed to the SingleCam photo provider for one job.
///
/// The provider receives already-configured SingleCam session facts. It may use
/// outputs owned by `CaptureSessionController`, but it must not add or remove
/// session inputs, outputs, or connections directly.
nonisolated struct CaptureSourceContext: @unchecked Sendable {
    let sessionConfiguration: SessionConfigurationResult
    let capturedAt: Date
    let location: CLLocation?
}

/// Result of a SingleCam photo-depth capture.
///
/// `AVCapturePhoto` is retained only long enough for the packaging layer to
/// create the embedded HEIC artifact and TAP manifest. The RGB image and depth
/// map remain Apple's paired output from one `AVCapturePhotoOutput` request.
nonisolated struct SingleCamPhotoCaptureResult: @unchecked Sendable {
    let photo: AVCapturePhoto
    let requestedCodec: AVVideoCodecType
    let depthDataFiltered: Bool
    let photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
}

/// Produces one paired SingleCam photo-depth result.
///
/// Apple's stable still-photo depth API returns the visual image, embedded-file
/// bytes, `AVCapturePhoto.depthData`, and capture metadata from one
/// `AVCapturePhotoOutput` callback. Modeling that as one unit keeps the code
/// aligned with Apple's paired still-photo depth pipeline.
protocol SingleCamPhotoCaptureProvider: Sendable {
    func capturePhotoDepth(job: CaptureJob, context: CaptureSourceContext) async throws -> SingleCamPhotoCaptureResult
}
