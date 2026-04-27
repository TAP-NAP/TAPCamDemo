//
//  CaptureSessionController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Foundation

/// Owns the managed v0.8 `AVCaptureSession` and its mutation queue.
///
/// This is the only production type that changes the AVFoundation session
/// graph. UI, capture providers, hooks, packagers, and writers interact with it
/// through value requests and capture calls, which preserves the RPD boundary:
/// external extension points can produce data but cannot casually add/remove
/// session inputs or outputs on arbitrary threads.
nonisolated final class CaptureSessionController: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(label: "tapcam.camera-capture.singlecam.session")

    func configure(_ request: SessionConfigurationRequest) async throws -> SessionConfigurationResult {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [session, photoOutput] in
                do {
                    let result = try Self.configureSession(
                        session: session,
                        photoOutput: photoOutput,
                        request: request
                    )

                    if !session.isRunning {
                        session.startRunning()
                    }

                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func capturePhoto(
        settings: AVCapturePhotoSettings,
        delegate: AVCapturePhotoCaptureDelegate
    ) {
        sessionQueue.async { [photoOutput] in
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private static func configureSession(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        request: SessionConfigurationRequest
    ) throws -> SessionConfigurationResult {
        let plan = request.capturePlan
        let zoom = plan.zoom?.actualVideoZoomFactor ?? plan.zoom?.requestedZoomFactor ?? 1.0

        session.beginConfiguration()
        do {
            session.sessionPreset = .photo
            session.inputs.forEach { session.removeInput($0) }

            try configureDeviceFormat(plan.resolvedCaptureDevice, selection: plan.formatSelection)

            let input = try AVCaptureDeviceInput(device: plan.resolvedCaptureDevice)
            guard session.canAddInput(input) else {
                throw TAPDepthCaptureError.unableToAddCameraInput
            }
            session.addInput(input)

            if !session.outputs.contains(photoOutput) {
                guard session.canAddOutput(photoOutput) else {
                    throw TAPDepthCaptureError.unableToAddPhotoOutput
                }
                session.addOutput(photoOutput)
            }

            photoOutput.maxPhotoQualityPrioritization = .quality
            if plan.captureConfig.depthDataDeliveryEnabled && !photoOutput.isDepthDataDeliverySupported {
                throw TAPDepthCaptureError.depthDeliveryUnsupported
            }
            photoOutput.isDepthDataDeliveryEnabled = plan.captureConfig.depthDataDeliveryEnabled
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }

        /*
         Apply zoom after the session graph has committed and photo depth delivery
         is enabled. Some virtual depth devices accept a zoom value while the
         graph is being configured, then reset it during `commitConfiguration()`.
         Setting zoom on the committed device is what makes the preview FOV match
         the capture plan's 48mm/2x or 77mm/3x intent instead of visually staying
         at the native 24mm/1x view.
         */
        try applyZoom(zoom, to: plan.resolvedCaptureDevice)

        let focalLabel = plan.requestedFocalLengthLabel.label
        let nativePreviewAspectRatio = portraitPreviewAspectRatio(for: plan.resolvedCaptureDevice.activeFormat)

        return SessionConfigurationResult(
            depthDeliverySupported: plan.captureConfig.depthDataDeliveryEnabled && photoOutput.isDepthDataDeliverySupported,
            cameraDisplayName: "\(focalLabel) · \(plan.depthSource?.displayName ?? "No Depth")",
            nativePreviewAspectRatio: nativePreviewAspectRatio,
            capturePlan: plan,
            device: plan.resolvedCaptureDevice,
            selectionContext: request.selectionContext
        )
    }

    private static func configureDeviceFormat(
        _ device: AVCaptureDevice,
        selection: PhotoDepthFormatSelection?
    ) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if let selection {
            /*
             v0.8 deliberately does not call `setActiveDepthDataFormat`.

             Apple's still-photo depth path only requires a depth-capable camera
             input plus `AVCapturePhotoOutput.isDepthDataDeliveryEnabled`. The
             explicit `activeDepthDataFormat` setter is useful when an app needs a
             specific depth-vs-disparity pixel format, but it raises an uncaught
             Objective-C exception for some virtual-camera/format transitions even
             when the format was discovered earlier from `supportedDepthDataFormats`.

             Because an Obj-C exception bypasses Swift `throw`/`catch`, the safe
             release behavior is to configure the selected depth-capable video
             format, then let `AVCapturePhotoOutput.isDepthDataDeliverySupported`
             tell us whether Apple's photo-depth pipeline is valid for the current
             session. The manifest still records the requested format selection and
             the actual `device.activeDepthDataFormat` if AVFoundation exposes one.
             */
            device.activeFormat = selection.videoFormat
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

    private static func applyZoom(_ zoomFactor: Double, to device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let clampedZoom = min(max(CGFloat(zoomFactor), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.videoZoomFactor = clampedZoom
        FOVDiagnostics.logAppliedZoom(
            requestedZoom: zoomFactor,
            clampedZoom: clampedZoom,
            actualZoom: device.videoZoomFactor,
            device: device
        )
    }

    private static func portraitPreviewAspectRatio(for format: AVCaptureDevice.Format) -> Double {
        /*
         A camera preview should match the active capture format, not a UI guess
         such as "always 4:3" or "always 16:9". AVFoundation reports video
         formats in sensor/video orientation, usually landscape dimensions. The
         SwiftUI viewfinder is portrait, so this converts the active format into
         a width/height ratio with the shorter edge as the portrait width.

         Typical still-photo formats on iPhone resolve to 3:4 in portrait, but a
         16:9 active format will resolve to 9:16. Keeping this value tied to the
         configured format also keeps preview-crop metadata meaningful when the
         selected source changes.
         */
        let presentationSize = CMVideoFormatDescriptionGetPresentationDimensions(
            format.formatDescription,
            usePixelAspectRatio: true,
            useCleanAperture: true
        )
        let width = Double(presentationSize.width)
        let height = Double(presentationSize.height)
        guard width > 0, height > 0 else {
            return 3.0 / 4.0
        }

        return min(width, height) / max(width, height)
    }
}
