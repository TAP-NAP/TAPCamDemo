//
//  CameraTickedSliderRow.swift
//  TAPCamDemo
//

import SwiftUI

struct CameraTickedSliderRow: View {
    let title: String
    let value: String
    let valueBinding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool
    let highlightColor: Color
    let contentRotation: Angle
    let riskRanges: [ClosedRange<Double>]
    let tickValueStep: Double?
    let isEVIntegerHapticsEnabled: Bool
    let onEditingBegan: () -> Void
    let onEditingEnded: () -> Void

    @Environment(\.cameraHapticFeedbackController) private var hapticFeedbackController
    @State private var lastHapticStepIndex: Int?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let portraitAdjustmentCenterline = proxy.size.width / 2
            let trackWidth = resolvedTrackWidth(for: proxy.size.width)
            let rowCenterY = proxy.size.height / 2

            ZStack {
                tickMarks
                    .frame(width: trackWidth, height: Metrics.trackHeight)
                    .position(x: portraitAdjustmentCenterline, y: rowCenterY)

                riskZoneLayer(trackWidth: trackWidth)
                    .position(x: portraitAdjustmentCenterline, y: rowCenterY)

                activeTick
                    .position(
                        x: activeTickX(
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
        GeometryReader { proxy in
            let descriptors = tickDescriptors
            ZStack(alignment: .leading) {
                ForEach(Array(descriptors.enumerated()), id: \.offset) { index, descriptor in
                    CameraTickedSliderTickMark(
                        visualState: visualState(for: descriptor),
                        highlightColor: highlightColor,
                        isEnabled: isEnabled
                    )
                        .position(
                            x: tickX(for: index, count: descriptors.count, width: proxy.size.width),
                            y: proxy.size.height / 2
                        )
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

    private var activeTick: some View {
        CameraTickedSliderTickMark(
            visualState: .active,
            highlightColor: highlightColor,
            isEnabled: isEnabled
        )
        .accessibilityHidden(true)
        .accessibilityIdentifier("camera.tickedAdjustmentStrip.activeTick")
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

    private func activeTickX(
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
        hapticFeedbackController.prepareAdjustmentFeedback()
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
        triggerHaptic(for: value)
    }

    private func triggerHaptic(for value: Double) {
        hapticFeedbackController.adjustmentChanged(style: adjustmentHapticStyle(for: value))
    }

    private func adjustmentHapticStyle(for value: Double) -> CameraAdjustmentHapticStyle {
        guard isEVIntegerHapticsEnabled else {
            return .selection
        }
        if isZeroValue(value) {
            return .zeroTick
        }

        if isIntegerValue(value) {
            return .integerTick
        }

        return .selection
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

    private var tickDescriptors: [TickDescriptor] {
        let values = tickValues()
        let midpointIndex = values.count / 2

        return values.enumerated().map { index, value in
            let isZero = isZeroValue(value)
            let isInteger = isEVIntegerHapticsEnabled && isIntegerValue(value)
            return TickDescriptor(
                isCenter: isZero || (!isEVIntegerHapticsEnabled && index == midpointIndex),
                isMajor: isZero || isInteger || (!isEVIntegerHapticsEnabled && index == midpointIndex)
            )
        }
    }

    private func tickValues() -> [Double] {
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        guard upperBound > lowerBound else {
            return [lowerBound]
        }

        if let tickValueStep = resolvedTickValueStep {
            let count = max(Int(((upperBound - lowerBound) / tickValueStep).rounded()), 1)
            return (0...count).map { index in
                index == count
                    ? upperBound
                    : min(lowerBound + Double(index) * tickValueStep, upperBound)
            }
        }

        let count = Metrics.defaultTickCount - 1
        return (0...count).map { index in
            lowerBound + Double(index) / Double(count) * (upperBound - lowerBound)
        }
    }

    private var resolvedTickValueStep: Double? {
        guard
            let tickValueStep,
            tickValueStep.isFinite,
            tickValueStep > 0,
            range.upperBound > range.lowerBound
        else {
            return nil
        }

        let count = Int(((range.upperBound - range.lowerBound) / tickValueStep).rounded())
        guard count > 0, count <= Metrics.maximumTickCount else {
            return nil
        }
        return tickValueStep
    }

    private func visualState(
        for descriptor: TickDescriptor
    ) -> CameraTickedSliderTickVisualState {
        if descriptor.isCenter {
            return .center
        }
        if descriptor.isMajor {
            return .major
        }
        return .minor
    }

    private func tickX(for index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else {
            return width / 2
        }
        return CGFloat(index) / CGFloat(count - 1) * width
    }

    private func isZeroValue(_ value: Double) -> Bool {
        abs(value) <= hapticValueTolerance
    }

    private func isIntegerValue(_ value: Double) -> Bool {
        let nearestInteger = value.rounded()
        return abs(value - nearestInteger) <= hapticValueTolerance
    }

    private var hapticValueTolerance: Double {
        max(resolvedStepSize / 10_000, 0.000_001)
    }

    private var resolvedStepSize: Double {
        step.isFinite && step > 0
            ? step
            : max((range.upperBound - range.lowerBound) / 100, 0.000_001)
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
        static let defaultTickCount = 17
        static let maximumTickCount = 61
        static let minimumTrackWidth: CGFloat = 128
        static let maximumTrackWidth: CGFloat = 208
        static let labelReserveWidth: CGFloat = titleWidth
            + valueWidth
            + labelGap * 2
            + horizontalInset * 2
    }

    private struct TickDescriptor: Equatable {
        let isCenter: Bool
        let isMajor: Bool
    }
}

private struct CameraTickedSliderTickMark: View {
    let visualState: CameraTickedSliderTickVisualState
    let highlightColor: Color
    let isEnabled: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(fillColor)
            .frame(width: visualState.width, height: visualState.height)
            .shadow(
                color: visualState == .active
                    ? .black.opacity(isEnabled ? 0.34 : 0)
                    : .clear,
                radius: visualState == .active ? 2 : 0
            )
    }

    private var fillColor: Color {
        if visualState.usesHighlightColor {
            return isEnabled
                ? highlightColor
                : .white.opacity(visualState.disabledOpacity)
        }
        return .white.opacity(
            isEnabled
                ? visualState.enabledOpacity
                : visualState.disabledOpacity
        )
    }
}

enum CameraTickedSliderTickVisualState: CaseIterable, Equatable {
    case minor
    case major
    case center
    case active

    var usesHighlightColor: Bool {
        self == .active
    }

    var width: CGFloat {
        switch self {
        case .minor:
            1
        case .major:
            1.5
        case .center:
            2
        case .active:
            3
        }
    }

    var height: CGFloat {
        switch self {
        case .minor:
            8
        case .major:
            13
        case .center:
            18
        case .active:
            24
        }
    }

    var enabledOpacity: Double {
        switch self {
        case .minor:
            0.20
        case .major:
            0.34
        case .center:
            0.52
        case .active:
            1
        }
    }

    var disabledOpacity: Double {
        switch self {
        case .minor:
            0.10
        case .major:
            0.17
        case .center:
            0.26
        case .active:
            0.36
        }
    }
}
