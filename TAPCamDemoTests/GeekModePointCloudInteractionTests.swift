import SceneKit
import SwiftUI
import Testing
import UIKit
@testable import TAPCamDemo

@Suite(.serialized)
struct GeekModePointCloudInteractionTests {
    @Test @MainActor func freezeDisablesGesturesAndPlaybackThenResumesTheSameScene() async throws {
        let store = TAPVideoPointCloudStore()
        store.present(payload(time: 1))
        let host = UIHostingController(rootView: GeekPointCloudTestHost(store: store, frozen: false, sourceID: "rear"))
        let window = try mount(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await update(host) { sceneView(in: host.view) != nil }
        let view = try #require(sceneView(in: host.view))
        let scene = try #require(view.scene)
        let interaction = try #require(scene.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
        interaction.eulerAngles = SCNVector3(0.1, 0.2, 0)
        let pose = interaction.transform
        let frame = view.accessibilityValue

        host.rootView = GeekPointCloudTestHost(store: store, frozen: true, sourceID: "rear")
        try await update(host) { !view.isUserInteractionEnabled && !view.isPlaying }
        #expect(sceneView(in: host.view) === view && view.scene === scene)
        #expect(view.accessibilityValue == frame)
        #expect(SCNMatrix4EqualToMatrix4(interaction.transform, pose))

        host.rootView = GeekPointCloudTestHost(store: store, frozen: false, sourceID: "rear")
        try await update(host) { view.isUserInteractionEnabled && view.isPlaying }
        store.present(payload(time: 2))
        #expect(view.accessibilityValue != frame, "Resuming must allow the next RGB/depth payload to appear")
        #expect(view.scene === scene && SCNMatrix4EqualToMatrix4(interaction.transform, pose))
        host.rootView = GeekPointCloudTestHost(store: nil, frozen: false, sourceID: "rear")
        try await update(host) { view.scene == nil }
    }

    @Test @MainActor func changingCameraRebuildsTheSceneAndDiscardsItsPreviousPose() async throws {
        let store = TAPVideoPointCloudStore()
        let stream = GeekModePointCloudStream(store: store)
        stream.setActive(true)
        store.present(payload(time: 1))
        let host = UIHostingController(rootView: GeekPointCloudTestHost(store: store, frozen: false, sourceID: "rear"))
        let window = try mount(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await update(host) { sceneView(in: host.view) != nil }
        let rearView = try #require(sceneView(in: host.view))
        let rearInteraction = try #require(rearView.scene?.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
        rearInteraction.eulerAngles = SCNVector3(0.1, 0.2, 0.3)
        stream.setFrozen(true)
        stream.reset()
        #expect(store.presentationTimeSeconds == nil, "A source reset must clear even while settings or capture keeps the stream frozen")
        host.rootView = GeekPointCloudTestHost(store: store, frozen: true, sourceID: "front")
        try await update(host) {
            guard let current = sceneView(in: host.view) else { return false }
            return current !== rearView && rearView.scene == nil
        }
        let frontView = try #require(sceneView(in: host.view))
        let frontInteraction = try #require(frontView.scene?.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
        #expect(!frontView.isPlaying && !frontView.isUserInteractionEnabled)
        #expect(frontInteraction.eulerAngles.x == 0 && frontInteraction.eulerAngles.y == 0 && frontInteraction.eulerAngles.z == 0)
        let detachedValue = rearView.accessibilityValue
        stream.setFrozen(false)
        store.present(payload(time: 2))
        #expect(rearView.accessibilityValue == detachedValue, "The replaced renderer must no longer receive frames")
        #expect(frontView.accessibilityValue != detachedValue)
        stream.setActive(false)
        #expect(store.presentationTimeSeconds == nil)
        host.rootView = GeekPointCloudTestHost(store: nil, frozen: false, sourceID: "front")
        try await update(host) { frontView.scene == nil }
    }

    @MainActor private func mount(_ host: UIHostingController<GeekPointCloudTestHost>) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        window.rootViewController = host
        window.isHidden = false
        return window
    }

    @MainActor private func payload(time: Double) -> TAPVideoPointCloudPayload {
        .init(presentationTimeSeconds: time, vertices: [SIMD3<Float>(0, 0, -2)],
              colors: [SIMD4<Float>(1, 1, 1, 1)],
              cameraModel: .init(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480))
    }

    @MainActor private func sceneView(in view: UIView) -> TAPVideoPointCloudSceneView? {
        if let view = view as? TAPVideoPointCloudSceneView { return view }
        return view.subviews.lazy.compactMap { sceneView(in: $0) }.first
    }

    @MainActor private func update(_ host: UIHostingController<GeekPointCloudTestHost>, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        repeat {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        try #require(condition(), "SwiftUI did not complete the Geek Mode renderer lifecycle update")
    }
}

private struct GeekPointCloudTestHost: View {
    let store: TAPVideoPointCloudStore?
    let frozen: Bool
    let sourceID: String
    var body: some View {
        if let store {
            GeekModePointCloudPreview(store: store, frozen: frozen, sourceID: sourceID)
        }
    }
}
