@preconcurrency import AVFoundation
import Combine
import Foundation

enum GeekModeCamera: Hashable {
    case rear, front
    var title: String { self == .rear ? "Rear · 24 mm" : "Front" }
}

/// Owns the demo's lifetime. Photos still use the shared capture, packaging and
/// pending-signing pipeline; projected preview pixels never enter that pipeline.
@MainActor
final class GeekModeCaptureController: ObservableObject {
    let sessionController = CaptureSessionController()
    let pointCloudStore = TAPVideoPointCloudStore()
    private(set) lazy var pointCloudStream: GeekModePointCloudStream = {
        let stream = GeekModePointCloudStream(store: pointCloudStore)
        stream.onFrameAvailabilityChanged = { [weak self] available in
            self?.depthAvailable = available
            if available { self?.hasPointCloud = true }
        }
        return stream
    }()
    @Published private(set) var isPreparing = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isReady = false
    @Published private(set) var hasPointCloud = false
    @Published private(set) var depthAvailable = false
    @Published private(set) var message: String?
    @Published private(set) var sourceRevision = 0
    @Published private(set) var previewAspectRatio = 3.0 / 4.0

    private let capturePlans: GeekModeCapturePlan
    private let locationProvider = LocationProvider()
    private let metricsStore = MetricsStore()
    private lazy var pipeline = CapturePipeline(
        photoDepthProvider: AVFoundationSingleCamPhotoProvider(sessionController: sessionController),
        metricsStore: metricsStore
    )
    private var configuration: SessionConfigurationResult?
    private var generation = 0
    private var wantsCamera = false
    private var deferredCamera: GeekModeCamera?

    init(capabilities: CapabilityMatrix) {
        capturePlans = GeekModeCapturePlan(capabilities: capabilities)
        sessionController.setRuntimeFailureHandler { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspend()
                self?.message = "Camera interrupted. Reopen Playground to retry."
            }
        }
    }

    var canCapture: Bool { isReady && depthAvailable && !isPreparing && !isCapturing }
    var hasFrontCamera: Bool { plan(for: .front) != nil }

    func prepare(_ camera: GeekModeCamera) async {
        wantsCamera = true
        if isCapturing {
            deferredCamera = camera
            return
        }
        generation += 1
        let requestGeneration = generation
        isPreparing = true
        isReady = false
        message = nil
        configuration = nil
        pointCloudStream.setActive(false)
        sessionController.stop()
        await sessionController.waitUntilSessionQueueIsResponsive()
        guard isCurrent(requestGeneration) else { return }
        sourceRevision += 1
        hasPointCloud = false
        depthAvailable = false
        pointCloudStream.reset()
        sessionController.setSceneActive(true)

        defer {
            if generation == requestGeneration { isPreparing = false }
        }
        do {
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                throw TAPDepthCaptureError.cameraAccessDenied
            }
            guard let plan = plan(for: camera) else {
                throw TAPDepthCaptureError.noDepthCameraAvailable
            }
            let format = CameraOutputFormatPreference.resolved(
                rawValue: UserDefaults.standard.string(forKey: CameraOutputFormatPreference.storageKey)
                    ?? CameraOutputFormatPreference.defaultValue.rawValue
            )
            let output = format.selectionIntent.resolved()
            guard output.isExecutable, let profile = output.selectedProfile else {
                throw TAPDepthCaptureError.depthDeliveryUnsupported
            }
            let configured = try await sessionController.configure(
                SessionConfigurationRequest(capturePlan: plan, outputProfile: profile)
            )
            guard isCurrent(requestGeneration) else { return }
            try await sessionController.restoreAutoPhotoControls(globalExposureBias: 0, to: configured.device)
            guard isCurrent(requestGeneration) else { return }
            configuration = configured
            previewAspectRatio = configured.nativePreviewAspectRatio

            let rotation = AVCaptureDevice.RotationCoordinator(device: configured.device, previewLayer: nil)
                .videoRotationAngleForHorizonLevelCapture
            let mirrored = camera == .front
            let stream = pointCloudStream
            stream.setActive(true)
            do {
                try await sessionController.prepareGeekModePreview(
                    configuration: configured,
                    videoRotationAngle: rotation,
                    isVideoMirrored: mirrored
                ) { video, depth in
                    stream.consume(video: video, depth: depth, rotationDegrees: Double(rotation), mirrored: mirrored)
                }
            } catch {
                guard isCurrent(requestGeneration) else { return }
                stream.setActive(false)
                message = "Live 3D unavailable. Switch cameras or reopen Playground to retry."
                return
            }
            guard isCurrent(requestGeneration) else { return }
            isReady = configured.depthDeliverySupported && configured.capturePlan.canCapturePhotoDepth
            if CameraCaptureDataUsePreferences.usesLocationData() { locationProvider.warmLocationCache() }
        } catch {
            guard isCurrent(requestGeneration) else { return }
            message = CameraCaptureStatusPresentation.message(for: error, context: .configuration)
        }
    }

    func capture(client: any AppAttestClient) async {
        guard canCapture, let configuration else { return }
        isCapturing = true
        message = nil
        pointCloudStream.setFrozen(true)
        let usesLocation = CameraCaptureDataUsePreferences.usesLocationData()
        let job = CaptureJob()
        let context = CaptureSourceContext(
            sessionConfiguration: PreCaptureConfigurationBuilder.configuration(
                from: configuration, previewCropRectNormalized: .fullFrame
            ),
            capturedAt: job.createdAt,
            location: usesLocation ? locationProvider.cachedCaptureLocation() : nil,
            suppressesShutterSound: CameraFeedbackPreferences.shouldSuppressShutterSound(
                storedIsEnabled: UserDefaults.standard.object(forKey: CameraFeedbackPreferences.shutterSoundEnabledKey)
                    as? Bool ?? CameraFeedbackPreferences.defaultShutterSoundEnabled,
                suppressionSupported: sessionController.isShutterSoundSuppressionSupported
            ),
            flashMode: .off,
            livePhotoRequest: .disabled
        )
        let result = await pipeline.runSingleCamJob(job: job, context: context, queueWaitDuration: 0)
        isCapturing = false
        pointCloudStream.setFrozen(false)
        switch result {
        case .success(let capture):
            message = capture.depthAvailability == .unavailable
                ? "Captured · Depth unavailable" : "Captured · Queued for signing"
            // Signing/export outlives this page and never extends the shutter freeze.
            Task {
                await TAPPendingCaptureProcessor.shared.processPendingCaptures(
                    store: .shared, appAttestClient: client
                )
            }
        case .failure(let error):
            message = CameraCaptureStatusPresentation.message(for: error, context: .capture)
        }
        if wantsCamera, let deferredCamera {
            self.deferredCamera = nil
            await prepare(deferredCamera)
        }
    }

    func suspend() {
        wantsCamera = false
        deferredCamera = nil
        generation += 1
        isPreparing = false
        isReady = false
        depthAvailable = false
        pointCloudStream.setActive(false)
        sessionController.setSceneActive(false)
        sessionController.pause()
    }

    func stop() async {
        suspend()
        sessionController.stop()
        await sessionController.waitUntilSessionQueueIsResponsive()
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        wantsCamera && generation == requestGeneration && !Task.isCancelled
    }

    private func plan(for camera: GeekModeCamera) -> CaptureSourcePlan? {
        camera == .rear ? capturePlans.rear : capturePlans.front
    }
}
