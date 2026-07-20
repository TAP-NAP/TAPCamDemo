//
//  TAPVideoPlayerSurfaceUIView.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import UIKit

@MainActor
final class TAPVideoPlayerSurfaceUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            preconditionFailure("TAPVideoPlayerSurfaceUIView requires AVPlayerLayer backing")
        }
        return playerLayer
    }

    private let overlaySurfaceView = TAPVideoDepthOverlaySurfaceView()
    private var showsRegisteredDepth = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        overlaySurfaceView.isHidden = true
        addSubview(overlaySurfaceView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            overlaySurfaceView.frame = playerLayer.videoRect
            overlaySurfaceView.layoutIfNeeded()
        }
        updateOverlayVisibility()
    }

    func setPlayer(_ player: AVPlayer?) {
        guard playerLayer.player !== player else {
            return
        }
        playerLayer.player = player
        setNeedsLayout()
    }

    func update(showsRegisteredDepth: Bool, overlayOpacity: Double) {
        self.showsRegisteredDepth = showsRegisteredDepth
        overlaySurfaceView.alpha = CGFloat(min(max(overlayOpacity, 0), 1))
        updateOverlayVisibility()
    }

    func present(_ overlay: TAPVideoRegisteredDepthOverlay?) {
        overlaySurfaceView.present(overlay)
        setNeedsLayout()
        updateOverlayVisibility()
    }

    func refreshVideoGeometry() {
        setNeedsLayout()
        layoutIfNeeded()
    }

    func reset() {
        showsRegisteredDepth = false
        overlaySurfaceView.present(nil)
        overlaySurfaceView.frame = .zero
        overlaySurfaceView.isHidden = true
        playerLayer.player = nil
    }

    private func updateOverlayVisibility() {
        let videoRect = playerLayer.videoRect
        let hasUsableVideoRect = videoRect.width > 0 && videoRect.height > 0
        overlaySurfaceView.isHidden = !showsRegisteredDepth
            || !overlaySurfaceView.hasImage
            || !hasUsableVideoRect
    }
}
