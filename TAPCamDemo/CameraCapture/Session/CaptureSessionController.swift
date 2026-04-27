//
//  CaptureSessionController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Foundation

/// Owns the managed SingleCam `AVCaptureSession` and its mutation queue.
///
/// This is the only production type that changes the AVFoundation session
/// graph. UI, the photo provider, packagers, and writers interact with it
/// through value requests and capture calls, keeping all format, depth-delivery,
/// and zoom mutation serialized on the session queue.
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
        let zoom = plan.zoom?.rawVideoZoomFactor ?? 1.0
        FOVDiagnostics.logSessionConfigurePhase(
            "start",
            plan: plan,
            session: session,
            photoOutput: photoOutput
        )
        if let reuseBlocker = currentGraphReuseBlocker(
            session: session,
            photoOutput: photoOutput,
            plan: plan
        ) {
            FOVDiagnostics.logSessionReuseDecision(
                reuse: false,
                reason: reuseBlocker,
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )
        } else {
            FOVDiagnostics.logSessionReuseDecision(
                reuse: true,
                reason: "sameDeviceFormatAndDepthState",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )

            /*
             FOV chips are usually just raw zoom choices on the same depth-capable
             virtual device and format. Reusing the current graph avoids a preview
             teardown where AVFoundation can briefly show the virtual device's wide
             baseline before the requested 77mm zoom is applied.
             */
            try applyZoom(zoom, to: plan.resolvedCaptureDevice, phase: "reuseZoomOnly")
            FOVDiagnostics.logSessionConfigurePhase(
                "reuseZoomOnly",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )
            return makeConfigurationResult(
                plan: plan,
                photoOutput: photoOutput,
                request: request
            )
        }

        session.beginConfiguration()
        do {
            FOVDiagnostics.logSessionConfigurePhase(
                "beginConfiguration",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )
            session.sessionPreset = .photo
            session.inputs.forEach { session.removeInput($0) }
            FOVDiagnostics.logSessionConfigurePhase(
                "inputsRemoved",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )

            try configureDeviceFormat(plan.resolvedCaptureDevice, selection: plan.formatSelection)
            FOVDiagnostics.logDeviceFormatApplied(
                device: plan.resolvedCaptureDevice,
                requestedFormat: plan.formatSelection?.videoFormat
            )

            /*
             Include the target raw zoom in the configuration transaction. When
             moving to or from the 77mm semantic FOV, some virtual cameras can
             briefly present their wide baseline during commit if zoom is only
             applied afterwards. We still re-apply after commit because several
             formats reset zoom during graph changes.
             */
            try applyZoom(zoom, to: plan.resolvedCaptureDevice, phase: "preCommit")

            let input = try AVCaptureDeviceInput(device: plan.resolvedCaptureDevice)
            guard session.canAddInput(input) else {
                throw TAPDepthCaptureError.unableToAddCameraInput
            }
            session.addInput(input)
            FOVDiagnostics.logSessionConfigurePhase(
                "inputAdded",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )

            if !session.outputs.contains(photoOutput) {
                guard session.canAddOutput(photoOutput) else {
                    throw TAPDepthCaptureError.unableToAddPhotoOutput
                }
                session.addOutput(photoOutput)
            }
            FOVDiagnostics.logSessionConfigurePhase(
                "outputReady",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )

            photoOutput.maxPhotoQualityPrioritization = .quality
            if plan.captureConfig.depthDataDeliveryEnabled && !photoOutput.isDepthDataDeliverySupported {
                throw TAPDepthCaptureError.depthDeliveryUnsupported
            }
            photoOutput.isDepthDataDeliveryEnabled = plan.captureConfig.depthDataDeliveryEnabled
            FOVDiagnostics.logSessionConfigurePhase(
                "beforeCommit",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )
            session.commitConfiguration()
            FOVDiagnostics.logSessionConfigurePhase(
                "afterCommit",
                plan: plan,
                session: session,
                photoOutput: photoOutput
            )
        } catch {
            session.commitConfiguration()
            throw error
        }

        /*
         Apply zoom after the session graph has committed and photo depth delivery
         is enabled. Some virtual depth devices accept a zoom value while the
         graph is being configured, then reset it during `commitConfiguration()`.
         Setting zoom on the committed device is what makes the preview FOV match
         the semantic capture plan. This matters when a label such as `48mm`
         resolves to raw zoom `4.0` on a depth-safe virtual-camera format instead
         of the familiar UI shorthand of `2x`.
         */
        try applyZoom(zoom, to: plan.resolvedCaptureDevice, phase: "postCommit")

        return makeConfigurationResult(
            plan: plan,
            photoOutput: photoOutput,
            request: request
        )
    }

    private static func currentGraphReuseBlocker(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        plan: CaptureSourcePlan
    ) -> String? {
        guard session.sessionPreset == .photo else {
            return "sessionPreset=\(session.sessionPreset.rawValue)"
        }

        let deviceInputs = session.inputs.compactMap { input in
            (input as? AVCaptureDeviceInput)?.device
        }
        guard deviceInputs.count == 1 else {
            return "inputCount=\(deviceInputs.count)"
        }

        let activeDevice = deviceInputs[0]
        guard activeDevice.uniqueID == plan.resolvedCaptureDevice.uniqueID else {
            return "deviceMismatch current=\(activeDevice.localizedName) requested=\(plan.resolvedCaptureDevice.localizedName)"
        }

        if let requestedFormat = plan.formatSelection?.videoFormat,
           !formatsRepresentSameDepthSafeVideoFormat(
            activeDevice.activeFormat,
            requestedFormat
           ) {
            return "formatMismatch"
        }

        guard session.outputs.contains(photoOutput) else {
            return "photoOutputMissing"
        }

        guard photoOutput.isDepthDataDeliveryEnabled == plan.captureConfig.depthDataDeliveryEnabled else {
            return "depthEnabledMismatch current=\(photoOutput.isDepthDataDeliveryEnabled) requested=\(plan.captureConfig.depthDataDeliveryEnabled)"
        }

        if plan.captureConfig.depthDataDeliveryEnabled && !photoOutput.isDepthDataDeliverySupported {
            return "depthUnsupported"
        }

        return nil
    }

    private static func formatsRepresentSameDepthSafeVideoFormat(
        _ activeFormat: AVCaptureDevice.Format,
        _ requestedFormat: AVCaptureDevice.Format
    ) -> Bool {
        if activeFormat === requestedFormat {
            return true
        }

        /*
         `AVCaptureDevice.activeFormat` can return an equivalent format object
         instead of the exact instance discovered by the capability layer. For
         FOV-only switches, requiring exact object, subtype, or range identity is
         too strict and forces a full input rebuild, which can make virtual
         devices flash their wide baseline before the target zoom is applied.

         The reusable graph check only needs to prove the active format has the
         same visual photo-depth signature. The selected raw zoom and depth-safe
         range were already validated by the capability layer, and the caller
         separately requires `AVCapturePhotoOutput` depth delivery to remain
         enabled and supported.
         */
        let activeDescription = activeFormat.formatDescription
        let requestedDescription = requestedFormat.formatDescription
        let activeDimensions = CMVideoFormatDescriptionGetDimensions(activeDescription)
        let requestedDimensions = CMVideoFormatDescriptionGetDimensions(requestedDescription)

        return activeDimensions.width == requestedDimensions.width
            && activeDimensions.height == requestedDimensions.height
            && abs(Double(activeFormat.videoFieldOfView - requestedFormat.videoFieldOfView)) < 0.01
            && abs(Double(activeFormat.videoMaxZoomFactor - requestedFormat.videoMaxZoomFactor)) < 0.01
    }

    private static func makeConfigurationResult(
        plan: CaptureSourcePlan,
        photoOutput: AVCapturePhotoOutput,
        request: SessionConfigurationRequest
    ) -> SessionConfigurationResult {
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
             SingleCam deliberately does not call `setActiveDepthDataFormat`.

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

    private static func applyZoom(_ zoomFactor: Double, to device: AVCaptureDevice, phase: String) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let clampedZoom = min(max(CGFloat(zoomFactor), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.videoZoomFactor = clampedZoom
        FOVDiagnostics.logAppliedZoom(
            phase: phase,
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
