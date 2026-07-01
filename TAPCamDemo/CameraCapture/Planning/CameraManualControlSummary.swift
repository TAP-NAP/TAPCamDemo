//
//  CameraManualControlSummary.swift
//  TAPCamDemo
//

import Foundation

/// Public-safe field summary for future manual-control UI and persistence review.
///
/// This type is still Planning-only. It does not persist values, does not call
/// Runtime, does not import AVFoundation, and deliberately avoids raw device
/// identifiers or requested numeric values.
nonisolated struct CameraManualControlSummary: Equatable, Sendable {
    nonisolated struct Row: Equatable, Sendable {
        let kind: FieldKind
        let title: String
        let value: String
        let requestKind: RequestKind
        let state: State
        let reason: String?

        var isRequested: Bool {
            requestKind != .unchanged
        }

        var isExecutable: Bool {
            state != .blocked && state != .blockedRequested
        }
    }

    nonisolated enum FieldKind: CaseIterable, Equatable, Hashable, Sendable {
        case camera
        case exposure
        case focus
        case whiteBalance
        case aperture
        case zoom

        var title: String {
            switch self {
            case .camera:
                "Camera"
            case .exposure:
                "Exposure"
            case .focus:
                "Focus"
            case .whiteBalance:
                "White balance"
            case .aperture:
                "Aperture"
            case .zoom:
                "Zoom"
            }
        }
    }

    nonisolated enum State: Equatable, Sendable {
        case unchanged
        case requested
        case blocked
        case blockedRequested
    }

    nonisolated enum RequestKind: Equatable, Sendable {
        case unchanged
        case explicitAuto
        case manualRequested
    }

    let rows: [Row]

    init(resolution: CameraManualControlResolution) {
        let blockedKinds = Set(resolution.violations.map(Self.fieldKind(for:)))
        var rows: [Row] = []

        if blockedKinds.contains(.camera) {
            rows.append(Row(
                kind: .camera,
                title: FieldKind.camera.title,
                value: "Stale request",
                requestKind: .unchanged,
                state: .blocked,
                reason: "Request was made for another active camera."
            ))
        }

        rows.append(Self.row(
            kind: .exposure,
            request: Self.exposureRequest(for: resolution.intent.exposure),
            blockedKinds: blockedKinds
        ))
        rows.append(Self.row(
            kind: .focus,
            request: Self.focusRequest(for: resolution.intent.focus),
            blockedKinds: blockedKinds
        ))
        rows.append(Self.row(
            kind: .whiteBalance,
            request: Self.whiteBalanceRequest(for: resolution.intent.whiteBalance),
            blockedKinds: blockedKinds
        ))
        rows.append(Self.row(
            kind: .aperture,
            request: Self.apertureRequest(for: resolution.intent.aperture),
            blockedKinds: blockedKinds
        ))
        rows.append(Self.row(
            kind: .zoom,
            request: Self.zoomRequest(for: resolution.intent.zoomFactor),
            blockedKinds: blockedKinds
        ))

        self.rows = rows
    }

    private static func row(
        kind: FieldKind,
        request: RequestPresentation,
        blockedKinds: Set<FieldKind>
    ) -> Row {
        let isBlocked = blockedKinds.contains(kind)
        let isRequested = request.kind != .unchanged
        return Row(
            kind: kind,
            title: kind.title,
            value: request.value ?? "No change",
            requestKind: request.kind,
            state: state(isRequested: isRequested, isBlocked: isBlocked),
            reason: isBlocked ? blockedReason(for: kind) : nil
        )
    }

    private static func state(isRequested: Bool, isBlocked: Bool) -> State {
        switch (isRequested, isBlocked) {
        case (false, false):
            .unchanged
        case (true, false):
            .requested
        case (false, true):
            .blocked
        case (true, true):
            .blockedRequested
        }
    }

    private static func exposureRequest(for exposure: CameraManualControlIntent.Exposure?) -> RequestPresentation {
        switch exposure {
        case nil:
            .unchanged
        case .continuousAuto:
            .explicitAuto("Automatic exposure")
        case .locked:
            .manual("Locked exposure")
        case .exposureBias:
            .manual("EV bias")
        case .custom:
            .manual("Manual ISO and shutter")
        }
    }

    private static func focusRequest(for focus: CameraManualControlIntent.Focus?) -> RequestPresentation {
        switch focus {
        case nil:
            .unchanged
        case .continuousAuto:
            .explicitAuto("Continuous auto focus")
        case .autoFocus, .autoFocusOnly:
            .manual("Auto focus")
        case .locked:
            .manual("Locked focus")
        }
    }

    private static func whiteBalanceRequest(for whiteBalance: CameraManualControlIntent.WhiteBalance?) -> RequestPresentation {
        switch whiteBalance {
        case nil:
            .unchanged
        case .continuousAuto:
            .explicitAuto("Automatic white balance")
        case .locked:
            .manual("Locked white balance")
        case .deviceGains:
            .manual("Manual white balance")
        }
    }

    private static func apertureRequest(for aperture: CameraManualControlIntent.Aperture?) -> RequestPresentation {
        switch aperture {
        case nil:
            .unchanged
        case .value:
            .manual("Aperture request")
        }
    }

    private static func zoomRequest(for zoomFactor: Double?) -> RequestPresentation {
        zoomFactor == nil ? .unchanged : .manual("Zoom request")
    }

    private static func blockedReason(for kind: FieldKind) -> String {
        switch kind {
        case .camera:
            "Request was made for another active camera."
        case .exposure:
            "Exposure request is unsupported or outside the active camera range."
        case .focus:
            "Focus request is unsupported or outside the normalized focus area."
        case .whiteBalance:
            "White-balance request is unsupported or outside the active camera range."
        case .aperture:
            "Aperture request is unsupported on the active camera."
        case .zoom:
            "Zoom request is unsupported or outside depth-safe bounds."
        }
    }

    private static func fieldKind(for violation: CameraManualControlViolation) -> FieldKind {
        switch violation {
        case .targetDeviceMismatch:
            .camera
        case .continuousAutoExposureUnsupported,
             .lockedExposureUnsupported,
             .exposureBiasUnsupported,
             .exposureBiasOutOfRange,
             .customExposureUnsupported,
             .isoOutOfRange,
             .shutterDurationOutOfRange:
            .exposure
        case .continuousAutoFocusUnsupported,
             .autoFocusUnsupported,
             .lockedFocusUnsupported,
             .customLensPositionUnsupported,
             .focusPointUnsupported,
             .focusPointOutOfBounds,
             .lensPositionOutOfRange:
            .focus
        case .continuousAutoWhiteBalanceUnsupported,
             .lockedWhiteBalanceUnsupported,
             .whiteBalanceGainOutOfRange:
            .whiteBalance
        case .apertureValueNotFinite,
             .apertureAdjustmentUnsupported:
            .aperture
        case .zoomOutOfRange,
             .zoomOutsideDepthSafeRanges:
            .zoom
        }
    }

    private struct RequestPresentation: Equatable, Sendable {
        let kind: RequestKind
        let value: String?

        static let unchanged = RequestPresentation(kind: .unchanged, value: nil)

        static func explicitAuto(_ value: String) -> RequestPresentation {
            RequestPresentation(kind: .explicitAuto, value: value)
        }

        static func manual(_ value: String) -> RequestPresentation {
            RequestPresentation(kind: .manualRequested, value: value)
        }
    }
}
