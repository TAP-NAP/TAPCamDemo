//
//  CameraControlService.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

nonisolated enum CameraManualFocusLockTarget: Equatable, Sendable {
    case current
    case position(Double)
}

/// Thread-safe lifetime token for one logical MF context. It lets the session
/// queue reject a write that became stale while waiting behind configuration
/// work, before touching `AVCaptureDevice`.
nonisolated final class CameraManualFocusOperationToken: @unchecked Sendable {
    let id = UUID()

    private let lock = NSLock()
    private var valid = true
    private var invalidationHandlers: [UUID: @Sendable () -> Void] = [:]

    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }

    func invalidate() {
        let handlers: [@Sendable () -> Void]
        lock.lock()
        guard valid else {
            lock.unlock()
            return
        }
        valid = false
        handlers = Array(invalidationHandlers.values)
        invalidationHandlers.removeAll()
        lock.unlock()
        handlers.forEach { $0() }
    }

    @discardableResult
    func addInvalidationHandler(
        _ handler: @escaping @Sendable () -> Void
    ) -> UUID? {
        let handlerID = UUID()
        lock.lock()
        if valid {
            invalidationHandlers[handlerID] = handler
            lock.unlock()
            return handlerID
        }
        lock.unlock()
        handler()
        return nil
    }

    func removeInvalidationHandler(_ handlerID: UUID?) {
        guard let handlerID else {
            return
        }
        lock.lock()
        invalidationHandlers.removeValue(forKey: handlerID)
        lock.unlock()
    }
}

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
        device.isSubjectAreaChangeMonitoringEnabled = true

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

    static func applyActiveDepthDataFormat(
        _ depthFormat: AVCaptureDevice.Format?,
        to device: AVCaptureDevice
    ) throws {
        try requireSessionQueueAccess()
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeDepthDataFormat = depthFormat
    }

    static func applyExposureTargetBias(_ exposureBias: Double, to device: AVCaptureDevice) throws {
        try requireSessionQueueAccess()
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let clampedBias = clampedExposureBias(
            exposureBias,
            minimum: Double(device.minExposureTargetBias),
            maximum: Double(device.maxExposureTargetBias)
        )
        device.setExposureTargetBias(Float(clampedBias), completionHandler: nil)
    }

    static func restoreAutoPhotoControls(
        globalExposureBias: Double,
        to device: AVCaptureDevice
    ) throws {
        try requireSessionQueueAccess()
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        let clampedBias = clampedExposureBias(
            globalExposureBias,
            minimum: Double(device.minExposureTargetBias),
            maximum: Double(device.maxExposureTargetBias)
        )
        device.setExposureTargetBias(Float(clampedBias), completionHandler: nil)

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
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

    /// Starts one completion-observable MF operation. Unlike the generic
    /// command plan path, this boundary does not report success until
    /// AVFoundation associates the locked position with an applied video frame.
    static func setManualFocusLocked(
        _ target: CameraManualFocusLockTarget,
        on device: AVCaptureDevice,
        completionHandler: @escaping @Sendable (CMTime) -> Void
    ) throws {
        try requireSessionQueueAccess()
        guard device.isFocusModeSupported(.locked) else {
            throw TAPDepthCaptureError.cameraControlUnsupportedCommand
        }

        let lensPosition: Float
        switch target {
        case .current:
            lensPosition = AVCaptureDevice.currentLensPosition
        case .position(let value):
            guard device.isLockingFocusWithCustomLensPositionSupported else {
                throw TAPDepthCaptureError.cameraControlUnsupportedCommand
            }
            lensPosition = Float(min(max(value, 0), 1))
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.isSubjectAreaChangeMonitoringEnabled = false
        device.setFocusModeLocked(
            lensPosition: lensPosition,
            completionHandler: completionHandler
        )
    }

    /// Starts the one-shot, focus-only AF phase used by MF tap assist.
    ///
    /// Exposure state is intentionally untouched and subject-area monitoring
    /// remains disabled because the transaction will immediately return to a
    /// locked manual lens position.
    static func startManualFocusTapAssistAutoFocus(
        at point: CameraManualControlIntent.NormalizedPoint,
        on device: AVCaptureDevice
    ) throws {
        try requireSessionQueueAccess()
        guard point.isInsideUnitRect,
              device.isFocusModeSupported(.autoFocus),
              device.isFocusPointOfInterestSupported else {
            throw TAPDepthCaptureError.cameraControlUnsupportedCommand
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.isSubjectAreaChangeMonitoringEnabled = false
        device.focusPointOfInterest = CGPoint(x: point.x, y: point.y)
        device.focusMode = .autoFocus
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

    static func clampedExposureBias(
        _ exposureBias: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        min(max(exposureBias, minimum), maximum)
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
            device.isSubjectAreaChangeMonitoringEnabled = true
        case .autoFocus(let pointOfInterest):
            if let pointOfInterest {
                let point = CGPoint(x: pointOfInterest.x, y: pointOfInterest.y)
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
            }
            device.focusMode = .autoFocus
            device.isSubjectAreaChangeMonitoringEnabled = true
        case .autoFocusOnly(let pointOfInterest):
            if let pointOfInterest, device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: pointOfInterest.x, y: pointOfInterest.y)
            }
            device.focusMode = .autoFocus
            device.isSubjectAreaChangeMonitoringEnabled = true
        case .locked(let lensPosition):
            device.isSubjectAreaChangeMonitoringEnabled = false
            if let lensPosition {
                device.setFocusModeLocked(lensPosition: Float(lensPosition), completionHandler: nil)
            } else {
                // Entering MF must preserve the lens position produced by AF.
                // Apple's current-position sentinel avoids turning the mode
                // switch itself into a custom lens movement.
                device.setFocusModeLocked(
                    lensPosition: AVCaptureDevice.currentLensPosition,
                    completionHandler: nil
                )
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
