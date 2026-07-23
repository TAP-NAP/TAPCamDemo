//
//  CameraManualFocusPreviewStream.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import OSLog

/// A lightweight live-frame source for the manual-focus loupe.
///
/// The capture-session owner adds `videoOutput` to the graph only for the
/// Photographer-mode camera path. The output and its delegate remain stable for
/// that graph's lifetime; showing or hiding the loupe only attaches or detaches
/// a renderer and never mutates the capture graph.
nonisolated final class CameraManualFocusPreviewStream: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    let videoOutput: AVCaptureVideoDataOutput

    private let delegateQueue: DispatchQueue
    private let activeDeviceLock = NSLock()
    private var activeDevice: AVCaptureDevice?
    private var isCaptureActive = false

    /// Main-actor observers are used only to rebuild UI rotation state after a
    /// session activation/deactivation. Frame delivery stays entirely on
    /// `delegateQueue`.
    @MainActor private var activeStateObservers: [UUID: () -> Void] = [:]

    /// Accessed only on `delegateQueue`.
    private var attachedRenderer: RendererReference?
    private var lastRendererFailureLogAt = Date.distantPast

    override init() {
        let delegateQueue = DispatchQueue(
            label: "tapcam.camera-capture.manual-focus-preview",
            qos: .userInteractive
        )
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        self.delegateQueue = delegateQueue
        self.videoOutput = videoOutput
        super.init()

        videoOutput.setSampleBufferDelegate(self, queue: delegateQueue)
    }

    deinit {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
    }

    /// Marks the stream active for a configured capture device.
    ///
    /// The capture-session owner calls this on its session queue after adding
    /// `videoOutput`. Buffer rotation stays at zero so the output does not pay
    /// for physical per-frame rotation; the loupe display layer applies the
    /// RotationCoordinator preview transform instead.
    func activate(for device: AVCaptureDevice) {
        activeDeviceLock.lock()
        let shouldResetRenderer = !isCaptureActive
            || activeDevice?.uniqueID != device.uniqueID
        activeDevice = device
        isCaptureActive = true
        activeDeviceLock.unlock()
        publishActiveStateChange()

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        guard shouldResetRenderer else {
            return
        }
        delegateQueue.async { [weak self] in
            self?.flushAttachedRenderer(removingDisplayedImage: true)
        }
    }

    /// Stops delivery immediately and removes the last loupe image.
    ///
    /// The active flag is changed under the lock before the flush is enqueued,
    /// so already queued capture callbacks drop their buffers rather than
    /// repainting the renderer after deactivation.
    func deactivate() {
        activeDeviceLock.lock()
        activeDevice = nil
        isCaptureActive = false
        activeDeviceLock.unlock()
        publishActiveStateChange()

        delegateQueue.async { [weak self] in
            self?.flushAttachedRenderer(removingDisplayedImage: true)
        }
    }

    /// A read-only snapshot used to build the UI-side RotationCoordinator.
    @MainActor
    func activeDeviceSnapshot() -> AVCaptureDevice? {
        activeDeviceLock.lock()
        defer { activeDeviceLock.unlock() }
        return isCaptureActive ? activeDevice : nil
    }

    /// Observes activation changes without making the frame source itself an
    /// ObservableObject. The callback re-reads the current snapshot, so rapid
    /// deactivate/activate events cannot deliver a stale device.
    @MainActor
    func observeActiveState(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        activeStateObservers[id] = observer
        observer()
        return id
    }

    @MainActor
    func removeActiveStateObserver(_ id: UUID) {
        activeStateObservers[id] = nil
    }

    private func publishActiveStateChange() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            for observer in activeStateObservers.values {
                observer()
            }
        }
    }

    /// Attaches the display-layer renderer without changing the capture graph.
    @MainActor
    func attach(renderer: AVSampleBufferVideoRenderer) {
        let reference = RendererReference(renderer)
        delegateQueue.async { [weak self, reference] in
            guard let self else {
                return
            }
            guard self.attachedRenderer?.renderer !== reference.renderer else {
                return
            }

            if let previous = self.attachedRenderer {
                self.attachedRenderer = nil
                Self.flush(previous.renderer, removingDisplayedImage: true)
            }
            self.attachedRenderer = reference
        }
    }

    /// Detaches only the renderer supplied by the caller.
    ///
    /// Clearing the reference before flushing prevents a late sample-buffer
    /// callback from making a hidden loupe visible again.
    @MainActor
    func detach(renderer: AVSampleBufferVideoRenderer) {
        let reference = RendererReference(renderer)
        delegateQueue.async { [weak self, reference] in
            guard let self,
                  self.attachedRenderer?.renderer === reference.renderer else {
                return
            }
            self.attachedRenderer = nil
            Self.flush(reference.renderer, removingDisplayedImage: true)
        }
    }

    private func captureIsActive() -> Bool {
        activeDeviceLock.lock()
        defer { activeDeviceLock.unlock() }
        return isCaptureActive
    }

    /// Must be called on `delegateQueue`.
    private func flushAttachedRenderer(removingDisplayedImage: Bool) {
        guard let renderer = attachedRenderer?.renderer else {
            return
        }
        Self.flush(renderer, removingDisplayedImage: removingDisplayedImage)
    }

    /// Must be called on `delegateQueue`.
    private static func flush(
        _ renderer: AVSampleBufferVideoRenderer,
        removingDisplayedImage: Bool
    ) {
        renderer.flush(
            removingDisplayedImage: removingDisplayedImage,
            completionHandler: nil
        )
    }

    private static func markForImmediateDisplay(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ),
        CFArrayGetCount(attachments) > 0,
        let rawDictionary = CFArrayGetValueAtIndex(attachments, 0) else {
            return
        }

        let dictionary = Unmanaged<CFMutableDictionary>
            .fromOpaque(rawDictionary)
            .takeUnretainedValue()
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoOutput,
              captureIsActive(),
              let renderer = attachedRenderer?.renderer else {
            return
        }

        if renderer.status == .failed {
            let now = Date()
            if now.timeIntervalSince(lastRendererFailureLogAt) >= 2 {
                lastRendererFailureLogAt = now
                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                let errorDescription = renderer.error.map(TAPDiagnostics.describe) ?? "none"
                TAPDiagnostics.cameraCapture.error(
                    "manual focus loupe renderer failed error=\(errorDescription, privacy: .public)"
                )
                #endif
            }
        }
        if renderer.requiresFlushToResumeDecoding || renderer.status == .failed {
            renderer.flush()
        }
        guard renderer.isReadyForMoreMediaData else {
            return
        }

        Self.markForImmediateDisplay(sampleBuffer)
        renderer.enqueue(sampleBuffer)
    }
}

private nonisolated final class RendererReference: @unchecked Sendable {
    let renderer: AVSampleBufferVideoRenderer

    init(_ renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
    }
}
