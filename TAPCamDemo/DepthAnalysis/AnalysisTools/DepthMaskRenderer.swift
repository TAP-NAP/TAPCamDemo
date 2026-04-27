//
//  DepthMaskRenderer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics

/// Renders a valid-depth coverage mask from the metric depth map.
///
/// Mask mode principle:
/// A sample is considered valid when it is finite and greater than zero. The
/// renderer outputs white for valid samples and black for invalid samples so a
/// user can immediately see where plane fitting and point reads have usable
/// depth data.
///
/// Data dependencies:
/// - `TAPMetricDepthMap.samples` after `AVDepthData` has been normalized into
///   `kCVPixelFormatType_DepthFloat32`.
/// - No camera intrinsics are required for mask rendering; mask is image-space
///   coverage only.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/avfoundation/avdepthdata
/// - https://developer.apple.com/documentation/coregraphics/cgimage
nonisolated enum TAPDepthMaskRenderer {
    static func validMask(for depthMap: TAPMetricDepthMap) throws -> CGImage {
        let pixels = depthMap.samples.flatMap { value -> [UInt8] in
            value.isFinite && value > 0 ? [255, 255, 255, 255] : [0, 0, 0, 255]
        }

        return try TAPDepthRGBAImageRenderer.image(pixels: pixels, width: depthMap.width, height: depthMap.height)
    }
}
