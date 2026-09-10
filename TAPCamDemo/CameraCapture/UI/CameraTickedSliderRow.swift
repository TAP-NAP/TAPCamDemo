//
//  CameraTickedSliderRow.swift
//  TAPCamDemo
//

import SwiftUI

struct CameraTickedSliderRow: View {
    let title: String
    let automationState: CameraAdjustmentAutomationState?
    let value: String
    let valueBinding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool
    let highlightColor: Color
    let contentRotation: Angle
    let riskRanges: [ClosedRange<Double>]
    let isEVIntegerHapticsEnabled: Bool
    let onRestoreAuto: () -> Void
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

                leadingControl
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
                        .foregroundStyle(isEnabled ? .white : .white.opacity(0.38))
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
        .background(.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            [title, automationState?.title, value]
                .compactMap { $0 }
                .joined(separator: " ")
        )
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

    @ViewBuilder
    private var leadingControl: some View {
        CenterAnchoredChromeRotation(
            rotation: contentRotation,
            width: Metrics.titleWidth,
            height: Metrics.touchHeight
        ) {
            if let automationState, automationState.canRestoreAuto {
                Button(action: onRestoreAuto) {
                    automationStateBadge(automationState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CameraAutomationRestoreButtonStyle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text(verbatim: "Manual. Restore Auto"))
                .accessibilityIdentifier("camera.tickedAdjustmentStrip.automation")
            } else if let automationState {
                automationStateBadge(automationState)
                    .accessibilityIdentifier("camera.tickedAdjustmentStrip.automation")
            } else {
                leadingLabel(title)
                    .foregroundStyle(.white)
            }
        }
    }

    private func automationStateBadge(
        _ automationState: CameraAdjustmentAutomationState
    ) -> some View {
        let isInteractive = automationState.canRestoreAuto
        let fillOpacity = isEnabled ? (isInteractive ? 0.30 : 0.14) : 0.06
        let strokeOpacity = isEnabled ? (isInteractive ? 0.96 : 0.62) : 0.24

        return leadingLabel(automationState.title)
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.38))
            .frame(
                width: Metrics.automationControlWidth,
                height: Metrics.automationControlHeight
            )
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(highlightColor.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        highlightColor.opacity(strokeOpacity),
                        lineWidth: isInteractive ? 1.4 : 1
                    )
            }
            .shadow(
                color: highlightColor.opacity(isEnabled && isInteractive ? 0.24 : 0),
                radius: 2,
                y: 1
            )
    }

    private func leadingLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .monospaced()
            .lineLimit(1)
            .minimumScaleFactor(0.64)
    }

    private var tickMarks: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ForEach(0..<Metrics.tickCount, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(isEnabled ? 0.34 : 0.17))
                        .frame(width: 1, height: 8)
                        .position(
                            x: CGFloat(index) / CGFloat(Metrics.tickCount - 1) * proxy.size.width,
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
        Capsule()
            .fill(isEnabled ? highlightColor : .white.opacity(0.36))
            .frame(width: 3, height: 24)
            .shadow(color: .black.opacity(isEnabled ? 0.34 : 0), radius: 2)
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
        static let titleWidth: CGFloat = 58
        static let automationControlWidth: CGFloat = 52
        static let automationControlHeight: CGFloat = 28
        static let valueWidth: CGFloat = 78
        static let labelGap: CGFloat = 8
        static let horizontalInset: CGFloat = 12
        static let tickCount = 17
        static let minimumTrackWidth: CGFloat = 128
        static let maximumTrackWidth: CGFloat = 208
        static let labelReserveWidth: CGFloat = titleWidth
            + valueWidth
            + labelGap * 2
            + horizontalInset * 2
    }
}

private struct CameraAutomationRestoreButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
