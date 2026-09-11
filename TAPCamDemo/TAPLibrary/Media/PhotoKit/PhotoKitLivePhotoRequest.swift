//
//  PhotoKitLivePhotoRequest.swift
//  TAPCamDemo
//

import Foundation
@preconcurrency import Photos
import UIKit

/// Interprets only Live Photo callbacks. A degraded value is provisional and
/// therefore does not terminate the request.
nonisolated enum PhotoKitLivePhotoResultAdapter {
    static func result(
        livePhoto: PHLivePhoto?,
        info: [AnyHashable: Any]?
    ) -> Result<LibraryLivePhoto, any Error>? {
        if info?[PHImageCancelledKey] as? Bool == true {
            return .failure(CancellationError())
        }
        if let error = info?[PHImageErrorKey] as? Error {
            return .failure(PhotoKitMediaFetchFailure.map(error))
        }
        if info?[PHImageResultIsDegradedKey] as? Bool == true {
            return nil
        }
        guard let livePhoto else {
            return .failure(MediaFetchFailure.decode)
        }
        return .success(LibraryLivePhoto(livePhoto))
    }
}

nonisolated final class PhotoKitLivePhotoRequestBridge: @unchecked Sendable {
    private let manager: PHImageManager
    private let progress: @Sendable (Double?) -> Void
    private let lifecycle: PhotoKitRequestLifecycle<PHImageRequestID, LibraryLivePhoto>

    init(
        manager: PHImageManager = .default(),
        progress: @escaping @Sendable (Double?) -> Void
    ) {
        self.manager = manager
        self.progress = progress
        self.lifecycle = PhotoKitRequestLifecycle(
            cancelRequest: { requestID in
                manager.cancelImageRequest(requestID)
            },
            onFinish: { result in
                if case .success = result {
                    progress(1)
                }
            }
        )
    }

    func start(asset: PHAsset, targetSize: CGSize) async throws -> LibraryLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            guard lifecycle.install(continuation: continuation) else {
                return
            }

            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.progressHandler = { [weak self] value, error, _, _ in
                if let error {
                    self?.lifecycle.finish(
                        .failure(PhotoKitMediaFetchFailure.map(error))
                    )
                } else {
                    self?.receiveProgress(value)
                }
            }
            let requestID = manager.requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] livePhoto, info in
                self?.receive(livePhoto: livePhoto, info: info)
            }
            lifecycle.install(requestID: requestID)
        }
    }

    func cancel() {
        lifecycle.cancel()
    }

    private func receive(livePhoto: PHLivePhoto?, info: [AnyHashable: Any]?) {
        guard let result = PhotoKitLivePhotoResultAdapter.result(
            livePhoto: livePhoto,
            info: info
        ) else {
            return
        }
        lifecycle.finish(result)
    }

    private func receiveProgress(_ value: Double) {
        lifecycle.reportProgress(value, to: progress)
    }
}
