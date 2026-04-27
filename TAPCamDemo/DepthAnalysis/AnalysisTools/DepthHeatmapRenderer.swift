//
//  DepthHeatmapRenderer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics

/// Converts metric depth pixels into a false-color diagnostic heatmap.
///
/// Depth mode principle:
/// Each valid metric depth sample is min/max normalized across the current map
/// and mapped to a visible color ramp. Near/far colors are only a display aid;
/// the actual distance remains the Float32 meter value in `samples`.
///
/// Called APIs and data:
/// - `CVPixelBuffer` samples are copied into `TAPMetricDepthMap` by
///   `TAPDepthMapReader` before this renderer runs.
/// - `CGImage` is created through `TAPDepthRGBAImageRenderer`, so SwiftUI can
///   display the diagnostic image without introducing Metal in v1.
///
/// Reference docs:
/// - https://developer.apple.com/documentation/corevideo/cvpixelbuffer
/// - https://developer.apple.com/documentation/coregraphics/cgimage
nonisolated enum TAPDepthHeatmapRenderer {
    static func heatmap(for depthMap: TAPMetricDepthMap) throws -> CGImage {
        let validSamples = depthMap.samples.filter { $0.isFinite && $0 > 0 }
        guard let minDepth = validSamples.min(), let maxDepth = validSamples.max() else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }

        let range = max(maxDepth - minDepth, 0.001)
        let pixels = depthMap.samples.flatMap { value -> [UInt8] in
            guard value.isFinite && value > 0 else {
                return [0, 0, 0, 255]
            }
            let normalized = min(max((value - minDepth) / range, 0), 1)
            return jetColor(normalized: normalized)
        }

        return try TAPDepthRGBAImageRenderer.image(pixels: pixels, width: depthMap.width, height: depthMap.height)
    }

    private static func jetColor(normalized: Float) -> [UInt8] {
        let t = Double(normalized)
        let red = UInt8((min(max(1.5 - abs(4.0 * t - 3.0), 0), 1) * 255).rounded())
        let green = UInt8((min(max(1.5 - abs(4.0 * t - 2.0), 0), 1) * 255).rounded())
        let blue = UInt8((min(max(1.5 - abs(4.0 * t - 1.0), 0), 1) * 255).rounded())
        return [red, green, blue, 255]
    }
}
