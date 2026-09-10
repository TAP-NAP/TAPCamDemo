import SceneKit
import SwiftUI

@MainActor
final class TAPVideoPointCloudStore {
    private weak var sink: TAPVideoPointCloudSceneView?
    private var payload: TAPVideoPointCloudPayload?
    var presentationTimeSeconds: Double? { payload?.presentationTimeSeconds }
    func attach(_ view: TAPVideoPointCloudSceneView) {
        sink = view
        view.present(payload)
    }
    func detach(_ view: TAPVideoPointCloudSceneView) {
        if sink === view { sink = nil }
    }
    func present(_ payload: TAPVideoPointCloudPayload) {
        self.payload = payload
        sink?.present(payload)
    }
    func clear() {
        payload = nil
        sink?.present(nil)
    }
}

struct TAPVideoPointCloudView: UIViewRepresentable {
    let store: TAPVideoPointCloudStore
    func makeUIView(context: Context) -> TAPVideoPointCloudSceneView {
        let view = TAPVideoPointCloudSceneView(frame: .zero)
        store.attach(view)
        context.coordinator.store = store
        return view
    }
    func updateUIView(_ uiView: TAPVideoPointCloudSceneView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ uiView: TAPVideoPointCloudSceneView, coordinator: Coordinator) {
        coordinator.store?.detach(uiView)
        uiView.isPlaying = false
        uiView.scene = nil
    }
    final class Coordinator { weak var store: TAPVideoPointCloudStore? }
}

final class TAPVideoPointCloudSceneView: SCNView, UIGestureRecognizerDelegate {
    private let interaction = SCNNode()
    private let cloud = SCNNode()
    private let cameraNode = SCNNode()
    private var cameraModel: TAPDepthProjectionCameraModel?
    private var hasSetTarget = false
    private var targetDepth: Float = 0.25
    private var panStartAngles = SCNVector3Zero
    private var translationStartPosition = SCNVector3Zero
    private var pinchStartScale: Float = 1
    private var rollStartAngle: Float = 0

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        backgroundColor = .black
        scene = SCNScene()
        interaction.name = "TAPVideoPointCloudInteraction"
        interaction.addChildNode(cloud)
        scene?.rootNode.addChildNode(interaction)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 100
        scene?.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        // Match photo projection: gestures move the model while the calibrated
        // camera stays fixed, including when the first gesture begins.
        allowsCameraControl = TAPDepthProjectionInteractionPolicy.usesSceneKitDefaultCameraControl
        installGestures()
        isAccessibilityElement = true
        accessibilityLabel = "3D projection"
        accessibilityIdentifier = "tap.video.point-cloud"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateProjection()
    }

    func present(_ payload: TAPVideoPointCloudPayload?) {
        guard let payload else {
            cloud.geometry = nil
            accessibilityValue = String(localized: "No current 3D frame")
            return
        }
        cameraModel = payload.cameraModel
        updateProjection()
        if !hasSetTarget {
            hasSetTarget = true
            let middle = payload.vertices[payload.vertices.count / 2]
            targetDepth = -middle.z
            interaction.position = TAPDepthProjectionInteractionPolicy.interactionPivotPosition(targetDepth: targetDepth)
            cloud.position = TAPDepthProjectionInteractionPolicy.geometryCompensationPosition(targetDepth: targetDepth)
        }
        let vertexData = payload.vertices.withUnsafeBytes { Data($0) }
        let colorData = payload.colors.withUnsafeBytes { Data($0) }
        let vertices = SCNGeometrySource(data: vertexData, semantic: .vertex,
            vectorCount: payload.vertices.count, usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let colors = SCNGeometrySource(data: colorData, semantic: .color,
            vectorCount: payload.colors.count, usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let indices = Array(0..<UInt32(payload.vertices.count))
        let element = SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) },
            primitiveType: .point, primitiveCount: indices.count, bytesPerIndex: 4)
        element.pointSize = 3
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 5
        let geometry = SCNGeometry(sources: [vertices, colors], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cloud.geometry = geometry
        SCNTransaction.commit()
        accessibilityValue = String(format: String(localized: "%.3f seconds, %d RGB points"), payload.presentationTimeSeconds, payload.vertices.count)
    }

    private func updateProjection() {
        guard let cameraModel, bounds.width > 0, bounds.height > 0 else { return }
        cameraNode.camera?.projectionTransform = TAPDepthProjectionCameraContract.projectionMatrix(
            cameraModel: cameraModel, viewportSize: bounds.size, near: 0.01, far: 100
        )
    }

    private func installGestures() {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbitPan(_:)))
        orbit.maximumNumberOfTouches = 1
        let translation = UIPanGestureRecognizer(target: self, action: #selector(handleTranslationPan(_:)))
        translation.minimumNumberOfTouches = 2
        translation.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let roll = UIRotationGestureRecognizer(target: self, action: #selector(handleRoll(_:)))
        let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset(_:)))
        reset.numberOfTapsRequired = 2
        for gesture in [orbit, translation, pinch, roll, reset] {
            gesture.cancelsTouchesInView = true
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            addGestureRecognizer(gesture)
        }
    }

    @objc func handleOrbitPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStartAngles = interaction.eulerAngles
        case .changed:
            let translation = gesture.translation(in: self)
            let pitch = panStartAngles.x + Float(translation.y / max(bounds.height, 1)) * .pi * 0.72
            interaction.eulerAngles.x = min(max(pitch, -.pi / 2), .pi / 2)
            interaction.eulerAngles.y = panStartAngles.y + Float(translation.x / max(bounds.width, 1)) * .pi
        default: break
        }
    }

    @objc private func handleTranslationPan(_ gesture: UIPanGestureRecognizer) {
        guard let cameraModel else { return }
        switch gesture.state {
        case .began:
            translationStartPosition = interaction.position
        case .changed:
            let offset = TAPDepthProjectionInteractionPolicy.scenePanOffset(
                forScreenTranslation: gesture.translation(in: self), cameraModel: cameraModel,
                viewportSize: bounds.size, targetDepth: targetDepth
            )
            interaction.position = SCNVector3(translationStartPosition.x + offset.x,
                                             translationStartPosition.y + offset.y, translationStartPosition.z)
        default: break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: pinchStartScale = interaction.scale.x
        case .changed:
            let scale = TAPDepthProjectionInteractionPolicy.clampedScale(pinchStartScale * Float(gesture.scale))
            interaction.scale = SCNVector3(scale, scale, scale)
        default: break
        }
    }

    @objc private func handleRoll(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began: rollStartAngle = interaction.eulerAngles.z
        case .changed:
            interaction.eulerAngles.z = TAPDepthProjectionInteractionPolicy.rollAngle(
                startAngle: rollStartAngle, gestureRotation: gesture.rotation
            )
        default: break
        }
    }

    @objc private func handleReset(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        interaction.position = TAPDepthProjectionInteractionPolicy.interactionPivotPosition(targetDepth: targetDepth)
        interaction.eulerAngles = SCNVector3Zero
        interaction.scale = SCNVector3(1, 1, 1)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer.view === self && otherGestureRecognizer.view === self
    }
}
