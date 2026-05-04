//
//  AVFoundationSingleCamPhotoProvider.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// Default SingleCam provider backed by `AVCapturePhotoOutput`.
///
/// This provider starts photo captures and receives delegate callbacks. It does
/// not configure cameras, inputs, outputs, formats, or zooms. Those mutations
/// are owned by `CaptureSessionController` so preview and capture stay on the
/// same Apple-paired photo-depth pipeline.
nonisolated final class AVFoundationSingleCamPhotoProvider: SingleCamPhotoCaptureProvider, @unchecked Sendable {
    private let sessionController: CaptureSessionController
    private let lockQueue = DispatchQueue(label: "tapcam.camera-capture.singlecam.provider")
    private var inFlightDelegates: [Int64: SingleCamPhotoCaptureDelegate] = [:]

    init(sessionController: CaptureSessionController) {
        self.sessionController = sessionController
    }

    /// Captures one Apple-paired photo-depth result from the configured session.
    ///
    /// The returned `AVCapturePhoto` contains the visible image, metadata, and
    /// `depthData` from the same `AVCapturePhotoOutput` request.
    ///
    /// - Tag: CaptureSingleCamPhotoDepth
    func capturePhotoDepth(job: CaptureJob, context: CaptureSourceContext) async throws -> SingleCamPhotoCaptureResult {
        let settings = SingleCamPhotoSettingsFactory.make(
            photoOutput: sessionController.photoOutput,
            suppressesShutterSound: context.suppressesShutterSound
        )
        let requestedCodec: AVVideoCodecType = sessionController.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
        let videoRotationAngle = Self.videoRotationAngleForHorizonLevelCapture(
            device: context.sessionConfiguration.device
        )

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = SingleCamPhotoCaptureDelegate { [weak self] result in
                self?.removeDelegate(uniqueID: settings.uniqueID)

                switch result {
                case .success(let photo):
                    continuation.resume(returning: SingleCamPhotoCaptureResult(
                        photo: photo,
                        requestedCodec: requestedCodec,
                        depthDataFiltered: settings.isDepthDataFiltered,
                        photoQualityPrioritization: settings.photoQualityPrioritization
                    ))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            storeDelegate(delegate, uniqueID: settings.uniqueID)
            sessionController.capturePhoto(
                settings: settings,
                delegate: delegate,
                videoRotationAngle: videoRotationAngle
            )
        }
    }

    @MainActor
    private static func videoRotationAngleForHorizonLevelCapture(device: AVCaptureDevice) -> CGFloat? {
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return rotationCoordinator.videoRotationAngleForHorizonLevelCapture
    }

    private func storeDelegate(_ delegate: SingleCamPhotoCaptureDelegate, uniqueID: Int64) {
        lockQueue.sync {
            inFlightDelegates[uniqueID] = delegate
        }
    }

    private func removeDelegate(uniqueID: Int64) {
        lockQueue.async {
            self.inFlightDelegates[uniqueID] = nil
        }
    }
}

/// Creates the single still-photo settings shape used by both prewarming and
/// actual capture. Keeping these settings identical makes
/// `setPreparedPhotoSettingsArray` representative of the requested HEIC + depth
/// capture instead of warming a cheaper default path.
nonisolated enum SingleCamPhotoSettingsFactory {
    static func make(
        photoOutput: AVCapturePhotoOutput,
        suppressesShutterSound: Bool = false
    ) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.isDepthDataDeliveryEnabled = true
        settings.embedsDepthDataInPhoto = true
        settings.isDepthDataFiltered = true
        settings.photoQualityPrioritization = .quality
        if suppressesShutterSound && photoOutput.isShutterSoundSuppressionSupported {
            settings.isShutterSoundSuppressionEnabled = true
        }
        return settings
    }
}

/// Delegate retained for exactly one `AVCapturePhotoOutput.capturePhoto` call.
///
/// `AVCapturePhotoOutput` does not retain its delegate, so the provider stores
/// this object until completion. The delegate only forwards the produced
/// `AVCapturePhoto`; packaging and persistence happen elsewhere.
nonisolated final class SingleCamPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<AVCapturePhoto, Error>) -> Void

    init(completion: @escaping (Result<AVCapturePhoto, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(photo))
        }
    }
}
