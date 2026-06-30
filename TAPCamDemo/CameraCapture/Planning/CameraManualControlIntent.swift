//
//  CameraManualControlIntent.swift
//  TAPCamDemo
//

import Foundation

/// Future user-facing manual camera control request.
///
/// This is a pure value model. It does not persist settings, mutate
/// `AVCaptureDevice`, or change the current Release camera UI. Future controls
/// should resolve this value against `CameraControlCapabilitySnapshot` before a
/// Runtime writer applies anything on the session queue.
nonisolated struct CameraManualControlIntent: Equatable, Sendable {
    nonisolated struct NormalizedPoint: Equatable, Sendable {
        let x: Double
        let y: Double

        var isInsideUnitRect: Bool {
            x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
        }
    }

    nonisolated struct WhiteBalanceGains: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var values: [Double] {
            [red, green, blue]
        }
    }

    nonisolated enum Exposure: Equatable, Sendable {
        case continuousAuto
        case locked
        case exposureBias(Double)
        case custom(iso: Double, shutterDurationSeconds: Double)
    }

    nonisolated enum Focus: Equatable, Sendable {
        case continuousAuto
        case autoFocus(pointOfInterest: NormalizedPoint?)
        case locked(lensPosition: Double?)
    }

    nonisolated enum WhiteBalance: Equatable, Sendable {
        case continuousAuto
        case locked
        case deviceGains(WhiteBalanceGains)
    }

    nonisolated enum Aperture: Equatable, Sendable {
        case value(Double)
    }

    /// Device id captured when UI created the intent. A stale request must not
    /// be replayed after the active camera/FOV changes.
    let targetDeviceID: String
    let exposure: Exposure?
    let focus: Focus?
    let whiteBalance: WhiteBalance?
    let aperture: Aperture?
    let zoomFactor: Double?

    static func noChanges(targetDeviceID: String) -> CameraManualControlIntent {
        CameraManualControlIntent(
            targetDeviceID: targetDeviceID,
            exposure: nil,
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
    }

    func resolved(
        against capability: CameraControlCapabilitySnapshot,
        depthSafeZoomRanges: [ClosedRange<Double>] = []
    ) -> CameraManualControlResolution {
        var violations: [CameraManualControlViolation] = []
        if targetDeviceID != capability.deviceID {
            violations.append(.targetDeviceMismatch(expected: targetDeviceID, actual: capability.deviceID))
        }
        violations.append(contentsOf: exposureViolations(against: capability.exposure))
        violations.append(contentsOf: focusViolations(against: capability.focus))
        violations.append(contentsOf: whiteBalanceViolations(against: capability.whiteBalance))
        violations.append(contentsOf: apertureViolations(against: capability.aperture))
        violations.append(contentsOf: zoomViolations(
            against: capability.zoom,
            depthSafeZoomRanges: depthSafeZoomRanges
        ))

        return CameraManualControlResolution(
            intent: self,
            capability: capability,
            violations: violations
        )
    }

    private func exposureViolations(
        against capability: CameraControlCapabilitySnapshot.Exposure
    ) -> [CameraManualControlViolation] {
        switch exposure {
        case nil:
            return []
        case .continuousAuto:
            return capability.supportsContinuousAutoExposure ? [] : [.continuousAutoExposureUnsupported]
        case .locked:
            return capability.supportsLockedExposure ? [] : [.lockedExposureUnsupported]
        case .exposureBias(let value):
            if !capability.exposureBiasRange.isAdjustable {
                return [.exposureBiasUnsupported]
            } else if !Self.contains(value, in: capability.exposureBiasRange) {
                return [.exposureBiasOutOfRange(
                    value: value,
                    minimum: capability.exposureBiasRange.minimum,
                    maximum: capability.exposureBiasRange.maximum
                )]
            } else {
                return []
            }
        case .custom(let iso, let shutterDurationSeconds):
            var violations: [CameraManualControlViolation] = []
            if !capability.supportsCustomExposure {
                violations.append(.customExposureUnsupported)
            }
            if !Self.contains(iso, in: capability.isoRange) {
                violations.append(.isoOutOfRange(
                    value: iso,
                    minimum: capability.isoRange.minimum,
                    maximum: capability.isoRange.maximum
                ))
            }
            if !Self.contains(shutterDurationSeconds, in: capability.shutterDurationRangeSeconds) {
                violations.append(.shutterDurationOutOfRange(
                    value: shutterDurationSeconds,
                    minimum: capability.shutterDurationRangeSeconds.minimum,
                    maximum: capability.shutterDurationRangeSeconds.maximum
                ))
            }
            return violations
        }
    }

    private func focusViolations(
        against capability: CameraControlCapabilitySnapshot.Focus
    ) -> [CameraManualControlViolation] {
        switch focus {
        case nil:
            return []
        case .continuousAuto:
            return capability.supportsContinuousAutoFocus ? [] : [.continuousAutoFocusUnsupported]
        case .autoFocus(let point):
            var violations: [CameraManualControlViolation] = []
            if !capability.supportsAutoFocus {
                violations.append(.autoFocusUnsupported)
            }
            if let point {
                if !capability.supportsFocusPointOfInterest {
                    violations.append(.focusPointUnsupported)
                }
                if !point.isInsideUnitRect {
                    violations.append(.focusPointOutOfBounds(x: point.x, y: point.y))
                }
            }
            return violations
        case .locked(let lensPosition):
            var violations: [CameraManualControlViolation] = []
            if !capability.supportsLockedFocus {
                violations.append(.lockedFocusUnsupported)
            }
            if lensPosition != nil && !capability.supportsCustomLensPosition {
                violations.append(.customLensPositionUnsupported)
            }
            if let lensPosition, !Self.contains(lensPosition, in: .init(minimum: 0, maximum: 1)) {
                violations.append(.lensPositionOutOfRange(lensPosition))
            }
            return violations
        }
    }

    private func whiteBalanceViolations(
        against capability: CameraControlCapabilitySnapshot.WhiteBalance
    ) -> [CameraManualControlViolation] {
        switch whiteBalance {
        case nil:
            return []
        case .continuousAuto:
            return capability.supportsContinuousAutoWhiteBalance ? [] : [.continuousAutoWhiteBalanceUnsupported]
        case .locked:
            return capability.supportsLockedWhiteBalance ? [] : [.lockedWhiteBalanceUnsupported]
        case .deviceGains(let gains):
            guard capability.supportsLockedWhiteBalance else {
                return [.lockedWhiteBalanceUnsupported]
            }
            let maximumGain = capability.maximumGain
            return gains.values.compactMap { value in
                guard value.isFinite && value >= 1 && value <= maximumGain else {
                    return .whiteBalanceGainOutOfRange(
                        value: value,
                        minimum: 1,
                        maximum: maximumGain
                    )
                }
                return nil
            }
        }
    }

    private func apertureViolations(
        against capability: CameraControlCapabilitySnapshot.Aperture
    ) -> [CameraManualControlViolation] {
        switch aperture {
        case nil:
            return []
        case .value(let value):
            if !value.isFinite {
                return [.apertureValueNotFinite(value)]
            }
            return capability.isAdjustable ? [] : [.apertureAdjustmentUnsupported]
        }
    }

    private func zoomViolations(
        against capability: CameraControlCapabilitySnapshot.Zoom,
        depthSafeZoomRanges: [ClosedRange<Double>]
    ) -> [CameraManualControlViolation] {
        guard let zoomFactor else {
            return []
        }

        guard Self.contains(zoomFactor, in: capability.range) else {
            return [.zoomOutOfRange(
                value: zoomFactor,
                minimum: capability.range.minimum,
                maximum: capability.range.maximum
            )]
        }

        guard !depthSafeZoomRanges.isEmpty else {
            return []
        }

        return depthSafeZoomRanges.contains { $0.contains(zoomFactor) }
            ? []
            : [.zoomOutsideDepthSafeRanges(zoomFactor)]
    }

    private static func contains(
        _ value: Double,
        in range: CameraControlCapabilitySnapshot.DoubleRange
    ) -> Bool {
        value.isFinite && value >= range.minimum && value <= range.maximum
    }
}

nonisolated struct CameraManualControlResolution: Equatable, Sendable {
    let intent: CameraManualControlIntent
    let capability: CameraControlCapabilitySnapshot
    let violations: [CameraManualControlViolation]

    var isExecutable: Bool {
        violations.isEmpty
    }
}

/// Public-safe summary for future manual-control UI or persistence review.
///
/// `CameraManualControlViolation.readerDescription` is intentionally more
/// detailed for developers and can include device ids or requested numeric
/// values. Future visible UI should start from this summary instead: it names
/// only fixed control groups and fixed status copy, while leaving execution and
/// device writes to the resolution plus Runtime service boundaries.
nonisolated struct CameraManualControlResolutionPresentation: Equatable, Sendable {
    nonisolated enum Status: Equatable, Sendable {
        case noChanges
        case ready
        case blocked
    }

    let status: Status
    let title: String
    let detail: String
    let requestedControlLabels: [String]
    let blockedControlLabels: [String]

    init(resolution: CameraManualControlResolution) {
        let summary = CameraManualControlSummary(resolution: resolution)
        let requestedControlLabels = summary.rows
            .filter(\.isRequested)
            .map(\.title)
        let blockedControlLabels = summary.rows
            .filter { !$0.isExecutable }
            .map(\.title)
        let status: Status
        let title: String
        let detail: String

        if !resolution.isExecutable {
            status = .blocked
            title = "Manual controls unavailable"
            detail = "The manual-control request is stale, unsupported, or outside depth-safe bounds."
        } else if requestedControlLabels.isEmpty {
            status = .noChanges
            title = "No manual control changes"
            detail = "No EV, focus, white balance, aperture, or zoom change requested."
        } else {
            status = .ready
            title = "Manual controls ready"
            detail = "Request matches the active camera capability snapshot."
        }

        self.status = status
        self.title = title
        self.detail = detail
        self.requestedControlLabels = requestedControlLabels
        self.blockedControlLabels = blockedControlLabels
    }
}

nonisolated enum CameraManualControlViolation: Equatable, Sendable {
    case targetDeviceMismatch(expected: String, actual: String)
    case continuousAutoExposureUnsupported
    case lockedExposureUnsupported
    case exposureBiasUnsupported
    case exposureBiasOutOfRange(value: Double, minimum: Double, maximum: Double)
    case customExposureUnsupported
    case isoOutOfRange(value: Double, minimum: Double, maximum: Double)
    case shutterDurationOutOfRange(value: Double, minimum: Double, maximum: Double)
    case continuousAutoFocusUnsupported
    case autoFocusUnsupported
    case lockedFocusUnsupported
    case customLensPositionUnsupported
    case focusPointUnsupported
    case focusPointOutOfBounds(x: Double, y: Double)
    case lensPositionOutOfRange(Double)
    case continuousAutoWhiteBalanceUnsupported
    case lockedWhiteBalanceUnsupported
    case whiteBalanceGainOutOfRange(value: Double, minimum: Double, maximum: Double)
    case apertureValueNotFinite(Double)
    case apertureAdjustmentUnsupported
    case zoomOutOfRange(value: Double, minimum: Double, maximum: Double)
    case zoomOutsideDepthSafeRanges(Double)

    var readerDescription: String {
        switch self {
        case .targetDeviceMismatch(let expected, let actual):
            "Manual control request targets device '\(expected)' but the active device is '\(actual)'."
        case .continuousAutoExposureUnsupported:
            "The active camera does not support continuous auto exposure."
        case .lockedExposureUnsupported:
            "The active camera does not support locked exposure."
        case .exposureBiasUnsupported:
            "The active camera does not expose an adjustable EV bias range."
        case .exposureBiasOutOfRange(let value, let minimum, let maximum):
            "Requested EV bias \(value) is outside \(minimum)...\(maximum)."
        case .customExposureUnsupported:
            "The active camera does not support custom ISO and shutter duration."
        case .isoOutOfRange(let value, let minimum, let maximum):
            "Requested ISO \(value) is outside \(minimum)...\(maximum)."
        case .shutterDurationOutOfRange(let value, let minimum, let maximum):
            "Requested shutter duration \(value)s is outside \(minimum)...\(maximum)s."
        case .continuousAutoFocusUnsupported:
            "The active camera does not support continuous auto focus."
        case .autoFocusUnsupported:
            "The active camera does not support one-shot auto focus."
        case .lockedFocusUnsupported:
            "The active camera does not support locked focus."
        case .customLensPositionUnsupported:
            "The active camera does not support custom lens position."
        case .focusPointUnsupported:
            "The active camera does not support a focus point of interest."
        case .focusPointOutOfBounds(let x, let y):
            "Requested focus point (\(x), \(y)) is outside the normalized unit rect."
        case .lensPositionOutOfRange(let value):
            "Requested lens position \(value) is outside 0...1."
        case .continuousAutoWhiteBalanceUnsupported:
            "The active camera does not support continuous auto white balance."
        case .lockedWhiteBalanceUnsupported:
            "The active camera does not support locked white balance."
        case .whiteBalanceGainOutOfRange(let value, let minimum, let maximum):
            "Requested white-balance gain \(value) is outside \(minimum)...\(maximum)."
        case .apertureValueNotFinite(let value):
            "Requested aperture \(value) is not finite."
        case .apertureAdjustmentUnsupported:
            "The active camera lens aperture is not adjustable."
        case .zoomOutOfRange(let value, let minimum, let maximum):
            "Requested zoom \(value) is outside \(minimum)...\(maximum)."
        case .zoomOutsideDepthSafeRanges(let value):
            "Requested zoom \(value) is outside the depth-safe zoom ranges."
        }
    }
}
