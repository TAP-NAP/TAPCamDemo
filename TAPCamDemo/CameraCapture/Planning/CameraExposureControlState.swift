//
//  CameraExposureControlState.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum CameraExposureControlMode: Equatable, Sendable {
    case auto
    case isoPriority
    case shutterPriority
    case manual

    var isISOAutomatic: Bool {
        switch self {
        case .auto, .shutterPriority:
            true
        case .isoPriority, .manual:
            false
        }
    }

    var isShutterAutomatic: Bool {
        switch self {
        case .auto, .isoPriority:
            true
        case .shutterPriority, .manual:
            false
        }
    }

    var isEVReadOnly: Bool {
        self == .manual
    }
}

nonisolated enum CameraExposureControlInteraction: Equatable, Sendable {
    case ev
    case iso
    case shutter
}

nonisolated enum CameraManualControlReadbackReason: String, Equatable, Sendable {
    case initialBaseline
    case focusMetering
    case exposureSettled
    case userInteractionEnded
    case debugOverlay
}

nonisolated enum CameraExposureControlDiscardReason: Equatable, Sendable {
    case staleDevice
    case staleControlSurface
    case staleGeneration
    case noMeterBaseline
}

nonisolated struct CameraExposureMeterSample: Equatable, Sendable {
    let deviceID: String
    let controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
    let generation: Int
    let iso: Double
    let shutterDurationSeconds: Double
    let exposureTargetOffset: Double
    let exposureTargetBias: Double
    let isSettled: Bool
    let reason: CameraManualControlReadbackReason

    var equivalentExposure: Double {
        guard iso.isFinite, shutterDurationSeconds.isFinite, exposureTargetOffset.isFinite else {
            return 0
        }
        return max(0, iso * shutterDurationSeconds * pow(2, -exposureTargetOffset))
    }
}

nonisolated struct CameraExposureMeterBaseline: Equatable, Sendable {
    let sample: CameraExposureMeterSample

    var equivalentExposure: Double {
        sample.equivalentExposure
    }
}

nonisolated struct CameraExposureControlDisplayState: Equatable, Sendable {
    let mode: CameraExposureControlMode
    let evBias: Double
    let evTitle: String
    let evValue: String
    let isEVReadOnly: Bool
    let iso: Double
    let shutterDurationSeconds: Double
    let isoBadge: String?
    let shutterBadge: String?
    let meterDeltaEV: Double?
    let baselineSettled: Bool
}

nonisolated struct CameraExposureControlDebugState: Equatable, Sendable {
    let mode: CameraExposureControlMode
    let generation: Int
    let baselineSettled: Bool
    let hasMeterBaseline: Bool
    let hasPendingMeterSample: Bool
    let lastReadbackReason: CameraManualControlReadbackReason?
    let lastDiscardedReason: CameraExposureControlDiscardReason?
    let equivalentExposure: Double?
    let targetExposure: Double?
    let meterDeltaEV: Double?
}

nonisolated struct CameraExposureControlResult: Equatable, Sendable {
    let nextState: CameraExposureControlState
    let displayState: CameraExposureControlDisplayState
    let manualControlIntent: CameraManualControlIntent?
    let debugState: CameraExposureControlDebugState
    let shouldReadback: Bool
    let readbackReason: CameraManualControlReadbackReason?
    let discardedReason: CameraExposureControlDiscardReason?
}

nonisolated struct CameraExposureControlState: Equatable, Sendable {
    var deviceID: String
    var controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
    var generation: Int
    var mode: CameraExposureControlMode
    var evBias: Double
    var iso: Double
    var shutterDurationSeconds: Double
    var meterBaseline: CameraExposureMeterBaseline?
    var baselineSettled: Bool
    var pendingMeterSample: CameraExposureMeterSample?
    var activeInteraction: CameraExposureControlInteraction?
    var lastReadbackReason: CameraManualControlReadbackReason?
    var lastDiscardedReason: CameraExposureControlDiscardReason?

    init(
        capability: CameraControlCapabilitySnapshot,
        generation: Int = 0,
        evBias: Double = 0
    ) {
        self.init(
            deviceID: capability.deviceID,
            controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(capability: capability),
            generation: generation,
            mode: .auto,
            evBias: Self.clampedEVBias(evBias),
            iso: Self.clamped(capability.exposure.currentISO, in: capability.exposure.isoRange),
            shutterDurationSeconds: Self.clamped(
                capability.exposure.currentShutterDurationSeconds,
                in: capability.exposure.shutterDurationRangeSeconds
            ),
            meterBaseline: nil,
            baselineSettled: false,
            pendingMeterSample: nil,
            activeInteraction: nil,
            lastReadbackReason: nil,
            lastDiscardedReason: nil
        )
    }

    private init(
        deviceID: String,
        controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature,
        generation: Int,
        mode: CameraExposureControlMode,
        evBias: Double,
        iso: Double,
        shutterDurationSeconds: Double,
        meterBaseline: CameraExposureMeterBaseline?,
        baselineSettled: Bool,
        pendingMeterSample: CameraExposureMeterSample?,
        activeInteraction: CameraExposureControlInteraction?,
        lastReadbackReason: CameraManualControlReadbackReason?,
        lastDiscardedReason: CameraExposureControlDiscardReason?
    ) {
        self.deviceID = deviceID
        self.controlSurfaceSignature = controlSurfaceSignature
        self.generation = generation
        self.mode = mode
        self.evBias = evBias
        self.iso = iso
        self.shutterDurationSeconds = shutterDurationSeconds
        self.meterBaseline = meterBaseline
        self.baselineSettled = baselineSettled
        self.pendingMeterSample = pendingMeterSample
        self.activeInteraction = activeInteraction
        self.lastReadbackReason = lastReadbackReason
        self.lastDiscardedReason = lastDiscardedReason
    }

    static func configurationChanged(
        capability: CameraControlCapabilitySnapshot,
        generation: Int,
        evBias: Double
    ) -> CameraExposureControlResult {
        let state = CameraExposureControlState(
            capability: capability,
            generation: generation,
            evBias: evBias
        )
        return state.result(
            intent: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .continuousAuto,
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ),
            shouldReadback: true,
            readbackReason: .initialBaseline
        )
    }

    var currentDisplayState: CameraExposureControlDisplayState {
        displayState()
    }

    func beginInteraction(_ interaction: CameraExposureControlInteraction) -> CameraExposureControlResult {
        var state = self
        state.activeInteraction = interaction
        return state.result()
    }

    func endInteraction() -> CameraExposureControlResult {
        var state = self
        state.activeInteraction = nil
        if let pendingMeterSample {
            state.pendingMeterSample = nil
            return state.applyMeterSample(pendingMeterSample)
        }
        return state.result(
            shouldReadback: true,
            readbackReason: .userInteractionEnded
        )
    }

    func receiveMeterSample(_ sample: CameraExposureMeterSample) -> CameraExposureControlResult {
        guard let discardedReason = staleReason(for: sample) else {
            if activeInteraction != nil {
                var state = self
                state.pendingMeterSample = sample
                state.lastDiscardedReason = nil
                return state.result()
            }
            return applyMeterSample(sample)
        }
        var state = self
        state.lastDiscardedReason = discardedReason
        return state.result(discardedReason: discardedReason)
    }

    func setEVBias(_ value: Double) -> CameraExposureControlResult {
        guard mode != .manual else {
            return result()
        }
        let nextBias = Self.clampedEVBias(value)
        var state = self
        state.evBias = nextBias
        state.lastDiscardedReason = nil
        switch mode {
        case .auto:
            return state.result(
                intent: CameraManualControlIntent(
                    targetDeviceID: deviceID,
                    exposure: .exposureBias(nextBias),
                    focus: nil,
                    whiteBalance: nil,
                    aperture: nil,
                    zoomFactor: nil
                )
            )
        case .isoPriority, .shutterPriority:
            let fallbackTargetExposure = currentEquivalentExposure
                * pow(2, nextBias - evBias)
            let resolvedState = state.resolvedAutomaticSide(
                fallbackTargetExposure: fallbackTargetExposure
            )
            return resolvedState.result(intent: resolvedState.customExposureIntent())
        case .manual:
            return state.result()
        }
    }

    func setISO(_ value: Double) -> CameraExposureControlResult {
        let clampedISO = CameraPhotographyExposureScale
            .iso(in: controlSurfaceSignature.iso.range)
            .snappedValue(for: value)
        let nextMode: CameraExposureControlMode = mode.isShutterAutomatic ? .isoPriority : .manual
        var pendingState = self
        pendingState.mode = nextMode
        pendingState.iso = clampedISO
        pendingState.lastDiscardedReason = nil
        let state = pendingState.resolvedAutomaticSide(
            fallbackTargetExposure: currentEquivalentExposure
        )
        return state.result(intent: state.customExposureIntent())
    }

    func setShutterDuration(_ value: Double) -> CameraExposureControlResult {
        let clampedShutter = CameraPhotographyExposureScale
            .shutterDuration(in: controlSurfaceSignature.shutterSeconds.range)
            .snappedValue(for: value)
        let nextMode: CameraExposureControlMode = mode.isISOAutomatic ? .shutterPriority : .manual
        var pendingState = self
        pendingState.mode = nextMode
        pendingState.shutterDurationSeconds = clampedShutter
        pendingState.lastDiscardedReason = nil
        let state = pendingState.resolvedAutomaticSide(
            fallbackTargetExposure: currentEquivalentExposure
        )
        return state.result(intent: state.customExposureIntent())
    }

    func makeISOAutomatic() -> CameraExposureControlResult {
        let nextMode: CameraExposureControlMode = mode.isShutterAutomatic ? .auto : .shutterPriority
        var pendingState = self
        pendingState.mode = nextMode
        let state = pendingState.resolvedAutomaticSide(
            fallbackTargetExposure: currentEquivalentExposure
        )
        return state.result(intent: state.intentForCurrentMode())
    }

    func makeShutterAutomatic() -> CameraExposureControlResult {
        let nextMode: CameraExposureControlMode = mode.isISOAutomatic ? .auto : .isoPriority
        var pendingState = self
        pendingState.mode = nextMode
        let state = pendingState.resolvedAutomaticSide(
            fallbackTargetExposure: currentEquivalentExposure
        )
        return state.result(intent: state.intentForCurrentMode())
    }

    func riskRangeForISO() -> [ClosedRange<Double>] {
        let isoScale = CameraPhotographyExposureScale.iso(
            in: controlSurfaceSignature.iso.range
        )
        let shutterScale = CameraPhotographyExposureScale.shutterDuration(
            in: controlSurfaceSignature.shutterSeconds.range
        )
        guard let isoRange = isoScale.adjustableValueRange,
              let shutterRange = shutterScale.adjustableValueRange else {
            return []
        }
        if mode.isShutterAutomatic {
            return automaticSideBoundaryRiskRanges(
                variableRange: isoRange,
                automaticRange: shutterRange
            )
        }
        return riskRanges(
            range: isoRange,
            fixedValue: shutterDurationSeconds,
            product: { iso, shutter in iso * shutter }
        )
    }

    func riskRangeForShutterDuration() -> [ClosedRange<Double>] {
        let isoScale = CameraPhotographyExposureScale.iso(
            in: controlSurfaceSignature.iso.range
        )
        let shutterScale = CameraPhotographyExposureScale.shutterDuration(
            in: controlSurfaceSignature.shutterSeconds.range
        )
        guard let isoRange = isoScale.adjustableValueRange,
              let shutterRange = shutterScale.adjustableValueRange else {
            return []
        }
        if mode.isISOAutomatic {
            return automaticSideBoundaryRiskRanges(
                variableRange: shutterRange,
                automaticRange: isoRange
            )
        }
        return riskRanges(
            range: shutterRange,
            fixedValue: iso,
            product: { shutter, iso in iso * shutter }
        )
    }

    private func applyMeterSample(_ sample: CameraExposureMeterSample) -> CameraExposureControlResult {
        guard let discardedReason = staleReason(for: sample) else {
            var pendingState = self
            if mode == .auto {
                pendingState.iso = Self.clamped(sample.iso, in: controlSurfaceSignature.iso.range)
                pendingState.shutterDurationSeconds = Self.clamped(
                    sample.shutterDurationSeconds,
                    in: controlSurfaceSignature.shutterSeconds.range
                )
            }
            pendingState.meterBaseline = CameraExposureMeterBaseline(sample: sample)
            pendingState.baselineSettled = sample.isSettled
            pendingState.pendingMeterSample = nil
            pendingState.lastReadbackReason = sample.reason
            pendingState.lastDiscardedReason = nil
            let state = pendingState.resolvedAutomaticSide()
            return state.result(intent: state.intentForCurrentMode())
        }
        var state = self
        state.lastDiscardedReason = discardedReason
        return state.result(discardedReason: discardedReason)
    }

    private func resolvedAutomaticSide(
        fallbackTargetExposure: Double? = nil
    ) -> CameraExposureControlState {
        guard let targetExposure = targetExposure ?? fallbackTargetExposure,
              targetExposure > 0 else {
            return self
        }

        switch mode {
        case .auto, .manual:
            return self
        case .isoPriority:
            let computedShutter = targetExposure / max(iso, 0.000_001)
            return updating(
                shutterDurationSeconds: CameraPhotographyExposureScale
                    .shutterDuration(in: controlSurfaceSignature.shutterSeconds.range)
                    .snappedValue(for: computedShutter)
            )
        case .shutterPriority:
            let computedISO = targetExposure / max(shutterDurationSeconds, 0.000_001)
            return updating(
                iso: CameraPhotographyExposureScale
                    .iso(in: controlSurfaceSignature.iso.range)
                    .snappedValue(for: computedISO)
            )
        }
    }

    private var targetExposure: Double? {
        guard let meterBaseline else {
            return nil
        }
        return meterBaseline.equivalentExposure * pow(2, evBias)
    }

    private var currentEquivalentExposure: Double {
        max(0, iso * shutterDurationSeconds)
    }

    private var meterDeltaEV: Double? {
        guard let targetExposure, targetExposure > 0, currentEquivalentExposure > 0 else {
            return nil
        }
        return log2(currentEquivalentExposure / targetExposure)
    }

    private func intentForCurrentMode() -> CameraManualControlIntent? {
        switch mode {
        case .auto:
            CameraManualControlIntent(
                targetDeviceID: deviceID,
                exposure: .continuousAuto,
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            )
        case .isoPriority, .shutterPriority, .manual:
            customExposureIntent()
        }
    }

    private func customExposureIntent() -> CameraManualControlIntent? {
        guard mode != .auto else {
            return nil
        }
        return CameraManualControlIntent(
            targetDeviceID: deviceID,
            exposure: .custom(iso: iso, shutterDurationSeconds: shutterDurationSeconds),
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
    }

    private func result(
        intent: CameraManualControlIntent? = nil,
        shouldReadback: Bool = false,
        readbackReason: CameraManualControlReadbackReason? = nil,
        discardedReason: CameraExposureControlDiscardReason? = nil
    ) -> CameraExposureControlResult {
        CameraExposureControlResult(
            nextState: self,
            displayState: displayState(),
            manualControlIntent: intent,
            debugState: debugState(discardedReason: discardedReason),
            shouldReadback: shouldReadback,
            readbackReason: readbackReason,
            discardedReason: discardedReason
        )
    }

    private func displayState() -> CameraExposureControlDisplayState {
        let delta = meterDeltaEV
        return CameraExposureControlDisplayState(
            mode: mode,
            evBias: evBias,
            evTitle: mode.isEVReadOnly ? "Meter" : "EV",
            evValue: mode.isEVReadOnly
                ? Self.signedLabel(delta ?? 0, zeroPrefix: "0.0")
                : Self.signedLabel(evBias, zeroPrefix: "0.0"),
            isEVReadOnly: mode.isEVReadOnly,
            iso: iso,
            shutterDurationSeconds: shutterDurationSeconds,
            isoBadge: mode.isISOAutomatic ? "A" : nil,
            shutterBadge: mode.isShutterAutomatic ? "A" : nil,
            meterDeltaEV: delta,
            baselineSettled: baselineSettled
        )
    }

    private func debugState(
        discardedReason: CameraExposureControlDiscardReason?
    ) -> CameraExposureControlDebugState {
        CameraExposureControlDebugState(
            mode: mode,
            generation: generation,
            baselineSettled: baselineSettled,
            hasMeterBaseline: meterBaseline != nil,
            hasPendingMeterSample: pendingMeterSample != nil,
            lastReadbackReason: lastReadbackReason,
            lastDiscardedReason: discardedReason ?? lastDiscardedReason,
            equivalentExposure: meterBaseline?.equivalentExposure,
            targetExposure: targetExposure,
            meterDeltaEV: meterDeltaEV
        )
    }

    private func staleReason(for sample: CameraExposureMeterSample) -> CameraExposureControlDiscardReason? {
        if sample.deviceID != deviceID {
            return .staleDevice
        }
        if sample.controlSurfaceSignature != controlSurfaceSignature {
            return .staleControlSurface
        }
        if sample.generation != generation {
            return .staleGeneration
        }
        return nil
    }

    private func riskRanges(
        range: ClosedRange<Double>,
        fixedValue: Double,
        product: (Double, Double) -> Double
    ) -> [ClosedRange<Double>] {
        guard let targetExposure, targetExposure > 0, fixedValue > 0 else {
            return []
        }

        let lowerDanger = targetExposure / 2
        let upperDanger = targetExposure * 2
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        let lowSafe = Self.crossingValue(
            targetProduct: lowerDanger,
            fixedValue: fixedValue
        )
        let highSafe = Self.crossingValue(
            targetProduct: upperDanger,
            fixedValue: fixedValue
        )
        var ranges: [ClosedRange<Double>] = []
        if lowSafe > lowerBound {
            ranges.append(lowerBound...min(lowSafe, upperBound))
        }
        if highSafe < upperBound {
            ranges.append(max(highSafe, lowerBound)...upperBound)
        }
        return ranges.filter { $0.lowerBound < $0.upperBound && product($0.lowerBound, fixedValue).isFinite }
    }

    private func automaticSideBoundaryRiskRanges(
        variableRange: ClosedRange<Double>,
        automaticRange: ClosedRange<Double>
    ) -> [ClosedRange<Double>] {
        guard let targetExposure, targetExposure > 0 else {
            return []
        }

        let lowSafe = targetExposure / max(automaticRange.upperBound, 0.000_001)
        let highSafe = targetExposure / max(automaticRange.lowerBound, 0.000_001)
        let lowerBound = variableRange.lowerBound
        let upperBound = variableRange.upperBound
        var ranges: [ClosedRange<Double>] = []
        if lowSafe > lowerBound {
            ranges.append(lowerBound...min(lowSafe, upperBound))
        }
        if highSafe < upperBound {
            ranges.append(max(highSafe, lowerBound)...upperBound)
        }
        return ranges.filter { $0.lowerBound < $0.upperBound }
    }

    private static func crossingValue(targetProduct: Double, fixedValue: Double) -> Double {
        guard fixedValue.isFinite, fixedValue > 0 else {
            return 0
        }
        return targetProduct / fixedValue
    }

    private func updating(
        mode: CameraExposureControlMode? = nil,
        evBias: Double? = nil,
        iso: Double? = nil,
        shutterDurationSeconds: Double? = nil,
        meterBaseline: CameraExposureMeterBaseline? = nil,
        baselineSettled: Bool? = nil,
        pendingMeterSample: CameraExposureMeterSample? = nil,
        activeInteraction: CameraExposureControlInteraction? = nil,
        lastReadbackReason: CameraManualControlReadbackReason? = nil,
        lastDiscardedReason: CameraExposureControlDiscardReason? = nil
    ) -> CameraExposureControlState {
        CameraExposureControlState(
            deviceID: deviceID,
            controlSurfaceSignature: controlSurfaceSignature,
            generation: generation,
            mode: mode ?? self.mode,
            evBias: evBias ?? self.evBias,
            iso: iso ?? self.iso,
            shutterDurationSeconds: shutterDurationSeconds ?? self.shutterDurationSeconds,
            meterBaseline: meterBaseline ?? self.meterBaseline,
            baselineSettled: baselineSettled ?? self.baselineSettled,
            pendingMeterSample: pendingMeterSample ?? self.pendingMeterSample,
            activeInteraction: activeInteraction ?? self.activeInteraction,
            lastReadbackReason: lastReadbackReason ?? self.lastReadbackReason,
            lastDiscardedReason: lastDiscardedReason ?? self.lastDiscardedReason
        )
    }

    private static func clamped(
        _ value: Double,
        in range: CameraManualControlCommandPlan.ControlSurfaceSignature.DoubleRange
    ) -> Double {
        clamped(value, minimum: range.minimum, maximum: range.maximum)
    }

    private static func clamped(
        _ value: Double,
        in range: ClosedRange<Double>
    ) -> Double {
        clamped(value, minimum: range.lowerBound, maximum: range.upperBound)
    }

    private static func clamped(
        _ value: Double,
        in range: CameraControlCapabilitySnapshot.DoubleRange
    ) -> Double {
        clamped(value, minimum: range.minimum, maximum: range.maximum)
    }

    private static func clamped(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite else {
            return minimum
        }
        let resolvedMinimum = min(minimum, maximum)
        let resolvedMaximum = max(minimum, maximum)
        return min(max(value, resolvedMinimum), resolvedMaximum)
    }

    private static func signedLabel(_ value: Double, zeroPrefix: String) -> String {
        guard value.isFinite, abs(value) >= 0.05 else {
            return zeroPrefix
        }
        return String(format: "%+0.1f", value)
    }

    private static func clampedEVBias(_ value: Double) -> Double {
        clamped(value, minimum: -2, maximum: 2)
    }
}

private extension CameraManualControlCommandPlan.ControlSurfaceSignature.DoubleRange {
    nonisolated var range: ClosedRange<Double> {
        let lower = min(minimum, maximum)
        let upper = max(minimum, maximum)
        if upper > lower {
            return lower...upper
        }
        return lower...(lower + 0.000_001)
    }
}
