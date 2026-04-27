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

/// Observable state for the v0.8 camera screen.
///
/// This view model is the presentation boundary for
/// `UI selection -> CapabilityMatrix -> RGBDepthPairingCoordinator ->
/// CaptureSessionController -> CapturePipeline`. SwiftUI reads profiles and
/// status values from here; it never inspects `AVCaptureDevice` directly.
@MainActor
final class CameraViewModel: ObservableObject {
    let sessionController: CaptureSessionController

    @Published private(set) var rgbSourceProfiles: [CameraProfile]
    @Published private(set) var focalLengthOptions: [FocalLengthOption]
    @Published private(set) var depthProfiles: [DepthProfile] = []
    @Published private(set) var zoomProfiles: [ZoomProfile] = []
    @Published private(set) var selectedFocalLengthOptionID: String?
    @Published private(set) var selectedRGBSourceID: String?
    @Published private(set) var selectedDepthProfileID: String?
    @Published private(set) var selectedZoomID: String?
    @Published private(set) var activeCameraDisplayName = "Preparing camera..."
    @Published private(set) var statusMessage = "Preparing capture session..."
    @Published private(set) var pendingJobCount = 0
    @Published private(set) var recentMetrics: [CaptureJobMetrics] = []
    @Published private(set) var isDepthCaptureReady = false
    @Published private(set) var nativePreviewAspectRatio = 3.0 / 4.0
    @Published private(set) var previewCropRectNormalized = CropRectNormalized.fullFrame
    @Published private(set) var recentThumbnail: UIImage?
    #if DEBUG
    @Published private(set) var debugDepthDeviceOptions: [DebugDepthDeviceOption]
    @Published private(set) var debugSelectedDepthDeviceID: String?
    @Published private(set) var debugZoomProfiles: [ZoomProfile] = []
    @Published private(set) var debugZoomCapability: ZoomCapability?
    @Published private(set) var debugSelectedZoomID: String?
    @Published private(set) var debugSelectedZoomFactor: Double = 1.0
    @Published private(set) var debugFOVLabel = "24mm"
    @Published private(set) var isDebugDepthOverrideActive = false
    #endif

    private let capabilityMatrix: CapabilityMatrix
    private let locationProvider = LocationProvider()
    private let jobQueue = CaptureJobQueue()
    private let metricsStore = MetricsStore()
    private let pipeline: CapturePipeline
    private var activeSessionConfiguration: SessionConfigurationResult?
    private var configurationGeneration = 0
    private var depthSelectionMode: DepthSelectionMode = .automatic

    var session: AVCaptureSession {
        sessionController.session
    }

    var canCapture: Bool {
        isDepthCaptureReady && pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs
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

    #if DEBUG
    var debugZoomSliderRange: ClosedRange<Double> {
        let ranges = debugZoomCapability?.depthSafeZoomRanges ?? []
        guard let lower = ranges.map(\.lowerBound).min(),
              let upper = ranges.map(\.upperBound).max(),
              lower < upper else {
            return 1.0...1.0
        }
        return lower...upper
    }

    var debugZoomSliderEnabled: Bool {
        debugZoomCapability?.isContinuous == true && debugZoomSliderRange.lowerBound < debugZoomSliderRange.upperBound
    }

    #endif

    init(
        capabilityMatrix: CapabilityMatrix = CameraCapabilityResolver.discover(),
        sessionController: CaptureSessionController = CaptureSessionController()
    ) {
        self.capabilityMatrix = capabilityMatrix
        self.sessionController = sessionController
        self.rgbSourceProfiles = capabilityMatrix.rgbSources
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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await configureDefaultSelection()
            loadRecentDepthAssetPreviewIfAvailable()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureDefaultSelection()
                loadRecentDepthAssetPreviewIfAvailable()
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
        sessionController.stop()
    }

    func updatePreviewCropRect(_ rect: CropRectNormalized) {
        guard previewCropRectNormalized != rect else { return }
        previewCropRectNormalized = rect
    }

    func selectRGBSource(_ profile: CameraProfile) async {
        guard profile.isEnabled else {
            statusMessage = profile.disabledReason ?? TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        selectedRGBSourceID = profile.id
        await configureCurrentSelection()
    }

    func selectFocalLengthOption(_ option: FocalLengthOption) async {
        guard option.isEnabled else {
            statusMessage = option.disabledReason ?? TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        depthSelectionMode = .automatic
        selectedDepthProfileID = nil
        selectedRGBSourceID = option.rgbSource.id
        selectedZoomID = option.zoom.id
        selectedFocalLengthOptionID = option.id
        FOVDiagnostics.logFocalSelection(option)
        await configureCurrentSelection()
    }

    func selectDepthProfile(_ profile: DepthProfile) async {
        guard profile.isSelectable else {
            statusMessage = profile.disabledReason ?? TAPDepthCaptureError.incompatibleRGBDepthPairing.localizedDescription
            return
        }

        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        depthSelectionMode = .manual
        selectedDepthProfileID = profile.id
        await configureCurrentSelection()
    }

    func selectZoom(_ zoom: ZoomProfile) async {
        guard zoom.isEnabled else {
            statusMessage = zoom.disabledReason ?? TAPDepthCaptureError.unsupportedZoomFactor.localizedDescription
            return
        }

        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        selectedZoomID = zoom.id
        await configureCurrentSelection()
    }

    #if DEBUG
    func selectDebugDepthDevice(_ option: DebugDepthDeviceOption) async {
        guard option.isSelectable,
              let rgbSource = option.rgbSource,
              let device = option.device else {
            statusMessage = option.disabledReason ?? TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        /*
         Picking a Debug depth device is a lens/source switch. It should start at
         that device's native 1x framing instead of inheriting a previous Debug
         or Release zoom. The format selection is therefore resolved against 1x
         before the override plan is built.
         */
        let initialZoomFactor = 1.0
        let initialFormatSelection = CameraCapabilityResolver.bestDepthFormatSelection(
            for: device,
            preferredZoomFactor: initialZoomFactor
        ) ?? option.formatSelection

        guard let initialFormatSelection,
              let depthProfile = option.depthProfile(formatSelection: initialFormatSelection) else {
            statusMessage = option.disabledReason ?? TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        /*
         Debug depth selection is an override of the single-cam capture pipeline,
         not a second device layered on top of the Release FOV selection. The
         selected depth-capable device becomes the source for preview, RGB photo,
         and `AVCapturePhoto.depthData`, which keeps the Apple paired-depth
         guarantees intact while we explore hardware behavior.
         */
        let zoomCapability = ZoomCapabilityResolver.resolve(
            rgbSource: rgbSource,
            depthProfile: depthProfile,
            selectedZoomID: nil,
            selectedZoomFactor: initialZoomFactor
        )
        let preferredZoom = zoomCapability.zoomProfiles.first { $0.isEnabled && abs($0.requestedZoomFactor - initialZoomFactor) < 0.001 }
            ?? zoomCapability.zoomProfiles.first(where: \.isEnabled)

        isDebugDepthOverrideActive = true
        depthSelectionMode = .debugDepthOverride
        selectedRGBSourceID = rgbSource.id
        selectedDepthProfileID = nil
        selectedZoomID = nil
        selectedFocalLengthOptionID = nil
        debugSelectedDepthDeviceID = option.id
        debugSelectedZoomID = preferredZoom?.id
        debugSelectedZoomFactor = preferredZoom?.actualVideoZoomFactor ?? preferredZoom?.requestedZoomFactor ?? initialZoomFactor
        debugZoomCapability = zoomCapability
        debugZoomProfiles = zoomCapability.zoomProfiles
        await configureCurrentSelection()
    }

    func selectDebugZoom(_ zoom: ZoomProfile) async {
        guard zoom.isEnabled else {
            statusMessage = zoom.disabledReason ?? TAPDepthCaptureError.unsupportedZoomFactor.localizedDescription
            return
        }

        isDebugDepthOverrideActive = true
        let isFixedCandidate = CameraCapabilityResolver.candidateZoomFactors
            .contains { abs($0 - zoom.requestedZoomFactor) < 0.001 }
        debugSelectedZoomID = isFixedCandidate ? zoom.id : nil
        debugSelectedZoomFactor = zoom.actualVideoZoomFactor ?? zoom.requestedZoomFactor
        await configureCurrentSelection()
    }

    func selectDebugZoomFactor(_ zoomFactor: Double) async {
        guard let capability = debugZoomCapability else {
            statusMessage = TAPDepthCaptureError.unsupportedZoomFactor.localizedDescription
            return
        }

        isDebugDepthOverrideActive = true
        let clamped = depthSafeZoomFactor(zoomFactor, capability: capability)
        debugSelectedZoomID = nil
        debugSelectedZoomFactor = clamped
        await configureCurrentSelection()
    }
    #endif

    func switchCameraPosition() async {
        #if DEBUG
        clearDebugDepthOverrideState()
        #endif
        let current = capabilityMatrix.rgbSource(id: selectedRGBSourceID)
        let targetPosition: AVCaptureDevice.Position = current?.device.position == .front ? .back : .front

        if targetPosition == .front {
            guard let target = defaultRGBSource(position: .front) else {
                statusMessage = TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
                return
            }

            selectedRGBSourceID = target.id
            selectedZoomID = nil
            selectedFocalLengthOptionID = nil
        } else {
            let options = capabilityMatrix.focalLengthOptions()
            let target = capabilityMatrix.bestOption(nearEquivalentMillimeters: 24, in: options)
                ?? capabilityMatrix.defaultFocalLengthOption

            guard let target else {
                statusMessage = TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
                return
            }

            selectedRGBSourceID = target.rgbSource.id
            selectedZoomID = target.zoom.id
            selectedFocalLengthOptionID = target.id
        }

        depthSelectionMode = .automatic
        selectedDepthProfileID = nil
        await configureCurrentSelection()
    }

    func capture() async {
        guard let activeSessionConfiguration else {
            statusMessage = TAPDepthCaptureError.depthDeliveryUnsupported.localizedDescription
            return
        }

        guard let captureConfiguration = configurationForCurrentCapture(from: activeSessionConfiguration),
              captureConfiguration.capturePlan.canCapturePhotoDepth else {
            statusMessage = TAPDepthCaptureError.incompatibleRGBDepthPairing.localizedDescription
            return
        }

        guard pendingJobCount < CaptureJobQueue.defaultMaximumPendingJobs else {
            statusMessage = TAPDepthCaptureError.captureBackpressureLimitReached.localizedDescription
            return
        }

        let queueEnteredAt = Date()
        let job = CaptureJob()

        do {
            let pendingCount = try await jobQueue.beginJob()
            pendingJobCount = pendingCount
            statusMessage = "Capture queued..."

            let location = await locationProvider.requestOneShotLocation()
            let context = CaptureSourceContext(
                sessionConfiguration: captureConfiguration,
                capturedAt: job.createdAt,
                location: location
            )
            let queueWaitDuration = Date().timeIntervalSince(queueEnteredAt)

            Task { [pipeline, jobQueue, metricsStore] in
                let result = await pipeline.runSingleCamJob(
                    job: job,
                    context: context,
                    pendingJobCount: pendingCount,
                    queueWaitDuration: queueWaitDuration
                )
                let remaining = await jobQueue.finishJob()
                let metrics = await metricsStore.recent()

                await MainActor.run {
                    self.pendingJobCount = remaining
                    self.recentMetrics = metrics
                    switch result {
                    case .success(let writeResult):
                        self.statusMessage = "Saved \(writeResult.destinationDescription)"
                        if let assetID = writeResult.assetLocalIdentifier {
                            self.loadRecentDepthAssetPreview(assetID: assetID)
                        }
                    case .failure(let error):
                        self.statusMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            pendingJobCount = await jobQueue.pendingCount()
        }
    }

    private func configureDefaultSelection() async {
        guard let option = capabilityMatrix.defaultFocalLengthOption else {
            if let frontSource = defaultRGBSource(position: .front) {
                selectedRGBSourceID = frontSource.id
                selectedFocalLengthOptionID = nil
                selectedDepthProfileID = nil
                selectedZoomID = nil
                depthSelectionMode = .automatic
                await configureCurrentSelection()
                return
            }

            isDepthCaptureReady = false
            statusMessage = TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }

        selectedRGBSourceID = option.rgbSource.id
        selectedFocalLengthOptionID = option.id
        selectedDepthProfileID = nil
        selectedZoomID = option.zoom.id
        depthSelectionMode = .automatic
        await configureCurrentSelection()
    }

    private func configureCurrentSelection() async {
        #if DEBUG
        if isDebugDepthOverrideActive,
           let plan = makeDebugDepthOverridePlan() {
            await configureDebugDepthOverride(plan)
            return
        }
        #endif

        guard let rgbSource = capabilityMatrix.rgbSource(id: selectedRGBSourceID) else {
            await configureDefaultSelection()
            return
        }

        let currentFocalLengthOptions = capabilityMatrix.focalLengthOptions()
        let selectedFocalLengthOption = selectedFocalLengthOptionID.flatMap { selectedID in
            currentFocalLengthOptions.first(where: { $0.id == selectedID })
        }
        let preferredZoomFactor = selectedFocalLengthOption?.zoom.requestedZoomFactor
        let depthRows = capabilityMatrix.depthProfiles(
            for: rgbSource,
            selectedKind: selectedDepthProfileID.flatMap(DepthProfileKind.init(rawValue:)),
            preferredZoomFactor: preferredZoomFactor
        )
        let depthProfile = selectedFocalLengthOption?.depthSource
            ?? resolvedDepthProfile(from: depthRows, selectedDepthProfileID: selectedDepthProfileID)
        /*
         Release FOV chips such as 48mm and 77mm are semantic framing choices,
         not always the same as the visible "2x/3x" zoom chips. Some Apple
         virtual depth formats expose their wide baseline at raw video zoom 2.0,
         so the 48mm slot can require raw zoom 4.0. Passing the Double keeps
         that non-standard factor alive when `ZoomCapabilityResolver` builds its
         runtime profile list; passing only `zoom-4x` would be lossy and would
         fall back to the first depth-safe zoom.
         */
        let plan = RGBDepthPairingCoordinator.makePlan(
            rgbSource: rgbSource,
            depthSource: depthProfile,
            selectionMode: depthSelectionMode,
            selectedZoomID: selectedZoomID,
            selectedZoomFactor: preferredZoomFactor,
            cropRectNormalized: previewCropRectNormalized
        )

        configurationGeneration += 1
        let generation = configurationGeneration
        isDepthCaptureReady = false
        rgbSourceProfiles = capabilityMatrix.rgbSources
        focalLengthOptions = currentFocalLengthOptions
        #if DEBUG
        debugDepthDeviceOptions = capabilityMatrix.debugDepthDeviceOptions()
        #endif
        depthProfiles = depthRows
        selectedRGBSourceID = rgbSource.id
        selectedDepthProfileID = depthProfile?.id
        zoomProfiles = plan.zoomCapability.zoomProfiles
        selectedZoomID = plan.zoom?.id
        selectedFocalLengthOptionID = rgbSource.device.position == .back
            ? focalLengthOptions.first { $0.rgbSource.id == rgbSource.id && $0.zoom.id == plan.zoom?.id }?.id
            : nil
        activeCameraDisplayName = "\(plan.requestedFocalLengthLabel.label) · \(depthProfile?.displayName ?? "No Depth")"
        statusMessage = statusText(for: plan)

        do {
            let result = try await sessionController.configure(SessionConfigurationRequest(capturePlan: plan))

            guard generation == configurationGeneration else {
                return
            }

            activeSessionConfiguration = result
            activeCameraDisplayName = result.cameraDisplayName
            nativePreviewAspectRatio = result.nativePreviewAspectRatio
            isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
            statusMessage = statusText(for: result.capturePlan)
        } catch {
            guard generation == configurationGeneration else {
                return
            }

            activeSessionConfiguration = nil
            isDepthCaptureReady = false
            nativePreviewAspectRatio = 3.0 / 4.0
            statusMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func makeDebugDepthOverridePlan() -> CaptureSourcePlan? {
        guard let option = debugDepthDeviceOptions.first(where: { $0.id == debugSelectedDepthDeviceID }),
              option.isSelectable,
              let rgbSource = option.rgbSource,
              let device = option.device else {
            return nil
        }

        /*
         Depth-safe zoom support belongs to the active video format, not just to
         the device. When the Debug zoom control moves to 2x/3x, re-resolve the
         depth format for that requested factor before building the plan. This
         prevents virtual devices such as Dual Wide/Triple/TrueDepth from briefly
         applying a zoom and then snapping back because the previously selected
         high-resolution format only supported depth at 1x.
         */
        let formatSelection = CameraCapabilityResolver.bestDepthFormatSelection(
            for: device,
            preferredZoomFactor: debugSelectedZoomFactor
        ) ?? option.formatSelection

        guard let formatSelection,
              let depthProfile = option.depthProfile(formatSelection: formatSelection) else {
            return nil
        }

        return RGBDepthPairingCoordinator.makePlan(
            rgbSource: rgbSource,
            depthSource: depthProfile,
            selectionMode: .debugDepthOverride,
            selectedZoomID: debugSelectedZoomID,
            selectedZoomFactor: debugSelectedZoomID == nil ? debugSelectedZoomFactor : nil,
            cropRectNormalized: previewCropRectNormalized
        )
    }

    private func configureDebugDepthOverride(_ plan: CaptureSourcePlan) async {
        configurationGeneration += 1
        let generation = configurationGeneration
        isDepthCaptureReady = false
        rgbSourceProfiles = capabilityMatrix.rgbSources
        focalLengthOptions = capabilityMatrix.focalLengthOptions()
        debugDepthDeviceOptions = capabilityMatrix.debugDepthDeviceOptions()
        debugZoomCapability = plan.zoomCapability
        debugZoomProfiles = plan.zoomCapability.zoomProfiles
        if debugSelectedZoomID != nil {
            debugSelectedZoomID = plan.zoom?.id
        }
        debugSelectedZoomFactor = plan.zoom?.actualVideoZoomFactor ?? plan.zoom?.requestedZoomFactor ?? debugSelectedZoomFactor
        debugFOVLabel = debugFOVText(for: plan)
        activeCameraDisplayName = "Debug · \(plan.depthSource?.displayName ?? "No Depth") · \(debugFOVLabel)"
        statusMessage = statusText(for: plan)

        do {
            let result = try await sessionController.configure(SessionConfigurationRequest(capturePlan: plan))

            guard generation == configurationGeneration else {
                return
            }

            activeSessionConfiguration = result
            let actualZoomFactor = Double(result.device.videoZoomFactor)
            debugSelectedZoomFactor = actualZoomFactor
            debugFOVLabel = debugFOVText(for: result.capturePlan, zoomFactor: actualZoomFactor)
            activeCameraDisplayName = "Debug · \(result.capturePlan.depthSource?.displayName ?? "No Depth") · \(debugFOVLabel)"
            nativePreviewAspectRatio = result.nativePreviewAspectRatio
            isDepthCaptureReady = result.depthDeliverySupported && result.capturePlan.canCapturePhotoDepth
            statusMessage = statusText(for: result.capturePlan)
        } catch {
            guard generation == configurationGeneration else {
                return
            }

            activeSessionConfiguration = nil
            isDepthCaptureReady = false
            nativePreviewAspectRatio = 3.0 / 4.0
            statusMessage = error.localizedDescription
        }
    }
    #endif

    private func resolvedDepthProfile(from rows: [DepthProfile], selectedDepthProfileID: String?) -> DepthProfile? {
        if let selectedDepthProfileID,
           let selected = rows.first(where: { $0.id == selectedDepthProfileID }) {
            #if DEBUG
            return selected
            #else
            if selected.isSelectable {
                return selected
            }
            #endif
        }

        return rows.first(where: \.isSelectable)
    }

    private func configurationForCurrentCapture(from active: SessionConfigurationResult) -> SessionConfigurationResult? {
        let plan = capturePlanForCurrentPreviewCrop(from: active.capturePlan)
        return SessionConfigurationResult(
            depthDeliverySupported: active.depthDeliverySupported && plan.canCapturePhotoDepth,
            cameraDisplayName: active.cameraDisplayName,
            nativePreviewAspectRatio: active.nativePreviewAspectRatio,
            capturePlan: plan,
            device: active.device,
            selectionContext: SessionConfigurationRequest(capturePlan: plan).selectionContext
        )
    }

    private func capturePlanForCurrentPreviewCrop(from activePlan: CaptureSourcePlan) -> CaptureSourcePlan {
        let activeZoom = activePlan.zoom
        let activeZoomFactor = activeZoom?.actualVideoZoomFactor ?? activeZoom?.requestedZoomFactor
        let usesFixedZoomCandidate = activeZoomFactor.map { zoom in
            CameraCapabilityResolver.candidateZoomFactors.contains { abs($0 - zoom) < 0.001 }
        } ?? false

        let plan = RGBDepthPairingCoordinator.makePlan(
            rgbSource: activePlan.rgbSource,
            depthSource: activePlan.depthSource,
            selectionMode: activePlan.selectionMode,
            selectedZoomID: usesFixedZoomCandidate ? activeZoom?.id : nil,
            selectedZoomFactor: usesFixedZoomCandidate ? nil : activeZoomFactor,
            cropRectNormalized: previewCropRectNormalized
        )

        return plan
    }

    private func defaultRGBSource(position: AVCaptureDevice.Position) -> CameraProfile? {
        rgbSourceProfiles
            .filter { $0.isEnabled && $0.device.position == position }
            .max { lhs, rhs in
                CameraCapabilityResolver.automaticPriority(for: lhs.device.deviceType) < CameraCapabilityResolver.automaticPriority(for: rhs.device.deviceType)
            }
    }

    private func statusText(for plan: CaptureSourcePlan) -> String {
        if plan.canCapturePhotoDepth {
            return "Ready · \(plan.pairingMode.rawValue) · crop metadata"
        }

        if plan.pairingMode == .requiresMultiCam {
            return TAPDepthCaptureError.multicamRequired.localizedDescription
        }

        return plan.compatibilityReason ?? TAPDepthCaptureError.incompatibleRGBDepthPairing.localizedDescription
    }

    #if DEBUG
    private func clearDebugDepthOverrideState() {
        isDebugDepthOverrideActive = false
        debugSelectedDepthDeviceID = nil
        debugSelectedZoomID = nil
        debugSelectedZoomFactor = 1.0
        debugZoomProfiles = []
        debugZoomCapability = nil
        debugFOVLabel = "24mm"
        depthSelectionMode = .automatic
    }

    private func depthSafeZoomFactor(_ requested: Double, capability: ZoomCapability) -> Double {
        /*
         Apple exposes depth-delivery zoom as runtime format data. Some formats
         allow continuous depth-safe ranges; others only allow discrete zoom
         factors. The Debug slider must therefore clamp to the nearest legal
         value before we ask `CaptureSessionController` to set `videoZoomFactor`.
         */
        let ranges = capability.depthSafeZoomRanges.isEmpty
            ? [capability.minAvailableVideoZoomFactor...capability.maxAvailableVideoZoomFactor]
            : capability.depthSafeZoomRanges

        if ranges.contains(where: { $0.contains(requested) }) {
            return requested
        }

        return ranges
            .flatMap { [$0.lowerBound, $0.upperBound] }
            .min { lhs, rhs in abs(lhs - requested) < abs(rhs - requested) }
            ?? capability.currentZoomFactor
            ?? 1.0
    }

    private func debugFOVText(for plan: CaptureSourcePlan, zoomFactor: Double? = nil) -> String {
        let resolvedZoomFactor = zoomFactor
            ?? plan.zoom?.actualVideoZoomFactor
            ?? plan.zoom?.requestedZoomFactor
            ?? 1.0
        let equivalentMillimeters = FocalLengthLabelResolver.equivalentMillimeters(
            for: plan.rgbSource,
            rawVideoZoomFactor: resolvedZoomFactor,
            formatSelection: plan.formatSelection
        )
        let label = FocalLengthLabelResolver.label(
            equivalentMillimeters: equivalentMillimeters,
            source: "\(plan.rgbSource.focalLengthLabelSource)+debugRawVideoZoomFactor"
        ).label
        let zoom = formattedZoom(resolvedZoomFactor)
        return "\(label) · \(zoom)"
    }

    private func formattedZoom(_ zoom: Double) -> String {
        if abs(zoom.rounded() - zoom) < 0.01 {
            return "\(Int(zoom.rounded()))x"
        }
        return String(format: "%.1fx", zoom)
    }
    #endif

    /// Loads the latest saved TAPCamDepth thumbnail without prompting for Photos
    /// access. The camera remains usable even when the user has not granted photo
    /// library read access; in that case the album button simply shows its generic
    /// placeholder until a new capture succeeds.
    private func loadRecentDepthAssetPreviewIfAvailable() {
        guard let asset = PhotoLibraryWriter.latestDepthAssetIfAuthorized() else {
            return
        }

        loadRecentDepthAssetPreview(assetID: asset.localIdentifier)
    }

    /// Updates the camera chrome's recent-photo entry point after a successful
    /// write. The full analysis flow still lives in `DepthAnalysisView`; the camera
    /// screen only owns the small thumbnail affordance and the sheet presentation.
    private func loadRecentDepthAssetPreview(assetID: String) {
        guard let asset = PhotoLibraryWriter.asset(localIdentifier: assetID) else {
            recentThumbnail = nil
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 144, height: 144),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            Task { @MainActor in
                self?.recentThumbnail = image
            }
        }
    }
}
