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

/// Placeholder result for future RGB providers.
///
/// v0.6 SingleCam uses `SingleCamPhotoCaptureProvider` because RGB and depth
/// arrive together as one `AVCapturePhoto`. The separate protocol exists so
/// MultiCam and external-session adapters can later provide RGB independently.
nonisolated struct RGBCaptureResult: @unchecked Sendable {
    let photo: AVCapturePhoto?
    let imageData: Data?
}

/// Placeholder result for future depth providers.
///
/// External providers can eventually return depth maps without owning the
/// managed session graph. SingleCam does not use this path yet.
nonisolated struct DepthCaptureResult: @unchecked Sendable {
    let depthData: AVDepthData?
}

/// Placeholder result for future RAW providers.
nonisolated struct RawCaptureResult: Sendable {
    let rawData: Data?
}

/// Produces RGB data for a capture job.
///
/// Implementations may use AVFoundation or an external camera pipeline.
/// Providers must not directly add or remove `AVCaptureSession` inputs or
/// outputs; session changes must go through `SessionConfigurationRequest`.
protocol RGBCaptureProvider: Sendable {
    func captureRGB(job: CaptureJob, context: CaptureSourceContext) async throws -> RGBCaptureResult
}

/// Produces depth data for a capture job.
///
/// This is reserved for MultiCam/external paths. SingleCam uses Apple's paired
/// `AVCapturePhoto.depthData` inside `SingleCamPhotoCaptureProvider`.
protocol DepthCaptureProvider: Sendable {
    func captureDepth(job: CaptureJob, context: CaptureSourceContext) async throws -> DepthCaptureResult
}

/// Produces RAW data for a capture job when available.
protocol RawCaptureProvider: Sendable {
    func captureRaw(job: CaptureJob, context: CaptureSourceContext) async throws -> RawCaptureResult?
}

/// Produces one paired SingleCam photo-depth result.
protocol SingleCamPhotoCaptureProvider: Sendable {
    func capturePhotoDepth(job: CaptureJob, context: CaptureSourceContext) async throws -> SingleCamPhotoCaptureResult
}

