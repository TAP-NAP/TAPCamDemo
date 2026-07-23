//
//  CameraManualControlReadbackSnapshot.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum CameraManualControlReadbackExposureMode: String, Equatable, Sendable {
    case continuousAuto
    case locked
    case custom
    case unknown
}

nonisolated enum CameraManualControlReadbackFocusMode: String, Equatable, Sendable {
    case continuousAuto
    case autoFocus
    case locked
    case unknown
}

nonisolated struct CameraManualControlReadbackSnapshot: Equatable, Sendable {
    let deviceID: String
    let controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
    let generation: Int
    let iso: Double
    let shutterDurationSeconds: Double
    let exposureTargetOffset: Double
    let exposureTargetBias: Double
    let lensPosition: Double
    let exposureMode: CameraManualControlReadbackExposureMode
    let focusMode: CameraManualControlReadbackFocusMode
    let isAdjustingExposure: Bool
    let isAdjustingFocus: Bool
    let reason: CameraManualControlReadbackReason

    var meterSample: CameraExposureMeterSample {
        CameraExposureMeterSample(
            deviceID: deviceID,
            controlSurfaceSignature: controlSurfaceSignature,
            generation: generation,
            iso: iso,
            shutterDurationSeconds: shutterDurationSeconds,
            exposureTargetOffset: exposureTargetOffset,
            exposureTargetBias: exposureTargetBias,
            isSettled: !isAdjustingExposure,
            reason: reason
        )
    }
}
