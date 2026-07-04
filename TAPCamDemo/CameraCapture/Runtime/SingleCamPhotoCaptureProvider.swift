//
//  SingleCamPhotoCaptureProvider.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreLocation
import CoreMedia
import Foundation

nonisolated enum CaptureFlashMode: Equatable, Sendable {
    case auto
    case on
    case off

    var avCaptureFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto:
            .auto
        case .on:
            .on
        case .off:
            .off
        }
    }
}

nonisolated struct CaptureLivePhotoRequest: Equatable, Sendable {
    static let disabled = CaptureLivePhotoRequest(isEnabled: false, capturesAudio: false)

    let isEnabled: Bool
    let capturesAudio: Bool
}

nonisolated struct CapturedLivePhotoMovie: Sendable {
    let fileURL: URL
    let duration: CMTime
    let photoDisplayTime: CMTime
    let dimensions: CapturePhotoDimensions
    let codec: String?
    let capturesAudio: Bool

    nonisolated func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
}

/// Context passed to the SingleCam photo provider for one job.
///
/// The provider receives already-configured SingleCam session facts. It may use
/// outputs owned by `CaptureSessionController`, but it must not add or remove
/// session inputs, outputs, or connections directly.
nonisolated struct CaptureSourceContext: @unchecked Sendable {
    let sessionConfiguration: SessionConfigurationResult
    let capturedAt: Date
    let location: CLLocation?
    let suppressesShutterSound: Bool
    let flashMode: CaptureFlashMode
    let livePhotoRequest: CaptureLivePhotoRequest

    init(
        sessionConfiguration: SessionConfigurationResult,
        capturedAt: Date,
        location: CLLocation?,
        suppressesShutterSound: Bool,
        flashMode: CaptureFlashMode,
        livePhotoRequest: CaptureLivePhotoRequest = .disabled
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.capturedAt = capturedAt
        self.location = location
        self.suppressesShutterSound = suppressesShutterSound
        self.flashMode = flashMode
        self.livePhotoRequest = livePhotoRequest
    }
}

/// Result of a SingleCam photo-depth capture.
///
/// `AVCapturePhoto` is retained only long enough for the packaging layer to
/// create the embedded HEIC artifact and TAP manifest. The RGB image and depth
/// map remain Apple's paired output from one `AVCapturePhotoOutput` request.
nonisolated struct SingleCamPhotoCaptureResult: @unchecked Sendable {
    let photo: AVCapturePhoto
    let livePhotoMovie: CapturedLivePhotoMovie?
    let livePhotoFailureReason: String?

    init(
        photo: AVCapturePhoto,
        livePhotoMovie: CapturedLivePhotoMovie? = nil,
        livePhotoFailureReason: String? = nil
    ) {
        self.photo = photo
        self.livePhotoMovie = livePhotoMovie
        self.livePhotoFailureReason = livePhotoFailureReason
    }
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
