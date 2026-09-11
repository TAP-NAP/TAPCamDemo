@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

/// Invalidates both queued work and results already waiting for the main actor.
nonisolated struct GeekModePointCloudAdmission {
    private(set) var generation: UInt64 = 0
    private(set) var isActive = false
    private(set) var isFrozen = false

    var token: UInt64? { isActive && !isFrozen ? generation : nil }

    mutating func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        reset()
    }

    mutating func setFrozen(_ frozen: Bool) {
        guard isFrozen != frozen else { return }
        isFrozen = frozen
        reset()
    }

    mutating func reset() { generation &+= 1 }
    func accepts(_ token: UInt64) -> Bool { self.token == token }
}

/// One projection worker, one replaceable input, and one replaceable presentation.
/// RGB already carries the supplied connection rotation/mirroring; depth stays native.
nonisolated final class GeekModePointCloudStream: @unchecked Sendable {
    @MainActor var onFrameAvailabilityChanged: ((Bool) -> Void)?

    private struct Input {
        let video: CMSampleBuffer
        let depth: AVDepthData
        let rotationDegrees: Double
        let mirrored: Bool
        let token: UInt64
        let frameIndex: Int
    }

    private struct Presentation {
        let token: UInt64
        let payload: TAPVideoPointCloudPayload?
    }

    private let store: TAPVideoPointCloudStore
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.tapnap.geek-mode.point-cloud", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var admission = GeekModePointCloudAdmission()
    private var latestInput: Input?
    private var latestPresentation: Presentation?
    private var workerRunning = false
    private var presentationScheduled = false
    @MainActor private var announcedAvailability: Bool?
    @MainActor private var availabilityGeneration: UInt64?
    private var frameIndex = 0

    init(store: TAPVideoPointCloudStore) { self.store = store }

    func consume(video: CMSampleBuffer, depth: AVDepthData, rotationDegrees: Double, mirrored: Bool) {
        lock.lock()
        guard let token = admission.token else {
            lock.unlock()
            return
        }
        frameIndex &+= 1
        latestInput = Input(video: video, depth: depth, rotationDegrees: rotationDegrees,
                            mirrored: mirrored, token: token, frameIndex: frameIndex)
        let shouldStart = !workerRunning
        workerRunning = true
        lock.unlock()
        if shouldStart { queue.async { [weak self] in self?.drain() } }
    }

    @MainActor func setActive(_ active: Bool) {
        invalidate { $0.setActive(active) }
        if !active { store.clear() }
    }

    @MainActor func setFrozen(_ frozen: Bool) {
        // Freeze retains the currently displayed frame, not a result still being built.
        invalidate { $0.setFrozen(frozen) }
    }

    @MainActor func reset() {
        invalidate { $0.reset() }
        store.clear()
    }

    private func invalidate(_ update: (inout GeekModePointCloudAdmission) -> Void) {
        lock.lock()
        let previous = admission.generation
        update(&admission)
        if previous != admission.generation {
            latestInput = nil
            latestPresentation = nil
            frameIndex = 0
        }
        lock.unlock()
    }

    private func drain() {
        while true {
            lock.lock()
            guard let input = latestInput else {
                workerRunning = false
                lock.unlock()
                return
            }
            latestInput = nil
            lock.unlock()
            let payload = autoreleasepool { try? project(input) }
            lock.lock()
            guard admission.accepts(input.token) else {
                lock.unlock()
                continue
            }
            latestPresentation = Presentation(token: input.token, payload: payload)
            let shouldPresent = !presentationScheduled
            presentationScheduled = true
            lock.unlock()
            if shouldPresent {
                Task { @MainActor [weak self] in self?.publishLatest() }
            }
        }
    }

    @MainActor private func publishLatest() {
        lock.lock()
        presentationScheduled = false
        let presentation = latestPresentation
        latestPresentation = nil
        guard let presentation, admission.accepts(presentation.token) else {
            lock.unlock()
            return
        }
        lock.unlock()
        // Lifecycle changes also run on MainActor, so none can interleave between
        // this token check and presentation. Rendering never holds the capture lock.
        let isAvailable = presentation.payload != nil
        let availabilityChanged = availabilityGeneration != presentation.token
            || announcedAvailability != isAvailable
        availabilityGeneration = presentation.token
        announcedAvailability = isAvailable
        if let payload = presentation.payload { store.present(payload) }
        // A transient invalid frame holds the last valid cloud. Only stop/reset
        // clears it; the callback lets the page mark the held view accurately.
        if availabilityChanged { onFrameAvailabilityChanged?(isAvailable) }
    }

    private func project(_ input: Input) throws -> TAPVideoPointCloudPayload? {
        let rotation = TAPVideoRecordingTransform.normalizedQuarterTurn(CGFloat(input.rotationDegrees))
        guard let rgb = CMSampleBufferGetImageBuffer(input.video),
              let description = CMSampleBufferGetFormatDescription(input.video),
              let nativeCalibration = input.depth.cameraCalibrationData,
              let calibration = TAPVideoPointCloudCalibration(Self.calibration(nativeCalibration)),
              [0, 90, 180, 270].contains(rotation) else { return nil }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(input.video))
        guard timestamp.isFinite else { return nil }
        let packed = try TAPDepthFrameCodec.pack(input.depth.depthDataMap)
        let rgbWidth = CVPixelBufferGetWidth(rgb)
        let rgbHeight = CVPixelBufferGetHeight(rgb)
        let swapsAxes = rotation == 90 || rotation == 270
        let alignedWidth = swapsAxes ? rgbHeight : rgbWidth
        let alignedHeight = swapsAxes ? rgbWidth : rgbHeight
        guard packed.width > 0, packed.height > 0, rgbWidth > 0, rgbHeight > 0,
              abs(Double(alignedWidth) / Double(alignedHeight)
                    - Double(packed.width) / Double(packed.height)) < 0.01 else { return nil }
        let aperture = CMVideoFormatDescriptionGetCleanAperture(description, originIsAtTopLeft: true)
        guard aperture.minX >= 0, aperture.minY >= 0,
              aperture.width > 0, aperture.height > 0,
              aperture.maxX <= Double(rgbWidth), aperture.maxY <= Double(rgbHeight) else { return nil }
        let scaleX = Double(alignedWidth) / Double(packed.width)
        let scaleY = Double(alignedHeight) / Double(packed.height)
        let projection = TAPVideoRegistrationProjection(
            depthWidth: packed.width, depthHeight: packed.height,
            alignedRGBWidth: alignedWidth, alignedRGBHeight: alignedHeight,
            encodedRGBWidth: rgbWidth, encodedRGBHeight: rgbHeight,
            depthToAlignedRGBPixelCenterAffine: [scaleX, 0, (scaleX - 1) / 2, 0, scaleY, (scaleY - 1) / 2],
            connectionRotationDegrees: rotation, isEncodedHorizontallyMirrored: input.mirrored,
            rgbCleanAperture: TAPVideoRegistrationRect(x: aperture.minX, y: aperture.minY,
                                                      width: aperture.width, height: aperture.height)
        )
        let descriptor = TAPVideoDepthRegistrationDescriptor(
            schemaID: "geek-mode-live", rgbPresentationWidth: Int(aperture.width),
            rgbPresentationHeight: Int(aperture.height), mapping: .avDepthDataWarpedToSynchronizedRGB,
            projection: projection
        )
        let source = CIImage(cvPixelBuffer: rgb)
        let crop = CGRect(x: aperture.minX, y: source.extent.height - aperture.maxY,
                          width: aperture.width, height: aperture.height)
        let scale = min(1, Double(TAPVideoPointCloudProjection.maximumRGBDimension) / max(crop.width, crop.height))
        let image = source.cropped(to: crop)
            .transformed(by: .init(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: .init(scaleX: scale, y: scale))
        guard let rgbImage = context.createCGImage(image, from: image.extent) else { return nil }
        let frame = TAPDecodedDepthVideoFrame(
            frameIndex: input.frameIndex, presentationTimeSeconds: timestamp,
            width: packed.width, height: packed.height, pixelFormat: packed.pixelFormat,
            image: UIImage(), retainedByteCount: packed.bytes.count, packedDepth: packed.bytes,
            inlineCalibration: calibration.value
        )
        return try TAPVideoPointCloudProjection.make(
            frame: frame, history: [], calibration: calibration, descriptor: descriptor, image: rgbImage
        )
    }

    private static func calibration(_ value: AVCameraCalibrationData) -> TAPVideoManifest.CameraCalibration {
        let intrinsic = value.intrinsicMatrix
        let extrinsic = value.extrinsicMatrix
        return TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [intrinsic.columns.0.x, intrinsic.columns.0.y, intrinsic.columns.0.z,
                              intrinsic.columns.1.x, intrinsic.columns.1.y, intrinsic.columns.1.z,
                              intrinsic.columns.2.x, intrinsic.columns.2.y, intrinsic.columns.2.z],
            intrinsicMatrixReferenceDimensions: .init(width: value.intrinsicMatrixReferenceDimensions.width,
                                                      height: value.intrinsicMatrixReferenceDimensions.height),
            extrinsicMatrix: [extrinsic.columns.0.x, extrinsic.columns.0.y, extrinsic.columns.0.z,
                              extrinsic.columns.1.x, extrinsic.columns.1.y, extrinsic.columns.1.z,
                              extrinsic.columns.2.x, extrinsic.columns.2.y, extrinsic.columns.2.z,
                              extrinsic.columns.3.x, extrinsic.columns.3.y, extrinsic.columns.3.z],
            pixelSizeMillimeters: value.pixelSize,
            lensDistortionCenter: .init(x: value.lensDistortionCenter.x, y: value.lensDistortionCenter.y),
            lensDistortionLookupTable: value.lensDistortionLookupTable,
            inverseLensDistortionLookupTable: value.inverseLensDistortionLookupTable
        )
    }
}
