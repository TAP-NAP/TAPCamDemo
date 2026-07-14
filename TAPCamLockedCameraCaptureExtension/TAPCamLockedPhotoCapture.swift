//
//  TAPCamLockedPhotoCapture.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreVideo
import Foundation

nonisolated struct TAPCamLockedPhotoCaptureResult: Equatable, Sendable {
    let photoByteCount: Int
    let photoWidth: Int
    let photoHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let depthPixelFormat: OSType
    let isDepthDataFiltered: Bool
    let storedFileName: String
}

nonisolated struct TAPCamLockedPhotoCapturePayload: Sendable {
    let photoData: Data
    let photoWidth: Int
    let photoHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let depthPixelFormat: OSType
    let isDepthDataFiltered: Bool

    func stored(fileName: String) -> TAPCamLockedPhotoCaptureResult {
        TAPCamLockedPhotoCaptureResult(
            photoByteCount: photoData.count,
            photoWidth: photoWidth,
            photoHeight: photoHeight,
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            depthPixelFormat: depthPixelFormat,
            isDepthDataFiltered: isDepthDataFiltered,
            storedFileName: fileName
        )
    }
}

nonisolated final class TAPCamLockedPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    typealias Completion = @Sendable (
        Result<TAPCamLockedPhotoCapturePayload, TAPCamLockedCaptureServiceError>
    ) -> Void

    private let completion: Completion
    private var processedResult: Result<TAPCamLockedPhotoCapturePayload, TAPCamLockedCaptureServiceError>?
    private var didComplete = false

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            processedResult = .failure(.photoCaptureFailed(error.localizedDescription))
            return
        }

        guard let photoData = photo.fileDataRepresentation() else {
            processedResult = .failure(.missingPhotoData)
            return
        }
        guard let depthData = photo.depthData else {
            processedResult = .failure(.missingDepthData)
            return
        }

        let photoDimensions = photo.resolvedSettings.photoDimensions
        let depthMap = depthData.depthDataMap
        processedResult = .success(
            TAPCamLockedPhotoCapturePayload(
                photoData: photoData,
                photoWidth: Int(photoDimensions.width),
                photoHeight: Int(photoDimensions.height),
                depthWidth: CVPixelBufferGetWidth(depthMap),
                depthHeight: CVPixelBufferGetHeight(depthMap),
                depthPixelFormat: CVPixelBufferGetPixelFormatType(depthMap),
                isDepthDataFiltered: depthData.isDepthDataFiltered
            )
        )
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        guard !didComplete else { return }
        didComplete = true

        if let error {
            completion(.failure(.photoCaptureFailed(error.localizedDescription)))
        } else {
            completion(processedResult ?? .failure(.missingPhotoData))
        }
    }
}
