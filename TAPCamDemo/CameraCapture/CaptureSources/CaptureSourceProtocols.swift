//
//  CaptureSourceProtocols.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreLocation
import Foundation

/// Context passed to capture providers for one job.
///
/// Providers receive the already-configured SingleCam session facts. They may
/// use outputs owned by `CaptureSessionController`, but they must not add or
/// remove session inputs, outputs, or connections directly.
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
/// `AVCapturePhotoOutput` callback. Modeling that as one provider avoids the
/// false impression that this demo can freely combine independent RGB, RAW, and
/// depth producers.
protocol SingleCamPhotoCaptureProvider: Sendable {
    func capturePhotoDepth(job: CaptureJob, context: CaptureSourceContext) async throws -> SingleCamPhotoCaptureResult
}
