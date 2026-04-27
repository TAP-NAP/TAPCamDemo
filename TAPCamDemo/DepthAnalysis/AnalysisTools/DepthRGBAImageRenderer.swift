//
//  DepthRGBAImageRenderer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics
import Foundation

/// Shared RGBA-to-CGImage bridge for depth analysis tools.
///
/// The analysis module intentionally keeps v1 rendering native and simple:
/// heatmaps and masks are diagnostic images generated from metric depth samples,
/// not alternate sources of measurement truth. The measurement path always
/// stays in `TAPMetricDepthMap.samples`.
nonisolated enum TAPDepthRGBAImageRenderer {
    static func image(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TAPDepthAnalysisError.imageRenderFailed
        }

        return image
    }
}
