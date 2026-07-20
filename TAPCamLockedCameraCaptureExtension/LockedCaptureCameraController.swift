//
//  LockedCaptureCameraController.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppIntents
import Combine
import CoreMedia
import CoreVideo
import Foundation
import LockedCameraCapture
import OSLog
import SwiftUI

typealias LockedCaptureCameraState = TAPCamLockedCameraViewState

nonisolated final class LockedCaptureCameraController: NSObject, ObservableObject, @unchecked Sendable {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()
    private static let frameWatchdogThreshold: TimeInterval = 4
    private static let maximumFrameRecoveryAttempts = 2

    let captureSession = AVCaptureSession()

    @MainActor @Published private(set) var state: LockedCaptureCameraState = .starting("Preparing viewfinder.")
    @MainActor @Published private(set) var activeLensLabel: String?
    @MainActor @Published private(set) var availableLenses: [TAPCamLockedCameraLensRecord] = []
    @MainActor @Published private(set) var selectedLensID: TAPCamLockedCameraLensRecord.ID?
    @MainActor @Published private(set) var lastCaptureSucceeded = false
    @MainActor @Published private(set) var isPreviewHostVisible = true

    private let sessionQueue = DispatchQueue(label: "TAPCam.LockedCameraCapture.session")
    private let videoQueue = DispatchQueue(label: "TAPCam.LockedCameraCapture.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var observers: [NSObjectProtocol] = []
    private var frameWatchdogTask: Task<Void, Never>?
    private var inFlightPhotoDelegates: [String: LockedPhotoCaptureDelegate] = [:]

    private var isActive = false
    private var isConfiguring = false
    private var activeLens: TAPCamLockedCameraLensRecord?
    private var lastFrameAt: Date?
    private var waitingForFirstFrameSince: Date?
    private var frameRecoveryAttemptCount = 0
    private var previewLayerInWindow = false
    private var previewLayerHasSuperlayer = false

    override init() {
        super.init()
        Self.logger.info("locked_camera_controller_init")
        Self.stdoutProbe("locked_camera_controller_init")
    }

    deinit {
        Self.logger.info("locked_camera_controller_deinit")
        frameWatchdogTask?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    @MainActor
    func start() async {
        guard !isConfiguring else {
            Self.logger.info("locked_camera_start_ignored reason=configuring")
            return
        }
        isActive = true
        isPreviewHostVisible = true
        installSessionObserversIfNeeded()
        startFrameWatchdogIfNeeded()
        setState(.starting("Loading camera context."))
        Self.logger.info("locked_camera_start_begin")

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        Self.logger.info("camera_authorization_status raw=\(authorizationStatus.rawValue, privacy: .public)")
        guard authorizationStatus == .authorized else {
            setUnavailable("Camera permission is not authorized: \(authorizationStatus.rawValue).")
            return
        }

        do {
            guard let context = try await TAPCamLockedCameraIntent.appContext else {
                setUnavailable("Open the main app once before using Lock Screen capture.")
                return
            }
            Self.logger.info(
                "locked_camera_context_loaded lensCount=\(context.lenses.count, privacy: .public) selectedLens=\(context.selectedLensID ?? "none", privacy: .public) unavailable=\(context.unavailableReason ?? "none", privacy: .public)"
            )
            if let reason = context.unavailableReason, context.lenses.isEmpty {
                availableLenses = []
                selectedLensID = nil
                setUnavailable(reason)
                return
            }
            guard let lens = context.selectedLens else {
                availableLenses = []
                selectedLensID = nil
                setUnavailable("No lock-screen lens is available.")
                return
            }

            availableLenses = context.lenses
            activeLens = lens
            activeLensLabel = Self.lensLabel(for: lens)
            selectedLensID = lens.id
            Self.logger.info(
                "locked_camera_lens_selected id=\(lens.id, privacy: .public) type=\(lens.captureDeviceTypeRawValue, privacy: .public) position=\(lens.captureDevicePosition, privacy: .public) zoom=\(lens.zoomFactor, privacy: .public)"
            )
            await configureAndStartSession(lens: lens, reason: "initial_start")
        } catch {
            availableLenses = []
            selectedLensID = nil
            setUnavailable("Camera context failed: \(Self.describe(error))")
        }
    }

    @MainActor
    func stop() {
        isActive = false
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil
        Self.logger.info("session_stop_requested")
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    @MainActor
    func handleScenePhase(_ phase: ScenePhase) {
        Self.logger.info(
            "scene_phase phase=\(String(describing: phase), privacy: .public) state=\(self.state.title, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public)"
        )
        switch phase {
        case .active:
            Task { await start() }
        case .inactive, .background:
            isActive = false
        @unknown default:
            break
        }
    }

    @MainActor
    func recordPreviewLayerState(inWindow: Bool, hasSuperlayer: Bool) {
        guard inWindow != previewLayerInWindow || hasSuperlayer != previewLayerHasSuperlayer else {
            return
        }
        previewLayerInWindow = inWindow
        previewLayerHasSuperlayer = hasSuperlayer
        Self.logger.info(
            "preview_layer_state inWindow=\(inWindow, privacy: .public) hasSuperlayer=\(hasSuperlayer, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public)"
        )
    }

    @MainActor
    func capturePhoto(into sessionContentURL: URL) {
        guard state.canCapture else {
            Self.logger.info("capture_ignored state=\(self.state.message, privacy: .public)")
            return
        }
        guard let activeLens else {
            setUnavailable("No active lens is configured.")
            return
        }

        let request = LockedPhotoCaptureRequest(
            captureID: UUID().uuidString,
            capturedAt: Date(),
            sessionContentURL: sessionContentURL,
            lens: activeLens
        )
        lastCaptureSucceeded = false
        setState(.capturing("Writing photo to session content."))
        Self.logger.info(
            "photo_capture_requested captureID=\(request.captureID, privacy: .public) url=\(sessionContentURL.path, privacy: .private(mask: .hash))"
        )
        Self.logger.info(
            "photo_capture_poc_defaults captureID=\(request.captureID, privacy: .public) fileContainer=heic photoQuality=quality flashMode=off livePhotoForcedOff=true location=nil appAttest=false photos=false network=false"
        )

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                let photoSettings = try self.makePhotoSettings()
                let delegate = LockedPhotoCaptureDelegate(request: request) { result in
                    Task { @MainActor [weak self] in
                        self?.handlePhotoCaptureResult(result)
                    }
                }
                self.inFlightPhotoDelegates[request.captureID] = delegate
                self.photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
            } catch {
                Task { @MainActor [weak self] in
                    self?.handlePhotoCaptureResult(LockedPhotoCaptureResult(
                        captureID: request.captureID,
                        outcome: .failure(error)
                    ))
                }
            }
        }
    }

    @MainActor
    func selectLens(_ lens: TAPCamLockedCameraLensRecord) {
        guard availableLenses.contains(where: { $0.id == lens.id }) else {
            Self.logger.info("lens_select_ignored reason=unknown_lens id=\(lens.id, privacy: .public)")
            return
        }
        guard selectedLensID != lens.id else {
            Self.logger.info("lens_select_ignored reason=already_selected id=\(lens.id, privacy: .public)")
            return
        }
        guard state.canCapture, !isConfiguring else {
            Self.logger.info("lens_select_ignored reason=not_live id=\(lens.id, privacy: .public) state=\(self.state.message, privacy: .public)")
            return
        }

        lastCaptureSucceeded = false
        activeLens = lens
        activeLensLabel = Self.lensLabel(for: lens)
        selectedLensID = lens.id
        Self.logger.info(
            "locked_camera_lens_change_requested id=\(lens.id, privacy: .public) type=\(lens.captureDeviceTypeRawValue, privacy: .public) position=\(lens.captureDevicePosition, privacy: .public) zoom=\(lens.zoomFactor, privacy: .public)"
        )

        Task {
            await configureAndStartSession(lens: lens, reason: "lens_selected")
        }
    }

    @MainActor
    func recordStatusPlaceholderTap(session: LockedCameraCaptureSession) {
        let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
            in: session.sessionContentURL
        )
        Self.stdoutProbe(
            "locked_album_placeholder_tapped_status_only lastCaptureSucceeded=\(self.lastCaptureSucceeded) state=\(self.state.title) sessionRunning=\(self.captureSession.isRunning) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none")"
        )
        Self.logger.info(
            "locked_album_placeholder_tapped_status_only lastCaptureSucceeded=\(self.lastCaptureSucceeded, privacy: .public) state=\(self.state.title, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
        )
    }

    @MainActor
    func recordExtensionContextResolved(hasContext: Bool) {
        Self.stdoutProbe("locked_camera_extension_context_resolved hasContext=\(hasContext)")
        Self.logger.info(
            "locked_camera_extension_context_resolved hasContext=\(hasContext, privacy: .public)"
        )
    }

    @MainActor
    func recordURLPlaceholderButtonTap(
        session: LockedCameraCaptureSession,
        hasExtensionContext: Bool
    ) {
        let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
            in: session.sessionContentURL
        )
        Self.stdoutProbe(
            "locked_album_placeholder_button_tap_e6c hasExtensionContext=\(hasExtensionContext) lastCaptureSucceeded=\(self.lastCaptureSucceeded) state=\(self.state.title) sessionRunning=\(self.captureSession.isRunning) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none")"
        )
        Self.logger.info(
            "locked_album_placeholder_button_tap_e6c hasExtensionContext=\(hasExtensionContext, privacy: .public) lastCaptureSucceeded=\(self.lastCaptureSucceeded, privacy: .public) state=\(self.state.title, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
        )
    }

    @MainActor
    @discardableResult
    func openHostApplicationWithExtensionContextURL(
        session: LockedCameraCaptureSession,
        extensionContext: NSExtensionContext?
    ) -> Bool {
        let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
            in: session.sessionContentURL
        )
        let route = TAPCamLockedCameraHandoff.urlOpenRouteName
        Self.stdoutProbe(
            "open_application_url_prepare route=\(route) hasExtensionContext=\(extensionContext != nil) sessionRunning=\(self.captureSession.isRunning) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none")"
        )
        Self.logger.info(
            "open_application_url_prepare route=\(route, privacy: .public) hasExtensionContext=\(extensionContext != nil, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
        )

        guard let extensionContext else {
            Self.stdoutProbe("open_application_url_failed reason=missingExtensionContext")
            Self.logger.error("open_application_url_failed reason=missingExtensionContext")
            return false
        }

        let url = TAPCamLockedCameraHandoff.lockedCaptureOpenURL
        Self.stdoutProbe("open_application_url_call route=\(route) url=\(url.absoluteString)")
        Self.logger.info(
            "open_application_url_call route=\(route, privacy: .public)"
        )
        extensionContext.open(url) { success in
            Self.stdoutProbe("open_application_url_result route=\(route) success=\(success)")
            Self.logger.info(
                "open_application_url_result route=\(route, privacy: .public) success=\(success, privacy: .public)"
            )
        }
        return true
    }

    @MainActor
    func openHostApplication(
        session: LockedCameraCaptureSession,
        tapAction: String,
        reason: String? = nil
    ) {
        let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
            in: session.sessionContentURL
        )
        Self.logger.info(
            "open_application_prepare tapAction=\(tapAction, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
        )

        let activity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        activity.title = "TAPCam Locked Camera"
        var userInfo: [String: String] = [
            TAPCamLockedCameraHandoff.sourceKey: TAPCamLockedCameraHandoff.sourceValue,
            TAPCamLockedCameraHandoff.tapActionKey: tapAction
        ]
        if let reason {
            userInfo[TAPCamLockedCameraHandoff.reasonKey] = reason
        }
        activity.userInfo = userInfo

        if Self.isMinimalRuntimeImportHandoff(tapAction) {
            Self.logger.info(
                "open_application_minimal_handoff tapAction=\(tapAction, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public)"
            )
            Task { [weak self] in
                do {
                    Self.logger.info("open_application_call tapAction=\(tapAction, privacy: .public)")
                    try await session.openApplication(for: activity)
                    Self.logger.info("open_application_requested tapAction=\(tapAction, privacy: .public)")
                } catch {
                    Self.logger.error("open_application_failed error=\(Self.describe(error), privacy: .public)")
                    await MainActor.run {
                        self?.setUnavailable("Open app failed: \(Self.describe(error))")
                    }
                }
            }
            return
        }

        setState(.recovering("Opening TAPCam."))
        isActive = false
        isPreviewHostVisible = false
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil

        Task { [weak self] in
            await self?.prepareForHostApplicationHandoff(tapAction: tapAction)
            do {
                Self.logger.info("open_application_call tapAction=\(tapAction, privacy: .public)")
                try await session.openApplication(for: activity)
                Self.logger.info("open_application_requested tapAction=\(tapAction, privacy: .public)")
            } catch {
                Self.logger.error("open_application_failed error=\(Self.describe(error), privacy: .public)")
                await MainActor.run {
                    self?.setUnavailable("Open app failed: \(Self.describe(error))")
                }
            }
        }
    }

    @MainActor
    func openHostApplicationSystemOnly(session: LockedCameraCaptureSession) {
        let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
            in: session.sessionContentURL
        )
        Self.logger.info(
            "open_application_system_only_prepare sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
        )
        let activity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        activity.title = "TAPCam Locked Camera"

        setState(.recovering("Opening TAPCam."))
        isActive = false
        isPreviewHostVisible = false
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil

        Task { [weak self] in
            await self?.prepareForHostApplicationHandoff(tapAction: "systemOnly")
            do {
                activity.title = "TAPCam Locked Camera E3B2 Teardown Complete"
                Self.logger.info("open_application_system_only_call")
                try await session.openApplication(for: activity)
                Self.logger.info("open_application_system_only_requested")
            } catch {
                Self.logger.error("open_application_system_only_failed error=\(Self.describe(error), privacy: .public)")
                await MainActor.run {
                    self?.setUnavailable("Open app failed: \(Self.describe(error))")
                }
            }
        }
    }

    @MainActor
    func openHostApplicationAppOwnedOpenOnly(session: LockedCameraCaptureSession) {
        let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
            in: session.sessionContentURL
        )
        Self.logger.info(
            "open_application_app_owned_prepare sessionRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
        )
        let activity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.openOnlyActivityType)
        activity.title = "TAPCam Locked Camera E3C App-Owned Open Only"

        setState(.recovering("Opening TAPCam."))
        isActive = false
        isPreviewHostVisible = false
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil

        Task { [weak self] in
            await self?.prepareForHostApplicationHandoff(tapAction: "appOwnedOpenOnly")
            do {
                Self.logger.info("open_application_app_owned_call")
                try await session.openApplication(for: activity)
                Self.logger.info("open_application_app_owned_requested")
            } catch {
                Self.logger.error("open_application_app_owned_failed error=\(Self.describe(error), privacy: .public)")
                await MainActor.run {
                    self?.setUnavailable("Open app failed: \(Self.describe(error))")
                }
            }
        }
    }

    private nonisolated static func isMinimalRuntimeImportHandoff(_ tapAction: String) -> Bool {
        tapAction == TAPCamLockedCameraHandoff.openTAPLibraryRuntimeImport
            || tapAction == TAPCamLockedCameraHandoff.openTAPCameraRuntimeImport
            || tapAction == TAPCamLockedCameraHandoff.openTAPNeutralRuntimeImport
            || tapAction == TAPCamLockedCameraHandoff.openTAPMainAppOnly
    }

    private nonisolated static func stdoutProbe(_ message: String) {
        print(message)
    }

    @MainActor
    private func prepareForHostApplicationHandoff(tapAction: String) async {
        Self.logger.info(
            "open_application_teardown_begin tapAction=\(tapAction, privacy: .public) sessionRunning=\(self.captureSession.isRunning, privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public)"
        )

        await Task.yield()

        await withCheckedContinuation { continuation in
            sessionQueue.async { [captureSession, videoOutput] in
                let wasRunning = captureSession.isRunning
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                if captureSession.isRunning {
                    captureSession.stopRunning()
                }

                captureSession.beginConfiguration()
                for output in captureSession.outputs {
                    captureSession.removeOutput(output)
                }
                for input in captureSession.inputs {
                    captureSession.removeInput(input)
                }
                captureSession.commitConfiguration()

                Self.logger.info(
                    "open_application_teardown_end tapAction=\(tapAction, privacy: .public) wasRunning=\(wasRunning, privacy: .public) isRunning=\(captureSession.isRunning, privacy: .public) inputCount=\(captureSession.inputs.count, privacy: .public) outputCount=\(captureSession.outputs.count, privacy: .public)"
                )
                continuation.resume()
            }
        }
    }

    @MainActor
    private func configureAndStartSession(
        lens: TAPCamLockedCameraLensRecord,
        reason: String
    ) async {
        guard !isConfiguring else {
            return
        }

        isConfiguring = true
        if !reason.contains("watchdog") {
            frameRecoveryAttemptCount = 0
        }
        lastFrameAt = nil
        waitingForFirstFrameSince = nil
        setState(reason == "initial_start" ? .starting("Starting viewfinder.") : .recovering("Restarting viewfinder."))
        Self.logger.info(
            "session_configure_begin reason=\(reason, privacy: .public) lens=\(lens.id, privacy: .public) device=\(lens.captureDeviceUniqueID, privacy: .private(mask: .hash)) zoom=\(lens.zoomFactor, privacy: .public)"
        )

        let result = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: Result<Void, Error>.failure(LockedCaptureCameraError.controllerReleased))
                    return
                }
                continuation.resume(returning: self.configureAndStartSessionOnQueue(lens: lens))
            }
        }

        isConfiguring = false

        switch result {
        case .success:
            waitingForFirstFrameSince = Date()
            setState(.starting("Waiting for first frame."))
            Self.logger.info("session_start_success isRunning=\(self.captureSession.isRunning, privacy: .public)")
        case .failure(let error):
            setUnavailable("Session failed: \(Self.describe(error))")
        }
    }

    private func configureAndStartSessionOnQueue(
        lens: TAPCamLockedCameraLensRecord
    ) -> Result<Void, Error> {
        guard let device = Self.resolveDevice(for: lens) else {
            Self.logger.error(
                "resolve_device_failed lens=\(lens.id, privacy: .public) type=\(lens.captureDeviceTypeRawValue, privacy: .public) position=\(lens.captureDevicePosition, privacy: .public)"
            )
            return .failure(LockedCaptureCameraError.deviceNotFound(lens.captureDeviceTypeRawValue))
        }
        Self.logger.info(
            "resolve_device_success name=\(device.localizedName, privacy: .public) id=\(device.uniqueID, privacy: .private(mask: .hash)) type=\(device.deviceType.rawValue, privacy: .public)"
        )

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        let configurationResult: Result<Void, Error> = {
            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
                Self.logger.info("session_configuration_committed")
            }

            do {
                for input in captureSession.inputs {
                    captureSession.removeInput(input)
                }
                for output in captureSession.outputs {
                    captureSession.removeOutput(output)
                }

                if captureSession.canSetSessionPreset(.photo) {
                    captureSession.sessionPreset = .photo
                }

                try configureZoom(for: device, requestedZoom: lens.zoomFactor)
                Self.logger.info("device_zoom_configured requested=\(lens.zoomFactor, privacy: .public)")

                let input = try AVCaptureDeviceInput(device: device)
                guard captureSession.canAddInput(input) else {
                    Self.logger.error("session_cannot_add_input device=\(device.localizedName, privacy: .public)")
                    return .failure(LockedCaptureCameraError.cannotAddInput(device.localizedName))
                }
                captureSession.addInput(input)

                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [
                    String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)
                ]
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                guard captureSession.canAddOutput(videoOutput) else {
                    Self.logger.error("session_cannot_add_video_output")
                    return .failure(LockedCaptureCameraError.cannotAddVideoOutput)
                }
                captureSession.addOutput(videoOutput)

                guard captureSession.canAddOutput(photoOutput) else {
                    Self.logger.error("session_cannot_add_photo_output")
                    return .failure(LockedCaptureCameraError.cannotAddPhotoOutput)
                }
                captureSession.addOutput(photoOutput)
                guard photoOutput.isDepthDataDeliverySupported else {
                    Self.logger.error("photo_output_depth_unsupported")
                    return .failure(LockedCaptureCameraError.depthDeliveryUnsupported)
                }
                photoOutput.isDepthDataDeliveryEnabled = true
                photoOutput.maxPhotoQualityPrioritization = .quality
                Self.logger.info(
                    "session_outputs_configured depthSupported=\(self.photoOutput.isDepthDataDeliverySupported, privacy: .public) depthEnabled=\(self.photoOutput.isDepthDataDeliveryEnabled, privacy: .public)"
                )
                return .success(())
            } catch {
                return .failure(error)
            }
        }()

        if case .failure(let error) = configurationResult {
            return .failure(error)
        }

        Self.logger.info("session_start_running_begin")
        captureSession.startRunning()
        Self.logger.info("session_start_running_end isRunning=\(self.captureSession.isRunning, privacy: .public)")
        guard captureSession.isRunning else {
            return .failure(LockedCaptureCameraError.sessionDidNotStart)
        }
        return .success(())
    }

    private func configureZoom(for device: AVCaptureDevice, requestedZoom: Double) throws {
        let minimumZoom = Double(device.minAvailableVideoZoomFactor)
        let maximumZoom = Double(device.maxAvailableVideoZoomFactor)
        let clampedZoom = min(max(requestedZoom, minimumZoom), maximumZoom)

        try device.lockForConfiguration()
        device.videoZoomFactor = CGFloat(clampedZoom)
        device.unlockForConfiguration()
    }

    private func makePhotoSettings() throws -> AVCapturePhotoSettings {
        guard photoOutput.isDepthDataDeliverySupported,
              photoOutput.isDepthDataDeliveryEnabled else {
            throw LockedCaptureCameraError.depthDeliveryNotEnabled
        }
        guard photoOutput.availablePhotoFileTypes.contains(.heic) else {
            throw LockedCaptureCameraError.heicFileTypeUnsupported
        }
        guard photoOutput.supportedPhotoCodecTypes(for: .heic).contains(.hevc)
                || photoOutput.availablePhotoCodecTypes.contains(.hevc) else {
            throw LockedCaptureCameraError.hevcCodecUnsupported
        }

        let processedFormat: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: 0.95
            ]
        ]
        let settings = AVCapturePhotoSettings(
            rawPixelFormatType: 0,
            rawFileType: nil,
            processedFormat: processedFormat,
            processedFileType: .heic
        )
        settings.isDepthDataDeliveryEnabled = true
        settings.embedsDepthDataInPhoto = true
        settings.isDepthDataFiltered = true
        settings.flashMode = .off

        switch photoOutput.maxPhotoQualityPrioritization {
        case .quality:
            settings.photoQualityPrioritization = .quality
        case .balanced:
            settings.photoQualityPrioritization = .balanced
        case .speed:
            settings.photoQualityPrioritization = .speed
        @unknown default:
            settings.photoQualityPrioritization = .balanced
        }

        return settings
    }

    @MainActor
    private func handlePhotoCaptureResult(_ result: LockedPhotoCaptureResult) {
        sessionQueue.async { [weak self] in
            self?.inFlightPhotoDelegates[result.captureID] = nil
        }

        switch result.outcome {
        case .success(let output):
            lastCaptureSucceeded = true
            setState(.live("Saved \(output.photoFileName)."))
            let contentSnapshot = LockedSessionContentDirectoryProbe.snapshot(
                in: output.sessionContentURL
            )
            Self.logger.info(
                "photo_capture_saved captureID=\(result.captureID, privacy: .public) bytes=\(output.byteCount, privacy: .public) photo=\(output.photoURL.path, privacy: .private(mask: .hash)) captureDirectoryCount=\(contentSnapshot.captureDirectoryCount, privacy: .public) flatHEICFileCount=\(contentSnapshot.flatHEICFileCount, privacy: .public) metadataFileCount=\(contentSnapshot.metadataFileCount, privacy: .public) unsignedHEICFileCount=\(contentSnapshot.unsignedHEICFileCount, privacy: .public) latestCaptureID=\(contentSnapshot.latestCaptureID ?? "none", privacy: .public)"
            )
        case .failure(let error):
            lastCaptureSucceeded = false
            setState(.live("Capture failed."))
            Self.logger.error(
                "photo_capture_failed captureID=\(result.captureID, privacy: .public) error=\(Self.describe(error), privacy: .public)"
            )
        }
    }

    @MainActor
    private func handleVideoFrame() {
        let now = Date()
        if lastFrameAt == nil {
            Self.logger.info(
                "first_frame sessionRunning=\(self.captureSession.isRunning, privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public)"
            )
        }
        lastFrameAt = now
        waitingForFirstFrameSince = nil
        frameRecoveryAttemptCount = 0

        switch state {
        case .starting, .recovering:
            setState(.live("Viewfinder live."))
        case .live, .capturing, .unavailable:
            break
        }
    }

    private func installSessionObserversIfNeeded() {
        guard observers.isEmpty else {
            return
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] notification in
                let reason = Self.interruptionReasonDescription(from: notification)
                Task { @MainActor [weak self] in
                    self?.handleWasInterrupted(reason: reason)
                }
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] notification in
                let isRunning = (notification.object as? AVCaptureSession)?.isRunning ?? false
                Task { @MainActor [weak self] in
                    self?.handleInterruptionEnded(sessionWasRunning: isRunning)
                }
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] notification in
                let errorDescription = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)
                    .map { "\($0.domain)(\($0.code))" }
                    ?? "unknown"
                Task { @MainActor [weak self] in
                    self?.handleRuntimeError(errorDescription: errorDescription)
                }
            }
        ]
    }

    @MainActor
    private func handleWasInterrupted(reason: String) {
        Self.logger.error(
            "session_interrupted reason=\(reason, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public)"
        )
        setState(.recovering("Camera interrupted: \(reason)."))
    }

    @MainActor
    private func handleInterruptionEnded(sessionWasRunning: Bool) {
        Self.logger.info(
            "session_interruption_ended notificationSessionRunning=\(sessionWasRunning, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public)"
        )
        restartActiveSession(reason: "interruption_ended")
    }

    @MainActor
    private func handleRuntimeError(errorDescription: String) {
        Self.logger.error(
            "session_runtime_error error=\(errorDescription, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public)"
        )
        restartActiveSession(reason: "runtime_error")
    }

    @MainActor
    private func restartActiveSession(reason: String) {
        guard isActive, let activeLens else {
            setUnavailable("Camera stopped before recovery could start.")
            return
        }

        Task {
            await configureAndStartSession(lens: activeLens, reason: reason)
        }
    }

    @MainActor
    private func startFrameWatchdogIfNeeded() {
        guard frameWatchdogTask == nil else {
            return
        }

        frameWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.evaluateFrameWatchdog()
            }
        }
    }

    @MainActor
    private func evaluateFrameWatchdog() {
        guard isActive else {
            return
        }

        switch state {
        case .live, .capturing:
            guard let lastFrameAt else {
                recoverFromFrameWatchdogMiss(
                    reason: "no_frame_watchdog",
                    message: "Waiting for viewfinder frame."
                )
                return
            }
            let age = Date().timeIntervalSince(lastFrameAt)
            if age > Self.frameWatchdogThreshold {
                Self.logger.error(
                    "frame_watchdog_missed age=\(age, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public)"
                )
                recoverFromFrameWatchdogMiss(
                    reason: "frame_watchdog",
                    message: "Viewfinder stopped."
                )
            }
        case .starting, .recovering:
            if lastFrameAt == nil {
                let waitAge = Date().timeIntervalSince(waitingForFirstFrameSince ?? Date())
                Self.logger.info(
                    "first_frame_watchdog_waiting age=\(waitAge, privacy: .public) state=\(self.state.message, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public)"
                )
                guard waitAge > Self.frameWatchdogThreshold else {
                    return
                }
                recoverFromFrameWatchdogMiss(
                    reason: "first_frame_watchdog",
                    message: "Viewfinder did not deliver a frame."
                )
            }
        case .unavailable:
            break
        }
    }

    @MainActor
    private func recoverFromFrameWatchdogMiss(reason: String, message: String) {
        frameRecoveryAttemptCount += 1
        Self.logger.error(
            "frame_watchdog_recovery_attempt reason=\(reason, privacy: .public) attempt=\(self.frameRecoveryAttemptCount, privacy: .public) maxAttempts=\(Self.maximumFrameRecoveryAttempts, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public) previewInWindow=\(self.previewLayerInWindow, privacy: .public) previewHasSuperlayer=\(self.previewLayerHasSuperlayer, privacy: .public)"
        )

        guard frameRecoveryAttemptCount <= Self.maximumFrameRecoveryAttempts else {
            setUnavailable("\(message) Unlock to continue.")
            return
        }

        setState(.recovering(message))
        restartActiveSession(reason: reason)
    }

    @MainActor
    private func setUnavailable(_ message: String) {
        Self.logger.error(
            "camera_unavailable message=\(message, privacy: .public) isRunning=\(self.captureSession.isRunning, privacy: .public) lastFrameAge=\(self.lastFrameAgeDescription(), privacy: .public)"
        )
        setState(.unavailable(message))
    }

    @MainActor
    private func setState(_ newState: LockedCaptureCameraState) {
        state = newState
    }

    @MainActor
    private func lastFrameAgeDescription() -> String {
        guard let lastFrameAt else {
            return "none"
        }
        return String(format: "%.2fs", Date().timeIntervalSince(lastFrameAt))
    }

    private static func resolveDevice(for lens: TAPCamLockedCameraLensRecord) -> AVCaptureDevice? {
        let deviceType = AVCaptureDevice.DeviceType(rawValue: lens.captureDeviceTypeRawValue)
        let position = AVCaptureDevice.Position(tapLockedCameraRawValue: lens.captureDevicePosition)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [deviceType],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first(where: { $0.uniqueID == lens.captureDeviceUniqueID })
    }

    private static func interruptionReasonDescription(from notification: Notification) -> String {
        let rawValue = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        guard let rawValue else {
            return "unknown"
        }
        return "rawValue=\(rawValue)"
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }

    private static func lensLabel(for lens: TAPCamLockedCameraLensRecord) -> String {
        "\(lens.numericLabel)\(lens.unitLabel)"
    }
}

nonisolated extension LockedCaptureCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { @MainActor in
            self.handleVideoFrame()
        }
    }
}

private enum LockedCaptureCameraError: LocalizedError {
    case controllerReleased
    case deviceNotFound(String)
    case cannotAddInput(String)
    case cannotAddVideoOutput
    case cannotAddPhotoOutput
    case depthDeliveryUnsupported
    case depthDeliveryNotEnabled
    case heicFileTypeUnsupported
    case hevcCodecUnsupported
    case sessionDidNotStart
    case missingPhotoData
    case missingDepthData

    var errorDescription: String? {
        switch self {
        case .controllerReleased:
            "Camera controller was released."
        case .deviceNotFound(let deviceType):
            "Capture device not found: \(deviceType)."
        case .cannotAddInput(let deviceName):
            "Cannot add camera input: \(deviceName)."
        case .cannotAddVideoOutput:
            "Cannot add video output."
        case .cannotAddPhotoOutput:
            "Cannot add photo output."
        case .depthDeliveryUnsupported:
            "Depth delivery is not supported for the selected locked-camera lens."
        case .depthDeliveryNotEnabled:
            "Depth delivery is not enabled for locked-camera capture."
        case .heicFileTypeUnsupported:
            "HEIC photo output is not available for locked-camera capture."
        case .hevcCodecUnsupported:
            "HEVC photo codec is not available for locked-camera capture."
        case .sessionDidNotStart:
            "Capture session did not start."
        case .missingPhotoData:
            "Photo data is missing."
        case .missingDepthData:
            "Captured photo does not contain depth data."
        }
    }
}

private struct LockedPhotoCaptureRequest: Sendable {
    let captureID: String
    let capturedAt: Date
    let sessionContentURL: URL
    let lens: TAPCamLockedCameraLensRecord
}

private struct LockedPhotoCaptureOutput: Sendable {
    let sessionContentURL: URL
    let photoURL: URL
    let metadataURL: URL
    let photoFileName: String
    let byteCount: Int
}

private struct LockedProcessedPhoto: Sendable {
    let data: Data
    let depthDataType: UInt32
    let isDepthDataFiltered: Bool
    let resolvedPhotoWidth: Int
    let resolvedPhotoHeight: Int
}

private struct LockedPhotoCaptureResult: Sendable {
    let captureID: String
    let outcome: Result<LockedPhotoCaptureOutput, Error>
}

nonisolated private final class LockedPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let request: LockedPhotoCaptureRequest
    private let completion: @Sendable (LockedPhotoCaptureResult) -> Void
    private var photoResult: Result<LockedProcessedPhoto, Error>?
    private var didFinishCapture = false
    private var didComplete = false

    init(
        request: LockedPhotoCaptureRequest,
        completion: @escaping @Sendable (LockedPhotoCaptureResult) -> Void
    ) {
        self.request = request
        self.completion = completion
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            photoResult = .failure(error)
        } else {
            guard let depthData = photo.depthData else {
                photoResult = .failure(LockedCaptureCameraError.missingDepthData)
                completeIfReady()
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                photoResult = .failure(LockedCaptureCameraError.missingPhotoData)
                completeIfReady()
                return
            }

            let dimensions = photo.resolvedSettings.photoDimensions
            photoResult = .success(LockedProcessedPhoto(
                data: data,
                depthDataType: depthData.depthDataType,
                isDepthDataFiltered: depthData.isDepthDataFiltered,
                resolvedPhotoWidth: Int(dimensions.width),
                resolvedPhotoHeight: Int(dimensions.height)
            ))
        }
        completeIfReady()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error, photoResult == nil {
            photoResult = .failure(error)
        }
        didFinishCapture = true
        completeIfReady()
    }

    private func completeIfReady() {
        guard !didComplete, didFinishCapture, let photoResult else {
            return
        }
        didComplete = true

        switch photoResult {
        case .success(let photo):
            completion(LockedPhotoCaptureResult(
                captureID: request.captureID,
                outcome: Result {
                    try writeCapture(photo: photo)
                }
            ))
        case .failure(let error):
            completion(LockedPhotoCaptureResult(captureID: request.captureID, outcome: .failure(error)))
        }
    }

    private func writeCapture(photo: LockedProcessedPhoto) throws -> LockedPhotoCaptureOutput {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: request.sessionContentURL,
            withIntermediateDirectories: true
        )

        let photoFileName = TAPCamLockedSessionContentPathPolicy.flatHEICFileName(
            captureID: request.captureID
        )
        let photoURL = TAPCamLockedSessionContentPathPolicy.flatHEICURL(
            sessionContentURL: request.sessionContentURL,
            captureID: request.captureID
        )
        try photo.data.write(to: photoURL, options: [.atomic])

        return LockedPhotoCaptureOutput(
            sessionContentURL: request.sessionContentURL,
            photoURL: photoURL,
            metadataURL: photoURL,
            photoFileName: photoFileName,
            byteCount: photo.data.count
        )
    }
}

private struct LockedSessionContentDirectorySnapshot: Sendable {
    var captureDirectoryCount: Int
    var flatHEICFileCount: Int
    var metadataFileCount: Int
    var unsignedHEICFileCount: Int
    var latestCaptureID: String?
}

private enum LockedSessionContentDirectoryProbe {
    static func snapshot(in sessionContentURL: URL) -> LockedSessionContentDirectorySnapshot {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sessionContentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return LockedSessionContentDirectorySnapshot(
                captureDirectoryCount: 0,
                flatHEICFileCount: 0,
                metadataFileCount: 0,
                unsignedHEICFileCount: 0,
                latestCaptureID: nil
            )
        }

        var captureDirectoryCount = 0
        var flatHEICFileCount = 0
        var metadataFileCount = 0
        var unsignedHEICFileCount = 0
        var latestCapture: (id: String, modifiedAt: Date)?

        for url in urls {
            let resourceValues = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
            )
            if resourceValues?.isDirectory == true,
               url.lastPathComponent != TAPCamLockedSessionContentPathPolicy.legacyCapturesDirectoryName {
                captureDirectoryCount += 1
                let metadataURL = TAPCamLockedSessionContentPathPolicy.metadataURL(in: url)
                let photoURL = TAPCamLockedSessionContentPathPolicy.unsignedPhotoURL(in: url)
                if FileManager.default.fileExists(atPath: metadataURL.path) {
                    metadataFileCount += 1
                }
                if FileManager.default.fileExists(atPath: photoURL.path) {
                    unsignedHEICFileCount += 1
                }
                let modifiedAt = resourceValues?.contentModificationDate ?? .distantPast
                if latestCapture == nil || modifiedAt > latestCapture!.modifiedAt {
                    latestCapture = (url.lastPathComponent, modifiedAt)
                }
            } else if resourceValues?.isRegularFile == true,
                      url.pathExtension.caseInsensitiveCompare("heic") == .orderedSame {
                flatHEICFileCount += 1
            }
        }

        return LockedSessionContentDirectorySnapshot(
            captureDirectoryCount: captureDirectoryCount,
            flatHEICFileCount: flatHEICFileCount,
            metadataFileCount: metadataFileCount,
            unsignedHEICFileCount: unsignedHEICFileCount,
            latestCaptureID: latestCapture?.id
        )
    }
}

private extension AVCaptureDevice.Position {
    nonisolated init(tapLockedCameraRawValue: String) {
        switch tapLockedCameraRawValue {
        case "front":
            self = .front
        case "back":
            self = .back
        default:
            self = .unspecified
        }
    }
}

private extension JSONEncoder {
    nonisolated static var tapLockedCamera: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
