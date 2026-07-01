//
//  CameraTickedSliderRow.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

struct CameraTickedSliderRow: View {
    let title: String
    let value: String
    let valueBinding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool
    let contentRotation: Angle
    let riskRanges: [ClosedRange<Double>]
    let onEditingBegan: () -> Void
    let onEditingEnded: () -> Void

    @State private var lastHapticStepIndex: Int?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let portraitAdjustmentCenterline = proxy.size.width / 2
            let trackWidth = resolvedTrackWidth(for: proxy.size.width)
            let rowCenterY = proxy.size.height / 2

            ZStack {
                tickMarks
                    .padding(.horizontal, Metrics.tickHorizontalPadding)
                    .frame(width: trackWidth, height: Metrics.trackHeight)
                    .position(x: portraitAdjustmentCenterline, y: rowCenterY)

                riskZoneLayer(trackWidth: trackWidth)
                    .position(x: portraitAdjustmentCenterline, y: rowCenterY)

                valueCursor
                    .position(
                        x: cursorX(
                            portraitAdjustmentCenterline: portraitAdjustmentCenterline,
                            trackWidth: trackWidth
                        ),
                        y: rowCenterY
                    )

                GeometryReader { trackProxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard isEnabled else {
                                        return
                                    }
                                    beginEditingIfNeeded()
                                    updateValue(
                                        steppedValue(
                                            at: value.location.x,
                                            width: trackProxy.size.width
                                        )
                                    )
                                }
                                .onEnded { _ in
                                    endEditingIfNeeded()
                                }
                        )
                }
                .frame(width: trackWidth, height: Metrics.touchHeight)
                .position(x: portraitAdjustmentCenterline, y: rowCenterY)
                .allowsHitTesting(isEnabled)

                CenterAnchoredChromeRotation(
                    rotation: contentRotation,
                    width: Metrics.titleWidth,
                    height: Metrics.labelHeight
                ) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .position(
                    x: titleX(
                        portraitAdjustmentCenterline: portraitAdjustmentCenterline,
                        trackWidth: trackWidth,
                        containerWidth: proxy.size.width
                    ),
                    y: rowCenterY
                )

                CenterAnchoredChromeRotation(
                    rotation: contentRotation,
                    width: Metrics.valueWidth,
                    height: Metrics.labelHeight
                ) {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .position(
                    x: valueX(
                        portraitAdjustmentCenterline: portraitAdjustmentCenterline,
                        trackWidth: trackWidth,
                        containerWidth: proxy.size.width
                    ),
                    y: rowCenterY
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.rowHeight)
        .foregroundStyle(isEnabled ? .white : .white.opacity(0.38))
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityIdentifier("camera.tickedAdjustmentStrip")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else {
                return
            }
            switch direction {
            case .increment:
                updateValue(adjustedValue(by: step))
            case .decrement:
                updateValue(adjustedValue(by: -step))
            @unknown default:
                break
            }
        }
    }

    private var tickMarks: some View {
        HStack(spacing: 0) {
            ForEach(0..<17, id: \.self) { index in
                Rectangle()
                    .fill(.white.opacity(index == 8 ? 0.50 : 0.24))
                    .frame(width: 1, height: index == 8 ? 18 : 10)
                if index < 16 {
                    Spacer(minLength: 0)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func riskZoneLayer(trackWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(riskRanges.enumerated()), id: \.offset) { _, range in
                let start = normalizedPosition(for: range.lowerBound)
                let end = normalizedPosition(for: range.upperBound)
                let width = max(CGFloat(end - start) * trackWidth, 0)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.gray.opacity(0.34))
                    .frame(width: width, height: 6)
                    .offset(x: CGFloat(start) * trackWidth)
            }
        }
        .frame(width: trackWidth, height: 8, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var valueCursor: some View {
        Circle()
            .fill(isEnabled ? .yellow : .white.opacity(0.36))
            .frame(width: 13, height: 13)
            .overlay {
                Circle()
                    .stroke(.white.opacity(isEnabled ? 0.72 : 0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.38), radius: 3)
            .accessibilityHidden(true)
            .accessibilityIdentifier("camera.tickedAdjustmentStrip.valueCursor")
    }

    private func resolvedTrackWidth(for containerWidth: CGFloat) -> CGFloat {
        let availableWidth = containerWidth - Metrics.labelReserveWidth
        return min(max(availableWidth, Metrics.minimumTrackWidth), Metrics.maximumTrackWidth)
    }

    private func titleX(
        portraitAdjustmentCenterline: CGFloat,
        trackWidth: CGFloat,
        containerWidth: CGFloat
    ) -> CGFloat {
        let rawX = portraitAdjustmentCenterline
            - trackWidth / 2
            - Metrics.labelGap
            - Metrics.titleWidth / 2
        return min(max(rawX, Metrics.horizontalInset + Metrics.titleWidth / 2), containerWidth / 2)
    }

    private func valueX(
        portraitAdjustmentCenterline: CGFloat,
        trackWidth: CGFloat,
        containerWidth: CGFloat
    ) -> CGFloat {
        let rawX = portraitAdjustmentCenterline
            + trackWidth / 2
            + Metrics.labelGap
            + Metrics.valueWidth / 2
        return max(
            min(rawX, containerWidth - Metrics.horizontalInset - Metrics.valueWidth / 2),
            containerWidth / 2
        )
    }

    private func cursorX(
        portraitAdjustmentCenterline: CGFloat,
        trackWidth: CGFloat
    ) -> CGFloat {
        portraitAdjustmentCenterline - trackWidth / 2 + CGFloat(normalizedValue) * trackWidth
    }

    private var normalizedValue: Double {
        normalizedPosition(for: valueBinding.wrappedValue)
    }

    private func normalizedPosition(for value: Double) -> Double {
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        guard upperBound > lowerBound else {
            return 0.5
        }
        return min(max((value - lowerBound) / (upperBound - lowerBound), 0), 1)
    }

    private func updateValue(_ value: Double) {
        let nextValue = steppedClampedValue(value)
        triggerSelectionHapticIfNeeded(for: nextValue)
        valueBinding.wrappedValue = nextValue
    }

    private func beginEditingIfNeeded() {
        guard !isDragging else {
            return
        }
        isDragging = true
        onEditingBegan()
    }

    private func endEditingIfNeeded() {
        guard isDragging else {
            return
        }
        isDragging = false
        onEditingEnded()
    }

    private func triggerSelectionHapticIfNeeded(for value: Double) {
        let nextStepIndex = hapticStepIndex(for: value)
        guard lastHapticStepIndex != nextStepIndex else {
            return
        }
        lastHapticStepIndex = nextStepIndex
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func hapticStepIndex(for value: Double) -> Int {
        let stepSize = step.isFinite && step > 0
            ? step
            : max((range.upperBound - range.lowerBound) / 100, 0.000_001)
        return Int(((value - range.lowerBound) / stepSize).rounded())
    }

    private func steppedValue(at x: CGFloat, width: CGFloat) -> Double {
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        guard upperBound > lowerBound else {
            return lowerBound
        }
        let normalized = min(max(Double(x / max(width, 1)), 0), 1)
        let rawValue = lowerBound + normalized * (upperBound - lowerBound)
        return steppedClampedValue(rawValue)
    }

    private func adjustedValue(by delta: Double) -> Double {
        let resolvedDelta = delta.isFinite && delta != 0 ? delta : (range.upperBound - range.lowerBound) / 100
        return steppedClampedValue(valueBinding.wrappedValue + resolvedDelta)
    }

    private func steppedClampedValue(_ value: Double) -> Double {
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        guard value.isFinite else {
            return lowerBound
        }
        let stepped: Double
        if step.isFinite, step > 0 {
            stepped = (value / step).rounded() * step
        } else {
            stepped = value
        }
        return min(max(stepped, lowerBound), upperBound)
    }

    private enum Metrics {
        static let rowHeight: CGFloat = 50
        static let trackHeight: CGFloat = 34
        static let touchHeight: CGFloat = 44
        static let labelHeight: CGFloat = 34
        static let titleWidth: CGFloat = 44
        static let valueWidth: CGFloat = 78
        static let labelGap: CGFloat = 8
        static let horizontalInset: CGFloat = 12
        static let tickHorizontalPadding: CGFloat = 6
        static let minimumTrackWidth: CGFloat = 128
        static let maximumTrackWidth: CGFloat = 208
        static let labelReserveWidth: CGFloat = titleWidth
            + valueWidth
            + labelGap * 2
            + horizontalInset * 2
    }
}
