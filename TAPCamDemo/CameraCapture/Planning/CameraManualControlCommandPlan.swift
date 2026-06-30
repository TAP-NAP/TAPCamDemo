//
//  CameraManualControlCommandPlan.swift
//  TAPCamDemo
//

import Foundation

/// Runtime-executable pure command plan for future manual camera writes.
///
/// This is not a public-safe display model. It may carry requested numeric
/// values and the target device id because a future Runtime writer needs them
/// to apply controls on the session queue and reject stale-camera writes.
/// SwiftUI, logs, and persistence should use
/// `CameraManualControlResolutionPresentation` or `CameraManualControlSummary`
/// instead.
nonisolated struct CameraManualControlCommandPlan: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
    nonisolated enum State: Equatable, Sendable {
        case noChanges
        case executable
        case blocked
    }

    nonisolated struct ControlSurfaceSignature: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
        nonisolated struct DoubleRange: Equatable, Sendable {
            let minimum: Double
            let maximum: Double

            init(_ range: CameraControlCapabilitySnapshot.DoubleRange) {
                minimum = range.minimum
                maximum = range.maximum
            }
        }

        let supportsContinuousAutoExposure: Bool
        let supportsLockedExposure: Bool
        let supportsCustomExposure: Bool
        let exposureBias: DoubleRange
        let iso: DoubleRange
        let shutterSeconds: DoubleRange
        let supportsAutoFocus: Bool
        let supportsContinuousAutoFocus: Bool
        let supportsLockedFocus: Bool
        let supportsCustomLensPosition: Bool
        let supportsFocusPointOfInterest: Bool
        let supportsLockedWhiteBalance: Bool
        let supportsContinuousAutoWhiteBalance: Bool
        let maximumWhiteBalanceGain: Double
        let fixedLensAperture: Double
        let zoom: DoubleRange

        init(capability: CameraControlCapabilitySnapshot) {
            supportsContinuousAutoExposure = capability.exposure.supportsContinuousAutoExposure
            supportsLockedExposure = capability.exposure.supportsLockedExposure
            supportsCustomExposure = capability.exposure.supportsCustomExposure
            exposureBias = DoubleRange(capability.exposure.exposureBiasRange)
            iso = DoubleRange(capability.exposure.isoRange)
            shutterSeconds = DoubleRange(capability.exposure.shutterDurationRangeSeconds)
            supportsAutoFocus = capability.focus.supportsAutoFocus
            supportsContinuousAutoFocus = capability.focus.supportsContinuousAutoFocus
            supportsLockedFocus = capability.focus.supportsLockedFocus
            supportsCustomLensPosition = capability.focus.supportsCustomLensPosition
            supportsFocusPointOfInterest = capability.focus.supportsFocusPointOfInterest
            supportsLockedWhiteBalance = capability.whiteBalance.supportsLockedWhiteBalance
            supportsContinuousAutoWhiteBalance = capability.whiteBalance.supportsContinuousAutoWhiteBalance
            maximumWhiteBalanceGain = capability.whiteBalance.maximumGain
            fixedLensAperture = capability.aperture.fixedLensAperture
            zoom = DoubleRange(capability.zoom.range)
        }

        var description: String {
            "controlSurfaceSignature"
        }

        var debugDescription: String {
            description
        }
    }

    nonisolated struct NormalizedPoint: Equatable, Sendable {
        let x: Double
        let y: Double
    }

    nonisolated struct WhiteBalanceGains: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    nonisolated enum Command: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
        case exposure(Exposure)
        case focus(Focus)
        case whiteBalance(WhiteBalance)
        case aperture(Aperture)
        case zoomFactor(Double)

        var isRuntimeSupported: Bool {
            switch self {
            case .exposure, .focus, .whiteBalance, .zoomFactor:
                true
            case .aperture:
                false
            }
        }

        var description: String {
            switch self {
            case .exposure:
                "exposure"
            case .focus:
                "focus"
            case .whiteBalance:
                "whiteBalance"
            case .aperture:
                "aperture"
            case .zoomFactor:
                "zoomFactor"
            }
        }

        var debugDescription: String {
            description
        }
    }

    nonisolated enum Exposure: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
        case continuousAuto
        case locked
        case exposureBias(Double)
        case custom(iso: Double, shutterDurationSeconds: Double)

        var description: String {
            switch self {
            case .continuousAuto:
                "continuousAuto"
            case .locked:
                "locked"
            case .exposureBias:
                "exposureBias"
            case .custom:
                "custom"
            }
        }

        var debugDescription: String {
            description
        }
    }

    nonisolated enum Focus: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
        case continuousAuto
        case autoFocus(pointOfInterest: NormalizedPoint?)
        case locked(lensPosition: Double?)

        var description: String {
            switch self {
            case .continuousAuto:
                "continuousAuto"
            case .autoFocus:
                "autoFocus"
            case .locked:
                "locked"
            }
        }

        var debugDescription: String {
            description
        }
    }

    nonisolated enum WhiteBalance: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
        case continuousAuto
        case locked
        case deviceGains(WhiteBalanceGains)

        var description: String {
            switch self {
            case .continuousAuto:
                "continuousAuto"
            case .locked:
                "locked"
            case .deviceGains:
                "deviceGains"
            }
        }

        var debugDescription: String {
            description
        }
    }

    nonisolated enum Aperture: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
        case value(Double)

        var description: String {
            "value"
        }

        var debugDescription: String {
            description
        }
    }

    let targetDeviceID: String
    let targetControlSignature: ControlSurfaceSignature
    let state: State
    let commands: [Command]

    var description: String {
        "CameraManualControlCommandPlan(state: \(state), commandCount: \(commands.count))"
    }

    var debugDescription: String {
        description
    }

    var requiresRuntimeWrite: Bool {
        !commands.isEmpty
    }

    init(resolution: CameraManualControlResolution) {
        targetDeviceID = resolution.intent.targetDeviceID
        targetControlSignature = ControlSurfaceSignature(capability: resolution.capability)

        guard resolution.isExecutable else {
            state = .blocked
            commands = []
            return
        }

        let commands = Self.commands(for: resolution.intent)
        self.state = commands.isEmpty ? .noChanges : .executable
        self.commands = commands
    }

    private static func commands(for intent: CameraManualControlIntent) -> [Command] {
        var commands: [Command] = []

        if let exposure = intent.exposure {
            commands.append(.exposure(command(for: exposure)))
        }
        if let focus = intent.focus {
            commands.append(.focus(command(for: focus)))
        }
        if let whiteBalance = intent.whiteBalance {
            commands.append(.whiteBalance(command(for: whiteBalance)))
        }
        if let aperture = intent.aperture {
            commands.append(.aperture(command(for: aperture)))
        }
        if let zoomFactor = intent.zoomFactor {
            commands.append(.zoomFactor(zoomFactor))
        }

        return commands
    }

    private static func command(for exposure: CameraManualControlIntent.Exposure) -> Exposure {
        switch exposure {
        case .continuousAuto:
            .continuousAuto
        case .locked:
            .locked
        case .exposureBias(let value):
            .exposureBias(value)
        case .custom(let iso, let shutterDurationSeconds):
            .custom(iso: iso, shutterDurationSeconds: shutterDurationSeconds)
        }
    }

    private static func command(for focus: CameraManualControlIntent.Focus) -> Focus {
        switch focus {
        case .continuousAuto:
            .continuousAuto
        case .autoFocus(let pointOfInterest):
            .autoFocus(pointOfInterest: pointOfInterest.map {
                NormalizedPoint(x: $0.x, y: $0.y)
            })
        case .locked(let lensPosition):
            .locked(lensPosition: lensPosition)
        }
    }

    private static func command(for whiteBalance: CameraManualControlIntent.WhiteBalance) -> WhiteBalance {
        switch whiteBalance {
        case .continuousAuto:
            .continuousAuto
        case .locked:
            .locked
        case .deviceGains(let gains):
            .deviceGains(WhiteBalanceGains(red: gains.red, green: gains.green, blue: gains.blue))
        }
    }

    private static func command(for aperture: CameraManualControlIntent.Aperture) -> Aperture {
        switch aperture {
        case .value(let value):
            .value(value)
        }
    }
}
