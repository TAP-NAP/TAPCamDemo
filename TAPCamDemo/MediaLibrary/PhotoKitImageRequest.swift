//
//  PhotoKitImageRequest.swift
//  TAPCamDemo
//

import Foundation
@preconcurrency import Photos
import UIKit

/// Interprets PhotoKit's image callback without conflating a degraded preview
/// with the final display image. `nil` means the request should keep waiting.
nonisolated enum PhotoKitDisplayImageResultAdapter {
    static func result(
        image: UIImage?,
        info: [AnyHashable: Any]?,
        pixelLength: Int,
        allowsNetworkAccess: Bool
    ) -> Result<Data, any Error>? {
        if info?[PHImageCancelledKey] as? Bool == true {
            return .failure(CancellationError())
        }
        if let error = info?[PHImageErrorKey] as? Error {
            return .failure(PhotoKitMediaFetchFailure.resourceError(error))
        }
        if info?[PHImageResultIsDegradedKey] as? Bool == true {
            return nil
        }
        if !allowsNetworkAccess,
           info?[PHImageResultIsInCloudKey] as? Bool == true,
           image == nil {
            return .failure(PhotoKitNetworkAccessRequired())
        }
        guard let image,
              let data = DepthAlbumThumbnailJPEGRenderer.aspectPreservingData(
                from: image,
                maximumPixelLength: pixelLength
              ) else {
            return .failure(MediaFetchFailure.decode)
        }
        return .success(data)
    }
}

/// Bounded display-image adapter used by the photo viewer. A local-only
/// request can identify an iCloud-only original without starting network work.
nonisolated final class PhotoKitDisplayImageRequestBridge: @unchecked Sendable {
    private let manager: PHImageManager
    private let allowsNetworkAccess: Bool
    private let progress: @Sendable (Double?) -> Void
    private let lifecycle: PhotoKitRequestLifecycle<PHImageRequestID, Data>

    init(
        manager: PHImageManager = .default(),
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void
    ) {
        self.manager = manager
        self.allowsNetworkAccess = allowsNetworkAccess
        self.progress = progress
        self.lifecycle = PhotoKitRequestLifecycle(
            cancelRequest: { requestID in
                manager.cancelImageRequest(requestID)
            },
            onFinish: { result in
                if case .success = result, allowsNetworkAccess {
                    progress(1)
                }
            }
        )
    }

    func start(asset: PHAsset, pixelLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            guard lifecycle.install(continuation: continuation) else {
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = allowsNetworkAccess
            options.progressHandler = { [weak self] value, error, _, _ in
                if let error {
                    self?.lifecycle.finish(
                        .failure(PhotoKitMediaFetchFailure.resourceError(error))
                    )
                } else {
                    self?.receiveProgress(value)
                }
            }
            let targetLength = max(pixelLength, 1)
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: targetLength, height: targetLength),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                self?.receive(
                    image: image,
                    info: info,
                    pixelLength: targetLength
                )
            }
            lifecycle.install(requestID: requestID)
        }
    }

    func cancel() {
        lifecycle.cancel()
    }

    private func receive(
        image: UIImage?,
        info: [AnyHashable: Any]?,
        pixelLength: Int
    ) {
        guard let result = PhotoKitDisplayImageResultAdapter.result(
            image: image,
            info: info,
            pixelLength: pixelLength,
            allowsNetworkAccess: allowsNetworkAccess
        ) else {
            return
        }
        lifecycle.finish(result)
    }

    private func receiveProgress(_ value: Double) {
        lifecycle.reportProgress(value, to: progress)
    }
}
