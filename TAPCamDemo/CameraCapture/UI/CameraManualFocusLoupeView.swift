//
//  CameraManualFocusLoupeView.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Geometry for centering a tapped preview pixel inside the MF loupe.
///
/// SwiftUI's scale anchor is only the point that remains stationary while the
/// full-size preview is magnified. It does not move that point to the center of
/// the smaller clipping viewport. The translation below closes that second
/// half of the transform while keeping the point in display-preview
/// coordinates; capture-device coordinates must not be applied a second time.
nonisolated struct CameraManualFocusLoupeTransform: Equatable, Sendable {
    let magnification: CGFloat
    let centeringOffset: CGSize
    private let anchor: CGPoint
    private let previewSize: CGSize

    init(
        focusPoint: CameraPreviewFocusPoint,
        previewSize: CGSize,
        magnification: CGFloat
    ) {
        let resolvedSize = CGSize(
            width: max(previewSize.width, 0),
            height: max(previewSize.height, 0)
        )
        self.magnification = max(magnification, 1)
        self.previewSize = resolvedSize
        anchor = CGPoint(
            x: CGFloat(focusPoint.x) * resolvedSize.width,
            y: CGFloat(focusPoint.y) * resolvedSize.height
        )
        centeringOffset = CGSize(
            width: (0.5 - CGFloat(focusPoint.x)) * resolvedSize.width,
            height: (0.5 - CGFloat(focusPoint.y)) * resolvedSize.height
        )
    }

    /// Mirrors the visual transform used by `CameraPreviewStageView`.
    ///
    /// This is intentionally pure so tests can prove that an off-center tapped
    /// pixel lands at the center of the full preview's clipping coordinate
    /// system after scale plus translation.
    func displayedPoint(for sourcePoint: CameraPreviewFocusPoint) -> CGPoint {
        let source = CGPoint(
            x: CGFloat(sourcePoint.x) * previewSize.width,
            y: CGFloat(sourcePoint.y) * previewSize.height
        )
        return CGPoint(
            x: anchor.x
                + (source.x - anchor.x) * magnification
                + centeringOffset.width,
            y: anchor.y
                + (source.y - anchor.y) * magnification
                + centeringOffset.height
        )
    }
}

/// SwiftUI bridge for the inset manual-focus preview.
///
/// It renders frames supplied by `CameraManualFocusPreviewStream`; it neither
/// creates another capture-preview connection nor mutates the capture session.
struct CameraManualFocusLoupePreview: UIViewRepresentable {
    let source: CameraManualFocusPreviewStream

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source)
    }

    func makeUIView(context: Context) -> CameraManualFocusLoupeDisplayView {
        let view = CameraManualFocusLoupeDisplayView()
        context.coordinator.connect(source: source, to: view)
        return view
    }

    func updateUIView(
        _ uiView: CameraManualFocusLoupeDisplayView,
        context: Context
    ) {
        context.coordinator.connect(source: source, to: uiView)
    }

    static func dismantleUIView(
        _ uiView: CameraManualFocusLoupeDisplayView,
        coordinator: Coordinator
    ) {
        coordinator.disconnect(from: uiView)
    }

    @MainActor
    final class Coordinator {
        private var source: CameraManualFocusPreviewStream
        private weak var displayView: CameraManualFocusLoupeDisplayView?
        private var activeDeviceID: String?
        private var activeStateObserverID: UUID?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        init(source: CameraManualFocusPreviewStream) {
            self.source = source
        }

        func connect(
            source nextSource: CameraManualFocusPreviewStream,
            to view: CameraManualFocusLoupeDisplayView
        ) {
            if source !== nextSource {
                if let displayView {
                    source.detach(renderer: displayView.displayLayer.sampleBufferRenderer)
                }
                removeActiveStateObserver()
                stopObservingRotation()
                source = nextSource
            }

            displayView = view
            source.attach(renderer: view.displayLayer.sampleBufferRenderer)
            if activeStateObserverID == nil {
                activeStateObserverID = source.observeActiveState { [weak self] in
                    guard let self, let displayView = self.displayView else {
                        return
                    }
                    self.refreshRotationCoordinator(for: displayView)
                }
            }
            refreshRotationCoordinator(for: view)
        }

        func disconnect(from view: CameraManualFocusLoupeDisplayView) {
            source.detach(renderer: view.displayLayer.sampleBufferRenderer)
            guard displayView === view else {
                return
            }
            removeActiveStateObserver()
            stopObservingRotation()
            displayView = nil
            view.previewRotationAngleDegrees = 0
        }

        private func refreshRotationCoordinator(
            for view: CameraManualFocusLoupeDisplayView
        ) {
            guard let device = source.activeDeviceSnapshot() else {
                stopObservingRotation()
                view.previewRotationAngleDegrees = 0
                return
            }
            guard activeDeviceID != device.uniqueID
                    || rotationCoordinator?.previewLayer !== view.displayLayer else {
                return
            }

            stopObservingRotation()
            activeDeviceID = device.uniqueID
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: view.displayLayer
            )
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak view] _, change in
                let angle = change.newValue ?? 0
                Task { @MainActor [weak view] in
                    view?.previewRotationAngleDegrees = angle
                }
            }
        }

        private func stopObservingRotation() {
            rotationObservation?.invalidate()
            rotationObservation = nil
            rotationCoordinator = nil
            activeDeviceID = nil
        }

        private func removeActiveStateObserver() {
            guard let activeStateObserverID else {
                return
            }
            source.removeActiveStateObserver(activeStateObserverID)
            self.activeStateObserverID = nil
        }
    }
}

@MainActor
final class CameraManualFocusLoupeDisplayView: UIView {
    /// Keep the renderer on a child layer. Rotating and swapping the bounds of
    /// the UIView's backing layer would also mutate the host view's geometry,
    /// which can feed back into SwiftUI layout and leave the loupe blank.
    let displayLayer = AVSampleBufferDisplayLayer()

    var previewRotationAngleDegrees: CGFloat = 0 {
        didSet {
            guard previewRotationAngleDegrees != oldValue else {
                return
            }
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureDisplayLayer()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDisplayLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let viewportSize = bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        let angle = normalizedRotationAngle(previewRotationAngleDegrees)
        let quarterTurns = Int((angle / 90).rounded()) % 4
        let swapsBounds = quarterTurns == 1 || quarterTurns == 3
        let contentSize = swapsBounds
            ? CGSize(width: viewportSize.height, height: viewportSize.width)
            : viewportSize
        let radians = angle * .pi / 180
        let absoluteCosine = abs(cos(radians))
        let absoluteSine = abs(sin(radians))
        let requiredWidth = viewportSize.width * absoluteCosine
            + viewportSize.height * absoluteSine
        let requiredHeight = viewportSize.width * absoluteSine
            + viewportSize.height * absoluteCosine
        let coverScale = max(
            requiredWidth / max(contentSize.width, 1),
            requiredHeight / max(contentSize.height, 1)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.setAffineTransform(.identity)
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.bounds = CGRect(origin: .zero, size: contentSize)
        displayLayer.setAffineTransform(
            CGAffineTransform(rotationAngle: radians)
                .scaledBy(x: coverScale, y: coverScale)
        )
        CATransaction.commit()
    }

    private func configureDisplayLayer() {
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.addSublayer(displayLayer)
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    private func normalizedRotationAngle(_ angle: CGFloat) -> CGFloat {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}
