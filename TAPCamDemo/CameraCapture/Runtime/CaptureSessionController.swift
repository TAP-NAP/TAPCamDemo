//
//  CaptureSessionController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import OSLog

nonisolated enum CaptureSessionFocusRuntimeEvent: Equatable, Sendable {
    case focusStarted
    case focusSettled
    case subjectAreaChanged
}

nonisolated enum CaptureSessionExposureRuntimeEvent: Equatable, Sendable {
    case exposureStarted
    case exposureSettled
}

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
    private var focusRuntimeEventHandler: (@Sendable (CaptureSessionFocusRuntimeEvent) -> Void)?
    private var exposureRuntimeEventHandler: (@Sendable (CaptureSessionExposureRuntimeEvent) -> Void)?
    private var subjectAreaChangeObserver: NSObjectProtocol?
    private var focusAdjustingObservation: NSKeyValueObservation?
    private var exposureAdjustingObservation: NSKeyValueObservation?

    init() {
        CameraControlService.registerSessionQueue(sessionQueue)
    }

    deinit {
        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
        }
        focusAdjustingObservation?.invalidate()
        exposureAdjustingObservation?.invalidate()
    }

    var isShutterSoundSuppressionSupported: Bool {
        photoOutput.isShutterSoundSuppressionSupported
    }

    func setFocusRuntimeEventHandler(
        _ handler: (@Sendable (CaptureSessionFocusRuntimeEvent) -> Void)?
    ) {
        sessionQueue.async { [weak self] in
            self?.focusRuntimeEventHandler = handler
        }
    }

    func setExposureRuntimeEventHandler(
        _ handler: (@Sendable (CaptureSessionExposureRuntimeEvent) -> Void)?
    ) {
        sessionQueue.async { [weak self] in
            self?.exposureRuntimeEventHandler = handler
        }
    }

    /// Applies a planned SingleCam photo-depth configuration.
    ///
    /// All AVFoundation graph mutation is serialized here. FOV-only changes can
    /// reuse the current graph and apply only raw zoom.
    ///
    /// - Tag: ConfigureSingleCamSession
    func configure(_ request: SessionConfigurationRequest) async throws -> SessionConfigurationResult {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self, session, photoOutput] in
                do {
                    let result = try Self.configureSession(
                        session: session,
                        photoOutput: photoOutput,
                        request: request
                    )
                    observeRuntimeEvents(for: result.device)

                    if !session.isRunning {
                        session.startRunning()
                    }

                    Self.prewarmPhotoOutput(photoOutput, resolvedOutput: result.resolvedOutput)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func observeRuntimeEvents(for device: AVCaptureDevice) {
        focusAdjustingObservation?.invalidate()
        focusAdjustingObservation = nil
        exposureAdjustingObservation?.invalidate()
        exposureAdjustingObservation = nil

        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
            self.subjectAreaChangeObserver = nil
        }

        subjectAreaChangeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: nil
        ) { [weak self] _ in
            self?.emitFocusRuntimeEvent(.subjectAreaChanged)
        }

        focusAdjustingObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
            guard let isAdjustingFocus = change.newValue else {
                return
            }
            self?.emitFocusRuntimeEvent(isAdjustingFocus ? .focusStarted : .focusSettled)
        }

        exposureAdjustingObservation = device.observe(\.isAdjustingExposure, options: [.new]) { [weak self] _, change in
            guard let isAdjustingExposure = change.newValue else {
                return
            }
            self?.emitExposureRuntimeEvent(isAdjustingExposure ? .exposureStarted : .exposureSettled)
        }
    }

    private func emitFocusRuntimeEvent(_ event: CaptureSessionFocusRuntimeEvent) {
        sessionQueue.async { [weak self] in
            self?.focusRuntimeEventHandler?(event)
        }
    }

    private func emitExposureRuntimeEvent(_ event: CaptureSessionExposureRuntimeEvent) {
        sessionQueue.async { [weak self] in
            self?.exposureRuntimeEventHandler?(event)
        }
    }

    func stop() {
        sessionQueue.async { [session, photoOutput] in
            guard session.isRunning else { return }
            photoOutput.setPreparedPhotoSettingsArray([], completionHandler: nil)
            session.stopRunning()
        }
    }

    func capturePhoto(
        settings: AVCapturePhotoSettings,
        delegate: AVCapturePhotoCaptureDelegate,
        videoRotationAngle: CGFloat?,
        isVideoMirrored: Bool
    ) {
        sessionQueue.async { [photoOutput] in
            if let connection = photoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isVideoMirrored
                }

                if let videoRotationAngle,
                   connection.isVideoRotationAngleSupported(videoRotationAngle) {
                    connection.videoRotationAngle = videoRotationAngle
                }
            }

            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func applyManualControlCommandPlan(
        _ plan: CameraManualControlCommandPlan,
        to device: AVCaptureDevice
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try CameraControlService.applyManualControlCommandPlan(plan, to: device)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func applyManualControlIntent(
        _ intent: CameraManualControlIntent,
        against capability: CameraControlCapabilitySnapshot,
        to device: AVCaptureDevice
    ) async throws -> CameraManualControlResolutionPresentation {
        let resolution = intent.resolved(against: capability)
        let presentation = CameraManualControlResolutionPresentation(resolution: resolution)
        guard resolution.isExecutable else {
            return presentation
        }

        try await applyManualControlCommandPlan(
            CameraManualControlCommandPlan(resolution: resolution),
            to: device
        )
        return presentation
    }

    func applyExposureTargetBias(_ exposureBias: Double, to device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try CameraControlService.applyExposureTargetBias(exposureBias, to: device)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    func readManualControlSnapshot(
        reason: CameraManualControlReadbackReason,
        generation: Int,
        from device: AVCaptureDevice
    ) async -> CameraManualControlReadbackSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                let capability = CameraControlCapabilitySnapshot.make(device: device)
                continuation.resume(returning: CameraManualControlReadbackSnapshot(
                    deviceID: device.uniqueID,
                    controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(capability: capability),
                    generation: generation,
                    iso: capability.exposure.currentISO,
                    shutterDurationSeconds: capability.exposure.currentShutterDurationSeconds,
                    exposureTargetOffset: capability.exposure.currentExposureTargetOffset,
                    exposureTargetBias: Double(device.exposureTargetBias),
                    lensPosition: capability.focus.currentLensPosition,
                    exposureMode: CameraManualControlReadbackExposureMode(device.exposureMode),
                    focusMode: CameraManualControlReadbackFocusMode(device.focusMode),
                    isAdjustingExposure: device.isAdjustingExposure,
                    isAdjustingFocus: device.isAdjustingFocus,
                    reason: reason
                ))
            }
        }
    }
    #endif

    func restoreAutoPhotoControls(
        globalExposureBias: Double,
        to device: AVCaptureDevice
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try CameraControlService.restoreAutoPhotoControls(
                        globalExposureBias: globalExposureBias,
                        to: device
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func configureSession(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        request: SessionConfigurationRequest
    ) throws -> SessionConfigurationResult {
        let plan = request.capturePlan
        let zoom = plan.zoom?.rawVideoZoomFactor ?? 1.0
        let resolvedOutput = try SingleCamPhotoSettingsFactory.resolvedOutput(
            photoOutput: photoOutput,
            activeFormat: targetActiveFormat(for: plan),
            assumesDepthDeliverySupported: true,
            outputProfile: request.outputProfile
        )
        try resolvedOutput.validateCapturePlanDepthConfiguration(
            depthDataDeliveryEnabled: plan.captureConfig.depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: plan.captureConfig.embedsDepthDataInPhoto
        )

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
            plan: plan,
            resolvedOutput: resolvedOutput
        ) {
            try CameraControlService.applyZoom(zoom, to: plan.resolvedCaptureDevice)
            let capabilities = CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: plan.resolvedCaptureDevice.activeFormat
            )
            logConfiguredOutput(resolvedOutput, capabilities: capabilities)
            return makeConfigurationResult(
                plan: plan,
                photoOutput: photoOutput,
                request: request,
                resolvedOutput: resolvedOutput
            )
        }

        try rebuildSessionGraph(
            session: session,
            photoOutput: photoOutput,
            plan: plan,
            resolvedOutput: resolvedOutput,
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
        try CameraControlService.applyZoom(zoom, to: plan.resolvedCaptureDevice)

        return makeConfigurationResult(
            plan: plan,
            photoOutput: photoOutput,
            request: request,
            resolvedOutput: resolvedOutput
        )
    }

    /// Rebuilds the AVFoundation graph for real source, format, or depth-state
    /// changes. FOV-only changes should take the fast path above instead.
    private static func rebuildSessionGraph(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        plan: CaptureSourcePlan,
        resolvedOutput: ResolvedCaptureOutputProfile,
        zoom: Double
    ) throws {
        session.beginConfiguration()
        do {
            session.sessionPreset = .photo
            session.inputs.forEach { session.removeInput($0) }

            try CameraControlService.configureBaselineControls(
                for: plan.resolvedCaptureDevice,
                formatSelection: plan.formatSelection
            )

            /*
             Include the target raw zoom in the configuration transaction. When
             moving to or from the 77mm semantic FOV, some virtual cameras can
             briefly present their wide baseline during commit if zoom is only
             applied afterwards. We still re-apply after commit because several
             formats reset zoom during graph changes.
             */
            try CameraControlService.applyZoom(zoom, to: plan.resolvedCaptureDevice)

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

            photoOutput.maxPhotoQualityPrioritization = resolvedOutput.maxPhotoQualityPrioritization
            if let maxPhotoDimensions = resolvedOutput.maxPhotoDimensions {
                photoOutput.maxPhotoDimensions = maxPhotoDimensions.cmVideoDimensions
            }
            let availableCapabilities = CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: plan.resolvedCaptureDevice.activeFormat
            )
            logAvailableOutput(resolvedOutput, capabilities: availableCapabilities)
            try resolvedOutput.validatePhotoOutputCapabilities(availableCapabilities)
            photoOutput.isDepthDataDeliveryEnabled = resolvedOutput.depthDataDeliveryEnabled
            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
            let configuredCapabilities = CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: plan.resolvedCaptureDevice.activeFormat
            )
            logConfiguredOutput(resolvedOutput, capabilities: configuredCapabilities)
            try resolvedOutput.validatePhotoOutputCapabilities(
                configuredCapabilities,
                requireConfiguredState: true
            )
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }
    }

    private static func logAvailableOutput(
        _ resolvedOutput: ResolvedCaptureOutputProfile,
        capabilities: CapturePhotoOutputCapabilitySnapshot
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("capture output capabilities profile=\(resolvedOutput.profileID, privacy: .public) container=\(resolvedOutput.fileContainer.rawValue, privacy: .public) fileType=\(resolvedOutput.processedFileType.rawValue, privacy: .public) codec=\(resolvedOutput.requestedCodec.rawValue, privacy: .public) selectedDimensions=\(dimensionsDescription(resolvedOutput.maxPhotoDimensions), privacy: .public) availableFileTypes=\(fileTypesDescription(capabilities), privacy: .public) availableCodecs=\(codecsDescription(capabilities), privacy: .public) supportedDimensions=\(dimensionsDescription(capabilities.supportedMaxPhotoDimensions), privacy: .public)")
        #endif
    }

    private static func logConfiguredOutput(
        _ resolvedOutput: ResolvedCaptureOutputProfile,
        capabilities: CapturePhotoOutputCapabilitySnapshot
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("capture output configured profile=\(resolvedOutput.profileID, privacy: .public) container=\(resolvedOutput.fileContainer.rawValue, privacy: .public) fileType=\(resolvedOutput.processedFileType.rawValue, privacy: .public) codec=\(resolvedOutput.requestedCodec.rawValue, privacy: .public) selectedDimensions=\(dimensionsDescription(resolvedOutput.maxPhotoDimensions), privacy: .public) configuredDimensions=\(dimensionsDescription(capabilities.configuredMaxPhotoDimensions), privacy: .public)")
        #endif
    }

    private static func fileTypesDescription(_ capabilities: CapturePhotoOutputCapabilitySnapshot) -> String {
        capabilities.availablePhotoFileTypeIdentifiers.sorted().joined(separator: "|")
    }

    private static func codecsDescription(_ capabilities: CapturePhotoOutputCapabilitySnapshot) -> String {
        capabilities.availablePhotoCodecTypes.map(\.rawValue).sorted().joined(separator: "|")
    }

    private static func dimensionsDescription(_ dimensions: [CapturePhotoDimensions]) -> String {
        dimensions.map(\.debugDescription).sorted().joined(separator: "|")
    }

    private static func dimensionsDescription(_ dimensions: CapturePhotoDimensions?) -> String {
        dimensions?.debugDescription ?? "none"
    }

    /// Returns true when the current SingleCam graph already represents the
    /// requested photo-depth pipeline and only the raw zoom factor needs to move.
    ///
    /// - Tag: ReuseSingleCamGraph
    private static func canReuseCurrentGraph(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        plan: CaptureSourcePlan,
        resolvedOutput: ResolvedCaptureOutputProfile
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

        guard photoOutput.isDepthDataDeliveryEnabled == resolvedOutput.depthDataDeliveryEnabled else {
            return false
        }

        if photoOutput.isLivePhotoCaptureSupported && !photoOutput.isLivePhotoCaptureEnabled {
            return false
        }

        guard (try? resolvedOutput.validatePhotoOutputCapabilities(
            CapturePhotoOutputCapabilitySnapshot(
                photoOutput: photoOutput,
                activeFormat: activeDevice.activeFormat
            ),
            requireConfiguredState: true
        )) != nil else {
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

    private static func targetActiveFormat(for plan: CaptureSourcePlan) -> AVCaptureDevice.Format {
        plan.formatSelection?.videoFormat ?? plan.resolvedCaptureDevice.activeFormat
    }

    private static func makeConfigurationResult(
        plan: CaptureSourcePlan,
        photoOutput: AVCapturePhotoOutput,
        request: SessionConfigurationRequest,
        resolvedOutput: ResolvedCaptureOutputProfile
    ) -> SessionConfigurationResult {
        let focalLabel = plan.requestedFocalLengthLabel.label
        let nativePreviewAspectRatio = portraitPreviewAspectRatio(for: plan.resolvedCaptureDevice.activeFormat)

        return SessionConfigurationResult(
            depthDeliverySupported: resolvedOutput.depthDataDeliveryEnabled && photoOutput.isDepthDataDeliverySupported,
            cameraDisplayName: "\(focalLabel) · \(plan.depthSource?.displayName ?? "No Depth")",
            nativePreviewAspectRatio: nativePreviewAspectRatio,
            capturePlan: plan,
            outputProfile: request.outputProfile,
            resolvedOutput: resolvedOutput,
            device: plan.resolvedCaptureDevice,
            controlCapabilities: CameraControlCapabilitySnapshot.make(device: plan.resolvedCaptureDevice),
            selectionContext: request.selectionContext
        )
    }

    private static func prewarmPhotoOutput(
        _ photoOutput: AVCapturePhotoOutput,
        resolvedOutput: ResolvedCaptureOutputProfile
    ) {
        let settings = SingleCamPhotoSettingsFactory.make(
            photoOutput: photoOutput,
            resolvedOutput: resolvedOutput
        )
        /*
         Prewarming is a latency hint, not a capture precondition. It does not
         need per-tap feedback preferences such as shutter sound suppression,
         and capture still proceeds normally if AVFoundation delays or declines
         preparation for the current photo-depth settings.
         */
        photoOutput.setPreparedPhotoSettingsArray([settings], completionHandler: nil)
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

#if TAP_ENABLE_PRO_CAMERA_CONTROLS
private extension CameraManualControlReadbackExposureMode {
    init(_ mode: AVCaptureDevice.ExposureMode) {
        switch mode {
        case .continuousAutoExposure, .autoExpose:
            self = .continuousAuto
        case .locked:
            self = .locked
        case .custom:
            self = .custom
        @unknown default:
            self = .unknown
        }
    }
}

private extension CameraManualControlReadbackFocusMode {
    init(_ mode: AVCaptureDevice.FocusMode) {
        switch mode {
        case .continuousAutoFocus:
            self = .continuousAuto
        case .autoFocus:
            self = .autoFocus
        case .locked:
            self = .locked
        @unknown default:
            self = .unknown
        }
    }
}
#endif
