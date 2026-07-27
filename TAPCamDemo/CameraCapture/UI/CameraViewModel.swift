//
//  CameraViewModel.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Combine
import Foundation
import Observation
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
    @Published var recentLibraryPresentation: RecentLibraryPresentation = .unresolved
    @Published var recentLibraryFetchState: IdentifiedMediaFetchState<MediaPoster, MediaPoster>?
    @Published var latestCaptureDepthHint: CameraCaptureDepthHint?
    @Published var focusRuntimeEvent: CameraFocusRuntimeEvent?
    @Published var exposureRuntimeEvent: CameraExposureRuntimeEvent?
    @Published var isVideoRecording = false
    @Published var videoRecordingStartedAt: Date?
    @Published var isPreparingVideoMode = false
    @Published var photographerModeState: PhotographerModeState
    @Published var suspendedRearModeIntent: PhotographerRearModeIntent = .standard
    @Published private(set) var isSessionControllerSuspectedWedged = false
    @Published var latestManualControlReadback: CameraManualControlReadbackSnapshot?
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
    let photographerModeAvailability: PhotographerModeAvailability
    let locationProvider = LocationProvider()
    let jobQueue = CaptureJobQueue()
    let metricsStore = MetricsStore()
    let pendingCaptureStore: TAPPendingCaptureStore
    let pendingCaptureProcessor: TAPPendingCaptureProcessor
    let libraryStore: LibraryMediaStore
    let libraryMediaFetcher: any LibraryMediaFetching
    let videoPosterGenerator: any LibraryVideoPosterGenerating
    let pipeline: CapturePipeline
    var activeSessionConfiguration: SessionConfigurationResult?
    var configurationGeneration = 0
    var depthSelectionMode: DepthSelectionMode = .automatic
    var requestedGlobalAutoExposureBias = CameraEVPreferences.defaultGlobalBias
    var activeVideoRecordingCaptureID: String?
    var videoRecordingTemporaryDirectoryURL: URL?
    var videoDurationLimitTask: Task<Void, Never>?
    var videoThermalObserver: NSObjectProtocol?
    var videoWriterFailureRecoveryTask: Task<Void, Never>?
    var recentLibraryPreviewRefreshTask: Task<Void, Never>?
    var recentLibraryCoverTask: Task<Void, Never>?
    var recentLibraryFetchGeneration: UInt64 = 0
    var lastHandledLibrarySnapshotRevision: UInt64 = 0
    var standardRearSelectionBeforePhotographerMode: StandardCameraSelectionSnapshot?
    /// Set from the persisted startup policy before `start()` is awaited.
    /// The request is consumed once so fallback configuration cannot loop.
    var requestedPhotographerModeOnStart = false
    var hasConsumedPhotographerModeStartupRequest = false
    var hasPendingSelectionReconfiguration = false
    var cameraPathConfigurationWatchdogTask: Task<Void, Never>?
    var cameraPathConfigurationWatchdogGeneration: Int?
    var sessionQueueLivenessProbeTask: Task<Void, Never>?
    private var manualFocusRuntimeEpoch: UInt64 = 0
    private var manualFocusRuntimeContext: CameraManualFocusRuntimeContext?
    private var manualFocusRuntimeToken: CameraManualFocusOperationToken?
    private var manualFocusWritePump = CameraManualFocusWritePumpState()
    private var manualFocusEntryRequestID: UUID?
    /// Unlike the logical MF context, this tail survives cancellation until
    /// AVFoundation has completed (or timed out) the physical write. A new MF
    /// context waits behind it, so rapid AF/MF toggles never overlap hardware
    /// focus writes.
    private let manualFocusTransport = CameraManualFocusTransportQueue()

    var session: AVCaptureSession {
        sessionController.session
    }

    var manualFocusPreviewStream: CameraManualFocusPreviewStream {
        sessionController.manualFocusPreviewStream
    }

    var recentThumbnail: UIImage? {
        recentLibraryPresentation.poster?.image
    }

    var recentLibraryStatusText: String? {
        switch recentLibraryPresentation {
        case .unresolved, .empty, .ready, .failed:
            nil
        case .resolving(_, let kind):
            LibraryMediaCopy.preparing(kind)
        case .loading(_, _, _, let progress):
            LibraryMediaCopy.loadingFromICloud(progress: progress)
        }
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
                && activeSessionConfiguration?.depthDeliverySupported == true
                && pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs)
    }

    var isCaptureWriteInProgress: Bool {
        pendingJobCount > 0
    }

    var isBusyForNonCaptureStartupWork: Bool {
        isConfiguringSession
            || photographerModeState.isTransitioning
            || isVideoRecording
            || isPreparingVideoMode
            || isPausedForAnalysis
    }

    var shouldShowFocalLengthSelector: Bool {
        guard let selectedSource = capabilityMatrix.rgbSource(id: selectedRGBSourceID) else {
            return false
        }
        return selectedSource.device.position == .back
            && !photographerModeState.isActive
            && !focalLengthOptions.isEmpty
    }

    var isPhotographerModeActive: Bool {
        photographerModeState.isActive
    }

    var isRearCameraActive: Bool {
        let position = activeSessionConfiguration?.device.position
            ?? capabilityMatrix.rgbSource(id: selectedRGBSourceID)?.device.position
        return position == .back
    }

    var canTogglePhotographerMode: Bool {
        photographerModeAvailability.isAvailable
            && isRearCameraActive
            && !isConfiguringSession
            && !isSessionControllerSuspectedWedged
            && !photographerModeState.isTransitioning
            && !photographerModeState.requiresStandardRecovery
            && !isVideoRecording
            && !isPreparingVideoMode
            && !isPausedForAnalysis
    }

    var canRetryUnconfiguredCameraRecovery: Bool {
        photographerModeState.requiresStandardRecovery
            && !isConfiguringSession
            && !hasPendingSelectionReconfiguration
            && !isSessionControllerSuspectedWedged
            && !isPausedForAnalysis
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
        return isEligiblePhotographerManualFocusConfiguration(activeSessionConfiguration)
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
        pendingCaptureProcessor: TAPPendingCaptureProcessor = .shared,
        libraryStore: LibraryMediaStore,
        libraryMediaFetcher: any LibraryMediaFetching = PhotoKitLibraryMediaFetcher(),
        videoPosterGenerator: any LibraryVideoPosterGenerating = AVAssetLibraryVideoPosterGenerator()
    ) {
        self.capabilityMatrix = capabilityMatrix
        let photographerModeAvailability = capabilityMatrix.photographerModeAvailability
        self.photographerModeAvailability = photographerModeAvailability
        self.photographerModeState = photographerModeAvailability.unavailableReason.map {
            .unavailable($0)
        } ?? .standard
        self.sessionController = sessionController
        self.pendingCaptureStore = pendingCaptureStore
        self.pendingCaptureProcessor = pendingCaptureProcessor
        self.libraryStore = libraryStore
        self.libraryMediaFetcher = libraryMediaFetcher
        self.videoPosterGenerator = videoPosterGenerator
        self.lastHandledLibrarySnapshotRevision = libraryStore.snapshot.revision
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
        sessionController.setRuntimeFailureHandler { [weak self] failure in
            Task { @MainActor [weak self, failure] in
                self?.handleCaptureSessionRuntimeFailure(failure)
            }
        }
        sessionController.setVideoRecordingFailureHandler { [weak self] failure in
            Task { @MainActor [weak self, failure] in
                self?.handleVideoRecordingWriterFailure(failure)
            }
        }
        beginObservingLibraryMediaStore()
    }

    private func handleCaptureSessionRuntimeFailure(
        _ failure: CaptureSessionRuntimeFailure
    ) {
        guard failure.isMediaServicesReset,
              !isVideoRecording,
              !isPreparingVideoMode,
              isConfiguringSession || activeSessionConfiguration != nil else {
            return
        }

        failCameraPathConfigurationAsUnresponsive(
            statusMessage: "Camera service restarted. Waiting for it to recover."
        )
    }

    func armCameraPathConfigurationWatchdog(generation: Int) {
        cancelCameraPathConfigurationWatchdog()
        cameraPathConfigurationWatchdogGeneration = generation
        cameraPathConfigurationWatchdogTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard let self,
                  self.cameraPathConfigurationWatchdogGeneration == generation,
                  self.configurationGeneration == generation,
                  self.isConfiguringSession else {
                return
            }
            self.failCameraPathConfigurationAsUnresponsive(
                statusMessage: "Camera service did not respond."
            )
        }
    }

    func cancelCameraPathConfigurationWatchdog(generation: Int? = nil) {
        if let generation,
           cameraPathConfigurationWatchdogGeneration != generation {
            return
        }
        cameraPathConfigurationWatchdogTask?.cancel()
        cameraPathConfigurationWatchdogTask = nil
        cameraPathConfigurationWatchdogGeneration = nil
    }

    func failCameraPathAfterPreviewTimeout() {
        guard !photographerModeState.isTransitioning else {
            return
        }

        if isConfiguringSession {
            failCameraPathConfigurationAsUnresponsive(
                statusMessage: "Camera configuration did not finish."
            )
            return
        }

        cancelManualFocusRuntime()
        configurationGeneration += 1
        cancelCameraPathConfigurationWatchdog()
        isConfiguringSession = false
        isDepthCaptureReady = false
        activeSessionConfiguration = nil
        hasPendingSelectionReconfiguration = false
        suspendedRearModeIntent = .standard
        isSessionControllerSuspectedWedged = false
        photographerModeState = .failed(
            recoveredMode: .unconfigured,
            reason: .configurationFailed
        )
        statusMessage = "Camera preview did not resume. Retry camera setup."
    }

    private func failCameraPathConfigurationAsUnresponsive(statusMessage: String) {
        cancelCameraPathConfigurationWatchdog()
        cancelManualFocusRuntime()
        configurationGeneration += 1
        isConfiguringSession = false
        isDepthCaptureReady = false
        activeSessionConfiguration = nil
        hasPendingSelectionReconfiguration = false
        suspendedRearModeIntent = .standard
        isSessionControllerSuspectedWedged = true
        photographerModeState = .failed(
            recoveredMode: .unconfigured,
            reason: .configurationFailed
        )
        self.statusMessage = statusMessage
        beginSessionQueueLivenessProbeIfNeeded()
    }

    private func beginSessionQueueLivenessProbeIfNeeded() {
        guard sessionQueueLivenessProbeTask == nil else {
            return
        }
        let controller = sessionController
        sessionQueueLivenessProbeTask = Task { @MainActor [weak self] in
            await controller.waitUntilSessionQueueIsResponsive()
            guard let self, !Task.isCancelled else {
                return
            }
            self.isSessionControllerSuspectedWedged = false
            self.sessionQueueLivenessProbeTask = nil
            self.statusMessage = "Camera service is ready to retry."
        }
    }

    private func beginObservingLibraryMediaStore() {
        withObservationTracking {
            _ = libraryStore.snapshot.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.beginObservingLibraryMediaStore()
                let revision = self.libraryStore.snapshot.revision
                guard revision != self.lastHandledLibrarySnapshotRevision else {
                    return
                }
                self.lastHandledLibrarySnapshotRevision = revision
                self.recentLibraryCoverTask?.cancel()
                self.recentLibraryCoverTask = Task { @MainActor [weak self] in
                    await self?.loadRecentLibraryCoverFromCanonicalSnapshot()
                }
            }
        }
    }

    func start() async {
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
        cancelCameraPathConfigurationWatchdog()
        cancelManualFocusRuntime()
        recentLibraryPreviewRefreshTask?.cancel()
        recentLibraryPreviewRefreshTask = nil
        recentLibraryCoverTask?.cancel()
        recentLibraryCoverTask = nil
        recentLibraryFetchGeneration &+= 1
        configurationGeneration += 1
        isConfiguringSession = false
        reconcileInterruptedPhotographerModeTransition()
        isPausedForAnalysis = false
        isPreparingVideoMode = false
        sessionController.stop()
    }

    func pauseForAnalysis() {
        cancelCameraPathConfigurationWatchdog()
        cancelManualFocusRuntime()
        recentLibraryPreviewRefreshTask?.cancel()
        recentLibraryPreviewRefreshTask = nil
        recentLibraryCoverTask?.cancel()
        recentLibraryCoverTask = nil
        recentLibraryFetchGeneration &+= 1
        configurationGeneration += 1
        isConfiguringSession = false
        reconcileInterruptedPhotographerModeTransition()
        isPreparingVideoMode = false
        isPausedForAnalysis = true
        isDepthCaptureReady = false
        activeSessionConfiguration = nil
        statusMessage = "Camera paused for analysis."
        sessionController.stop()
    }

    private func reconcileInterruptedPhotographerModeTransition() {
        guard photographerModeState.isTransitioning else {
            return
        }
        let recoveredMode = photographerModeState.effectiveMode
        photographerModeState = .failed(
            recoveredMode: recoveredMode,
            reason: .configurationFailed
        )
        suspendedRearModeIntent = recoveredMode == .photographer
            ? .photographer
            : .standard
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
        cancelManualFocusRuntime()
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

    /// Accepts slider values at UI cadence while allowing only one hardware
    /// focus operation in flight. During that operation, intermediate values
    /// collapse into one latest value, so the lens keeps moving without an
    /// unbounded FIFO of stale positions.
    func queueManualFocus(lensPosition: Double) {
        guard let activeSessionConfiguration,
              isEligiblePhotographerManualFocusConfiguration(activeSessionConfiguration) else {
            statusMessage = "Manual focus unavailable"
            return
        }

        manualFocusWritePump.queue(
            lensPosition: Self.clamped(
                lensPosition,
                in: .init(minimum: 0, maximum: 1)
            )
        )
        guard manualFocusRuntimeContext != nil else {
            guard manualFocusEntryRequestID == nil else {
                return
            }
            let requestID = UUID()
            manualFocusEntryRequestID = requestID
            Task { @MainActor [weak self] in
                guard let self,
                      manualFocusEntryRequestID == requestID else {
                    return
                }
                manualFocusEntryRequestID = nil
                _ = await lockManualFocusAtCurrentLensPosition()
            }
            return
        }
        startNextManualFocusWriteIfNeeded()
    }

    /// Temporarily runs one focus-only AF cycle at the tapped point, then locks
    /// the current lens position again before reporting success. The whole
    /// transaction owns the MF transport tail, so slider values entered during
    /// assist wait behind the lock barrier and collapse to one latest value.
    func performManualFocusTapAssist(
        at point: CameraPreviewFocusPoint
    ) async -> CameraManualFocusTapAssistOutcome {
        guard let activeSessionConfiguration,
              isEligiblePhotographerManualFocusConfiguration(activeSessionConfiguration) else {
            statusMessage = "Manual focus assist unavailable"
            return .unavailable
        }

        let capability = activeSessionConfiguration.controlCapabilities
        guard capability.focus.supportsAutoFocus,
              capability.focus.supportsFocusPointOfInterest,
              capability.focus.supportsLockedFocus else {
            statusMessage = "Manual focus assist unavailable"
            return .unavailable
        }

        let context = beginManualFocusRuntime(
            for: activeSessionConfiguration,
            preservingPendingLensPosition: nil
        )
        guard let operationToken = manualFocusRuntimeToken,
              operationToken.id == context.operationID else {
            return .cancelled
        }

        let controller = sessionController
        let device = activeSessionConfiguration.device
        let intentPoint = CameraManualControlIntent.NormalizedPoint(x: point.x, y: point.y)

        do {
            let completion = try await CameraManualFocusTapAssistTransaction.perform(
                through: manualFocusTransport,
                preflight: { [weak self, operationToken] in
                    guard let self else {
                        return false
                    }
                    return operationToken.isValid
                        && self.isCurrentManualFocusContext(context)
                },
                autoFocusAndWait: {
                    try await controller.autoFocusOnlyAndWaitForManualFocusTapAssist(
                        at: intentPoint,
                        expectedDeviceID: context.deviceID,
                        expectedControlSignature: context.controlSurfaceSignature,
                        operationToken: operationToken,
                        on: device
                    )
                },
                lockCurrent: {
                    let snapshot = try await controller.setManualFocusLocked(
                        .current,
                        expectedDeviceID: context.deviceID,
                        expectedControlSignature: context.controlSurfaceSignature,
                        generation: context.generation,
                        operationToken: operationToken,
                        on: device
                    )
                    guard snapshot.focusMode == .locked else {
                        throw TAPDepthCaptureError.cameraControlCommandPlanNotExecutable
                    }
                    return snapshot
                }
            )

            guard isCurrentManualFocusContext(context) else {
                return .cancelled
            }
            manualFocusWritePump.completeEntry()

            switch completion {
            case .focused(let snapshot):
                latestManualControlReadback = snapshot
                startNextManualFocusWriteIfNeeded()
                return .focused(snapshot)
            case .recovered(let snapshot):
                latestManualControlReadback = snapshot
                startNextManualFocusWriteIfNeeded()
                statusMessage = "Manual focus assist could not settle. Focus stayed locked."
                return .failedButRecovered(snapshot)
            }
        } catch is CancellationError {
            if manualFocusRuntimeContext == context {
                cancelManualFocusRuntime()
            }
            return .cancelled
        } catch {
            guard manualFocusRuntimeContext == context else {
                return .cancelled
            }
            cancelManualFocusRuntime()
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
            return .manualFocusLost
        }
    }

    /// Enters MF without moving the lens away from the position AF has already
    /// reached. Numeric lens-position writes are reserved for an actual slider
    /// adjustment, which keeps the AF -> MF mode switch free of a hardware
    /// focus jump.
    func lockManualFocusAtCurrentLensPosition() async -> CameraManualControlReadbackSnapshot? {
        guard let activeSessionConfiguration else {
            return nil
        }

        guard isEligiblePhotographerManualFocusConfiguration(activeSessionConfiguration) else {
            statusMessage = "Manual focus unavailable"
            return nil
        }

        let context = beginManualFocusRuntime(
            for: activeSessionConfiguration,
            preservingPendingLensPosition: manualFocusWritePump.pendingLensPositionSnapshot
        )

        do {
            let snapshot = try await performSerializedManualFocusWrite(
                .current,
                context: context,
                device: activeSessionConfiguration.device
            )
            guard isCurrentManualFocusContext(context) else {
                return nil
            }
            manualFocusWritePump.completeEntry()
            latestManualControlReadback = snapshot
            startNextManualFocusWriteIfNeeded()
            return snapshot
        } catch {
            guard manualFocusRuntimeContext == context else {
                return nil
            }
            cancelManualFocusRuntime()
            statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
            return nil
        }
    }

    private func beginManualFocusRuntime(
        for configuration: SessionConfigurationResult,
        preservingPendingLensPosition pendingLensPosition: Double?
    ) -> CameraManualFocusRuntimeContext {
        let capability = configuration.controlCapabilities
        manualFocusEntryRequestID = nil
        cancelManualFocusRuntime()
        manualFocusRuntimeEpoch &+= 1
        let operationToken = CameraManualFocusOperationToken()
        let context = CameraManualFocusRuntimeContext(
            epoch: manualFocusRuntimeEpoch,
            generation: configurationGeneration,
            deviceID: capability.deviceID,
            operationID: operationToken.id,
            controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(
                capability: capability
            )
        )
        manualFocusRuntimeContext = context
        manualFocusRuntimeToken = operationToken
        manualFocusWritePump.beginEntry(preserving: pendingLensPosition)
        return context
    }

    func cancelManualFocusRuntime() {
        manualFocusRuntimeToken?.invalidate()
        manualFocusRuntimeToken = nil
        manualFocusRuntimeEpoch &+= 1
        manualFocusRuntimeContext = nil
        manualFocusWritePump.cancel()
        manualFocusEntryRequestID = nil
    }

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
        cancelManualFocusRuntime()
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

    private func startNextManualFocusWriteIfNeeded() {
        guard let context = manualFocusRuntimeContext,
              isCurrentManualFocusContext(context),
              let activeSessionConfiguration,
              let lensPosition = manualFocusWritePump.takeNextPositionIfReady() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let snapshot = try await performSerializedManualFocusWrite(
                    .position(lensPosition),
                    context: context,
                    device: activeSessionConfiguration.device
                )
                guard isCurrentManualFocusContext(context) else {
                    return
                }
                manualFocusWritePump.completePositionWrite()
                latestManualControlReadback = snapshot
                startNextManualFocusWriteIfNeeded()
            } catch {
                guard manualFocusRuntimeContext == context else {
                    return
                }
                cancelManualFocusRuntime()
                statusMessage = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
            }
        }
    }

    private func isCurrentManualFocusContext(_ context: CameraManualFocusRuntimeContext) -> Bool {
        guard manualFocusRuntimeContext == context,
              context.epoch == manualFocusRuntimeEpoch,
              context.generation == configurationGeneration,
              manualFocusRuntimeToken?.id == context.operationID,
              manualFocusRuntimeToken?.isValid == true,
              let configuration = activeSessionConfiguration,
              configuration.device.uniqueID == context.deviceID,
              CameraManualControlCommandPlan.ControlSurfaceSignature(
                capability: configuration.controlCapabilities
              ) == context.controlSurfaceSignature else {
            return false
        }
        return isEligiblePhotographerManualFocusConfiguration(configuration)
    }

    private func performSerializedManualFocusWrite(
        _ target: CameraManualFocusLockTarget,
        context: CameraManualFocusRuntimeContext,
        device: AVCaptureDevice
    ) async throws -> CameraManualControlReadbackSnapshot {
        let controller = sessionController
        guard let operationToken = manualFocusRuntimeToken,
              operationToken.id == context.operationID else {
            throw CancellationError()
        }
        return try await manualFocusTransport.perform(
            preflight: { [weak self, operationToken] in
                guard let self else {
                    return false
                }
                return operationToken.isValid
                    && self.isCurrentManualFocusContext(context)
            },
            operation: { [operationToken] in
                try await controller.setManualFocusLocked(
                    target,
                    expectedDeviceID: context.deviceID,
                    expectedControlSignature: context.controlSurfaceSignature,
                    generation: context.generation,
                    operationToken: operationToken,
                    on: device
                )
            }
        )
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

    private func isEligiblePhotographerManualFocusConfiguration(
        _ configuration: SessionConfigurationResult
    ) -> Bool {
        photographerModeState.effectiveMode == .photographer
            && !photographerModeState.isTransitioning
            && !isConfiguringSession
            && configuration.device.position == .back
            && configuration.device.deviceType == .builtInLiDARDepthCamera
            && configuration.controlCapabilities.focus.supportsManualLensPosition
    }

}

private nonisolated struct CameraManualFocusRuntimeContext: Equatable, Sendable {
    let epoch: UInt64
    let generation: Int
    let deviceID: String
    let operationID: UUID
    let controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
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
