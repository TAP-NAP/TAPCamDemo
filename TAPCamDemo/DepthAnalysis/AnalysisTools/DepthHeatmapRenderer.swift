//
//  DepthHeatmapRenderer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics
import Foundation

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
    static func heatmap(for depthMap: TAPMetricDepthMap) throws -> TAPDepthHeatmapVisualization {
        _ = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(for: depthMap)
        let validSamples = depthMap.samples.filter { $0.isFinite && $0 > 0 }
        guard let minDepth = validSamples.min(), let maxDepth = validSamples.max() else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }

        let rangeMeters = minDepth...maxDepth
        let pixels = heatmapPixels(for: depthMap, rangeMeters: rangeMeters)
        let image = try TAPDepthRGBAImageRenderer.image(pixels: pixels, width: depthMap.width, height: depthMap.height)

        return TAPDepthHeatmapVisualization(
            image: image,
            rangeMeters: rangeMeters,
            legendStops: legendStops(rangeMeters: rangeMeters),
            rangeScope: .global
        )
    }

    static func heatmap(for depthMap: TAPMetricDepthMap, region: CGRect) throws -> TAPDepthHeatmapVisualization {
        _ = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(for: depthMap)
        let bounds = pixelBounds(region, width: depthMap.width, height: depthMap.height)
        var validSamples: [Float] = []
        validSamples.reserveCapacity(max(bounds.width * bounds.height, 0))

        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                if let value = depthMap.sample(x: x, y: y) {
                    validSamples.append(value)
                }
            }
        }

        guard let minDepth = validSamples.min(), let maxDepth = validSamples.max() else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }

        let rangeMeters = minDepth...maxDepth
        let visibleRegion = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        let pixels = heatmapPixels(for: depthMap, rangeMeters: rangeMeters, visibleRegion: visibleRegion)
        let image = try TAPDepthRGBAImageRenderer.image(pixels: pixels, width: depthMap.width, height: depthMap.height)

        return TAPDepthHeatmapVisualization(
            image: image,
            rangeMeters: rangeMeters,
            legendStops: legendStops(rangeMeters: rangeMeters),
            rangeScope: .region
        )
    }

    static func heatmapPixels(
        for depthMap: TAPMetricDepthMap,
        rangeMeters: ClosedRange<Float>
    ) -> [UInt8] {
        heatmapPixels(for: depthMap, rangeMeters: rangeMeters, visibleRegion: nil)
    }

    static func heatmapPixels(
        for depthMap: TAPMetricDepthMap,
        rangeMeters: ClosedRange<Float>,
        visibleRegion: CGRect?
    ) -> [UInt8] {
        guard TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap) else {
            return []
        }

        let range = max(rangeMeters.upperBound - rangeMeters.lowerBound, 0.001)
        let bounds = visibleRegion.map { pixelBounds($0, width: depthMap.width, height: depthMap.height) }
        var pixels: [UInt8] = []
        pixels.reserveCapacity(depthMap.samples.count * 4)

        for y in 0..<depthMap.height {
            for x in 0..<depthMap.width {
                if let bounds,
                   (x < bounds.minX || x >= bounds.maxX || y < bounds.minY || y >= bounds.maxY) {
                    pixels.append(contentsOf: [0, 0, 0, 0])
                    continue
                }

                let value = depthMap.sample(x: x, y: y)
                guard let value else {
                    pixels.append(contentsOf: [0, 0, 0, 0])
                    continue
                }

                let normalized = min(max((value - rangeMeters.lowerBound) / range, 0), 1)
                pixels.append(contentsOf: viridisColor(normalized: normalized).bytes)
            }
        }

        return pixels
    }

    static func croppedHeatmapPixels(
        for depthMap: TAPMetricDepthMap,
        rangeMeters: ClosedRange<Float>,
        region: CGRect
    ) -> (pixels: [UInt8], width: Int, height: Int) {
        guard TAPDepthAnalysisInputValidation.isValidDepthMapLayout(depthMap) else {
            return ([], 0, 0)
        }

        let bounds = pixelBounds(region, width: depthMap.width, height: depthMap.height)
        let range = max(rangeMeters.upperBound - rangeMeters.lowerBound, 0.001)
        var pixels: [UInt8] = []
        pixels.reserveCapacity(max(bounds.width * bounds.height * 4, 0))

        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                guard let value = depthMap.sample(x: x, y: y) else {
                    pixels.append(contentsOf: [0, 0, 0, 0])
                    continue
                }
                let normalized = min(max((value - rangeMeters.lowerBound) / range, 0), 1)
                pixels.append(contentsOf: viridisColor(normalized: normalized).bytes)
            }
        }

        return (pixels, bounds.width, bounds.height)
    }

    static func legendStops(rangeMeters: ClosedRange<Float>) -> [TAPDepthLegendStop] {
        [
            TAPDepthLegendStop(position: 0.0, label: "Near \(formatMeters(rangeMeters.lowerBound))", color: viridisColor(normalized: 0.0)),
            TAPDepthLegendStop(position: 0.25, label: formatMeters(interpolate(rangeMeters, at: 0.25)), color: viridisColor(normalized: 0.25)),
            TAPDepthLegendStop(position: 0.5, label: formatMeters(interpolate(rangeMeters, at: 0.5)), color: viridisColor(normalized: 0.5)),
            TAPDepthLegendStop(position: 0.75, label: formatMeters(interpolate(rangeMeters, at: 0.75)), color: viridisColor(normalized: 0.75)),
            TAPDepthLegendStop(position: 1.0, label: "Far \(formatMeters(rangeMeters.upperBound))", color: viridisColor(normalized: 1.0))
        ]
    }

    static func viridisColor(normalized: Float) -> TAPRGBAColor {
        let t = min(max(Double(normalized), 0), 1)
        let anchors: [(position: Double, color: TAPRGBAColor)] = [
            (0.00, TAPRGBAColor(red: 68, green: 1, blue: 84, alpha: 255)),
            (0.25, TAPRGBAColor(red: 59, green: 82, blue: 139, alpha: 255)),
            (0.50, TAPRGBAColor(red: 33, green: 145, blue: 140, alpha: 255)),
            (0.75, TAPRGBAColor(red: 94, green: 201, blue: 98, alpha: 255)),
            (1.00, TAPRGBAColor(red: 253, green: 231, blue: 37, alpha: 255))
        ]

        guard let upperIndex = anchors.firstIndex(where: { $0.position >= t }) else {
            return anchors[anchors.count - 1].color
        }
        guard upperIndex > 0 else {
            return anchors[0].color
        }

        let lower = anchors[upperIndex - 1]
        let upper = anchors[upperIndex]
        let span = max(upper.position - lower.position, 0.001)
        let localT = (t - lower.position) / span
        return TAPRGBAColor(
            red: interpolate(lower.color.red, upper.color.red, t: localT),
            green: interpolate(lower.color.green, upper.color.green, t: localT),
            blue: interpolate(lower.color.blue, upper.color.blue, t: localT),
            alpha: 255
        )
    }

    private static func interpolate(_ range: ClosedRange<Float>, at position: Double) -> Float {
        range.lowerBound + Float(position) * (range.upperBound - range.lowerBound)
    }

    private static func interpolate(_ lhs: UInt8, _ rhs: UInt8, t: Double) -> UInt8 {
        UInt8((Double(lhs) + (Double(rhs) - Double(lhs)) * t).rounded())
    }

    private static func formatMeters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }

    private static func pixelBounds(_ region: CGRect, width: Int, height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int) {
        guard width >= 0, height >= 0, TAPDepthAnalysisInputValidation.isFiniteRegion(region) else {
            return (0, 0, 0, 0, 0, 0)
        }

        let minX = min(max(Int(region.minX.rounded(.down)), 0), width)
        let minY = min(max(Int(region.minY.rounded(.down)), 0), height)
        let maxX = min(max(Int(region.maxX.rounded(.up)), minX), width)
        let maxY = min(max(Int(region.maxY.rounded(.up)), minY), height)
        return (minX, minY, maxX, maxY, maxX - minX, maxY - minY)
    }
}
