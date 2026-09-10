//
//  CameraPhotographyExposureScale.swift
//  TAPCamDemo
//

import Foundation

/// A device-clipped, discrete set of conventional photography values.
///
/// AVFoundation exposes continuous ISO and duration ranges. The camera UI
/// should not surface arbitrary values such as ISO 117 or 1/143s, so the
/// adjustment strips operate on indices into familiar nominal third-stop values
/// and convert the selected index back to the hardware value at the UI edge.
nonisolated struct CameraPhotographyExposureScale: Equatable, Sendable {
    nonisolated struct Stop: Equatable, Sendable {
        let value: Double
        let label: String
    }

    let supportedRange: ClosedRange<Double>
    let stops: [Stop]

    var positionRange: ClosedRange<Double> {
        0...Double(max(stops.count - 1, 0))
    }

    var isAdjustable: Bool {
        stops.count >= 2
    }

    var adjustableValueRange: ClosedRange<Double>? {
        guard isAdjustable,
              let firstValue = stops.first?.value,
              let lastValue = stops.last?.value else {
            return nil
        }
        return firstValue...lastValue
    }

    func position(for value: Double) -> Double {
        guard isAdjustable else {
            return 0
        }
        return Double(nearestIndex(to: value))
    }

    func snappedValue(for value: Double) -> Double {
        guard isAdjustable else {
            return clampedToSupportedRange(value)
        }
        return stops[nearestIndex(to: value)].value
    }

    func value(at position: Double) -> Double {
        guard isAdjustable else {
            return supportedRange.lowerBound
        }
        return stops[resolvedIndex(for: position)].value
    }

    func label(for value: Double) -> String {
        guard isAdjustable else {
            return "--"
        }
        return stops[nearestIndex(to: value)].label
    }

    func positionRanges(
        for valueRanges: [ClosedRange<Double>]
    ) -> [ClosedRange<Double>] {
        guard isAdjustable else {
            return []
        }
        let mappedRanges: [ClosedRange<Double>] = valueRanges.compactMap { range in
            let includedIndices = stops.indices.filter { index in
                let value = stops[index].value
                let tolerance = max(abs(value) * 0.000_001, 0.000_000_001)
                return value >= range.lowerBound - tolerance
                    && value <= range.upperBound + tolerance
            }
            guard let firstIndex = includedIndices.first,
                  let lastIndex = includedIndices.last else {
                return nil
            }
            let lower = max(Double(firstIndex) - 0.5, positionRange.lowerBound)
            let upper = min(Double(lastIndex) + 0.5, positionRange.upperBound)
            return lower...upper
        }
        .sorted { $0.lowerBound < $1.lowerBound }

        var mergedRanges: [ClosedRange<Double>] = []
        for range in mappedRanges {
            guard let previous = mergedRanges.last,
                  range.lowerBound <= previous.upperBound else {
                mergedRanges.append(range)
                continue
            }
            mergedRanges[mergedRanges.count - 1] =
                previous.lowerBound...max(previous.upperBound, range.upperBound)
        }
        return mergedRanges
    }

    static func iso(in supportedRange: ClosedRange<Double>) -> Self {
        makeScale(
            from: canonicalISOValues.map {
                Stop(
                    value: $0,
                    label: String(Int($0.rounded()))
                )
            },
            supportedRange: supportedRange
        )
    }

    static func shutterDuration(in supportedRange: ClosedRange<Double>) -> Self {
        let reciprocalStops = canonicalShutterDenominators.map { denominator in
            Stop(
                value: 1 / denominator,
                label: "1/\(formattedNumber(denominator))"
            )
        }
        let slowShutterStops = canonicalSlowShutterDurations.map { duration in
            Stop(
                value: duration,
                label: "\(formattedNumber(duration))\""
            )
        }
        return makeScale(
            from: reciprocalStops + slowShutterStops,
            supportedRange: supportedRange
        )
    }

    private func nearestIndex(to value: Double) -> Int {
        guard value.isFinite, value > 0 else {
            return 0
        }
        return stops.indices.min { lhs, rhs in
            Self.logarithmicDistance(stops[lhs].value, value)
                < Self.logarithmicDistance(stops[rhs].value, value)
        } ?? 0
    }

    private func resolvedIndex(for position: Double) -> Int {
        guard position.isFinite else {
            return 0
        }
        return min(max(Int(position.rounded()), 0), stops.count - 1)
    }

    private func clampedToSupportedRange(_ value: Double) -> Double {
        guard value.isFinite else {
            return supportedRange.lowerBound
        }
        return min(max(value, supportedRange.lowerBound), supportedRange.upperBound)
    }

    private static func makeScale(
        from canonicalStops: [Stop],
        supportedRange: ClosedRange<Double>
    ) -> Self {
        let rawLower = min(supportedRange.lowerBound, supportedRange.upperBound)
        let rawUpper = max(supportedRange.lowerBound, supportedRange.upperBound)
        let lower = rawLower.isFinite && rawLower > 0 ? rawLower : 0.000_001
        let upper = rawUpper.isFinite && rawUpper >= lower ? rawUpper : lower
        let resolvedSupportedRange = lower...upper
        let clippedStops = canonicalStops
            .filter { stop in
                let tolerance = max(abs(stop.value) * 0.000_001, 0.000_000_001)
                return stop.value >= lower - tolerance && stop.value <= upper + tolerance
            }
            .map { stop in
                Stop(
                    value: min(max(stop.value, lower), upper),
                    label: stop.label
                )
            }
            .sorted { $0.value < $1.value }
        var uniqueStops: [Stop] = []
        for stop in clippedStops {
            guard let previous = uniqueStops.last else {
                uniqueStops.append(stop)
                continue
            }
            let tolerance = max(abs(stop.value) * 0.000_001, 0.000_000_001)
            if abs(previous.value - stop.value) > tolerance {
                uniqueStops.append(stop)
            }
        }

        return Self(
            supportedRange: resolvedSupportedRange,
            stops: uniqueStops
        )
    }

    private static func logarithmicDistance(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs > 0, rhs > 0 else {
            return abs(lhs - rhs)
        }
        return abs(log2(lhs / rhs))
    }

    private static func formattedNumber(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private static let canonicalISOValues: [Double] = [
        6, 8, 10, 12, 16, 20, 25, 32, 40, 50, 64, 80,
        100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1_000, 1_250, 1_600, 2_000, 2_500, 3_200, 4_000,
        5_000, 6_400, 8_000, 10_000, 12_800, 16_000, 20_000,
        25_600, 32_000, 40_000, 51_200, 64_000, 80_000,
        102_400, 128_000, 160_000, 204_800,
    ]

    /// Fastest to slowest, expressed as the denominator in `1/x` seconds.
    private static let canonicalShutterDenominators: [Double] = [
        32_000, 25_000, 20_000, 16_000, 12_800, 10_000,
        8_000, 6_400, 5_000, 4_000, 3_200, 2_500, 2_000,
        1_600, 1_250, 1_000, 800, 640, 500, 400, 320, 250,
        200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 20, 15,
        13, 10, 8, 6, 5, 4,
    ]

    private static let canonicalSlowShutterDurations: [Double] = [
        1 / 3.2, 1 / 2.5, 1 / 2, 1 / 1.6, 1 / 1.3,
        1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30,
    ]
}
