//
//  DepthContourRenderer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/5/4.
//

import CoreGraphics
import Foundation

/// Renders image-space metric depth contours from the dense Float32 depth map.
///
/// Contour mode principle:
/// The line overlay is a diagnostic view only. The renderer finds neighboring
/// valid depth pixels that cross each requested meter level, then writes a
/// transparent RGBA overlay with high-contrast lines and compact meter labels.
/// Measurements still come from `TAPMetricDepthMap.samples`.
nonisolated enum TAPDepthContourRenderer {
    static let minimumLineCount = 6
    static let defaultLineCount = 10
    static let maximumLineCount = 24

    static let contourLineColor = TAPRGBAColor(red: 255, green: 244, blue: 182, alpha: 255)
    static let contourShadowColor = TAPRGBAColor(red: 0, green: 0, blue: 0, alpha: 190)
    static let contourLabelFillColor = TAPRGBAColor(red: 255, green: 255, blue: 244, alpha: 255)
    static let contourLabelBackgroundColor = TAPRGBAColor(red: 0, green: 0, blue: 0, alpha: 176)

    static func contours(
        for depthMap: TAPMetricDepthMap,
        lineCount: Int = defaultLineCount
    ) throws -> TAPDepthContourVisualization {
        let products = try contourProducts(for: depthMap, lineCount: lineCount)
        let image = try TAPDepthRGBAImageRenderer.image(
            pixels: products.pixels,
            width: depthMap.width,
            height: depthMap.height
        )

        return TAPDepthContourVisualization(
            image: image,
            rangeMeters: products.rangeMeters,
            contourIntervalMeters: products.contourIntervalMeters,
            lineCount: products.lineCount,
            levels: products.levels,
            legendStops: legendStops(
                rangeMeters: products.rangeMeters,
                contourIntervalMeters: products.contourIntervalMeters,
                lineCount: products.lineCount
            )
        )
    }

    static func contourPixels(
        for depthMap: TAPMetricDepthMap,
        lineCount: Int = defaultLineCount
    ) throws -> [UInt8] {
        try contourProducts(for: depthMap, lineCount: lineCount).pixels
    }

    static func contourLevels(
        rangeMeters: ClosedRange<Float>,
        lineCount: Int
    ) -> [TAPDepthContourLevel] {
        let count = clampedLineCount(lineCount)
        let span = rangeMeters.upperBound - rangeMeters.lowerBound
        guard span.isFinite, span > 0 else {
            return [
                TAPDepthContourLevel(
                    depthMeters: rangeMeters.lowerBound,
                    label: formatMeters(rangeMeters.lowerBound),
                    position: 0.5
                )
            ]
        }

        let step = span / Float(count + 1)
        return (1...count).map { index in
            let value = rangeMeters.lowerBound + Float(index) * step
            return TAPDepthContourLevel(
                depthMeters: value,
                label: formatMeters(value),
                position: Double(index) / Double(count + 1)
            )
        }
    }

    private static func contourProducts(
        for depthMap: TAPMetricDepthMap,
        lineCount: Int
    ) throws -> (
        pixels: [UInt8],
        rangeMeters: ClosedRange<Float>,
        contourIntervalMeters: Float,
        lineCount: Int,
        levels: [TAPDepthContourLevel]
    ) {
        let validSamples = depthMap.samples.filter { $0.isFinite && $0 > 0 }
        guard let minDepth = validSamples.min(), let maxDepth = validSamples.max() else {
            throw TAPDepthAnalysisError.noValidDepthSamples
        }

        let rangeMeters = minDepth...maxDepth
        let levels = contourLevels(rangeMeters: rangeMeters, lineCount: lineCount)
        let interval = contourInterval(rangeMeters: rangeMeters, lineCount: levels.count)
        let pixels = renderPixels(for: depthMap, levels: levels)
        return (pixels, rangeMeters, interval, levels.count, levels)
    }

    private static func renderPixels(
        for depthMap: TAPMetricDepthMap,
        levels: [TAPDepthContourLevel]
    ) -> [UInt8] {
        var pixels = Array(repeating: UInt8(0), count: max(depthMap.samples.count * 4, 0))
        guard depthMap.width > 1, depthMap.height > 1 else {
            return pixels
        }

        let labelScale = labelPixelScale(width: depthMap.width, height: depthMap.height)
        var occupiedLabelRects: [PixelRect] = []

        for level in levels {
            var candidates: [PixelPoint] = []
            candidates.reserveCapacity(depthMap.width * 2)

            for y in 0..<depthMap.height {
                for x in 0..<depthMap.width {
                    guard let value = depthMap.sample(x: x, y: y) else {
                        continue
                    }

                    if x + 1 < depthMap.width,
                       let next = depthMap.sample(x: x + 1, y: y),
                       crosses(level.depthMeters, lhs: value, rhs: next) {
                        drawContourPoint(
                            x: x,
                            y: y,
                            width: depthMap.width,
                            height: depthMap.height,
                            pixels: &pixels
                        )
                        drawContourPoint(
                            x: x + 1,
                            y: y,
                            width: depthMap.width,
                            height: depthMap.height,
                            pixels: &pixels
                        )
                        candidates.append(PixelPoint(x: x, y: y))
                    }

                    if y + 1 < depthMap.height,
                       let next = depthMap.sample(x: x, y: y + 1),
                       crosses(level.depthMeters, lhs: value, rhs: next) {
                        drawContourPoint(
                            x: x,
                            y: y,
                            width: depthMap.width,
                            height: depthMap.height,
                            pixels: &pixels
                        )
                        drawContourPoint(
                            x: x,
                            y: y + 1,
                            width: depthMap.width,
                            height: depthMap.height,
                            pixels: &pixels
                        )
                        candidates.append(PixelPoint(x: x, y: y))
                    }
                }
            }

            drawLabel(
                level.label,
                near: labelAnchor(from: candidates, width: depthMap.width, height: depthMap.height),
                scale: labelScale,
                occupiedRects: &occupiedLabelRects,
                isValidForLabel: { x, y in depthMap.sample(x: x, y: y) != nil },
                width: depthMap.width,
                height: depthMap.height,
                pixels: &pixels
            )
        }

        return pixels
    }

    private static func drawContourPoint(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        drawSquare(
            centerX: x,
            centerY: y,
            radius: 1,
            color: contourShadowColor,
            width: width,
            height: height,
            pixels: &pixels
        )
        drawPixel(
            x: x,
            y: y,
            color: contourLineColor,
            width: width,
            height: height,
            pixels: &pixels
        )
    }

    private static func drawLabel(
        _ label: String,
        near anchor: PixelPoint?,
        scale: Int,
        occupiedRects: inout [PixelRect],
        isValidForLabel: (Int, Int) -> Bool,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        guard let anchor else {
            return
        }

        let textSize = bitmapTextSize(label, scale: scale)
        let padding = max(2, scale * 2)
        let rectSize = PixelSize(
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        let preferredOrigin = PixelPoint(
            x: anchor.x - rectSize.width / 2,
            y: anchor.y - rectSize.height / 2
        )
        let origin = labelOrigin(
            preferredOrigin: preferredOrigin,
            rectSize: rectSize,
            occupiedRects: occupiedRects,
            width: width,
            height: height
        )
        let rect = PixelRect(origin: origin, size: rectSize)
        guard labelRectFits(rect, width: width, height: height),
              labelRectIsValid(rect, isValidForLabel: isValidForLabel) else {
            return
        }
        occupiedRects.append(rect.insetBy(dx: -2 * scale, dy: -2 * scale))

        drawFilledRect(
            rect,
            color: contourLabelBackgroundColor,
            width: width,
            height: height,
            pixels: &pixels
        )
        drawBitmapText(
            label,
            origin: PixelPoint(x: origin.x + padding + scale, y: origin.y + padding + scale),
            scale: scale,
            color: contourShadowColor,
            width: width,
            height: height,
            pixels: &pixels
        )
        drawBitmapText(
            label,
            origin: PixelPoint(x: origin.x + padding, y: origin.y + padding),
            scale: scale,
            color: contourLabelFillColor,
            width: width,
            height: height,
            pixels: &pixels
        )
    }

    private static func labelAnchor(
        from candidates: [PixelPoint],
        width: Int,
        height: Int
    ) -> PixelPoint? {
        guard !candidates.isEmpty else {
            return nil
        }

        let center = PixelPoint(x: width / 2, y: height / 2)
        return candidates.min { lhs, rhs in
            squaredDistance(lhs, center) < squaredDistance(rhs, center)
        }
    }

    private static func labelOrigin(
        preferredOrigin: PixelPoint,
        rectSize: PixelSize,
        occupiedRects: [PixelRect],
        width: Int,
        height: Int
    ) -> PixelPoint {
        let offsets = [
            PixelPoint(x: 0, y: 0),
            PixelPoint(x: 12, y: -10),
            PixelPoint(x: -12, y: 10),
            PixelPoint(x: 16, y: 12),
            PixelPoint(x: -16, y: -12),
            PixelPoint(x: 0, y: 18)
        ]

        for offset in offsets {
            let origin = clampedOrigin(
                PixelPoint(x: preferredOrigin.x + offset.x, y: preferredOrigin.y + offset.y),
                rectSize: rectSize,
                width: width,
                height: height
            )
            let rect = PixelRect(origin: origin, size: rectSize)
            if !occupiedRects.contains(where: { $0.intersects(rect) }) {
                return origin
            }
        }

        return clampedOrigin(preferredOrigin, rectSize: rectSize, width: width, height: height)
    }

    private static func clampedOrigin(
        _ origin: PixelPoint,
        rectSize: PixelSize,
        width: Int,
        height: Int
    ) -> PixelPoint {
        PixelPoint(
            x: min(max(origin.x, 0), max(width - rectSize.width, 0)),
            y: min(max(origin.y, 0), max(height - rectSize.height, 0))
        )
    }

    private static func labelRectFits(_ rect: PixelRect, width: Int, height: Int) -> Bool {
        rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= width && rect.maxY <= height
    }

    private static func labelRectIsValid(
        _ rect: PixelRect,
        isValidForLabel: (Int, Int) -> Bool
    ) -> Bool {
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX where !isValidForLabel(x, y) {
                return false
            }
        }
        return true
    }

    private static func drawBitmapText(
        _ text: String,
        origin: PixelPoint,
        scale: Int,
        color: TAPRGBAColor,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        var cursorX = origin.x
        for character in text.lowercased() {
            let glyph = bitmapGlyph(for: character)
            for row in 0..<glyph.rows.count {
                let pattern = Array(glyph.rows[row])
                for column in 0..<pattern.count where pattern[column] == "1" {
                    drawFilledRect(
                        PixelRect(
                            origin: PixelPoint(x: cursorX + column * scale, y: origin.y + row * scale),
                            size: PixelSize(width: scale, height: scale)
                        ),
                        color: color,
                        width: width,
                        height: height,
                        pixels: &pixels
                    )
                }
            }
            cursorX += (glyph.width + 1) * scale
        }
    }

    private static func bitmapTextSize(_ text: String, scale: Int) -> PixelSize {
        let widths = text.lowercased().map { bitmapGlyph(for: $0).width }
        let totalCharacterWidth = widths.reduce(0, +)
        let spacing = max(widths.count - 1, 0)
        return PixelSize(width: (totalCharacterWidth + spacing) * scale, height: 5 * scale)
    }

    private static func drawSquare(
        centerX: Int,
        centerY: Int,
        radius: Int,
        color: TAPRGBAColor,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        for y in (centerY - radius)...(centerY + radius) {
            for x in (centerX - radius)...(centerX + radius) {
                drawPixel(x: x, y: y, color: color, width: width, height: height, pixels: &pixels)
            }
        }
    }

    private static func drawFilledRect(
        _ rect: PixelRect,
        color: TAPRGBAColor,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        let minX = min(max(rect.minX, 0), width)
        let maxX = min(max(rect.maxX, minX), width)
        let minY = min(max(rect.minY, 0), height)
        let maxY = min(max(rect.maxY, minY), height)
        guard minX < maxX, minY < maxY else {
            return
        }

        for y in minY..<maxY {
            for x in minX..<maxX {
                drawPixel(x: x, y: y, color: color, width: width, height: height, pixels: &pixels)
            }
        }
    }

    private static func drawPixel(
        x: Int,
        y: Int,
        color: TAPRGBAColor,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        guard x >= 0, y >= 0, x < width, y < height else {
            return
        }

        let offset = (y * width + x) * 4
        guard offset + 3 < pixels.count else {
            return
        }

        pixels[offset] = color.red
        pixels[offset + 1] = color.green
        pixels[offset + 2] = color.blue
        pixels[offset + 3] = color.alpha
    }

    private static func crosses(_ level: Float, lhs: Float, rhs: Float) -> Bool {
        let lower = min(lhs, rhs)
        let upper = max(lhs, rhs)
        return upper - lower > 0.0001 && lower <= level && level <= upper
    }

    private static func legendStops(
        rangeMeters: ClosedRange<Float>,
        contourIntervalMeters: Float,
        lineCount: Int
    ) -> [TAPDepthLegendStop] {
        [
            TAPDepthLegendStop(position: 0.0, label: "Near \(formatMeters(rangeMeters.lowerBound))", color: contourLineColor),
            TAPDepthLegendStop(position: 0.5, label: "\(lineCount) lines / \(formatMeters(contourIntervalMeters))", color: contourLabelFillColor),
            TAPDepthLegendStop(position: 1.0, label: "Far \(formatMeters(rangeMeters.upperBound))", color: contourLineColor)
        ]
    }

    private static func contourInterval(rangeMeters: ClosedRange<Float>, lineCount: Int) -> Float {
        let span = max(rangeMeters.upperBound - rangeMeters.lowerBound, 0)
        guard span > 0, lineCount > 0 else {
            return 0
        }
        return span / Float(lineCount + 1)
    }

    private static func clampedLineCount(_ lineCount: Int) -> Int {
        min(max(lineCount, minimumLineCount), maximumLineCount)
    }

    private static func labelPixelScale(width: Int, height: Int) -> Int {
        let shortSide = min(width, height)
        if shortSide >= 360 {
            return 3
        }
        if shortSide >= 150 {
            return 2
        }
        return 1
    }

    private static func formatMeters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }

    private static func squaredDistance(_ lhs: PixelPoint, _ rhs: PixelPoint) -> Int {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private static func bitmapGlyph(for character: Character) -> BitmapGlyph {
        switch character {
        case "0":
            BitmapGlyph(width: 3, rows: ["111", "101", "101", "101", "111"])
        case "1":
            BitmapGlyph(width: 3, rows: ["010", "110", "010", "010", "111"])
        case "2":
            BitmapGlyph(width: 3, rows: ["111", "001", "111", "100", "111"])
        case "3":
            BitmapGlyph(width: 3, rows: ["111", "001", "111", "001", "111"])
        case "4":
            BitmapGlyph(width: 3, rows: ["101", "101", "111", "001", "001"])
        case "5":
            BitmapGlyph(width: 3, rows: ["111", "100", "111", "001", "111"])
        case "6":
            BitmapGlyph(width: 3, rows: ["111", "100", "111", "101", "111"])
        case "7":
            BitmapGlyph(width: 3, rows: ["111", "001", "010", "010", "010"])
        case "8":
            BitmapGlyph(width: 3, rows: ["111", "101", "111", "101", "111"])
        case "9":
            BitmapGlyph(width: 3, rows: ["111", "101", "111", "001", "111"])
        case ".":
            BitmapGlyph(width: 1, rows: ["0", "0", "0", "0", "1"])
        case "-":
            BitmapGlyph(width: 3, rows: ["000", "000", "111", "000", "000"])
        case "m":
            BitmapGlyph(width: 5, rows: ["00000", "11010", "10101", "10101", "10101"])
        default:
            BitmapGlyph(width: 3, rows: ["000", "000", "000", "000", "000"])
        }
    }
}

nonisolated private struct PixelPoint {
    let x: Int
    let y: Int
}

nonisolated private struct PixelSize {
    let width: Int
    let height: Int
}

nonisolated private struct PixelRect {
    let origin: PixelPoint
    let size: PixelSize

    var minX: Int { origin.x }
    var minY: Int { origin.y }
    var maxX: Int { origin.x + size.width }
    var maxY: Int { origin.y + size.height }

    func intersects(_ other: PixelRect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    func insetBy(dx: Int, dy: Int) -> PixelRect {
        PixelRect(
            origin: PixelPoint(x: origin.x + dx, y: origin.y + dy),
            size: PixelSize(width: size.width - dx * 2, height: size.height - dy * 2)
        )
    }
}

nonisolated private struct BitmapGlyph {
    let width: Int
    let rows: [String]
}
