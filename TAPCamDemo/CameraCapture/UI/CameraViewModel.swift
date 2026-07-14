//
//  CameraViewModel.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Combine
import Foundation
import OSLog
import Photos
import UIKit

/// Observable state for the SingleCam photo-depth screen.
///
/// This view model is the UI boundary for
/// `FOV/debug selection -> CapabilityMatrix -> CaptureSourcePlan ->
/// CaptureSessionController -> CapturePipeline`. SwiftUI reads profiles and
/// status values from here; it never inspects `AVCaptureDevice` directly.
@MainActor
final class CameraViewModel: ObservableObject {
    let sessionController: CaptureSessionController

    @Published var focalLengthOptions: [FocalLengthOption]
    @Published var selectedFocalLengthOptionID: String?
    @Published var selectedRGBSourceID: String?
    @Published var selectedZoomID: String?
    @Published var activeCameraDisplayName = "Preparing camera..."
    @Published var statusMessage = "Preparing capture session..."
    @Published var pendingJobCount = 0
    @Published var recentMetrics: [CaptureJobMetrics] = []
    @Published var isDepthCaptureReady = false
    @Published var isConfiguringSession = false
    @Published var isPausedForAnalysis = false
    @Published var nativePreviewAspectRatio = 3.0 / 4.0
    @Published var previewCropRectNormalized = CropRectNormalized.fullFrame
    @Published var recentThumbnail: UIImage?
    @Published var latestCaptureDepthHint: CameraCaptureDepthHint?
    @Published var focusRuntimeEvent: CameraFocusRuntimeEvent?
    @Published var exposureRuntimeEvent: CameraExposureRuntimeEvent?
    @Published var isVideoRecording = false
    @Published var isPreparingVideoMode = false
    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    @Published var latestManualControlReadback: CameraManualControlReadbackSnapshot?
    #endif
    #if DEBUG
    @Published var debugDepthDeviceOptions: [DebugDepthDeviceOption]
    @Published var debugSelectedDepthDeviceID: String?
    @Published var debugZoomProfiles: [ZoomProfile] = []
    @Published var debugZoomCapability: ZoomCapability?
    @Published var debugSelectedZoomID: String?
    @Published var debugSelectedZoomFactor: Double = 1.0
    @Published var debugFOVLabel = "24mm"
    @Published var isDebugDepthOverrideActive = false
    #endif

    let capabilityMatrix: CapabilityMatrix
    let locationProvider = LocationProvider()
    let jobQueue = CaptureJobQueue()
    let metricsStore = MetricsStore()
    let pendingCaptureStore: TAPPendingCaptureStore
    let pendingCaptureProcessor: TAPPendingCaptureProcessor
    let pipeline: CapturePipeline
    var activeSessionConfiguration: SessionConfigurationResult?
    var configurationGeneration = 0
    var depthSelectionMode: DepthSelectionMode = .automatic
    var requestedGlobalAutoExposureBias = CameraEVPreferences.defaultGlobalBias
    var activeVideoRecordingCaptureID: String?
    var videoRecordingTemporaryDirectoryURL: URL?
    var videoDurationLimitTask: Task<Void, Never>?
    var videoThermalObserver: NSObjectProtocol?
    var recentLibraryPreviewRefreshTask: Task<Void, Never>?

    var session: AVCaptureSession {
        sessionController.session
    }

    var isShutterSoundSuppressionSupported: Bool {
        sessionController.isShutterSoundSuppressionSupported
    }

    var canCapture: Bool {
        !isPausedForAnalysis
            && isDepthCaptureReady
            && pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs
    }

    var canUseVideoShutter: Bool {
        isVideoRecording
            || (!isPreparingVideoMode
                && !isPausedForAnalysis
                && activeSessionConfiguration != nil
                && pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs)
    }

    var isCaptureWriteInProgress: Bool {
        pendingJobCount > 0
    }

    var isBusyForNonCaptureStartupWork: Bool {
        isConfiguringSession || isVideoRecording || isPreparingVideoMode || isPausedForAnalysis
    }

    var shouldShowFocalLengthSelector: Bool {
        guard let selectedSource = capabilityMatrix.rgbSource(id: selectedRGBSourceID) else {
            return false
        }
        return selectedSource.device.position == .back && !focalLengthOptions.isEmpty
    }

    /// The FOV chip that should look active in the release selector.
    ///
    /// Debug depth override is intentionally modeled as another lens selection
    /// surface. Once a debug depth-capable device is selected, the Release FOV
    /// selector remains available as a way back to the normal path, but it no
    /// longer claims one of its chips is the active lens.
    var activeFocalLengthOptionID: String? {
        #if DEBUG
        if isDebugDepthOverrideActive {
            return nil
        }
        #endif
        return selectedFocalLengthOptionID
    }

    var activeControlCapabilities: CameraControlCapabilitySnapshot? {
        activeSessionConfiguration?.controlCapabilities
    }

    var isManualFocusControlAvailable: Bool {
        guard let activeSessionConfiguration else {
            return false
        }
        return activeSessionConfiguration.device.position != .front
            && activeSessionConfiguration.controlCapabilities.focus.supportsManualLensPosition
    }

    var isFlashAvailable: Bool {
        sessionController.photoOutput.supportedFlashModes.contains(.auto)
            || sessionController.photoOutput.supportedFlashModes.contains(.on)
    }

    var isLivePhotoCaptureSupported: Bool {
        sessionController.photoOutput.isLivePhotoCaptureSupported
    }

    init(
        capabilityMatrix: CapabilityMatrix = CameraCapabilityResolver.discover(),
        sessionController: CaptureSessionController = CaptureSessionController(),
        pendingCaptureStore: TAPPendingCaptureStore = .shared,
        pendingCaptureProcessor: TAPPendingCaptureProcessor = .shared
    ) {
        self.capabilityMatrix = capabilityMatrix
        self.sessionController = sessionController
        self.pendingCaptureStore = pendingCaptureStore
        self.pendingCaptureProcessor = pendingCaptureProcessor
        self.focalLengthOptions = capabilityMatrix.focalLengthOptions()
        #if DEBUG
        self.debugDepthDeviceOptions = capabilityMatrix.debugDepthDeviceOptions()
        #endif

        let provider = AVFoundationSingleCamPhotoProvider(sessionController: sessionController)
        self.pipeline = CapturePipeline(
            photoDepthProvider: provider,
            writer: TAPPendingCaptureArtifactWriter(store: pendingCaptureStore),
            metricsStore: metricsStore
        )
        sessionController.setFocusRuntimeEventHandler { [weak self] event in
            Task { @MainActor [weak self, event] in
                self?.focusRuntimeEvent = CameraFocusRuntimeEvent(
                    kind: CameraFocusRuntimeEvent.Kind(captureSessionEvent: event)
                )
            }
        }
        sessionController.setExposureRuntimeEventHandler { [weak self] event in
            Task { @MainActor [weak self, event] in
                self?.exposureRuntimeEvent = CameraExposureRuntimeEvent(
                    kind: CameraExposureRuntimeEvent.Kind(captureSessionEvent: event)
                )
            }
        }
    }

    func start() async {
        LockedCameraDiagnostics.logger.notice(
            "r4b_main_camera_start_begin running=\(self.sessionController.session.isRunning) paused=\(self.isPausedForAnalysis) authorization=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"
        )
        defer {
            LockedCameraDiagnostics.logger.notice(
                "r4b_main_camera_start_finish running=\(self.sessionController.session.isRunning) paused=\(self.isPausedForAnalysis) configuring=\(self.isConfiguringSession)"
            )
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await configureDefaultSelection()
            if CameraCaptureDataUsePreferences.usesLocationData() {
                locationProvider.warmLocationCache()
            }
            scheduleRecentTAPLibraryPreviewRefresh()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureDefaultSelection()
                if CameraCaptureDataUsePreferences.usesLocationData() {
                    locationProvider.warmLocationCache()
                }
                scheduleRecentTAPLibraryPreviewRefresh()
            } else {
                statusMessage = CameraCaptureStatusPresentation.message(
                    for: TAPDepthCaptureError.cameraAccessDenied,
                    context: .configuration
                )
            }
        case .denied, .restricted:
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraAccessDenied,
                context: .configuration
            )
        @unknown default:
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraAccessDenied,
                context: .configuration
            )
        }
    }

    func stop() {
        LockedCameraDiagnostics.logger.notice(
            "r4b_main_camera_stop_requested running=\(self.sessionController.session.isRunning) paused=\(self.isPausedForAnalysis)"
        )
        recentLibraryPreviewRefreshTask?.cancel()
        recentLibraryPreviewRefreshTask = nil
        isConfiguringSession = false
        isPausedForAnalysis = false
        isPreparingVideoMode = false
        sessionController.stop()
    }

    func pauseForAnalysis() {
        LockedCameraDiagnostics.logger.notice(
            "r4b_main_camera_pause_requested running=\(self.sessionController.session.isRunning) paused=\(self.isPausedForAnalysis)"
        )
        recentLibraryPreviewRefreshTask?.cancel()
        recentLibraryPreviewRefreshTask = nil
        configurationGeneration += 1
        isConfiguringSession = false
        isPreparingVideoMode = false
        isPausedForAnalysis = true
        isDepthCaptureReady = false
        activeSessionConfiguration = nil
        statusMessage = "Camera paused for analysis."
        sessionController.stop()
    }

    func resumeAfterAnalysis() async {
        guard isPausedForAnalysis else {
            return
        }

        isPausedForAnalysis = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            if selectedRGBSourceID == nil {
                await configureDefaultSelection()
            } else {
                await configureCurrentSelection()
            }
            if CameraCaptureDataUsePreferences.usesLocationData() {
                locationProvider.warmLocationCache()
            }
            scheduleRecentTAPLibraryPreviewRefresh()
        case .notDetermined:
            await start()
        case .denied, .restricted:
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraAccessDenied,
                context: .configuration
            )
        @unknown default:
            statusMessage = CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraAccessDenied,
                context: .configuration
            )
        }
    }

    func updatePreviewCropRect(_ rect: CropRectNormalized) {
        guard previewCropRectNormalized != rect else { return }
        previewCropRectNormalized = rect
    }

    func setGlobalAutoExposureBias(
        _ exposureBias: Double,
        effectiveExposureBias: Double? = nil
    ) async {
        requestedGlobalAutoExposureBias = CameraEVPreferences.clampedBias(exposureBias)
        await applyEffectiveAutoExposureBiasToActiveConfiguration(
            effectiveExposureBias ?? requestedGlobalAutoExposureBias
        )
    }

    func restoreAutoCameraControls(globalExposureBias: Double) async {
        requestedGlobalAutoExposureBias = CameraEVPreferences.clampedBias(globalExposureBias)
        guard let activeSessionConfiguration else {
            return
        }

        do {
            try await sessionController.restoreAutoPhotoControls(
                globalExposureBias: requestedGlobalAutoExposureBias,
                to: activeSessionConfiguration.device
            )
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
    }

    func applyRequestedGlobalAutoExposureBiasToActiveConfiguration() async {
        await applyEffectiveAutoExposureBiasToActiveConfiguration(requestedGlobalAutoExposureBias)
    }

    func applyEffectiveAutoExposureBiasToActiveConfiguration(_ exposureBias: Double) async {
        guard let activeSessionConfiguration else {
            return
        }

        let effectiveExposureBias = CameraEVPreferences.clampedBias(exposureBias)
        #if TAP_ENABLE_PRO_CAMERA_CONTROLS
        let intent = CameraManualControlIntent(
            targetDeviceID: activeSessionConfiguration.controlCapabilities.deviceID,
            exposure: .exposureBias(effectiveExposureBias),
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
        do {
            let presentation = try await sessionController.applyManualControlIntent(
                intent,
                against: activeSessionConfiguration.controlCapabilities,
                to: activeSessionConfiguration.device
            )
            if presentation.status == .blocked {
                statusMessage = "\(presentation.title) · \(presentation.detail)"
            }
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
        #else
        do {
            try await sessionController.applyExposureTargetBias(
                effectiveExposureBias,
                to: activeSessionConfiguration.device
            )
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
        #endif
    }

    func focusAtPreviewPoint(
        _ point: CameraPreviewFocusPoint,
        globalExposureBias: Double
    ) async {
        requestedGlobalAutoExposureBias = CameraEVPreferences.clampedBias(globalExposureBias)
        guard let activeSessionConfiguration else {
            return
        }

        let intentPoint = CameraManualControlIntent.NormalizedPoint(x: point.x, y: point.y)
        let intent = CameraManualControlIntent(
            targetDeviceID: activeSessionConfiguration.controlCapabilities.deviceID,
            exposure: nil,
            focus: .autoFocus(pointOfInterest: intentPoint),
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )

        do {
            let presentation = try await sessionController.applyManualControlIntent(
                intent,
                against: activeSessionConfiguration.controlCapabilities,
                to: activeSessionConfiguration.device
            )
            if presentation.status == .blocked {
                statusMessage = "\(presentation.title) · \(presentation.detail)"
            } else {
                await applyEffectiveAutoExposureBiasToActiveConfiguration(requestedGlobalAutoExposureBias)
            }
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
    }

    func focusOnlyAtPreviewPoint(_ point: CameraPreviewFocusPoint) async {
        guard let activeSessionConfiguration else {
            return
        }

        let intentPoint = CameraManualControlIntent.NormalizedPoint(x: point.x, y: point.y)
        let intent = CameraManualControlIntent(
            targetDeviceID: activeSessionConfiguration.controlCapabilities.deviceID,
            exposure: nil,
            focus: .autoFocusOnly(pointOfInterest: intentPoint),
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )

        await applyCameraControlIntent(
            intent,
            against: activeSessionConfiguration.controlCapabilities,
            to: activeSessionConfiguration.device
        )
    }

    func lockFocusAndExposure() async {
        await lockFocusAndExposure(at: nil)
    }

    func lockFocusAndExposure(at point: CameraPreviewFocusPoint) async {
        await lockFocusAndExposure(at: CameraManualControlIntent.NormalizedPoint(x: point.x, y: point.y))
    }

    private func lockFocusAndExposure(
        at point: CameraManualControlIntent.NormalizedPoint?
    ) async {
        guard let activeSessionConfiguration else {
            return
        }

        if let point {
            let pointIntent = CameraManualControlIntent(
                targetDeviceID: activeSessionConfiguration.controlCapabilities.deviceID,
                exposure: nil,
                focus: .autoFocus(pointOfInterest: point),
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            )

            do {
                let presentation = try await sessionController.applyManualControlIntent(
                    pointIntent,
                    against: activeSessionConfiguration.controlCapabilities,
                    to: activeSessionConfiguration.device
                )
                if presentation.status == .blocked {
                    statusMessage = "\(presentation.title) · \(presentation.detail)"
                }
            } catch {
                statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
            }
        }

        let intent = CameraManualControlIntent(
            targetDeviceID: activeSessionConfiguration.controlCapabilities.deviceID,
            exposure: .locked,
            focus: .locked(lensPosition: nil),
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )

        do {
            let presentation = try await sessionController.applyManualControlIntent(
                intent,
                against: activeSessionConfiguration.controlCapabilities,
                to: activeSessionConfiguration.device
            )
            if presentation.status == .blocked {
                statusMessage = "\(presentation.title) · \(presentation.detail)"
            }
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
    }

    func restoreAutoExposure(globalExposureBias: Double) async {
        requestedGlobalAutoExposureBias = CameraEVPreferences.clampedBias(globalExposureBias)
        guard let activeSessionConfiguration else {
            return
        }

        let capability = activeSessionConfiguration.controlCapabilities
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .continuousAuto,
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
        await applyCameraControlIntent(intent, against: capability, to: activeSessionConfiguration.device)
        await applyEffectiveAutoExposureBiasToActiveConfiguration(requestedGlobalAutoExposureBias)
    }

    func applyCustomExposure(
        iso: Double,
        shutterDurationSeconds: Double
    ) async {
        guard let activeSessionConfiguration else {
            return
        }

        let capability = activeSessionConfiguration.controlCapabilities
        guard capability.exposure.hasManualRange else {
            statusMessage = "Manual exposure unavailable"
            return
        }

        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .custom(
                iso: Self.clamped(iso, in: capability.exposure.isoRange),
                shutterDurationSeconds: Self.clamped(
                    shutterDurationSeconds,
                    in: capability.exposure.shutterDurationRangeSeconds
                )
            ),
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
        await applyCameraControlIntent(intent, against: capability, to: activeSessionConfiguration.device)
    }

    func applyManualFocus(lensPosition: Double) async {
        guard let activeSessionConfiguration else {
            return
        }

        let capability = activeSessionConfiguration.controlCapabilities
        guard activeSessionConfiguration.device.position != .front,
              capability.focus.supportsManualLensPosition else {
            statusMessage = "Manual focus unavailable"
            return
        }

        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: nil,
            focus: .locked(lensPosition: Self.clamped(lensPosition, in: .init(minimum: 0, maximum: 1))),
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
        await applyCameraControlIntent(intent, against: capability, to: activeSessionConfiguration.device)
    }

    #if TAP_ENABLE_PRO_CAMERA_CONTROLS
    func readManualControlSnapshot(
        reason: CameraManualControlReadbackReason
    ) async -> CameraManualControlReadbackSnapshot? {
        guard let activeSessionConfiguration else {
            return nil
        }

        let snapshot = await sessionController.readManualControlSnapshot(
            reason: reason,
            generation: configurationGeneration,
            from: activeSessionConfiguration.device
        )
        latestManualControlReadback = snapshot
        return snapshot
    }
    #endif

    func applyManualControlIntent(_ intent: CameraManualControlIntent) async {
        guard let activeSessionConfiguration else {
            return
        }

        await applyCameraControlIntent(
            intent,
            against: activeSessionConfiguration.controlCapabilities,
            to: activeSessionConfiguration.device
        )
    }

    func restoreAutoFocus() async {
        guard let activeSessionConfiguration else {
            return
        }

        let capability = activeSessionConfiguration.controlCapabilities
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: nil,
            focus: .continuousAuto,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )
        await applyCameraControlIntent(intent, against: capability, to: activeSessionConfiguration.device)
    }

    private func applyCameraControlIntent(
        _ intent: CameraManualControlIntent,
        against capability: CameraControlCapabilitySnapshot,
        to device: AVCaptureDevice
    ) async {
        do {
            let presentation = try await sessionController.applyManualControlIntent(
                intent,
                against: capability,
                to: device
            )
            if presentation.status == .blocked {
                statusMessage = "\(presentation.title) · \(presentation.detail)"
            }
        } catch {
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
    }

    private static func clamped(
        _ value: Double,
        in range: CameraControlCapabilitySnapshot.DoubleRange
    ) -> Double {
        guard value.isFinite else {
            return range.minimum
        }
        return min(max(value, range.minimum), range.maximum)
    }

}

nonisolated struct CameraCaptureDepthHint: Equatable, Sendable {
    let id: UUID
    let message: String

    init(message: String) {
        self.id = UUID()
        self.message = message
    }
}

private extension CameraFocusRuntimeEvent.Kind {
    init(captureSessionEvent: CaptureSessionFocusRuntimeEvent) {
        switch captureSessionEvent {
        case .focusStarted:
            self = .focusStarted
        case .focusSettled:
            self = .focusSettled
        case .subjectAreaChanged:
            self = .subjectAreaChanged
        }
    }
}

private extension CameraExposureRuntimeEvent.Kind {
    init(captureSessionEvent: CaptureSessionExposureRuntimeEvent) {
        switch captureSessionEvent {
        case .exposureStarted:
            self = .exposureStarted
        case .exposureSettled:
            self = .exposureSettled
        }
    }
}
