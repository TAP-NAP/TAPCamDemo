//
//  CaptureSessionController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
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

    /// Applies a planned SingleCam photo-depth configuration.
    ///
    /// All AVFoundation graph mutation is serialized here. FOV-only changes can
    /// reuse the current graph and apply only raw zoom.
    ///
    /// - Tag: ConfigureSingleCamSession
    func configure(_ request: SessionConfigurationRequest) async throws -> SessionConfigurationResult {
        try await withCheckedThrowingContinuation { continuation in
            StartupTrace.mark("CaptureSessionController.configure enqueue")
            sessionQueue.async { [session, photoOutput] in
                StartupTrace.mark("CaptureSessionController.configure sessionQueue begin")
                do {
                    let result = try StartupTrace.measure("CaptureSessionController.configureSession") {
                        try Self.configureSession(
                            session: session,
                            photoOutput: photoOutput,
                            request: request
                        )
                    }

                    if !session.isRunning {
                        StartupTrace.mark("AVCaptureSession.startRunning begin")
                        session.startRunning()
                        StartupTrace.mark("AVCaptureSession.startRunning end")
                    }

                    StartupTrace.measure("AVCapturePhotoOutput.prewarm") {
                        Self.prewarmPhotoOutput(photoOutput)
                    }
                    StartupTrace.mark("CaptureSessionController.configure sessionQueue end")
                    continuation.resume(returning: result)
                } catch {
                    StartupTrace.mark("CaptureSessionController.configure failed \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        StartupTrace.mark("CaptureSessionController.stop enqueue")
        sessionQueue.async { [session, photoOutput] in
            guard session.isRunning else { return }
            StartupTrace.mark("AVCaptureSession.stopRunning begin")
            photoOutput.setPreparedPhotoSettingsArray([], completionHandler: nil)
            session.stopRunning()
            StartupTrace.mark("AVCaptureSession.stopRunning end")
        }
    }

    func capturePhoto(
        settings: AVCapturePhotoSettings,
        delegate: AVCapturePhotoCaptureDelegate,
        videoRotationAngle: CGFloat?
    ) {
        sessionQueue.async { [photoOutput] in
            if let videoRotationAngle,
               let connection = photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(videoRotationAngle) {
                connection.videoRotationAngle = videoRotationAngle
            }

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

        /*
         Release FOV chips such as 24mm, 48mm, and 77mm usually resolve to raw
         `videoZoomFactor` values on the same Apple-paired photo-depth graph.
         When the active graph already matches the requested device, format, and
         depth state, changing only zoom keeps the preview continuous and avoids
         an input teardown that can briefly show the virtual camera's wide
         baseline.
         */
        if canReuseCurrentGraph(
            session: session,
            photoOutput: photoOutput,
            plan: plan
        ) {
            try applyZoom(zoom, to: plan.resolvedCaptureDevice)
            return makeConfigurationResult(
                plan: plan,
                photoOutput: photoOutput,
                request: request
            )
        }

        try rebuildSessionGraph(
            session: session,
            photoOutput: photoOutput,
            plan: plan,
            zoom: zoom
        )

        /*
         Apply zoom after the session graph has committed and photo depth delivery
         is enabled. Some virtual depth devices accept a zoom value while the
         graph is being configured, then reset it during `commitConfiguration()`.
         Setting zoom on the committed device is what makes the preview FOV match
         the semantic capture plan. This matters when a label such as `48mm`
         resolves to raw zoom `4.0` on a depth-safe virtual-camera format instead
         of the familiar UI shorthand of `2x`.
         */
        try applyZoom(zoom, to: plan.resolvedCaptureDevice)

        return makeConfigurationResult(
            plan: plan,
            photoOutput: photoOutput,
            request: request
        )
    }

    /// Rebuilds the AVFoundation graph for real source, format, or depth-state
    /// changes. FOV-only changes should take the fast path above instead.
    private static func rebuildSessionGraph(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        plan: CaptureSourcePlan,
        zoom: Double
    ) throws {
        session.beginConfiguration()
        do {
            session.sessionPreset = .photo
            session.inputs.forEach { session.removeInput($0) }

            try configureDeviceFormat(plan.resolvedCaptureDevice, selection: plan.formatSelection)

            /*
             Include the target raw zoom in the configuration transaction. When
             moving to or from the 77mm semantic FOV, some virtual cameras can
             briefly present their wide baseline during commit if zoom is only
             applied afterwards. We still re-apply after commit because several
             formats reset zoom during graph changes.
             */
            try applyZoom(zoom, to: plan.resolvedCaptureDevice)

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
    }

    /// Returns true when the current SingleCam graph already represents the
    /// requested photo-depth pipeline and only the raw zoom factor needs to move.
    ///
    /// - Tag: ReuseSingleCamGraph
    private static func canReuseCurrentGraph(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        plan: CaptureSourcePlan
    ) -> Bool {
        guard session.sessionPreset == .photo else {
            return false
        }

        let deviceInputs = session.inputs.compactMap { input in
            (input as? AVCaptureDeviceInput)?.device
        }
        guard deviceInputs.count == 1 else {
            return false
        }

        let activeDevice = deviceInputs[0]
        guard activeDevice.uniqueID == plan.resolvedCaptureDevice.uniqueID else {
            return false
        }

        if let requestedFormat = plan.formatSelection?.videoFormat,
           !formatsHaveSamePhotoDepthPreviewSignature(
            activeDevice.activeFormat,
            requestedFormat
           ) {
            return false
        }

        guard session.outputs.contains(photoOutput) else {
            return false
        }

        guard photoOutput.isDepthDataDeliveryEnabled == plan.captureConfig.depthDataDeliveryEnabled else {
            return false
        }

        if plan.captureConfig.depthDataDeliveryEnabled && !photoOutput.isDepthDataDeliverySupported {
            return false
        }

        return true
    }

    private static func formatsHaveSamePhotoDepthPreviewSignature(
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

    private static func prewarmPhotoOutput(_ photoOutput: AVCapturePhotoOutput) {
        let settings = SingleCamPhotoSettingsFactory.make(photoOutput: photoOutput)
        /*
         Prewarming is a latency hint, not a capture precondition. Capture still
         proceeds normally if AVFoundation delays or declines resource
         preparation for the current photo-depth settings.
         */
        photoOutput.setPreparedPhotoSettingsArray([settings], completionHandler: nil)
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

    private static func applyZoom(_ zoomFactor: Double, to device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let clampedZoom = min(max(CGFloat(zoomFactor), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.videoZoomFactor = clampedZoom
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
