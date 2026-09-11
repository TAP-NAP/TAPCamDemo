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
    var exposureDeltaForValue: (Double) -> Double? = { _ in nil }
    var automaticValue: (() -> Double?)? = nil
    let isEVIntegerHapticsEnabled: Bool
    let onRestoreAuto: () -> Void
    let onEditingBegan: () async -> Double?
    let onEditingEnded: () -> Void

    @Environment(\.cameraHapticFeedbackController) private var hapticFeedbackController
    @State private var drag: CameraSliderDrag?
    @State private var interactionTask: Task<Void, Never>?
    @State private var isEditing = false
    @State private var lastEmittedValue: Double?
    @State private var lastTickPosition: Double?

    private var tickIntervals: Int {
        isEVIntegerHapticsEnabled ? max(Int(((range.upperBound - range.lowerBound) * 2).rounded()), 1) : 16
    }

    private var isAutomatic: Bool {
        if let drag, interactionTask != nil || drag.applied != nil || drag.isAutomatic {
            return drag.isAutomatic
        }
        return automationState == .automatic
    }

    var body: some View {
        GeometryReader { proxy in
            let center = proxy.size.width / 2
            let trackWidth = min(max(proxy.size.width - 176, 128), 208)
            let trackStart = center - trackWidth / 2
            let trackEnd = center + trackWidth / 2
            let autoX = min(trackEnd + 47, proxy.size.width - 51)
            let touchWidth = automationState == nil ? trackWidth : proxy.size.width - 12 - trackStart
            let y = proxy.size.height / 2

            ZStack {
                tickMarks
                    .frame(width: trackWidth, height: 34)
                    .position(x: center, y: y)
                riskZoneLayer(trackWidth: trackWidth)
                    .position(x: center, y: y)
                cursor
                    .position(
                        x: isAutomatic ? autoX : trackStart + (drag?.cursorX(width: trackWidth)
                            ?? normalizedPosition(for: valueBinding.wrappedValue) * trackWidth),
                        y: y
                    )
                    .opacity(isAutomatic ? 0 : 1)

                CenterAnchoredChromeRotation(rotation: contentRotation, width: 58, height: 34) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.38))
                }
                .position(x: max(trackStart - 37, 41), y: y)

                if automationState != nil {
                    CenterAnchoredChromeRotation(rotation: contentRotation, width: 78, height: 34) {
                        Text("Auto")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isAutomatic ? highlightColor : .white.opacity(0.4))
                            .overlay(alignment: .bottom) {
                                Capsule()
                                    .fill(highlightColor)
                                    .frame(width: 16, height: 2)
                                    .offset(y: 5)
                                    .opacity(isAutomatic ? 1 : 0)
                            }
                            .opacity(isEnabled ? 1 : 0.38)
                            .animation(.easeOut(duration: 0.12), value: isAutomatic)
                    }
                    .position(x: autoX, y: y)
                    .accessibilityIdentifier("camera.tickedAdjustmentStrip.automation")
                }

                Color.clear
                    .frame(width: touchWidth, height: 44)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { updateDrag($0, width: trackWidth) }
                            .onEnded { finishDrag($0, width: trackWidth) }
                    )
                    .position(x: trackStart + touchWidth / 2, y: y)
                    .allowsHitTesting(isEnabled)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: [automationState?.title, value].compactMap { $0 }.joined(separator: " ")))
        .accessibilityIdentifier("camera.tickedAdjustmentStrip")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustAccessibly(by: resolvedStepSize)
            case .decrement: adjustAccessibly(by: -resolvedStepSize)
            @unknown default: break
            }
        }
        .accessibilityActions {
            if automationState == .manual {
                Button("Auto") { restoreAuto() }
            }
        }
        .onDisappear { cancelInteraction(committingReleasedValue: isEnabled) }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { cancelInteraction() }
        }
    }

    private var tickMarks: some View {
        GeometryReader { proxy in
            ForEach(0...tickIntervals, id: \.self) { index in
                let position = Double(index) / Double(tickIntervals)
                let isZero = isEVIntegerHapticsEnabled && abs(position - normalizedPosition(for: 0)) < 0.000_001
                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.34 : 0.17))
                    .frame(width: 1, height: isZero ? 18 : 8)
                    .position(x: position * proxy.size.width, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func riskZoneLayer(trackWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(riskRanges.enumerated()), id: \.offset) { _, range in
                let start = normalizedPosition(for: range.lowerBound)
                let end = normalizedPosition(for: range.upperBound)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.gray.opacity(0.34))
                    .frame(width: max(end - start, 0) * trackWidth, height: 6)
                    .offset(x: start * trackWidth)
            }
        }
        .frame(width: trackWidth, height: 8, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var cursor: some View {
        Capsule()
            .frame(width: 3, height: 24)
            .foregroundStyle(isEnabled ? highlightColor : .white.opacity(0.36))
            .shadow(color: .black.opacity(0.34), radius: 2)
            .allowsHitTesting(false)
            .accessibilityIdentifier("camera.tickedAdjustmentStrip.activeTick")
    }

    private func updateDrag(_ event: DragGesture.Value, width: Double) {
        guard isEnabled else { return }
        let startsTouch = drag?.isTouching != true
        if startsTouch {
            let startsAutomatic = isAutomatic
            cancelInteraction(committingReleasedValue: true)
            drag = CameraSliderDrag(isAutomatic: startsAutomatic)
            hapticFeedbackController.prepareAdjustmentFeedback()
        }
        guard var next = drag else { return }
        let wasAutomatic = next.isAutomatic
        next.move(
            x: event.location.x, width: width, velocity: event.velocity.width,
            time: event.time.timeIntervalSinceReferenceDate, hasAuto: automationState != nil
        )
        drag = next
        if startsTouch || wasAutomatic != next.isAutomatic { lastTickPosition = next.target }
        if next.isAutomatic, !wasAutomatic {
            detentFeedback(.autoDetent)
            beginAutomaticReturn()
        } else if !next.isAutomatic, wasAutomatic || startsTouch {
            stopEditing()
            if wasAutomatic { detentFeedback(.autoRelease) }
            continueAdjustment(id: next.id)
        } else if !next.isAutomatic {
            tickFeedback(at: next.target)
        }
        if !next.isAutomatic, next.applied != nil, interactionTask == nil, !next.hasReachedTarget {
            continueAdjustment(id: next.id)
        }
    }

    private func finishDrag(_ event: DragGesture.Value, width: Double) {
        guard drag != nil else { return }
        updateDrag(event, width: width)
        guard var next = drag else { return }
        next.isTouching = false
        drag = next
        if interactionTask == nil {
            cancelInteraction()
        }
    }

    private func continueAdjustment(id: UUID) {
        isEditing = true
        interactionTask = Task { @MainActor in
            guard !Task.isCancelled, drag?.id == id else { return }
            if drag?.applied == nil {
                let startingValue = await onEditingBegan()
                guard !Task.isCancelled, drag?.id == id else { return }
                guard let startingValue, startingValue.isFinite else {
                    stopEditing()
                    if drag?.isTouching == false { drag = nil }
                    return
                }
                lastEmittedValue = steppedClampedValue(startingValue)
                drag?.beginManual(at: normalizedPosition(for: startingValue))
            }
            var lastTick = Date.timeIntervalSinceReferenceDate
            while !Task.isCancelled, var current = drag, current.id == id {
                let now = Date.timeIntervalSinceReferenceDate
                if let position = current.advance(
                    at: now, elapsed: now - lastTick, smoothsChanges: automationState != nil,
                    riskEV: increasingExposureRisk(for: current)
                ) {
                    drag = current
                    emitValue(value(at: position))
                }
                lastTick = now
                if current.hasReachedTarget {
                    if current.isAutomatic { finishAutomaticReturn() }
                    else if current.isTouching { interactionTask = nil }
                    else { cancelInteraction() }
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    return
                }
            }
        }
    }

    private func increasingExposureRisk(for current: CameraSliderDrag) -> Double {
        guard !current.isAutomatic, let applied = current.applied,
              riskRanges.contains(where: { $0.contains(value(at: current.target)) }),
              let targetDelta = exposureDeltaForValue(value(at: current.target)),
              let currentDelta = exposureDeltaForValue(value(at: applied)),
              currentDelta * targetDelta >= 0,
              abs(targetDelta) > abs(currentDelta) else { return 0 }
        return abs(targetDelta)
    }

    private func beginAutomaticReturn() {
        interactionTask?.cancel()
        interactionTask = nil
        guard let target = automaticValue?(), target.isFinite, let id = drag?.id else {
            finishAutomaticReturn()
            return
        }
        drag?.approachAutomatic(
            from: normalizedPosition(for: valueBinding.wrappedValue),
            to: normalizedPosition(for: target)
        )
        continueAdjustment(id: id)
    }

    private func finishAutomaticReturn() {
        stopEditing()
        drag?.finishAutomatic()
        onRestoreAuto()
        if drag?.isTouching == false { drag = nil }
    }

    private func stopEditing() {
        interactionTask?.cancel()
        interactionTask = nil
        if isEditing {
            isEditing = false
            onEditingEnded()
        }
    }

    private func cancelInteraction(committingReleasedValue: Bool = false) {
        let completesAutomaticReturn = committingReleasedValue && drag?.isTouching == false
            && drag?.isAutomatic == true && drag?.applied != nil
        if committingReleasedValue, let drag, !drag.isTouching,
           drag.applied != nil, !drag.hasReachedTarget {
            emitValue(value(at: drag.target))
        }
        stopEditing()
        drag = nil
        lastEmittedValue = nil
        lastTickPosition = nil
        if completesAutomaticReturn { onRestoreAuto() }
    }

    private func restoreAuto() {
        guard isEnabled else { return }
        cancelInteraction()
        detentFeedback(.autoDetent)
        drag = CameraSliderDrag(isAutomatic: true)
        drag?.isTouching = false
        beginAutomaticReturn()
    }

    private func adjustAccessibly(by delta: Double) {
        guard isEnabled else { return }
        if automationState == .manual, delta > 0, valueBinding.wrappedValue >= range.upperBound {
            restoreAuto()
            return
        }
        cancelInteraction()
        let wasAutomatic = automationState == .automatic
        isEditing = true
        interactionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let seed = await onEditingBegan()
            guard !Task.isCancelled else { return }
            if let seed {
                let next = steppedClampedValue(seed + delta)
                emitValue(next)
                if wasAutomatic { detentFeedback(.autoRelease) }
                else { feedbackForTick(value: next) }
            }
            cancelInteraction()
        }
    }

    private func emitValue(_ next: Double) {
        guard next != lastEmittedValue else { return }
        lastEmittedValue = next
        valueBinding.wrappedValue = next
    }

    private func detentFeedback(_ style: CameraAdjustmentHapticStyle) {
        hapticFeedbackController.adjustmentChanged(style: style)
    }

    private func tickFeedback(at position: Double) {
        defer { lastTickPosition = position }
        guard let previous = lastTickPosition,
              let tick = CameraSliderDrag.crossedTick(
                from: previous, to: position, intervals: tickIntervals,
                zeroPosition: isEVIntegerHapticsEnabled ? normalizedPosition(for: 0) : nil
              ) else { return }
        feedbackForTick(value: range.lowerBound + tick * (range.upperBound - range.lowerBound))
    }

    private func feedbackForTick(value: Double) {
        let tolerance = max(resolvedStepSize / 10_000, 0.000_001)
        let style: CameraAdjustmentHapticStyle
        if isEVIntegerHapticsEnabled, abs(value) <= tolerance {
            style = .zeroTick
        } else if isEVIntegerHapticsEnabled, abs(value - value.rounded()) <= tolerance {
            style = .integerTick
        } else if automationState != nil, value == range.lowerBound || value == range.upperBound {
            style = .limit
        } else {
            style = .selection
        }
        detentFeedback(style)
    }

    private func normalizedPosition(for value: Double) -> Double {
        guard range.upperBound > range.lowerBound else { return 0.5 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private func value(at position: Double) -> Double {
        steppedClampedValue(range.lowerBound + position * (range.upperBound - range.lowerBound))
    }

    private func steppedClampedValue(_ value: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let stepped = step.isFinite && step > 0 ? (value / step).rounded() * step : value
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private var resolvedStepSize: Double {
        step.isFinite && step > 0 ? step : max((range.upperBound - range.lowerBound) / 100, 0.000_001)
    }
}
