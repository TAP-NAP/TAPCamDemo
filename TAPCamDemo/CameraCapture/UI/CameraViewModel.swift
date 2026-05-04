//
//  CameraViewModel.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Combine
import Foundation
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
    @Published var isPausedForAnalysis = false
    @Published var nativePreviewAspectRatio = 3.0 / 4.0
    @Published var previewCropRectNormalized = CropRectNormalized.fullFrame
    @Published var recentThumbnail: UIImage?
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
    let pipeline: CapturePipeline
    var activeSessionConfiguration: SessionConfigurationResult?
    var configurationGeneration = 0
    var depthSelectionMode: DepthSelectionMode = .automatic

    var session: AVCaptureSession {
        sessionController.session
    }

    var canCapture: Bool {
        !isPausedForAnalysis && isDepthCaptureReady && pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs
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

    init(
        capabilityMatrix: CapabilityMatrix = CameraCapabilityResolver.discover(),
        sessionController: CaptureSessionController = CaptureSessionController()
    ) {
        self.capabilityMatrix = capabilityMatrix
        self.sessionController = sessionController
        self.focalLengthOptions = capabilityMatrix.focalLengthOptions()
        #if DEBUG
        self.debugDepthDeviceOptions = capabilityMatrix.debugDepthDeviceOptions()
        #endif

        let provider = AVFoundationSingleCamPhotoProvider(sessionController: sessionController)
        self.pipeline = CapturePipeline(
            photoDepthProvider: provider,
            metricsStore: metricsStore
        )
    }

    func start() async {
        StartupTrace.mark("CameraViewModel.start begin")
        defer {
            StartupTrace.mark("CameraViewModel.start end")
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await StartupTrace.measureAsync("CameraViewModel.configureDefaultSelection authorized") {
                await configureDefaultSelection()
            }
            StartupTrace.measure("LocationProvider.warmLocationCache") {
                locationProvider.warmLocationCache()
            }
            StartupTrace.measure("CameraViewModel.loadRecentDepthAssetPreviewIfAvailable") {
                loadRecentDepthAssetPreviewIfAvailable()
            }
        case .notDetermined:
            let granted = await StartupTrace.measureAsync("AVCaptureDevice.requestAccess video") {
                await AVCaptureDevice.requestAccess(for: .video)
            }
            if granted {
                await StartupTrace.measureAsync("CameraViewModel.configureDefaultSelection after authorization") {
                    await configureDefaultSelection()
                }
                StartupTrace.measure("LocationProvider.warmLocationCache") {
                    locationProvider.warmLocationCache()
                }
                StartupTrace.measure("CameraViewModel.loadRecentDepthAssetPreviewIfAvailable") {
                    loadRecentDepthAssetPreviewIfAvailable()
                }
            } else {
                statusMessage = TAPDepthCaptureError.cameraAccessDenied.localizedDescription
            }
        case .denied, .restricted:
            statusMessage = TAPDepthCaptureError.cameraAccessDenied.localizedDescription
        @unknown default:
            statusMessage = TAPDepthCaptureError.cameraAccessDenied.localizedDescription
        }
    }

    func stop() {
        StartupTrace.mark("CameraViewModel.stop")
        isPausedForAnalysis = false
        sessionController.stop()
    }

    func pauseForAnalysis() {
        configurationGeneration += 1
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
            locationProvider.warmLocationCache()
            loadRecentDepthAssetPreviewIfAvailable()
        case .notDetermined:
            await start()
        case .denied, .restricted:
            statusMessage = TAPDepthCaptureError.cameraAccessDenied.localizedDescription
        @unknown default:
            statusMessage = TAPDepthCaptureError.cameraAccessDenied.localizedDescription
        }
    }

    func updatePreviewCropRect(_ rect: CropRectNormalized) {
        guard previewCropRectNormalized != rect else { return }
        previewCropRectNormalized = rect
    }

}
