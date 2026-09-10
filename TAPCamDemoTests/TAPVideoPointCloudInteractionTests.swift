import SceneKit
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPVideoPointCloudInteractionTests {
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
