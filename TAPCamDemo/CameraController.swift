//
//  CameraController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import Combine
import CoreLocation
import Foundation
import Photos
import UIKit

/// Owns the complete capture pipeline:
///
/// 1. choose a user-facing photo lens preset,
/// 2. resolve that preset to a depth-capable `AVCaptureDevice`,
/// 2. configure `AVCapturePhotoOutput` for depth delivery,
/// 3. receive `AVCapturePhoto.depthData` for the same shutter press,
/// 4. package the capture as HEIC with depth auxiliary data,
/// 5. inject the TAP XMP manifest,
/// 6. save the final bytes into the Photos album.
///
/// UI code observes only high-level state. All format and metadata decisions
/// live here or in the dedicated writer/manifest types so the README can map
/// each pipeline stage to a concrete code location.
@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var statusMessage = "Preparing camera..."
    @Published var isDepthCaptureAvailable = false
    @Published var isCapturing = false
    @Published var lastCaptureSummary: String?
    @Published private(set) var rearPhotoLensOptions: [PhotoLensOption] = []
    @Published private(set) var selectedPhotoLensID = PhotoLensOption.oneX.id
    @Published private(set) var currentPosition: AVCaptureDevice.Position = .back
    @Published private(set) var currentCameraDisplayName = "Back camera"
    @Published private(set) var recentAssetID: String?
    @Published private(set) var recentThumbnail: UIImage?

    var canCapture: Bool {
        isDepthCaptureAvailable && !isCapturing
    }

    var depthStatusText: String {
        isDepthCaptureAvailable ? "Depth capture ready" : "Depth unavailable"
    }

    var cameraPositionText: String {
        currentCameraDisplayName
    }

    private let sessionQueue = DispatchQueue(label: "tapcam.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let locationProvider = LocationProvider()
    private var currentDevice: AVCaptureDevice?
    private var currentPhotoLens = PhotoLensOption.oneX
    private var inFlightProcessors: [Int64: PhotoCaptureProcessor] = [:]

    override init() {
        super.init()
        refreshPhotoLensOptions()
    }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession(position: currentPosition)
            loadRecentDepthAssetPreviewIfAvailable()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                configureAndStartSession(position: currentPosition)
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
        let session = session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func switchCamera() {
        let nextPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        if nextPosition == .front {
            selectedPhotoLensID = PhotoLensOption.front.id
        } else if selectedPhotoLensID == PhotoLensOption.front.id {
            selectedPhotoLensID = PhotoLensOption.oneX.id
        }
        configureAndStartSession(position: nextPosition)
    }

    func selectPhotoLens(_ lens: PhotoLensOption) {
        guard currentPosition == .back else {
            selectedPhotoLensID = lens.id
            return
        }

        selectedPhotoLensID = lens.id
        configureAndStartSession(position: .back)
    }

    func captureDepthPhoto() async {
        guard canCapture else { return }

        isCapturing = true
        statusMessage = "Capturing depth HEIC..."
        let capturedAt = Date()
        let location = await locationProvider.requestOneShotLocation()
        let photoOutput = photoOutput
        guard let device = currentDevice else {
            isCapturing = false
            statusMessage = TAPDepthCaptureError.noDepthCameraAvailable.localizedDescription
            return
        }
        let photoLens = currentPhotoLens
        let settings = makePhotoSettings()
        let requestedCodec = requestedCodec

        let processor = PhotoCaptureProcessor(
            device: device,
            photoLens: photoLens,
            capturedAt: capturedAt,
            location: location,
            requestedCodec: requestedCodec,
            depthDataFiltered: settings.isDepthDataFiltered,
            photoQualityPrioritization: settings.photoQualityPrioritization
        ) { [weak self] result in
            Task { @MainActor in
                await self?.handleCaptureResult(result, uniqueID: settings.uniqueID)
            }
        }
        inFlightProcessors[settings.uniqueID] = processor

        sessionQueue.async { [weak self] in
            guard photoOutput.isDepthDataDeliverySupported else {
                let controller = self
                Task { @MainActor in
                    controller?.isCapturing = false
                    controller?.isDepthCaptureAvailable = false
                    controller?.statusMessage = TAPDepthCaptureError.depthDeliveryUnsupported.localizedDescription
                }
                return
            }

            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    private func configureAndStartSession(position: AVCaptureDevice.Position) {
        statusMessage = "Configuring \(position.tapDescription) depth camera..."
        let session = session
        let photoOutput = photoOutput
        let selectedPhotoLensID = selectedPhotoLensID

        sessionQueue.async { [weak self] in
            do {
                let configuration = try Self.configureSession(
                    session: session,
                    photoOutput: photoOutput,
                    position: position,
                    selectedPhotoLensID: selectedPhotoLensID
                )
                if !session.isRunning {
                    session.startRunning()
                }

                let controller = self
                Task { @MainActor in
                    guard let controller else { return }
                    controller.currentPosition = position
                    controller.currentCameraDisplayName = configuration.cameraDisplayName
                    controller.selectedPhotoLensID = configuration.photoLens.id
                    controller.currentDevice = configuration.device
                    controller.currentPhotoLens = configuration.photoLens
                    controller.refreshPhotoLensOptions()
                    controller.isDepthCaptureAvailable = configuration.depthDeliverySupported
                    controller.statusMessage = configuration.depthDeliverySupported
                        ? "Ready. Captures save to the TAPCamDepth album."
                        : "Camera selected, but depth delivery is unavailable."
                }
            } catch {
                let controller = self
                Task { @MainActor in
                    controller?.isDepthCaptureAvailable = false
                    controller?.statusMessage = error.localizedDescription
                }
            }
        }
    }

    nonisolated private static func configureSession(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        position: AVCaptureDevice.Position,
        selectedPhotoLensID: String
    ) throws -> SessionConfiguration {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }

        let requestedLens = PhotoLensOption.option(id: selectedPhotoLensID, position: position)
        guard let selection = Self.bestCaptureSelection(position: position, photoLens: requestedLens) else {
            throw TAPDepthCaptureError.noDepthCameraAvailable
        }
        let device = selection.device

        try configureDevice(device, selection: selection, photoLens: requestedLens)

        let input = try AVCaptureDeviceInput(device: device)
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
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }

        return SessionConfiguration(
            depthDeliverySupported: photoOutput.isDepthDataDeliverySupported,
            cameraDisplayName: Self.cameraStatusText(photoLens: requestedLens, device: device),
            photoLens: requestedLens.resolved(with: device),
            device: device
        )
    }

    nonisolated private static func configureDevice(
        _ device: AVCaptureDevice,
        selection: CaptureDeviceSelection,
        photoLens: PhotoLensOption
    ) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = selection.videoFormat
        device.activeDepthDataFormat = selection.depthFormat

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        let zoom = min(max(photoLens.zoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.videoZoomFactor = zoom
    }

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.isDepthDataDeliveryEnabled = true
        settings.embedsDepthDataInPhoto = true
        settings.isDepthDataFiltered = true
        settings.photoQualityPrioritization = .quality
        return settings
    }

    private var requestedCodec: AVVideoCodecType {
        photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
    }

    private func handleCaptureResult(_ result: Result<ProcessedDepthPhoto, Error>, uniqueID: Int64) async {
        inFlightProcessors[uniqueID] = nil

        do {
            let processed = try result.get()
            let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
                processed.heicData,
                capturedAt: processed.capturedAt,
                location: processed.location
            )

            isCapturing = false
            lastCaptureSummary = "Saved HEIC + depth + TAP manifest. Asset: \(assetID)"
            statusMessage = "Capture complete."
            loadRecentDepthAssetPreview(assetID: assetID)
        } catch {
            isCapturing = false
            lastCaptureSummary = nil
            statusMessage = error.localizedDescription
        }
    }

    private func refreshPhotoLensOptions() {
        rearPhotoLensOptions = Self.supportedRearPhotoLensOptions()
        if currentPosition == .back, !rearPhotoLensOptions.contains(where: { $0.id == selectedPhotoLensID }) {
            selectedPhotoLensID = rearPhotoLensOptions.first?.id ?? PhotoLensOption.oneX.id
        }
    }

    private func loadRecentDepthAssetPreviewIfAvailable() {
        guard let asset = PhotoLibraryWriter.latestDepthAssetIfAuthorized() else {
            return
        }

        loadRecentDepthAssetPreview(assetID: asset.localIdentifier)
    }

    private func loadRecentDepthAssetPreview(assetID: String) {
        recentAssetID = assetID
        guard let asset = PhotoLibraryWriter.asset(localIdentifier: assetID) else {
            recentThumbnail = nil
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
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

    nonisolated private static func supportedRearPhotoLensOptions() -> [PhotoLensOption] {
        PhotoLensOption.rearDefaults.filter { bestCaptureSelection(position: .back, photoLens: $0) != nil }
    }

    nonisolated private static func bestCaptureSelection(
        position: AVCaptureDevice.Position,
        photoLens: PhotoLensOption
    ) -> CaptureDeviceSelection? {
        let preferredTypes = position == .front ? frontCameraTypes : rearCameraTypes
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position
        ).devices

        for device in devices where device.supports(photoLens: photoLens) {
            if let depthSelection = bestDepthFormatSelection(for: device) {
                return CaptureDeviceSelection(
                    device: device,
                    videoFormat: depthSelection.videoFormat,
                    depthFormat: depthSelection.depthFormat
                )
            }
        }

        return nil
    }

    nonisolated private static var frontCameraTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInTrueDepthCamera,
            .builtInWideAngleCamera
        ]
    }

    nonisolated private static var rearCameraTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInLiDARDepthCamera,
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera
        ]
    }

    nonisolated private static func cameraStatusText(photoLens: PhotoLensOption, device: AVCaptureDevice) -> String {
        if photoLens.position == .front {
            return "\(displayName(for: device))"
        }
        return "\(photoLens.displayName) · \(displayName(for: device))"
    }

    nonisolated static func displayName(for device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInLiDARDepthCamera:
            "LiDAR depth"
        case .builtInTripleCamera:
            "Triple camera"
        case .builtInDualWideCamera:
            "Dual wide"
        case .builtInDualCamera:
            "Dual camera"
        case .builtInWideAngleCamera:
            "Wide"
        case .builtInUltraWideCamera:
            "Ultra wide"
        case .builtInTelephotoCamera:
            "Telephoto"
        case .builtInTrueDepthCamera:
            "TrueDepth"
        default:
            device.localizedName
        }
    }

    nonisolated private static func bestDepthFormatSelection(for device: AVCaptureDevice) -> DepthFormatSelection? {
        let selections = device.formats.compactMap { videoFormat -> DepthFormatSelection? in
            guard let depthFormat = bestDepthFormat(in: videoFormat.supportedDepthDataFormats) else {
                return nil
            }
            return DepthFormatSelection(videoFormat: videoFormat, depthFormat: depthFormat)
        }

        return selections.max { lhs, rhs in
            let lhsDimensions = CMVideoFormatDescriptionGetDimensions(lhs.videoFormat.formatDescription)
            let rhsDimensions = CMVideoFormatDescriptionGetDimensions(rhs.videoFormat.formatDescription)
            return Int(lhsDimensions.width) * Int(lhsDimensions.height) < Int(rhsDimensions.width) * Int(rhsDimensions.height)
        }
    }

    nonisolated private static func bestDepthFormat(in formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        formats.max { lhs, rhs in
            let lhsScore = depthFormatScore(lhs)
            let rhsScore = depthFormatScore(rhs)
            if lhsScore == rhsScore {
                let lhsDimensions = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
                let rhsDimensions = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
                return Int(lhsDimensions.width) * Int(lhsDimensions.height) < Int(rhsDimensions.width) * Int(rhsDimensions.height)
            }
            return lhsScore < rhsScore
        }
    }

    nonisolated private static func depthFormatScore(_ format: AVCaptureDevice.Format) -> Int {
        switch CMFormatDescriptionGetMediaSubType(format.formatDescription) {
        case kCVPixelFormatType_DepthFloat32:
            4
        case kCVPixelFormatType_DepthFloat16:
            3
        case kCVPixelFormatType_DisparityFloat32:
            2
        case kCVPixelFormatType_DisparityFloat16:
            1
        default:
            0
        }
    }
}

/// Stable UI model for the user-facing photo lens choice.
///
/// This intentionally represents the user's framing intent (`0.5x`, `1x`,
/// `2x`, `3x`, or front), not the depth source. AVFoundation may resolve that
/// intent through a virtual multi-camera device, and the manifest records both
/// this requested lens and the resolved capture/depth source.
nonisolated struct PhotoLensOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let position: AVCaptureDevice.Position
    let zoomFactor: CGFloat

    static let ultraWide = PhotoLensOption(id: "rear-0.5x", displayName: "0.5x", position: .back, zoomFactor: 0.5)
    static let oneX = PhotoLensOption(id: "rear-1x", displayName: "1x", position: .back, zoomFactor: 1.0)
    static let twoX = PhotoLensOption(id: "rear-2x", displayName: "2x", position: .back, zoomFactor: 2.0)
    static let threeX = PhotoLensOption(id: "rear-3x", displayName: "3x", position: .back, zoomFactor: 3.0)
    static let front = PhotoLensOption(id: "front", displayName: "Front", position: .front, zoomFactor: 1.0)

    static let rearDefaults = [ultraWide, oneX, twoX, threeX]

    static func option(id: String, position: AVCaptureDevice.Position) -> PhotoLensOption {
        if position == .front {
            return front
        }
        return rearDefaults.first(where: { $0.id == id }) ?? oneX
    }

    func resolved(with device: AVCaptureDevice) -> PhotoLensOption {
        PhotoLensOption(
            id: id,
            displayName: displayName,
            position: position,
            zoomFactor: min(max(zoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        )
    }
}

extension AVCaptureDevice {
    nonisolated func supports(photoLens: PhotoLensOption) -> Bool {
        guard position == photoLens.position else {
            return false
        }

        if photoLens.position == .front {
            return true
        }

        return minAvailableVideoZoomFactor <= photoLens.zoomFactor
            && maxAvailableVideoZoomFactor >= photoLens.zoomFactor
    }
}

private struct SessionConfiguration {
    let depthDeliverySupported: Bool
    let cameraDisplayName: String
    let photoLens: PhotoLensOption
    let device: AVCaptureDevice
}

nonisolated private struct CaptureDeviceSelection {
    let device: AVCaptureDevice
    let videoFormat: AVCaptureDevice.Format
    let depthFormat: AVCaptureDevice.Format
}

nonisolated private struct DepthFormatSelection {
    let videoFormat: AVCaptureDevice.Format
    let depthFormat: AVCaptureDevice.Format
}

private struct ProcessedDepthPhoto {
    let heicData: Data
    let manifest: TAPDepthManifest
    let capturedAt: Date
    let location: CLLocation?
}

nonisolated private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let device: AVCaptureDevice
    private let photoLens: PhotoLensOption
    private let capturedAt: Date
    private let location: CLLocation?
    private let requestedCodec: AVVideoCodecType
    private let depthDataFiltered: Bool
    private let photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    private let completion: (Result<ProcessedDepthPhoto, Error>) -> Void

    init(
        device: AVCaptureDevice,
        photoLens: PhotoLensOption,
        capturedAt: Date,
        location: CLLocation?,
        requestedCodec: AVVideoCodecType,
        depthDataFiltered: Bool,
        photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization,
        completion: @escaping (Result<ProcessedDepthPhoto, Error>) -> Void
    ) {
        self.device = device
        self.photoLens = photoLens
        self.capturedAt = capturedAt
        self.location = location
        self.requestedCodec = requestedCodec
        self.depthDataFiltered = depthDataFiltered
        self.photoQualityPrioritization = photoQualityPrioritization
        self.completion = completion
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }

        do {
            let manifest = try TAPDepthManifestBuilder.makeManifest(
                photo: photo,
                device: device,
                photoLens: photoLens,
                capturedAt: capturedAt,
                location: location,
                requestedCodec: requestedCodec,
                depthDataFiltered: depthDataFiltered,
                photoQualityPrioritization: photoQualityPrioritization
            )

            let customizer = TAPPhotoFileMetadataCustomizer(
                capturedAt: capturedAt,
                location: location,
                device: device
            )

            guard let baseHEICData = photo.fileDataRepresentation(with: customizer) else {
                throw TAPDepthCaptureError.unableToCreatePhotoData
            }

            let finalHEICData = try TAPDepthHEICWriter.injectingManifest(manifest, into: baseHEICData)
            let processed = ProcessedDepthPhoto(
                heicData: finalHEICData,
                manifest: manifest,
                capturedAt: capturedAt,
                location: location
            )
            completion(.success(processed))
        } catch {
            completion(.failure(error))
        }
    }
}
