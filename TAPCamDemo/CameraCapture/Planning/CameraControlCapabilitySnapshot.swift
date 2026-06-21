//
//  CameraControlCapabilitySnapshot.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Read-only manual camera control capabilities for the active capture device.
///
/// This is not a control service and it does not mutate AVFoundation. It is the
/// value boundary future EV, ISO, shutter, focus, white-balance, and aperture UI
/// should read before calling a session-queue-safe control writer.
nonisolated struct CameraControlCapabilitySnapshot: Equatable, Sendable {
    nonisolated struct DoubleRange: Equatable, Sendable {
        let minimum: Double
        let maximum: Double

        var isAdjustable: Bool {
            maximum > minimum
        }
    }

    nonisolated struct Exposure: Equatable, Sendable {
        let supportsContinuousAutoExposure: Bool
        let supportsLockedExposure: Bool
        let supportsCustomExposure: Bool
        let exposureBiasRange: DoubleRange
        let isoRange: DoubleRange
        let shutterDurationRangeSeconds: DoubleRange

        var hasManualRange: Bool {
            supportsCustomExposure
                && isoRange.isAdjustable
                && shutterDurationRangeSeconds.isAdjustable
        }
    }

    nonisolated struct Focus: Equatable, Sendable {
        let supportsAutoFocus: Bool
        let supportsContinuousAutoFocus: Bool
        let supportsLockedFocus: Bool
        let supportsFocusPointOfInterest: Bool
        let supportsSmoothAutoFocus: Bool
    }

    nonisolated struct WhiteBalance: Equatable, Sendable {
        let supportsContinuousAutoWhiteBalance: Bool
        let supportsLockedWhiteBalance: Bool
        let maximumGain: Double
    }

    nonisolated struct Aperture: Equatable, Sendable {
        let fixedLensAperture: Double

        /// iOS camera aperture is treated as fixed until a future device/API
        /// exposes an adjustable aperture range.
        var isAdjustable: Bool {
            false
        }
    }

    nonisolated struct Zoom: Equatable, Sendable {
        let range: DoubleRange
    }

    let deviceID: String
    let deviceDisplayName: String
    let deviceTypeRawValue: String
    let exposure: Exposure
    let focus: Focus
    let whiteBalance: WhiteBalance
    let aperture: Aperture
    let zoom: Zoom

    var supportsAnyManualControl: Bool {
        exposure.exposureBiasRange.isAdjustable
            || exposure.hasManualRange
            || focus.supportsLockedFocus
            || whiteBalance.supportsLockedWhiteBalance
            || aperture.isAdjustable
            || zoom.range.isAdjustable
    }

    static func make(
        device: AVCaptureDevice,
        activeFormat: AVCaptureDevice.Format? = nil
    ) -> CameraControlCapabilitySnapshot {
        let format = activeFormat ?? device.activeFormat
        return CameraControlCapabilitySnapshot(
            deviceID: device.uniqueID,
            deviceDisplayName: device.localizedName,
            deviceTypeRawValue: device.deviceType.rawValue,
            exposure: Exposure(
                supportsContinuousAutoExposure: device.isExposureModeSupported(.continuousAutoExposure),
                supportsLockedExposure: device.isExposureModeSupported(.locked),
                supportsCustomExposure: device.isExposureModeSupported(.custom),
                exposureBiasRange: DoubleRange(
                    minimum: Double(device.minExposureTargetBias),
                    maximum: Double(device.maxExposureTargetBias)
                ),
                isoRange: DoubleRange(
                    minimum: Double(format.minISO),
                    maximum: Double(format.maxISO)
                ),
                shutterDurationRangeSeconds: DoubleRange(
                    minimum: finiteSeconds(format.minExposureDuration),
                    maximum: finiteSeconds(format.maxExposureDuration)
                )
            ),
            focus: Focus(
                supportsAutoFocus: device.isFocusModeSupported(.autoFocus),
                supportsContinuousAutoFocus: device.isFocusModeSupported(.continuousAutoFocus),
                supportsLockedFocus: device.isFocusModeSupported(.locked),
                supportsFocusPointOfInterest: device.isFocusPointOfInterestSupported,
                supportsSmoothAutoFocus: device.isSmoothAutoFocusSupported
            ),
            whiteBalance: WhiteBalance(
                supportsContinuousAutoWhiteBalance: device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance),
                supportsLockedWhiteBalance: device.isWhiteBalanceModeSupported(.locked),
                maximumGain: Double(device.maxWhiteBalanceGain)
            ),
            aperture: Aperture(fixedLensAperture: Double(device.lensAperture)),
            zoom: Zoom(
                range: DoubleRange(
                    minimum: Double(device.minAvailableVideoZoomFactor),
                    maximum: Double(device.maxAvailableVideoZoomFactor)
                )
            )
        )
    }

    private static func finiteSeconds(_ time: CMTime) -> Double {
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : 0
    }
}
