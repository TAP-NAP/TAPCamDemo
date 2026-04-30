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
    static let validFillColor = TAPRGBAColor(red: 42, green: 205, blue: 132, alpha: 104)
    static let boundaryColor = TAPRGBAColor(red: 255, green: 214, blue: 10, alpha: 230)

    static func validMask(for depthMap: TAPMetricDepthMap) throws -> TAPDepthMaskVisualization {
        let pixels = overlayPixels(for: depthMap)
        let validSampleCount = depthMap.samples.filter { $0.isFinite && $0 > 0 }.count
        let totalSampleCount = depthMap.samples.count
        let image = try TAPDepthRGBAImageRenderer.image(pixels: pixels, width: depthMap.width, height: depthMap.height)

        return TAPDepthMaskVisualization(
            image: image,
            validSampleCount: validSampleCount,
            totalSampleCount: totalSampleCount,
            validRatio: totalSampleCount == 0 ? 0 : Double(validSampleCount) / Double(totalSampleCount),
            legendStops: [
                TAPDepthLegendStop(position: 0, label: "Valid depth", color: validFillColor),
                TAPDepthLegendStop(position: 1, label: "Valid/invalid edge", color: boundaryColor)
            ]
        )
    }

    static func overlayPixels(for depthMap: TAPMetricDepthMap) -> [UInt8] {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(depthMap.samples.count * 4)

        for y in 0..<depthMap.height {
            for x in 0..<depthMap.width {
                guard isValid(depthMap, x: x, y: y) else {
                    pixels.append(contentsOf: [0, 0, 0, 0])
                    continue
                }

                let color = isBoundary(depthMap, x: x, y: y) ? boundaryColor : validFillColor
                pixels.append(contentsOf: premultipliedBytes(color))
            }
        }

        return pixels
    }

    private static func isBoundary(_ depthMap: TAPMetricDepthMap, x: Int, y: Int) -> Bool {
        let neighbors = [
            (x - 1, y),
            (x + 1, y),
            (x, y - 1),
            (x, y + 1)
        ]
        return neighbors.contains { neighborX, neighborY in
            !isValid(depthMap, x: neighborX, y: neighborY)
        }
    }

    private static func isValid(_ depthMap: TAPMetricDepthMap, x: Int, y: Int) -> Bool {
        depthMap.sample(x: x, y: y) != nil
    }

    private static func premultipliedBytes(_ color: TAPRGBAColor) -> [UInt8] {
        let alphaScale = Double(color.alpha) / 255.0
        return [
            UInt8((Double(color.red) * alphaScale).rounded()),
            UInt8((Double(color.green) * alphaScale).rounded()),
            UInt8((Double(color.blue) * alphaScale).rounded()),
            color.alpha
        ]
    }
}
