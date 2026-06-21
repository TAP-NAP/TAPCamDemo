//
//  TAPPendingCaptureThumbnailRenderer.swift
//  TAPCamDemo
//

@preconcurrency import ImageIO
import Foundation
import UIKit

nonisolated enum TAPPendingCaptureThumbnailRenderer {
    private static let pixelLength = 320
    private static let compressionQuality: CGFloat = 0.78

    static func thumbnailData(from heicData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelLength
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelLength, height: pixelLength), format: format)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { context in
            let canvas = CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(canvas)
            UIImage(cgImage: image).draw(in: aspectFillRect(imageSize: CGSize(width: image.width, height: image.height), targetSize: canvas.size))
        }
    }

    private static func aspectFillRect(imageSize: CGSize, targetSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: targetSize)
        }
        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}
