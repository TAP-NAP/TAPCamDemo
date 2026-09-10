import SceneKit
import SwiftUI
import simd

@MainActor
final class TAPVideoPointCloudStore {
    private weak var sink: TAPVideoPointCloudSceneView?
    private var payload: TAPVideoPointCloudPayload?
    private var cameraRotation = matrix_identity_float4x4
    var presentationTimeSeconds: Double? { payload?.presentationTimeSeconds }
    func attach(_ view: TAPVideoPointCloudSceneView) {
        sink = view
        view.present(payload)
        view.rotateCamera(cameraRotation)
    }
    func detach(_ view: TAPVideoPointCloudSceneView) {
        if sink === view { sink = nil }
    }
    func present(_ payload: TAPVideoPointCloudPayload) {
        self.payload = payload
        cameraRotation = matrix_identity_float4x4
        sink?.present(payload)
        sink?.rotateCamera(cameraRotation)
    }
    func rotateCamera(_ rotation: simd_float4x4) {
        guard rotation != cameraRotation else { return }
        cameraRotation = rotation
        sink?.rotateCamera(rotation)
    }
    func clear() {
        payload = nil
        cameraRotation = matrix_identity_float4x4
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
    private var historicalNodes: [Double: (node: SCNNode, frame: TAPVideoPointCloudKeyframe)] = [:]
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
        cloud.name = "TAPVideoPointCloudCurrent"
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
            for entry in historicalNodes.values { entry.node.removeFromParentNode() }
            historicalNodes.removeAll()
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
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cloud.geometry = geometry(vertices: payload.vertices, colors: payload.colors)
        presentHistory(payload)
        SCNTransaction.commit()
        accessibilityValue = String(format: String(localized: "%.3f seconds, %d RGB points"), payload.presentationTimeSeconds, payload.vertices.count)
    }

    private func presentHistory(_ payload: TAPVideoPointCloudPayload) {
        let timestamps = Set(payload.historicalFrames.map(\.presentationTimeSeconds))
        for time in Array(historicalNodes.keys) where !timestamps.contains(time) {
            historicalNodes.removeValue(forKey: time)?.node.removeFromParentNode()
        }
        let anchorToCurrent = simd_inverse(payload.cameraToAnchor)
        for frame in payload.historicalFrames {
            let time = frame.presentationTimeSeconds
            let node: SCNNode
            if let existing = historicalNodes[time] {
                node = existing.node
                // A display-only crop may reveal different points of the same
                // frozen piece, even when its visible point count stays equal.
                if existing.frame.vertices != frame.vertices || existing.frame.colors != frame.colors {
                    node.geometry = geometry(vertices: frame.vertices, colors: frame.colors)
                }
            }
            else {
                node = SCNNode(geometry: geometry(vertices: frame.vertices, colors: frame.colors))
                node.name = "TAPVideoPointCloudHistoricalFrame"
                cloud.addChildNode(node)
            }
            historicalNodes[time] = (node, frame)
            node.simdTransform = anchorToCurrent * frame.cameraToAnchor
        }
    }

    func rotateCamera(_ rotation: simd_float4x4) {
        var compensation = matrix_identity_float4x4
        compensation.columns.3.z = targetDepth
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cloud.simdTransform = compensation * rotation
        SCNTransaction.commit()
    }

    private func geometry(vertices points: [SIMD3<Float>], colors rgb: [SIMD4<Float>]) -> SCNGeometry {
        let vertexData = points.withUnsafeBytes { Data($0) }
        let colorData = rgb.withUnsafeBytes { Data($0) }
        let vertices = SCNGeometrySource(data: vertexData, semantic: .vertex,
            vectorCount: points.count, usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let colors = SCNGeometrySource(data: colorData, semantic: .color,
            vectorCount: rgb.count, usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let indices = Array(0..<UInt32(points.count))
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
        return geometry
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

    @objc func handleTranslationPan(_ gesture: UIPanGestureRecognizer) {
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

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: pinchStartScale = interaction.scale.x
        case .changed:
            let scale = TAPDepthProjectionInteractionPolicy.clampedScale(pinchStartScale * Float(gesture.scale))
            interaction.scale = SCNVector3(scale, scale, scale)
        default: break
        }
    }

    @objc func handleRoll(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began: rollStartAngle = interaction.eulerAngles.z
        case .changed:
            interaction.eulerAngles.z = TAPDepthProjectionInteractionPolicy.rollAngle(
                startAngle: rollStartAngle, gestureRotation: gesture.rotation
            )
        default: break
        }
    }

    @objc func handleReset(_ gesture: UITapGestureRecognizer) {
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
