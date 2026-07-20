//
//  TAPVideoPlayerSurface.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import SwiftUI

/// A presentation-only video surface. SwiftUI owns every interactive control;
/// this view owns only AVPlayerLayer and the registered-depth overlay.
@MainActor
struct TAPVideoPlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    let overlayStore: TAPVideoDepthOverlayStore
    let showsRegisteredDepth: Bool
    let overlayOpacity: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(overlayStore: overlayStore)
    }

    func makeUIView(context: Context) -> TAPVideoPlayerSurfaceUIView {
        let surfaceView = TAPVideoPlayerSurfaceUIView()
        surfaceView.setPlayer(player)
        context.coordinator.bind(to: surfaceView)
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
    final class Coordinator: NSObject, TAPVideoDepthOverlaySink {
        private let overlayStore: TAPVideoDepthOverlayStore
        private weak var surfaceView: TAPVideoPlayerSurfaceUIView?
        private var playerLayerReadyObservation: NSKeyValueObservation?
        private var showsRegisteredDepth = false
        private var overlayOpacity = 1.0

        init(overlayStore: TAPVideoDepthOverlayStore) {
            self.overlayStore = overlayStore
            super.init()
        }

        func bind(to surfaceView: TAPVideoPlayerSurfaceUIView) {
            self.surfaceView = surfaceView
            overlayStore.attach(self)
            observeReadiness(of: surfaceView.playerLayer)
            surfaceView.refreshVideoGeometry()
        }

        func unbind() {
            playerLayerReadyObservation?.invalidate()
            playerLayerReadyObservation = nil

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
        }

        func setRegisteredDepthOverlay(_ overlay: TAPVideoRegisteredDepthOverlay?) {
            surfaceView?.present(overlay)
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

    }
}
