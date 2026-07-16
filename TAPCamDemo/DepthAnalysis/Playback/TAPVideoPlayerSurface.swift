//
//  TAPVideoPlayerSurface.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AVKit
import SwiftUI

/// A presentation-only video surface. SwiftUI owns every interactive control;
/// this view owns only AVPlayerLayer, the registered-depth overlay, and the PiP
/// bridge required to switch back to RGB for system playback surfaces.
@MainActor
struct TAPVideoPlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    let overlayStore: TAPVideoDepthOverlayStore
    let showsRegisteredDepth: Bool
    let overlayOpacity: Double
    let onSystemPlaybackRequiresRGB: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            overlayStore: overlayStore,
            onSystemPlaybackRequiresRGB: onSystemPlaybackRequiresRGB
        )
    }

    func makeUIView(context: Context) -> TAPVideoPlayerSurfaceUIView {
        let surfaceView = TAPVideoPlayerSurfaceUIView()
        surfaceView.setPlayer(player)
        context.coordinator.bind(to: surfaceView, player: player)
        context.coordinator.update(
            showsRegisteredDepth: showsRegisteredDepth,
            overlayOpacity: overlayOpacity
        )
        return surfaceView
    }

    func updateUIView(
        _ surfaceView: TAPVideoPlayerSurfaceUIView,
        context: Context
    ) {
        if surfaceView.playerLayer.player !== player {
            surfaceView.setPlayer(player)
            context.coordinator.observeExternalPlayback(on: player)
        }
        context.coordinator.update(
            showsRegisteredDepth: showsRegisteredDepth,
            overlayOpacity: overlayOpacity
        )
        surfaceView.refreshVideoGeometry()
    }

    static func dismantleUIView(
        _ surfaceView: TAPVideoPlayerSurfaceUIView,
        coordinator: Coordinator
    ) {
        coordinator.unbind()
        surfaceView.reset()
    }

    @MainActor
    final class Coordinator: NSObject,
        AVPictureInPictureControllerDelegate,
        TAPVideoDepthOverlaySink {
        private let overlayStore: TAPVideoDepthOverlayStore
        private let onSystemPlaybackRequiresRGB: () -> Void
        private weak var surfaceView: TAPVideoPlayerSurfaceUIView?
        private weak var observedPlayer: AVPlayer?
        private var externalPlaybackObservation: NSKeyValueObservation?
        private var playerLayerReadyObservation: NSKeyValueObservation?
        private var pictureInPictureController: AVPictureInPictureController?
        private var showsRegisteredDepth = false
        private var overlayOpacity = 1.0
        private var isPictureInPictureActive = false

        init(
            overlayStore: TAPVideoDepthOverlayStore,
            onSystemPlaybackRequiresRGB: @escaping () -> Void
        ) {
            self.overlayStore = overlayStore
            self.onSystemPlaybackRequiresRGB = onSystemPlaybackRequiresRGB
            super.init()
        }

        func bind(to surfaceView: TAPVideoPlayerSurfaceUIView, player: AVPlayer) {
            self.surfaceView = surfaceView
            overlayStore.attach(self)
            observeExternalPlayback(on: player)
            observeReadiness(of: surfaceView.playerLayer)
            configurePictureInPicture(for: surfaceView.playerLayer)
            surfaceView.refreshVideoGeometry()
        }

        func unbind() {
            externalPlaybackObservation?.invalidate()
            externalPlaybackObservation = nil
            playerLayerReadyObservation?.invalidate()
            playerLayerReadyObservation = nil
            observedPlayer = nil

            if let pictureInPictureController {
                if pictureInPictureController.isPictureInPictureActive {
                    pictureInPictureController.stopPictureInPicture()
                }
                pictureInPictureController.delegate = nil
            }
            pictureInPictureController = nil
            isPictureInPictureActive = false
            overlayStore.detach(self)
            surfaceView?.present(nil)
            surfaceView = nil
        }

        func update(showsRegisteredDepth: Bool, overlayOpacity: Double) {
            self.showsRegisteredDepth = showsRegisteredDepth
            self.overlayOpacity = overlayOpacity
            surfaceView?.update(
                showsRegisteredDepth: showsRegisteredDepth,
                overlayOpacity: overlayOpacity
            )
            if showsRegisteredDepth
                && (observedPlayer?.isExternalPlaybackActive == true
                    || isPictureInPictureActive) {
                requireRGBForSystemPlayback()
            }
        }

        func setRegisteredDepthOverlay(_ overlay: TAPVideoRegisteredDepthOverlay?) {
            surfaceView?.present(overlay)
        }

        func observeExternalPlayback(on player: AVPlayer) {
            externalPlaybackObservation?.invalidate()
            observedPlayer = player
            externalPlaybackObservation = player.observe(
                \.isExternalPlaybackActive,
                options: [.initial, .new]
            ) { [weak self] player, _ in
                guard player.isExternalPlaybackActive else {
                    return
                }
                Task { @MainActor [weak self, weak player] in
                    guard let self,
                          let player,
                          observedPlayer === player else {
                        return
                    }
                    requireRGBForSystemPlayback()
                }
            }
        }

        func pictureInPictureControllerWillStartPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            guard self.pictureInPictureController === pictureInPictureController else {
                return
            }
            isPictureInPictureActive = true
            requireRGBForSystemPlayback()
        }

        func pictureInPictureControllerDidStopPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            guard self.pictureInPictureController === pictureInPictureController else {
                return
            }
            isPictureInPictureActive = false
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: any Error
        ) {
            guard self.pictureInPictureController === pictureInPictureController else {
                return
            }
            _ = error
            isPictureInPictureActive = false
        }

        private func observeReadiness(of playerLayer: AVPlayerLayer) {
            playerLayerReadyObservation?.invalidate()
            playerLayerReadyObservation = playerLayer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.surfaceView?.refreshVideoGeometry()
                }
            }
        }

        private func configurePictureInPicture(for playerLayer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported(),
                  let controller = AVPictureInPictureController(
                    playerLayer: playerLayer
                  ) else {
                pictureInPictureController = nil
                return
            }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController = controller
        }

        private func requireRGBForSystemPlayback() {
            guard showsRegisteredDepth else {
                return
            }
            showsRegisteredDepth = false
            surfaceView?.update(
                showsRegisteredDepth: false,
                overlayOpacity: overlayOpacity
            )
            onSystemPlaybackRequiresRGB()
        }
    }
}
