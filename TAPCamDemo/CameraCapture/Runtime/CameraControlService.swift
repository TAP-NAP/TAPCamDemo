//
//  CameraControlService.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// Runtime boundary for AVFoundation device control writes.
///
/// `CaptureSessionController` owns the serial session queue. This service owns
/// the actual `AVCaptureDevice.lockForConfiguration()` write blocks that apply
/// baseline autofocus, virtual-device switching, raw zoom, and future
/// manual-control command plans. SwiftUI and planning code should never write
/// directly to `AVCaptureDevice`.
nonisolated enum CameraControlService {
    private static let sessionQueueKey = DispatchSpecificKey<UUID>()
    private static let sessionQueueValue = UUID()

    static func registerSessionQueue(_ queue: DispatchQueue) {
        queue.setSpecific(key: sessionQueueKey, value: sessionQueueValue)
    }

    static var isRunningOnRegisteredSessionQueue: Bool {
        DispatchQueue.getSpecific(key: sessionQueueKey) == sessionQueueValue
    }

    static func configureBaselineControls(
        for device: AVCaptureDevice,
        formatSelection: PhotoDepthFormatSelection?
    ) throws {
        try requireSessionQueueAccess()
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if let formatSelection {
            /*
             SingleCam deliberately does not call `setActiveDepthDataFormat`.

             Apple's still-photo depth path only requires a depth-capable camera
             input plus `AVCapturePhotoOutput.isDepthDataDeliveryEnabled`. The
             explicit `activeDepthDataFormat` setter is useful when an app needs
             a specific depth-vs-disparity pixel format, but it raises an
             Objective-C exception for some virtual-camera/format transitions
             even when the format was discovered earlier from
             `supportedDepthDataFormats`.

             Because an Obj-C exception bypasses Swift `throw`/`catch`, the safe
             release behavior is to configure the selected depth-capable video
             format, then let `AVCapturePhotoOutput.isDepthDataDeliverySupported`
             tell us whether Apple's photo-depth pipeline is valid for the
             current session.
             */
            device.activeFormat = formatSelection.videoFormat
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
            /*
             Debug zoom exploration needs AVFoundation to freely select the
             appropriate constituent device inside a virtual camera. Keeping the
             default/explicit `.auto` behavior avoids artificial restrictions
             that can make Dual Wide or Triple previews appear stuck at 1x.
             */
            device.setPrimaryConstituentDeviceSwitchingBehavior(
                .auto,
                restrictedSwitchingBehaviorConditions: []
            )
        }
    }

    static func applyZoom(_ zoomFactor: Double, to device: AVCaptureDevice) throws {
        try requireSessionQueueAccess()
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.videoZoomFactor = CGFloat(clampedZoomFactor(
            zoomFactor,
            minimum: Double(device.minAvailableVideoZoomFactor),
            maximum: Double(device.maxAvailableVideoZoomFactor)
        ))
    }

    static func applyManualControlCommandPlan(
        _ plan: CameraManualControlCommandPlan,
        to device: AVCaptureDevice
    ) throws {
        try requireSessionQueueAccess()
        try validateManualControlCommandPlan(
            plan,
            activeDeviceID: device.uniqueID,
            activeControlSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(
                capability: CameraControlCapabilitySnapshot.make(device: device)
            )
        )

        guard plan.requiresRuntimeWrite else {
            return
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        for command in plan.commands {
            try apply(command, to: device)
        }
    }

    static func validateManualControlCommandPlan(
        _ plan: CameraManualControlCommandPlan,
        activeDeviceID: String,
        activeControlSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
    ) throws {
        guard plan.state != .blocked else {
            throw TAPDepthCaptureError.cameraControlCommandPlanNotExecutable
        }
        guard plan.targetDeviceID == activeDeviceID else {
            throw TAPDepthCaptureError.cameraControlTargetDeviceChanged
        }
        guard plan.targetControlSignature == activeControlSignature else {
            throw TAPDepthCaptureError.cameraControlTargetSurfaceChanged
        }
        guard plan.commands.allSatisfy(\.isRuntimeSupported) else {
            throw TAPDepthCaptureError.cameraControlUnsupportedCommand
        }
    }

    static func clampedZoomFactor(
        _ zoomFactor: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        min(max(zoomFactor, minimum), maximum)
    }

    private static func apply(
        _ command: CameraManualControlCommandPlan.Command,
        to device: AVCaptureDevice
    ) throws {
        switch command {
        case .exposure(let exposure):
            apply(exposure, to: device)
        case .focus(let focus):
            apply(focus, to: device)
        case .whiteBalance(let whiteBalance):
            apply(whiteBalance, to: device)
        case .aperture:
            throw TAPDepthCaptureError.cameraControlCommandPlanNotExecutable
        case .zoomFactor(let zoomFactor):
            device.videoZoomFactor = CGFloat(clampedZoomFactor(
                zoomFactor,
                minimum: Double(device.minAvailableVideoZoomFactor),
                maximum: Double(device.maxAvailableVideoZoomFactor)
            ))
        }
    }

    private static func apply(
        _ exposure: CameraManualControlCommandPlan.Exposure,
        to device: AVCaptureDevice
    ) {
        switch exposure {
        case .continuousAuto:
            device.exposureMode = .continuousAutoExposure
        case .locked:
            device.exposureMode = .locked
        case .exposureBias(let value):
            device.setExposureTargetBias(Float(value), completionHandler: nil)
        case .custom(let iso, let shutterDurationSeconds):
            device.setExposureModeCustom(
                duration: CMTime(seconds: shutterDurationSeconds, preferredTimescale: 1_000_000),
                iso: Float(iso),
                completionHandler: nil
            )
        }
    }

    private static func apply(
        _ focus: CameraManualControlCommandPlan.Focus,
        to device: AVCaptureDevice
    ) {
        switch focus {
        case .continuousAuto:
            device.focusMode = .continuousAutoFocus
        case .autoFocus(let pointOfInterest):
            if let pointOfInterest {
                device.focusPointOfInterest = CGPoint(x: pointOfInterest.x, y: pointOfInterest.y)
            }
            device.focusMode = .autoFocus
        case .locked(let lensPosition):
            if let lensPosition {
                device.setFocusModeLocked(lensPosition: Float(lensPosition), completionHandler: nil)
            } else {
                device.focusMode = .locked
            }
        }
    }

    private static func apply(
        _ whiteBalance: CameraManualControlCommandPlan.WhiteBalance,
        to device: AVCaptureDevice
    ) {
        switch whiteBalance {
        case .continuousAuto:
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        case .locked:
            device.whiteBalanceMode = .locked
        case .deviceGains(let gains):
            device.setWhiteBalanceModeLocked(
                with: AVCaptureDevice.WhiteBalanceGains(
                    redGain: Float(gains.red),
                    greenGain: Float(gains.green),
                    blueGain: Float(gains.blue)
                ),
                completionHandler: nil
            )
        }
    }

    private static func requireSessionQueueAccess() throws {
        guard isRunningOnRegisteredSessionQueue else {
            assertionFailure("CameraControlService device writes must run on CaptureSessionController's session queue.")
            throw TAPDepthCaptureError.cameraControlOutsideSessionQueue
        }
    }
}
