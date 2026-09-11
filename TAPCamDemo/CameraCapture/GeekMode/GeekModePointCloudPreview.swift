import SceneKit
import SwiftUI

/// The video viewer's renderer and gestures, with a small optional idle demonstration.
struct GeekModePointCloudPreview: View {
    let store: TAPVideoPointCloudStore
    let frozen: Bool
    let sourceID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeekModePointCloudSurface(store: store, frozen: frozen, reduceMotion: reduceMotion)
            .id(sourceID)
    }
}

private struct GeekModePointCloudSurface: UIViewRepresentable {
    let store: TAPVideoPointCloudStore
    let frozen: Bool
    let reduceMotion: Bool

    func makeUIView(context: Context) -> TAPVideoPointCloudSceneView {
        let view = TAPVideoPointCloudSceneView(frame: .zero)
        view.accessibilityIdentifier = "tap.geek-mode.point-cloud"
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        context.coordinator.attach(view: view, store: store)
        context.coordinator.configure(frozen: frozen, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ view: TAPVideoPointCloudSceneView, context: Context) {
        if context.coordinator.store !== store {
            context.coordinator.detach()
            context.coordinator.attach(view: view, store: store)
        }
        context.coordinator.configure(frozen: frozen, reduceMotion: reduceMotion)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: TAPVideoPointCloudSceneView, coordinator: Coordinator) {
        coordinator.detach()
        view.isPlaying = false
        view.scene = nil
    }

    @MainActor final class Coordinator {
        private static let idleActionKey = "geek-mode-idle-tilt"
        weak var store: TAPVideoPointCloudStore?
        private weak var view: TAPVideoPointCloudSceneView?
        private var touchObserver: GeekModeTouchObserver?
        private var idleTask: Task<Void, Never>?
        private var frozen = true
        private var reduceMotion = true
        private var isTouching = false
        private var hasFrame = false

        private var interaction: SCNNode? {
            view?.scene?.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: true)
        }

        func attach(view: TAPVideoPointCloudSceneView, store: TAPVideoPointCloudStore) {
            self.view = view
            self.store = store
            store.attach(view)
            let observer = GeekModeTouchObserver { [weak self] touching in
                guard let self else { return }
                isTouching = touching
                stopIdleMotion()
                if !touching { scheduleIdleMotion() }
            }
            touchObserver = observer
            view.addGestureRecognizer(observer)
            scheduleIdleMotion()
        }

        func configure(frozen: Bool, reduceMotion: Bool) {
            view?.isUserInteractionEnabled = !frozen
            view?.isPlaying = !frozen
            let hasFrame = store?.presentationTimeSeconds != nil
            guard self.frozen != frozen || self.reduceMotion != reduceMotion || self.hasFrame != hasFrame else { return }
            self.frozen = frozen
            self.reduceMotion = reduceMotion
            self.hasFrame = hasFrame
            stopIdleMotion()
            if frozen { isTouching = false }
            scheduleIdleMotion()
        }

        func detach() {
            stopIdleMotion()
            if let view {
                store?.detach(view)
                if let touchObserver { view.removeGestureRecognizer(touchObserver) }
            }
            touchObserver = nil
            view = nil
            store = nil
        }

        private func stopIdleMotion() {
            idleTask?.cancel()
            idleTask = nil
            // SceneKit keeps the current pose when an action stops, so touching
            // the view continues naturally from the position the visitor sees.
            interaction?.removeAction(forKey: Self.idleActionKey)
        }

        private func scheduleIdleMotion() {
            guard !frozen, !reduceMotion, !isTouching, hasFrame, view != nil else { return }
            idleTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard let self, !frozen, !reduceMotion, !isTouching,
                      store?.presentationTimeSeconds != nil,
                      let interaction else { return }
                idleTask = nil
                let movements: [(CGFloat, CGFloat, TimeInterval)] = [
                    (0.035, 0.07, 0.65),
                    (-0.07, -0.14, 1.3),
                    (0.035, 0.07, 0.65)
                ]
                let actions = movements.map { pitch, yaw, duration in
                    let action = SCNAction.rotateBy(x: pitch, y: yaw, z: 0, duration: duration)
                    action.timingMode = .easeInEaseOut
                    return action
                }
                interaction.runAction(.sequence(actions), forKey: Self.idleActionKey, completionHandler: nil)
            }
        }
    }
}

/// Observes the beginning of every touch without taking ownership from the
/// renderer's orbit, pan, pinch, roll, or reset recognizers.
@MainActor private final class GeekModeTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onActivity: (Bool) -> Void
    private var activeTouches: Set<UITouch> = []

    init(onActivity: @escaping (Bool) -> Void) {
        self.onActivity = onActivity
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.formUnion(touches)
        onActivity(true)
        state = state == .possible ? .began : .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            onActivity(false)
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            onActivity(false)
            state = .cancelled
        }
    }

    override func reset() {
        super.reset()
        activeTouches.removeAll()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
