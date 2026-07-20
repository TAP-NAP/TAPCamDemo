//
//  LockedCameraAppContextPublisher.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppIntents
import Foundation
import OSLog

nonisolated enum LockedCameraDiagnostics {
    static let logger = TAPCamLockedCameraDiagnostics.logger()
}

nonisolated struct LockedCameraAppContextPublisher: Sendable {
    static func publishCurrentContextIfAvailable() async {
        let context = makeContext()
        do {
            try await TAPCamLockedCameraIntent.updateAppContext(context)
            LockedCameraDiagnostics.logger.info(
                "locked_camera_context_published lensCount=\(context.lenses.count, privacy: .public) selectedLens=\(context.selectedLensID ?? "none", privacy: .public) unavailable=\(context.unavailableReason ?? "none", privacy: .public)"
            )
        } catch {
            LockedCameraDiagnostics.logger.error(
                "locked_camera_context_publish_failed error=\(describe(error), privacy: .public)"
            )
        }
    }

    static func makeContext(
        capabilityMatrix: CapabilityMatrix = CameraCapabilityResolver.discover(),
        generatedAt: Date = Date()
    ) -> TAPCamLockedCameraContext {
        let options = capabilityMatrix.focalLengthOptions().filter(\.isEnabled)
        let selectedOption = capabilityMatrix.defaultFocalLengthOption
            ?? options.first

        let lenses = options.map(Self.lensRecord(for:))
        let selectedLensID = selectedOption?.id
        let unavailableReason = lenses.isEmpty
            ? "No depth-capable lock-screen lens is available. Unlock to continue."
            : nil

        return TAPCamLockedCameraContext(
            generatedAt: generatedAt,
            defaults: TAPCamLockedCameraDefaults(
                outputFormat: CameraOutputFormatPreference.defaultValue.rawValue,
                photoQuality: CameraPhotoQualityPreference.defaultValue.rawValue,
                livePhotoEnabled: CameraLivePhotoPreferences.resolvedStartupIsEnabled(),
                flashMode: CameraFlashControlMode.resolvedStartupMode().rawValue
            ),
            selectedLensID: selectedLensID,
            lenses: lenses,
            unavailableReason: unavailableReason
        )
    }

    private static func lensRecord(for option: FocalLengthOption) -> TAPCamLockedCameraLensRecord {
        let captureDevice = option.depthSource?.resolvedDevice ?? option.rgbSource.device
        return TAPCamLockedCameraLensRecord(
            id: option.id,
            displayName: option.displayName,
            numericLabel: option.numericLabel,
            unitLabel: option.unitLabel,
            equivalentFocalLength35mmMillimeters: option.equivalentFocalLength35mmMillimeters,
            captureDeviceUniqueID: captureDevice.uniqueID,
            captureDeviceTypeRawValue: captureDevice.deviceType.rawValue,
            captureDevicePosition: captureDevice.position.tapLockedCameraRawValue,
            zoomFactor: option.zoom.requestedZoomFactor
        )
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }
}

private extension AVCaptureDevice.Position {
    nonisolated var tapLockedCameraRawValue: String {
        switch self {
        case .front:
            "front"
        case .back:
            "back"
        case .unspecified:
            "unspecified"
        @unknown default:
            "unspecified"
        }
    }
}
