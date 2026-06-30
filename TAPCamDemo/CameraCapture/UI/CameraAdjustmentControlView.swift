//
//  CameraAdjustmentControlView.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI
import UIKit

nonisolated struct CameraAdjustmentControlState: Equatable, Sendable {
    nonisolated enum ExposureMode: Equatable, Sendable {
        case auto(globalBias: Double)
        case custom(meterOffset: Double)
    }

    nonisolated struct Exposure: Equatable, Sendable {
        let isAvailable: Bool
        let mode: ExposureMode
        let isoRange: ClosedRange<Double>
        let shutterDurationRangeSeconds: ClosedRange<Double>
        let iso: Double
        let shutterDurationSeconds: Double

        var isCustom: Bool {
            switch mode {
            case .auto:
                false
            case .custom:
                true
            }
        }

        var evTitle: String {
            isCustom ? "Meter" : "EV"
        }

        var evValue: String {
            switch mode {
            case .auto(let globalBias):
                Self.signedLabel(globalBias, zeroPrefix: "0.0")
            case .custom(let meterOffset):
                Self.signedLabel(meterOffset, zeroPrefix: "0.0")
            }
        }

        var isoValue: String {
            isoLabel(for: iso)
        }

        var shutterValue: String {
            shutterLabel(for: shutterDurationSeconds)
        }

        nonisolated func clampedISO(_ value: Double) -> Double {
            clamped(value, in: isoRange)
        }

        nonisolated func clampedShutterDuration(_ value: Double) -> Double {
            clamped(value, in: shutterDurationRangeSeconds)
        }

        nonisolated func normalizedShutterPosition(for duration: Double) -> Double {
            let minimum = max(shutterDurationRangeSeconds.lowerBound, 0.000_001)
            let maximum = max(shutterDurationRangeSeconds.upperBound, minimum)
            guard maximum > minimum else {
                return 0
            }
            let clampedDuration = clampedShutterDuration(duration)
            return (log(clampedDuration) - log(minimum)) / (log(maximum) - log(minimum))
        }

        nonisolated func shutterDuration(forNormalizedPosition position: Double) -> Double {
            let minimum = max(shutterDurationRangeSeconds.lowerBound, 0.000_001)
            let maximum = max(shutterDurationRangeSeconds.upperBound, minimum)
            guard maximum > minimum else {
                return minimum
            }
            let clampedPosition = clamped(position, in: 0...1)
            return exp(log(minimum) + clampedPosition * (log(maximum) - log(minimum)))
        }

        nonisolated func isoLabel(for value: Double) -> String {
            String(format: "%.0f", clampedISO(value))
        }

        nonisolated func shutterLabel(for duration: Double) -> String {
            let clampedDuration = clampedShutterDuration(duration)
            guard clampedDuration < 1 else {
                return String(format: "%.1fs", clampedDuration)
            }
            let reciprocal = 1 / max(clampedDuration, 0.000_001)
            if reciprocal >= 10 {
                return "1/\(Int(reciprocal.rounded()))"
            }
            return String(format: "%.2fs", clampedDuration)
        }

        private static func signedLabel(_ value: Double, zeroPrefix: String) -> String {
            guard value.isFinite, abs(value) >= 0.05 else {
                return zeroPrefix
            }
            return String(format: "%+0.1f", value)
        }
    }

    nonisolated struct Focus: Equatable, Sendable {
        let isAvailable: Bool
        let mode: CameraFocusControlMode
        let lensPositionRange: ClosedRange<Double>
        let lensPosition: Double
        let minimumFocusDistanceLabel: String?

        var title: String {
            mode.title
        }

        var lensPositionValue: String {
            lensPositionLabel(for: lensPosition)
        }

        var lensPositionDetail: String {
            if let minimumFocusDistanceLabel {
                return "\(lensPositionValue) · \(minimumFocusDistanceLabel)"
            }
            return lensPositionValue
        }

        nonisolated func clampedLensPosition(_ value: Double) -> Double {
            clamped(value, in: lensPositionRange)
        }

        nonisolated func lensPositionLabel(for value: Double) -> String {
            String(format: "%.2f", clampedLensPosition(value))
        }
    }

    nonisolated struct Aperture: Equatable, Sendable {
        let fixedValue: Double

        var value: String {
            String(format: "%.1f", fixedValue)
        }
    }

    let activeControl: CameraAdjustmentControl?
    let exposure: Exposure
    let focus: Focus
    let aperture: Aperture

    init(
        capability: CameraControlCapabilitySnapshot,
        activeControl: CameraAdjustmentControl?,
        exposureMode: ExposureMode,
        focusMode: CameraFocusControlMode,
        draft: CameraAdjustmentControlDraft
    ) {
        let exposureRange = Self.closedRange(from: capability.exposure.shutterDurationRangeSeconds)
        let isoRange = Self.closedRange(from: capability.exposure.isoRange)
        let focusRange = 0.0...1.0
        exposure = Exposure(
            isAvailable: capability.exposure.hasManualRange,
            mode: exposureMode,
            isoRange: isoRange,
            shutterDurationRangeSeconds: exposureRange,
            iso: clamped(draft.iso, in: isoRange),
            shutterDurationSeconds: clamped(draft.shutterDurationSeconds, in: exposureRange)
        )
        focus = Focus(
            isAvailable: capability.focus.supportsManualLensPosition,
            mode: focusMode,
            lensPositionRange: focusRange,
            lensPosition: clamped(draft.lensPosition, in: focusRange),
            minimumFocusDistanceLabel: Self.minimumFocusDistanceLabel(
                capability.focus.minimumFocusDistanceMillimeters
            )
        )
        aperture = Aperture(fixedValue: capability.aperture.fixedLensAperture)
        self.activeControl = activeControl
    }

    static func defaultDraft(from capability: CameraControlCapabilitySnapshot) -> CameraAdjustmentControlDraft {
        CameraAdjustmentControlDraft(
            iso: capability.exposure.currentISO,
            shutterDurationSeconds: capability.exposure.currentShutterDurationSeconds,
            lensPosition: capability.focus.currentLensPosition
        )
    }

    private static func closedRange(
        from range: CameraControlCapabilitySnapshot.DoubleRange
    ) -> ClosedRange<Double> {
        let lower = range.minimum.isFinite ? range.minimum : 0
        let upper = range.maximum.isFinite ? range.maximum : lower
        let minimum = min(lower, upper)
        let maximum = max(lower, upper)
        if maximum > minimum {
            return minimum...maximum
        }
        return minimum...(minimum + 0.000_001)
    }

    private static func minimumFocusDistanceLabel(_ millimeters: Int?) -> String? {
        guard let millimeters else {
            return nil
        }
        if millimeters >= 1_000 {
            return String(format: "min %.1fm", Double(millimeters) / 1_000.0)
        }
        return "min \(millimeters)mm"
    }
}

nonisolated struct CameraAdjustmentControlDraft: Equatable, Sendable {
    let iso: Double
    let shutterDurationSeconds: Double
    let lensPosition: Double

    static let fallback = CameraAdjustmentControlDraft(
        iso: 100,
        shutterDurationSeconds: 1.0 / 120.0,
        lensPosition: 0.5
    )

    func clamped(to state: CameraAdjustmentControlState) -> CameraAdjustmentControlDraft {
        CameraAdjustmentControlDraft(
            iso: state.exposure.clampedISO(iso),
            shutterDurationSeconds: state.exposure.clampedShutterDuration(shutterDurationSeconds),
            lensPosition: state.focus.clampedLensPosition(lensPosition)
        )
    }

    func replacingISO(_ value: Double) -> CameraAdjustmentControlDraft {
        CameraAdjustmentControlDraft(
            iso: value,
            shutterDurationSeconds: shutterDurationSeconds,
            lensPosition: lensPosition
        )
    }

    func replacingShutterDuration(_ value: Double) -> CameraAdjustmentControlDraft {
        CameraAdjustmentControlDraft(
            iso: iso,
            shutterDurationSeconds: value,
            lensPosition: lensPosition
        )
    }

    func replacingLensPosition(_ value: Double) -> CameraAdjustmentControlDraft {
        CameraAdjustmentControlDraft(
            iso: iso,
            shutterDurationSeconds: shutterDurationSeconds,
            lensPosition: value
        )
    }
}

nonisolated struct CameraAdjustmentControlDraftMemory: Equatable, Sendable {
    private var draftsByControlKey: [String: CameraAdjustmentControlDraft] = [:]

    var storedDraftCount: Int {
        draftsByControlKey.count
    }

    func storedDraft(for controlKey: String) -> CameraAdjustmentControlDraft? {
        draftsByControlKey[controlKey]
    }

    mutating func draft(
        for controlKey: String?,
        state: CameraAdjustmentControlState,
        fallback: CameraAdjustmentControlDraft = .fallback
    ) -> CameraAdjustmentControlDraft {
        let resolved = (controlKey.flatMap { draftsByControlKey[$0] } ?? fallback)
            .clamped(to: state)
        if let controlKey {
            draftsByControlKey[controlKey] = resolved
        }
        return resolved
    }

    mutating func store(
        _ draft: CameraAdjustmentControlDraft,
        for controlKey: String?,
        state: CameraAdjustmentControlState
    ) -> CameraAdjustmentControlDraft {
        let resolved = draft.clamped(to: state)
        if let controlKey {
            draftsByControlKey[controlKey] = resolved
        }
        return resolved
    }
}

struct CameraLowerToolbarView: View {
    let state: CameraAdjustmentControlState
    let contentRotation: Angle
    let onSelectControl: (CameraAdjustmentControl) -> Void
    let onToggleFocusMode: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            parameterButton(
                title: state.exposure.evTitle,
                value: state.exposure.evValue,
                badge: nil,
                control: .ev,
                isEnabled: true,
                contentRotation: contentRotation
            )

            parameterButton(
                title: "ISO",
                value: state.exposure.isoValue,
                badge: state.exposure.isCustom ? nil : "A",
                control: .iso,
                isEnabled: state.exposure.isAvailable,
                contentRotation: contentRotation
            )

            parameterButton(
                title: "S",
                value: state.exposure.shutterValue,
                badge: state.exposure.isCustom ? nil : "A",
                control: .shutter,
                isEnabled: state.exposure.isAvailable,
                contentRotation: contentRotation
            )

            Button(action: onToggleFocusMode) {
                CameraToolbarButtonContent(
                    title: state.focus.title,
                    value: nil,
                    badge: nil,
                    isActive: state.activeControl == .focus,
                    isEnabled: state.focus.isAvailable || state.focus.mode == .auto,
                    contentRotation: contentRotation
                )
            }
            .buttonStyle(.plain)
            .disabled(!state.focus.isAvailable && state.focus.mode == .auto)
            .accessibilityLabel(state.focus.mode == .auto ? "Auto focus" : "Manual focus")
            .accessibilityIdentifier("camera.lowerToolbar.focus")

            CameraToolbarButtonContent(
                title: "ƒ",
                value: state.aperture.value,
                badge: nil,
                isActive: false,
                isEnabled: false,
                contentRotation: contentRotation
            )
            .accessibilityLabel("Aperture \(state.aperture.value)")
            .accessibilityIdentifier("camera.lowerToolbar.aperture")
        }
        .foregroundStyle(.white)
    }

    private func parameterButton(
        title: String,
        value: String,
        badge: String?,
        control: CameraAdjustmentControl,
        isEnabled: Bool,
        contentRotation: Angle
    ) -> some View {
        Button {
            onSelectControl(control)
        } label: {
            CameraToolbarButtonContent(
                title: title,
                value: value,
                badge: badge,
                isActive: state.activeControl == control,
                isEnabled: isEnabled,
                contentRotation: contentRotation
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityIdentifier("camera.lowerToolbar.\(control.rawValue)")
    }
}

struct CameraTickedAdjustmentStrip: View {
    let state: CameraAdjustmentControlState
    let contentRotation: Angle
    let onAdjustEV: (Double) -> Void
    let onAdjustISO: (Double) -> Void
    let onAdjustShutterPosition: (Double) -> Void
    let onAdjustLensPosition: (Double) -> Void

    var body: some View {
        Group {
            switch state.activeControl {
            case .ev:
                evStrip
            case .iso:
                isoStrip
            case .shutter:
                shutterStrip
            case .focus:
                focusStrip
            case nil:
                EmptyView()
            }
        }
        .accessibilityIdentifier("camera.tickedAdjustmentStrip")
    }

    private var evStrip: some View {
        let bias: Double = {
            switch state.exposure.mode {
            case .auto(let globalBias):
                return globalBias
            case .custom:
                return 0
            }
        }()
        return TickedSliderRow(
            title: "EV",
            value: state.exposure.evValue,
            valueBinding: Binding(
                get: { bias },
                set: { onAdjustEV(CameraEVPreferences.clampedBias($0)) }
            ),
            range: CameraEVPreferences.minimumGlobalBias...CameraEVPreferences.maximumGlobalBias,
            step: CameraEVPreferences.adjustmentStep,
            isEnabled: !state.exposure.isCustom,
            contentRotation: contentRotation
        )
    }

    private var isoStrip: some View {
        TickedSliderRow(
            title: "ISO",
            value: state.exposure.isoValue,
            valueBinding: Binding(
                get: { state.exposure.iso },
                set: { onAdjustISO(state.exposure.clampedISO($0)) }
            ),
            range: state.exposure.isoRange,
            step: 1,
            isEnabled: state.exposure.isAvailable,
            contentRotation: contentRotation
        )
    }

    private var shutterStrip: some View {
        TickedSliderRow(
            title: "S",
            value: state.exposure.shutterValue,
            valueBinding: Binding(
                get: { state.exposure.normalizedShutterPosition(for: state.exposure.shutterDurationSeconds) },
                set: { onAdjustShutterPosition($0) }
            ),
            range: 0...1,
            step: 0.01,
            isEnabled: state.exposure.isAvailable,
            contentRotation: contentRotation
        )
    }

    private var focusStrip: some View {
        TickedSliderRow(
            title: "MF",
            value: state.focus.lensPositionDetail,
            valueBinding: Binding(
                get: { state.focus.lensPosition },
                set: { onAdjustLensPosition(state.focus.clampedLensPosition($0)) }
            ),
            range: state.focus.lensPositionRange,
            step: 0.01,
            isEnabled: state.focus.isAvailable && state.focus.mode == .manual,
            contentRotation: contentRotation
        )
    }
}

private struct CameraToolbarButtonContent: View {
    let title: String
    let value: String?
    let badge: String?
    let isActive: Bool
    let isEnabled: Bool
    let contentRotation: Angle

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CenterAnchoredChromeRotation(
                rotation: contentRotation,
                width: 58,
                height: 38
            ) {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if let value {
                        Text(value)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
            }
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? .white.opacity(0.72) : .white.opacity(0.12), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.38)

            if let badge {
                CenterAnchoredChromeRotation(
                    rotation: contentRotation,
                    width: 13,
                    height: 13
                ) {
                    Text(badge)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }
                .background(.white, in: Circle())
                .offset(x: 3, y: -4)
            }
        }
    }

    private var backgroundStyle: Color {
        isActive ? .white.opacity(0.22) : .black.opacity(0.48)
    }
}

private struct TickedSliderRow: View {
    let title: String
    let value: String
    let valueBinding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool
    let contentRotation: Angle

    @State private var lastHapticStepIndex: Int?

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
                                    updateValue(
                                        steppedValue(
                                            at: value.location.x,
                                            width: trackProxy.size.width
                                        )
                                    )
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
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        guard upperBound > lowerBound else {
            return 0.5
        }
        return min(max((valueBinding.wrappedValue - lowerBound) / (upperBound - lowerBound), 0), 1)
    }

    private func updateValue(_ value: Double) {
        let nextValue = steppedClampedValue(value)
        triggerSelectionHapticIfNeeded(for: nextValue)
        valueBinding.wrappedValue = nextValue
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

nonisolated private func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
    guard value.isFinite else {
        return range.lowerBound
    }
    return min(max(value, range.lowerBound), range.upperBound)
}
