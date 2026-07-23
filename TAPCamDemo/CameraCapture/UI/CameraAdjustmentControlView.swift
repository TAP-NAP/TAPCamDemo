//
//  CameraAdjustmentControlView.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI

nonisolated struct CameraAdjustmentControlState: Equatable, Sendable {
    nonisolated struct ExposureRiskRanges: Equatable, Sendable {
        let iso: [ClosedRange<Double>]
        let shutterDurationSeconds: [ClosedRange<Double>]

        static let empty = ExposureRiskRanges(iso: [], shutterDurationSeconds: [])
    }

    nonisolated enum ExposureMode: Equatable, Sendable {
        case auto(globalBias: Double)
        case isoPriority(globalBias: Double)
        case shutterPriority(globalBias: Double)
        case custom(meterOffset: Double)

        var isISOAutomatic: Bool {
            switch self {
            case .auto, .shutterPriority:
                true
            case .isoPriority, .custom:
                false
            }
        }

        var isShutterAutomatic: Bool {
            switch self {
            case .auto, .isoPriority:
                true
            case .shutterPriority, .custom:
                false
            }
        }

        var isEVReadOnly: Bool {
            switch self {
            case .custom:
                true
            case .auto, .isoPriority, .shutterPriority:
                false
            }
        }
    }

    nonisolated struct Exposure: Equatable, Sendable {
        let isAvailable: Bool
        let mode: ExposureMode
        let isoRange: ClosedRange<Double>
        let shutterDurationRangeSeconds: ClosedRange<Double>
        let isoRiskRanges: [ClosedRange<Double>]
        let shutterDurationRiskRanges: [ClosedRange<Double>]
        let iso: Double
        let shutterDurationSeconds: Double

        var isCustom: Bool {
            switch mode {
            case .auto:
                false
            case .isoPriority, .shutterPriority, .custom:
                true
            }
        }

        var evTitle: String {
            mode.isEVReadOnly ? "Meter" : "EV"
        }

        var evValue: String {
            switch mode {
            case .auto(let globalBias):
                Self.signedLabel(globalBias, zeroPrefix: "0.0")
            case .isoPriority(let globalBias):
                Self.signedLabel(globalBias, zeroPrefix: "0.0")
            case .shutterPriority(let globalBias):
                Self.signedLabel(globalBias, zeroPrefix: "0.0")
            case .custom(let meterOffset):
                Self.signedLabel(meterOffset, zeroPrefix: "0.0")
            }
        }

        var isoBadge: String {
            mode.isISOAutomatic ? "A" : "M"
        }

        var shutterBadge: String {
            mode.isShutterAutomatic ? "A" : "M"
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
        draft: CameraAdjustmentControlDraft,
        exposureRiskRanges: ExposureRiskRanges = .empty,
        allowsManualFocusControl: Bool = true
    ) {
        let exposureRange = Self.closedRange(from: capability.exposure.shutterDurationRangeSeconds)
        let isoRange = Self.closedRange(from: capability.exposure.isoRange)
        let focusRange = 0.0...1.0
        exposure = Exposure(
            isAvailable: capability.exposure.hasManualRange,
            mode: exposureMode,
            isoRange: isoRange,
            shutterDurationRangeSeconds: exposureRange,
            isoRiskRanges: exposureRiskRanges.iso,
            shutterDurationRiskRanges: exposureRiskRanges.shutterDurationSeconds,
            iso: clamped(draft.iso, in: isoRange),
            shutterDurationSeconds: clamped(draft.shutterDurationSeconds, in: exposureRange)
        )
        focus = Focus(
            isAvailable: allowsManualFocusControl && capability.focus.supportsManualLensPosition,
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
                badge: state.exposure.isoBadge,
                control: .iso,
                isEnabled: state.exposure.isAvailable,
                contentRotation: contentRotation
            )

            parameterButton(
                title: "S",
                value: state.exposure.shutterValue,
                badge: state.exposure.shutterBadge,
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
                    isEnabled: state.focus.isAvailable,
                    contentRotation: contentRotation
                )
            }
            .buttonStyle(.plain)
            .disabled(!state.focus.isAvailable)
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
    let highlightColor: Color
    let contentRotation: Angle
    let onAdjustEV: (Double) -> Void
    let onAdjustISO: (Double) -> Void
    let onAdjustShutterPosition: (Double) -> Void
    let onAdjustLensPosition: (Double) -> Void
    let onBeginAdjustment: (CameraAdjustmentControl) -> Void
    let onEndAdjustment: (CameraAdjustmentControl) -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .accessibilityIdentifier("camera.tickedAdjustmentStrip")
    }

    @ViewBuilder
    private var content: some View {
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

    private var evStrip: some View {
        let bias: Double = {
            switch state.exposure.mode {
            case .auto(let globalBias):
                return globalBias
            case .isoPriority(let globalBias):
                return globalBias
            case .shutterPriority(let globalBias):
                return globalBias
            case .custom:
                return 0
            }
        }()
        return CameraTickedSliderRow(
            title: "EV",
            value: state.exposure.evValue,
            valueBinding: Binding(
                get: { bias },
                set: { onAdjustEV(CameraEVPreferences.clampedBias($0)) }
            ),
            range: CameraEVPreferences.minimumGlobalBias...CameraEVPreferences.maximumGlobalBias,
            step: CameraEVPreferences.adjustmentStep,
            isEnabled: !state.exposure.mode.isEVReadOnly,
            highlightColor: highlightColor,
            contentRotation: contentRotation,
            riskRanges: [],
            tickValueStep: CameraEVPreferences.adjustmentStep,
            isEVIntegerHapticsEnabled: true,
            onEditingBegan: { onBeginAdjustment(.ev) },
            onEditingEnded: { onEndAdjustment(.ev) }
        )
    }

    private var isoStrip: some View {
        CameraTickedSliderRow(
            title: "ISO",
            value: state.exposure.isoValue,
            valueBinding: Binding(
                get: { state.exposure.iso },
                set: { onAdjustISO(state.exposure.clampedISO($0)) }
            ),
            range: state.exposure.isoRange,
            step: 1,
            isEnabled: state.exposure.isAvailable,
            highlightColor: highlightColor,
            contentRotation: contentRotation,
            riskRanges: state.exposure.isoRiskRanges,
            tickValueStep: nil,
            isEVIntegerHapticsEnabled: false,
            onEditingBegan: { onBeginAdjustment(.iso) },
            onEditingEnded: { onEndAdjustment(.iso) }
        )
    }

    private var shutterStrip: some View {
        CameraTickedSliderRow(
            title: "S",
            value: state.exposure.shutterValue,
            valueBinding: Binding(
                get: { state.exposure.normalizedShutterPosition(for: state.exposure.shutterDurationSeconds) },
                set: { onAdjustShutterPosition($0) }
            ),
            range: 0...1,
            step: 0.01,
            isEnabled: state.exposure.isAvailable,
            highlightColor: highlightColor,
            contentRotation: contentRotation,
            riskRanges: shutterRiskRangesForSlider,
            tickValueStep: nil,
            isEVIntegerHapticsEnabled: false,
            onEditingBegan: { onBeginAdjustment(.shutter) },
            onEditingEnded: { onEndAdjustment(.shutter) }
        )
    }

    private var shutterRiskRangesForSlider: [ClosedRange<Double>] {
        state.exposure.shutterDurationRiskRanges.map { range in
            let lower = state.exposure.normalizedShutterPosition(for: range.lowerBound)
            let upper = state.exposure.normalizedShutterPosition(for: range.upperBound)
            return min(lower, upper)...max(lower, upper)
        }
    }

    private var focusStrip: some View {
        CameraTickedSliderRow(
            title: "MF",
            value: state.focus.lensPositionDetail,
            valueBinding: Binding(
                get: { state.focus.lensPosition },
                set: { onAdjustLensPosition(state.focus.clampedLensPosition($0)) }
            ),
            range: state.focus.lensPositionRange,
            step: 0.01,
            isEnabled: state.focus.isAvailable && state.focus.mode == .manual,
            highlightColor: highlightColor,
            contentRotation: contentRotation,
            riskRanges: [],
            tickValueStep: nil,
            isEVIntegerHapticsEnabled: false,
            onEditingBegan: { onBeginAdjustment(.focus) },
            onEditingEnded: { onEndAdjustment(.focus) }
        )
    }
}

struct CameraLowerToolbarPlaceholderView: View {
    let contentRotation: Angle

    var body: some View {
        HStack(spacing: 8) {
            CameraToolbarButtonContent(
                title: "EV",
                value: "0.0",
                badge: nil,
                isActive: false,
                isEnabled: false,
                contentRotation: contentRotation
            )

            CameraToolbarButtonContent(
                title: "ISO",
                value: "--",
                badge: "A",
                isActive: false,
                isEnabled: false,
                contentRotation: contentRotation
            )

            CameraToolbarButtonContent(
                title: "S",
                value: "--",
                badge: "A",
                isActive: false,
                isEnabled: false,
                contentRotation: contentRotation
            )

            CameraToolbarButtonContent(
                title: "AF",
                value: nil,
                badge: nil,
                isActive: false,
                isEnabled: false,
                contentRotation: contentRotation
            )

            CameraToolbarButtonContent(
                title: "ƒ",
                value: "--",
                badge: nil,
                isActive: false,
                isEnabled: false,
                contentRotation: contentRotation
            )
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("camera.lowerToolbar.placeholder")
    }
}

struct CameraToolbarButtonContent: View {
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

nonisolated private func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
    guard value.isFinite else {
        return range.lowerBound
    }
    return min(max(value, range.lowerBound), range.upperBound)
}
