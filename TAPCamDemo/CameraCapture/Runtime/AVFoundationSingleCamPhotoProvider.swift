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
        let resolvedOutput = context.sessionConfiguration.resolvedOutput
        let livePhotoPlan = try Self.livePhotoCapturePlan(
            requested: context.livePhotoRequest,
            photoOutput: sessionController.photoOutput
        )
        let settings = SingleCamPhotoSettingsFactory.make(
            photoOutput: sessionController.photoOutput,
            resolvedOutput: resolvedOutput,
            suppressesShutterSound: context.suppressesShutterSound,
            flashMode: context.flashMode,
            livePhotoMovieFileURL: livePhotoPlan?.movieFileURL,
            livePhotoVideoCodecType: livePhotoPlan?.codec
        )
        let videoRotationAngle = Self.videoRotationAngleForHorizonLevelCapture(
            device: context.sessionConfiguration.device
        )

        return try await withCheckedThrowingContinuation { continuation in
            let complete: @Sendable (Result<SingleCamPhotoCaptureResult, Error>) -> Void = { [weak self] result in
                self?.removeDelegate(uniqueID: settings.uniqueID)

                switch result {
                case .success(let captureResult):
                    if captureResult.livePhotoMovie == nil {
                        livePhotoPlan?.removeTemporaryDirectory()
                    }
                    continuation.resume(returning: captureResult)
                case .failure(let error):
                    livePhotoPlan?.removeTemporaryDirectory()
                    continuation.resume(throwing: error)
                }
            }
            let delegate = SingleCamPhotoCaptureDelegate(
                completion: complete,
                expectsLivePhotoMovie: livePhotoPlan != nil,
                livePhotoVideoCodec: livePhotoPlan?.codec?.rawValue,
                capturesLivePhotoAudio: livePhotoPlan?.capturesAudio ?? false
            )

            storeDelegate(delegate, uniqueID: settings.uniqueID)
            sessionController.capturePhoto(
                settings: settings,
                resolvedOutput: resolvedOutput,
                delegate: delegate,
                videoRotationAngle: videoRotationAngle,
                isVideoMirrored: context.sessionConfiguration.device.position == .front,
                onFailure: { complete(.failure($0)) }
            )
        }
    }

    private static func livePhotoCapturePlan(
        requested: CaptureLivePhotoRequest,
        photoOutput: AVCapturePhotoOutput
    ) throws -> SingleCamLivePhotoCapturePlan? {
        guard requested.isEnabled,
              photoOutput.isLivePhotoCaptureSupported,
              photoOutput.isLivePhotoCaptureEnabled else {
            return nil
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPLivePhoto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let movieFileURL = directoryURL.appendingPathComponent("paired-video.mov")
        let availableCodecs = photoOutput.availableLivePhotoVideoCodecTypes
        let codec = availableCodecs.first(where: { $0 == .hevc })
            ?? availableCodecs.first(where: { $0 == .h264 })
            ?? availableCodecs.first
        return SingleCamLivePhotoCapturePlan(
            movieFileURL: movieFileURL,
            codec: codec,
            capturesAudio: requested.capturesAudio
        )
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

private struct SingleCamLivePhotoCapturePlan {
    let movieFileURL: URL
    let codec: AVVideoCodecType?
    let capturesAudio: Bool

    func removeTemporaryDirectory() {
        try? FileManager.default.removeItem(at: movieFileURL.deletingLastPathComponent())
    }
}

/// Creates the single still-photo settings shape used by actual capture.
/// Runtime intentionally avoids retaining prepared settings across camera-graph
/// changes so repeated Standard/LiDAR switching cannot carry resource hints
/// from one physical capture source into the next.
nonisolated enum SingleCamPhotoSettingsFactory {
    static func make(
        photoOutput: AVCapturePhotoOutput,
        resolvedOutput: ResolvedCaptureOutputProfile,
        suppressesShutterSound: Bool = false,
        flashMode: CaptureFlashMode = .auto,
        livePhotoMovieFileURL: URL? = nil,
        livePhotoVideoCodecType: AVVideoCodecType? = nil
    ) -> AVCapturePhotoSettings {
        let processedFormat: [String: Any] = [
            AVVideoCodecKey: resolvedOutput.codec.avVideoCodecType,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: resolvedOutput.compressionQuality
            ]
        ]
        let settings = AVCapturePhotoSettings(
            rawPixelFormatType: 0,
            rawFileType: nil,
            processedFormat: processedFormat,
            processedFileType: resolvedOutput.processedFileType
        )

        settings.isDepthDataDeliveryEnabled = resolvedOutput.depthDataDeliveryEnabled
        settings.embedsDepthDataInPhoto = resolvedOutput.embedsDepthDataInPhoto
        settings.isDepthDataFiltered = resolvedOutput.depthDataFiltered
        settings.photoQualityPrioritization = resolvedOutput.photoQualityPrioritization
        if let maxPhotoDimensions = resolvedOutput.maxPhotoDimensions {
            settings.maxPhotoDimensions = maxPhotoDimensions.cmVideoDimensions
        }
        let requestedFlashMode = flashMode.avCaptureFlashMode
        if photoOutput.supportedFlashModes.contains(requestedFlashMode) {
            settings.flashMode = requestedFlashMode
        }
        if suppressesShutterSound && photoOutput.isShutterSoundSuppressionSupported {
            settings.isShutterSoundSuppressionEnabled = true
        }
        if let livePhotoMovieFileURL {
            settings.livePhotoMovieFileURL = livePhotoMovieFileURL
            if let livePhotoVideoCodecType,
               photoOutput.availableLivePhotoVideoCodecTypes.contains(livePhotoVideoCodecType) {
                settings.livePhotoVideoCodecType = livePhotoVideoCodecType
            }
        }
        return settings
    }

    static func resolvedOutput(
        photoOutput: AVCapturePhotoOutput,
        activeFormat: AVCaptureDevice.Format? = nil,
        assumesDepthDeliverySupported: Bool = true,
        outputProfile: CaptureOutputProfile = CaptureOutputProfileCatalog.releaseDefaultProfile
    ) throws -> ResolvedCaptureOutputProfile {
        try outputProfile.resolvedPhotoOutput(
            capabilities: CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: activeFormat,
                assumesDepthDeliverySupported: assumesDepthDeliverySupported
            )
        )
    }
}

/// Delegate retained for exactly one `AVCapturePhotoOutput.capturePhoto` call.
///
/// `AVCapturePhotoOutput` does not retain its delegate, so the provider stores
/// this object until completion. The delegate only forwards the produced
/// `AVCapturePhoto`; packaging and persistence happen elsewhere.
nonisolated final class SingleCamPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<SingleCamPhotoCaptureResult, Error>) -> Void
    private let expectsLivePhotoMovie: Bool
    private let livePhotoVideoCodec: String?
    private let capturesLivePhotoAudio: Bool
    private var photoResult: Result<AVCapturePhoto, Error>?
    private var livePhotoMovieResult: Result<CapturedLivePhotoMovie, Error>?
    private var didFinishCapture = false
    private var didComplete = false

    init(
        completion: @escaping (Result<SingleCamPhotoCaptureResult, Error>) -> Void,
        expectsLivePhotoMovie: Bool = false,
        livePhotoVideoCodec: String? = nil,
        capturesLivePhotoAudio: Bool = false
    ) {
        self.completion = completion
        self.expectsLivePhotoMovie = expectsLivePhotoMovie
        self.livePhotoVideoCodec = livePhotoVideoCodec
        self.capturesLivePhotoAudio = capturesLivePhotoAudio
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            photoResult = .failure(error)
        } else {
            photoResult = .success(photo)
        }
        completeIfReady()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            livePhotoMovieResult = .failure(error)
        } else {
            let dimensions = CapturePhotoDimensions(resolvedSettings.livePhotoMovieDimensions)
            livePhotoMovieResult = .success(CapturedLivePhotoMovie(
                fileURL: outputFileURL,
                duration: duration,
                photoDisplayTime: photoDisplayTime,
                dimensions: dimensions,
                codec: livePhotoVideoCodec,
                capturesAudio: capturesLivePhotoAudio
            ))
        }
        completeIfReady()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error, photoResult == nil {
            photoResult = .failure(error)
        }
        didFinishCapture = true
        completeIfReady()
    }

    private func completeIfReady() {
        guard !didComplete, didFinishCapture, let photoResult else {
            return
        }
        didComplete = true

        switch photoResult {
        case .failure(let error):
            completion(.failure(error))
        case .success(let photo):
            if expectsLivePhotoMovie {
                switch livePhotoMovieResult {
                case .success(let movie):
                    completion(.success(SingleCamPhotoCaptureResult(
                        photo: photo,
                        livePhotoMovie: movie
                    )))
                case .failure(let error):
                    completion(.success(SingleCamPhotoCaptureResult(
                        photo: photo,
                        livePhotoFailureReason: TAPDiagnostics.describe(error)
                    )))
                case .none:
                    completion(.success(SingleCamPhotoCaptureResult(
                        photo: photo,
                        livePhotoFailureReason: "Live Photo movie was not delivered."
                    )))
                }
            } else {
                completion(.success(SingleCamPhotoCaptureResult(photo: photo)))
            }
        }
    }
}
