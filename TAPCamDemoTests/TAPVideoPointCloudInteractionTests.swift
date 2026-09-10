import SceneKit
import SwiftUI
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPVideoPointCloudInteractionTests {
    @Test @MainActor func retainedHostRebindsTheStoreAndDetachesItsCurrentOwner() async throws {
        let firstStore = TAPVideoPointCloudStore()
        let secondStore = TAPVideoPointCloudStore()
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480)
        func payload(_ time: Double) -> TAPVideoPointCloudPayload {
            .init(presentationTimeSeconds: time, vertices: [SIMD3<Float>(0, 0, -2)],
                  colors: [SIMD4<Float>(1, 1, 1, 1)], cameraModel: model)
        }
        firstStore.present(payload(1))
        secondStore.present(payload(2))
        let host = UIHostingController(rootView: VideoPointCloudTestHost(store: firstStore))
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        try await updateHost(host) { pointCloudView(in: host.view) != nil }
        let view = try #require(pointCloudView(in: host.view))
        let scene = try #require(view.scene)
        let interaction = try #require(scene.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
        interaction.eulerAngles = SCNVector3(0.1, 0.2, 0.3)
        let userTransform = interaction.transform
        let firstValue = view.accessibilityValue

        host.rootView = VideoPointCloudTestHost(store: secondStore)
        try await updateHost(host) { view.accessibilityValue != firstValue }
        #expect(pointCloudView(in: host.view) === view)
        #expect(view.scene === scene)
        #expect(SCNMatrix4EqualToMatrix4(interaction.transform, userTransform))
        let secondValue = view.accessibilityValue
        firstStore.present(payload(3))
        firstStore.clear()
        #expect(view.accessibilityValue == secondValue, "Late updates from the detached Store must not replace the current frame")
        secondStore.present(payload(4))
        #expect(view.accessibilityValue != secondValue)
        #expect(SCNMatrix4EqualToMatrix4(interaction.transform, userTransform))

        host.rootView = VideoPointCloudTestHost(store: nil)
        try await updateHost(host) { view.scene == nil }
        let dismantledValue = view.accessibilityValue
        secondStore.present(payload(5))
        secondStore.clear()
        #expect(view.accessibilityValue == dismantledValue, "Teardown must detach the replacement Store while the native view is still retained")
        #expect(!view.isPlaying)
    }

    @Test @MainActor func gesturesKeepTheCalibratedCameraAndSurviveVideoFrameUpdates() throws {
        let view = TAPVideoPointCloudSceneView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480)
        let first = TAPVideoPointCloudPayload(presentationTimeSeconds: 0, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [SIMD4<Float>(1, 1, 1, 1)], cameraModel: model)
        view.present(first)
        let camera = try #require(view.pointOfView)
        let projection = try #require(camera.camera).projectionTransform
        let interaction = try #require(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
        let initialTransform = interaction.transform
        let cameraTransform = camera.transform
        let pan = VideoPointCloudTestPan()
        view.addGestureRecognizer(pan)
        pan.phase = .began
        view.handleOrbitPan(pan)
        pan.phase = .changed
        view.handleOrbitPan(pan)
        #expect(!view.allowsCameraControl)
        #expect(SCNMatrix4EqualToMatrix4(interaction.transform, initialTransform))
        #expect(SCNMatrix4EqualToMatrix4(camera.transform, cameraTransform))
        #expect(SCNMatrix4EqualToMatrix4(try #require(view.pointOfView?.camera).projectionTransform, projection))

        pan.offset = CGPoint(x: 32, y: 0)
        view.handleOrbitPan(pan)
        #expect(abs(interaction.eulerAngles.y - .pi / 10) < 0.000_001)
        #expect(interaction.scale.x == 1 && interaction.position.z == -2)
        let userTransform = interaction.transform
        view.present(nil)
        view.present(.init(presentationTimeSeconds: 1, vertices: [SIMD3<Float>(0, 0, -4)],
            colors: first.colors, cameraModel: model))
        #expect(view.pointOfView === camera)
        #expect(SCNMatrix4EqualToMatrix4(camera.transform, cameraTransform))
        #expect(SCNMatrix4EqualToMatrix4(interaction.transform, userTransform))
        #expect(SCNMatrix4EqualToMatrix4(try #require(camera.camera).projectionTransform, projection))
    }

    @MainActor private func pointCloudView(in view: UIView) -> TAPVideoPointCloudSceneView? {
        if let view = view as? TAPVideoPointCloudSceneView { return view }
        return view.subviews.lazy.compactMap { pointCloudView(in: $0) }.first
    }

    @MainActor private func updateHost(
        _ host: UIHostingController<VideoPointCloudTestHost>,
        until condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        repeat {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        try #require(condition(), "SwiftUI did not complete the representable lifecycle update")
    }
}

private struct VideoPointCloudTestHost: View {
    let store: TAPVideoPointCloudStore?
    var body: some View {
        if let store { TAPVideoPointCloudView(store: store) }
    }
}

@MainActor
private final class VideoPointCloudTestPan: UIPanGestureRecognizer {
    var phase: UIGestureRecognizer.State = .possible
    var offset = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { phase }
        set { phase = newValue }
    }
    override func translation(in view: UIView?) -> CGPoint { offset }
}
