import SceneKit
import Testing
import UIKit
import simd
@testable import TAPCamDemo

struct TAPVideoPointCloudInteractionTests {
    @Test func historyFreezesEveryCurrentPointWithoutDecimation() throws {
        let model = TAPDepthProjectionCameraModel(fx: 2, fy: 2, cx: 1.5, cy: 1.5, imageWidth: 4, imageHeight: 4)
        let points = (0..<6_001).map { SIMD3<Float>(Float($0 % 100) * 0.002 - 0.1, Float($0 / 100) * 0.002 - 0.06, -2) }
        let colors = points.indices.map { SIMD4<Float>(Float($0 % 256) / 255, 0.4, 0.2, 1) }
        var history = TAPVideoPointCloudHistory()
        _ = history.accept(.init(presentationTimeSeconds: 0, vertices: points, colors: colors, cameraModel: model))
        #expect(history.frames.count == 1 && history.frames[0].vertices == points && history.frames[0].colors == colors)
        var step = matrix_identity_float4x4
        step.columns.3.x = -5
        let result = history.accept(.init(presentationTimeSeconds: 1, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [SIMD4<Float>(1, 1, 1, 1)], cameraModel: model), previousToCurrent: step)
        let frozen = try #require(result.historicalFrames.first)
        #expect(result.historicalFrames.count == 1 && frozen.presentationTimeSeconds == 0)
        #expect(frozen.vertices == points && frozen.colors == colors)
        #expect(frozen.vertices.count == 6_001 && history.frames.count == 2)
        #expect(result.cameraToAnchor.columns.3.x == 5)
        #expect(result.vertices.count == 1 && result.rawSamples.isEmpty)
    }

    @Test func returningToAViewReplacesCoveredOldPointsAndRGB() {
        let model = TAPDepthProjectionCameraModel(fx: 2, fy: 2, cx: 1.5, cy: 1.5, imageWidth: 4, imageHeight: 4)
        let original = [SIMD3<Float>(-0.2, 0, -2), SIMD3<Float>(0.2, 0, -2)]
        let red = [SIMD4<Float>](repeating: SIMD4(1, 0, 0, 1), count: original.count)
        let away = [SIMD3<Float>(0, 0, -2)]
        let blue = [SIMD4<Float>(0, 0, 1, 1)]
        var history = TAPVideoPointCloudHistory()
        _ = history.accept(.init(presentationTimeSeconds: 0, vertices: original, colors: red, cameraModel: model))
        var step = matrix_identity_float4x4
        step.columns.3.x = -5
        _ = history.accept(.init(presentationTimeSeconds: 1, vertices: away, colors: blue, cameraModel: model), previousToCurrent: step)
        step.columns.3.x = 5
        let current = [SIMD3<Float>(0.4, 0, -3)]
        let green = [SIMD4<Float>(0, 1, 0, 1)]
        let returned = history.accept(.init(presentationTimeSeconds: 2, vertices: current, colors: green, cameraModel: model),
                                      previousToCurrent: step)
        #expect(returned.vertices == current && returned.colors == green)
        #expect(returned.cameraToAnchor == matrix_identity_float4x4)
        #expect(returned.historicalFrames.map(\.presentationTimeSeconds) == [1])
        #expect(returned.historicalFrames[0].vertices == away && returned.historicalFrames[0].colors == blue)
        #expect(history.frames.map(\.presentationTimeSeconds) == [1, 2])
        #expect(history.frames.last?.vertices == current && history.frames.last?.colors == green)
    }

    @Test func fixedCameraUpdatesDoNotStackOldScenePoints() {
        let model = TAPDepthProjectionCameraModel(fx: 2, fy: 2, cx: 1.5, cy: 1.5, imageWidth: 4, imageHeight: 4)
        var history = TAPVideoPointCloudHistory()
        for index in 0..<100 {
            let points = [SIMD3<Float>(Float(index % 7) * 0.02, 0, -2)]
            let colors = [SIMD4<Float>(Float(index) / 100, 0.4, 0.2, 1)]
            let time = Double(index) * 0.03
            let result = history.accept(.init(presentationTimeSeconds: time,
                vertices: points, colors: colors, cameraModel: model), previousToCurrent: matrix_identity_float4x4)
            #expect(result.historicalFrames.isEmpty && result.vertices == points && result.colors == colors)
            #expect(history.frames.count == 1 && history.frames[0].presentationTimeSeconds == time)
            #expect(history.frames[0].vertices == points && history.frames[0].colors == colors && history.latestTime == time)
        }
    }

    @Test func movingViewTrimsOnlyCoveredPointsFromAnExistingPiece() {
        let model = TAPDepthProjectionCameraModel(fx: 2, fy: 2, cx: 1.5, cy: 1.5, imageWidth: 4, imageHeight: 4)
        let points = [SIMD3<Float>(-1, 0, -2), SIMD3<Float>(0, 0, -2), SIMD3<Float>(1, 0, -2)]
        let colors = [SIMD4<Float>(1, 0, 0, 1), SIMD4<Float>(0, 1, 0, 1), SIMD4<Float>(0, 0, 1, 1)]
        var history = TAPVideoPointCloudHistory()
        _ = history.accept(.init(presentationTimeSeconds: 0, vertices: points, colors: colors, cameraModel: model))
        var step = matrix_identity_float4x4
        step.columns.3.x = -4
        _ = history.accept(.init(presentationTimeSeconds: 1, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [SIMD4<Float>(1, 1, 1, 1)], cameraModel: model), previousToCurrent: step)
        step.columns.3.x = 1.5
        let result = history.accept(.init(presentationTimeSeconds: 2, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [SIMD4<Float>(1, 1, 0, 1)], cameraModel: model), previousToCurrent: step)
        let trimmed = result.historicalFrames.first { $0.presentationTimeSeconds == 0 }
        #expect(trimmed?.vertices == Array(points.prefix(2)) && trimmed?.colors == Array(colors.prefix(2)))
        #expect(trimmed?.cameraToAnchor == matrix_identity_float4x4)
    }

    @Test func weakFirstFrameDoesNotPreventAUsableRegistrationSeed() throws {
        let observation = try registrationObservation(at: 1)
        var weak = TAPVideoPointCloudPayload(presentationTimeSeconds: 0,
            vertices: Array(observation.payload.vertices.prefix(1)), colors: Array(observation.payload.colors.prefix(1)),
            cameraModel: observation.payload.cameraModel)
        weak.rawSamples = Array(observation.payload.rawSamples.prefix(1))
        var history = TAPVideoPointCloudHistory()
        let standalone = try #require(try history.accept(weak, image: observation.image))
        #expect(standalone.vertices == weak.vertices && standalone.colors == weak.colors && standalone.rawSamples.isEmpty)
        #expect(history.frames.isEmpty && history.latestTime == nil)
        let seeded = try #require(try history.accept(observation.payload, image: observation.image))
        #expect(seeded.presentationTimeSeconds == 1 && history.latestTime == 1 && history.frames.count == 1)
        #expect(history.frames[0].vertices == observation.payload.vertices && history.frames[0].colors == observation.payload.colors)
    }

    @Test func failedRegistrationPreservesFrozenPointsUntilRealAlignmentRecovers() throws {
        let first = try registrationObservation(at: 0)
        var history = TAPVideoPointCloudHistory()
        _ = try #require(try history.accept(first.payload, image: first.image))
        let saved = try #require(history.frames.first)
        let pose = history.cameraToAnchor
        for time: Double in [1, 2] {
            var failed = TAPVideoPointCloudPayload(presentationTimeSeconds: time, vertices: [SIMD3<Float>(Float(time) * 0.2, 0, -3)],
                colors: [SIMD4<Float>(Float(time) * 0.3, 0.4, 0.2, 1)], cameraModel: first.payload.cameraModel)
            failed.rawSamples = [.init(position: failed.vertices[0], imagePoint: SIMD2(0.6, 0.5))]
            // Insufficient correspondence cannot change the map, but this valid
            // current RGB-D observation must still advance the displayed frame.
            let result = try history.accept(failed, image: first.image)
            #expect(result == nil)
            let current = history.presentation(of: failed, cameraToAnchor: pose)
            #expect(current.presentationTimeSeconds == time && current.cameraToAnchor == pose)
            #expect(current.vertices == failed.vertices && current.colors == failed.colors && current.rawSamples.isEmpty)
            #expect(current.historicalFrames.isEmpty)
            let turnedPose = simd_float4x4(simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)))
            let turned = history.presentation(of: failed, cameraToAnchor: turnedPose)
            #expect(turned.presentationTimeSeconds == time && turned.cameraToAnchor == turnedPose)
            #expect(turned.vertices == failed.vertices && turned.colors == failed.colors && turned.rawSamples.isEmpty)
            // The first display crop was temporary: turning away reveals every
            // original point again, at its saved pose and with its original RGB.
            let visible = try #require(turned.historicalFrames.first)
            #expect(turned.historicalFrames.count == 1 && visible.presentationTimeSeconds == 0)
            #expect(visible.vertices == saved.vertices && visible.colors == saved.colors && visible.cameraToAnchor == saved.cameraToAnchor)
            #expect(history.latestTime == 0 && history.cameraToAnchor == pose && history.frames.count == 1)
            #expect(history.frames[0].presentationTimeSeconds == saved.presentationTimeSeconds)
            #expect(history.frames[0].vertices == saved.vertices && history.frames[0].colors == saved.colors)
            #expect(history.frames[0].cameraToAnchor == saved.cameraToAnchor)
        }
        // This invokes Vision optical flow and the real rigid fit against the retained good reference.
        let next = try registrationObservation(at: 3)
        let recovered = try #require(try history.accept(next.payload, image: next.image))
        #expect(recovered.presentationTimeSeconds == 3 && history.latestTime == 3)
        #expect(recovered.vertices == next.payload.vertices && recovered.colors == next.payload.colors)
        #expect(recovered.rawSamples.isEmpty && history.frames.last?.presentationTimeSeconds == 3)
        #expect(simd_length(history.cameraToAnchor.columns.3 - pose.columns.3) < 0.001)
    }

    @Test func sameTimestampRefreshReusesPoseWithoutDuplicatingEdgePoints() throws {
        let first = try registrationObservation(at: 0)
        var history = TAPVideoPointCloudHistory()
        _ = try #require(try history.accept(first.payload, image: first.image))
        var step = matrix_identity_float4x4
        step.columns.3.x = -5
        let current = TAPVideoPointCloudPayload(presentationTimeSeconds: 1, vertices: [SIMD3<Float>(2, 0, -2)],
            colors: [SIMD4<Float>(0, 0, 1, 1)], cameraModel: first.payload.cameraModel)
        _ = history.accept(current, previousToCurrent: step)
        let frozen = try #require(history.frames.first)
        let pose = history.cameraToAnchor
        var refreshed = TAPVideoPointCloudPayload(presentationTimeSeconds: 1, vertices: current.vertices,
            colors: [SIMD4<Float>(0, 1, 0, 1)], cameraModel: current.cameraModel)
        // This point lies outside the frustum, so treating a refresh as a new visit
        // would retain the old current point and append a duplicate timestamp.
        _ = history.accept(refreshed)
        #expect(history.frames.map(\.presentationTimeSeconds) == [0, 1])
        #expect(history.cameraToAnchor == pose && history.frames.last?.colors == refreshed.colors)
        #expect(history.frames[0].vertices == frozen.vertices && history.frames[0].colors == frozen.colors)
        refreshed.rawSamples = [.init(position: refreshed.vertices[0], imagePoint: SIMD2(0.5, 0.5))]
        // A real registration against this single sample would fail. The already
        // accepted capture timestamp must reuse its pose without invoking that path.
        let samePTS = try #require(try history.accept(refreshed, image: first.image))
        #expect(samePTS.presentationTimeSeconds == 1 && samePTS.cameraToAnchor == pose)
        #expect(samePTS.vertices == refreshed.vertices && samePTS.colors == refreshed.colors && samePTS.rawSamples.isEmpty)
        #expect(history.frames.map(\.presentationTimeSeconds) == [0, 1] && history.latestTime == 1)
        #expect(samePTS.historicalFrames.count == 1)
        #expect(samePTS.historicalFrames[0].vertices == frozen.vertices && samePTS.historicalFrames[0].colors == frozen.colors)
        #expect(samePTS.historicalFrames[0].cameraToAnchor == frozen.cameraToAnchor)
    }

    private func registrationObservation(at time: Double) throws -> (payload: TAPVideoPointCloudPayload, image: CGImage) {
        let width = 320, height = 240
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8(truncatingIfNeeded: ((x / 4 * 1237) ^ (y / 4 * 7919) ^ (x / 4 * y / 4 * 31)))
                let index = (y * width + x) * 4
                bytes[index] = value
                bytes[index + 1] = value
                bytes[index + 2] = value
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 159.5, cy: 119.5, imageWidth: width, imageHeight: height)
        var points: [SIMD3<Float>] = [], colors: [SIMD4<Float>] = []
        var samples: [TAPVideoPointCloudRegistrationFrame.Sample] = []
        for y in stride(from: 20, through: 220, by: 20) {
            for x in stride(from: 20, through: 300, by: 20) {
                let point = SIMD3<Float>((Float(x) - model.cx) / model.fx * 2, -(Float(y) - model.cy) / model.fy * 2, -2)
                let value = Float(bytes[(y * width + x) * 4]) / 255
                points.append(point)
                colors.append(SIMD4(value, value, value, 1))
                samples.append(.init(position: point, imagePoint: SIMD2((Float(x) + 0.5) / Float(width),
                                                                       (Float(y) + 0.5) / Float(height))))
            }
        }
        var payload = TAPVideoPointCloudPayload(presentationTimeSeconds: time, vertices: points, colors: colors, cameraModel: model)
        payload.rawSamples = samples
        return (payload, image)
    }

    @Test @MainActor func historicalGeometryKeepsOriginalRGBAndRefreshesTrimmedPieces() throws {
        let view = TAPVideoPointCloudSceneView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480)
        let points = [SIMD3<Float>(-3, 0, -2), SIMD3<Float>(-2.5, 0, -2), SIMD3<Float>(-1, 0, -2)]
        let colors = [SIMD4<Float>(0.8, 0.4, 0.2, 1), SIMD4<Float>(0.2, 0.8, 0.4, 1), SIMD4<Float>(0.4, 0.2, 0.8, 1)]
        var payload = TAPVideoPointCloudPayload(presentationTimeSeconds: 1,
            vertices: [SIMD3<Float>(0, 0, -2)], colors: [colors[0]], cameraModel: model)
        payload.cameraToAnchor.columns.3.x = 0.25
        payload.historicalFrames = [.init(presentationTimeSeconds: 0, vertices: points, colors: colors,
                                          cameraToAnchor: matrix_identity_float4x4)]
        view.present(payload)
        let camera = try #require(view.pointOfView)
        let cameraTransform = camera.transform
        let old = try #require(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudHistoricalFrame", recursively: true))
        let geometry = try #require(old.geometry)
        let current = try #require(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudCurrent", recursively: true)?.geometry)
        #expect(geometry.sources(for: .vertex).first?.data == points.withUnsafeBytes { Data($0) })
        #expect(geometry.sources(for: .color).first?.data == colors.withUnsafeBytes { Data($0) })
        let material = try #require(geometry.firstMaterial)
        #expect(material.program == nil && material.transparency == 1)
        #expect(material.readsFromDepthBuffer && material.writesToDepthBuffer && !old.isHidden)
        #expect(material.lightingModel == current.firstMaterial?.lightingModel)
        #expect(geometry.elements[0].pointSize == current.elements[0].pointSize)
        #expect(geometry.elements[0].minimumPointScreenSpaceRadius == current.elements[0].minimumPointScreenSpaceRadius)
        #expect(geometry.elements[0].maximumPointScreenSpaceRadius == current.elements[0].maximumPointScreenSpaceRadius)
        #expect(old.simdPosition.x == -0.25)
        let remainingPoints = Array(points.prefix(2)), remainingColors = Array(colors.prefix(2))
        payload.cameraToAnchor.columns.3.x = 0.5
        payload.historicalFrames = [.init(presentationTimeSeconds: 0, vertices: remainingPoints, colors: remainingColors,
                                          cameraToAnchor: matrix_identity_float4x4)]
        view.present(payload)
        let updated = try #require(old.geometry)
        #expect(updated !== geometry && old.simdPosition.x == -0.5)
        #expect(updated.sources(for: .vertex).first?.vectorCount == 2)
        #expect(updated.sources(for: .vertex).first?.data == remainingPoints.withUnsafeBytes { Data($0) })
        #expect(updated.sources(for: .color).first?.data == remainingColors.withUnsafeBytes { Data($0) })
        let otherPoints = Array(points.suffix(2)), otherColors = Array(colors.suffix(2))
        payload.historicalFrames = [.init(presentationTimeSeconds: 0, vertices: otherPoints, colors: otherColors,
                                          cameraToAnchor: matrix_identity_float4x4)]
        view.present(payload)
        let recropped = try #require(old.geometry)
        #expect(recropped !== updated && recropped.sources(for: .vertex).first?.vectorCount == 2)
        #expect(recropped.sources(for: .vertex).first?.data == otherPoints.withUnsafeBytes { Data($0) })
        #expect(recropped.sources(for: .color).first?.data == otherColors.withUnsafeBytes { Data($0) })
        #expect(SCNMatrix4EqualToMatrix4(camera.transform, cameraTransform))
        view.present(nil)
        #expect(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudHistoricalFrame", recursively: true) == nil)
    }

    @Test @MainActor func holdingAFrameAndGesturesKeepScenePointCountsAndHistoryVisible() throws {
        let view = TAPVideoPointCloudSceneView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480)
        let points = [SIMD3<Float>(-3, 0, -2), SIMD3<Float>(-2.5, 0, -2), SIMD3<Float>(-1, 0, -2)]
        let colors = [SIMD4<Float>](repeating: SIMD4(0.8, 0.4, 0.2, 1), count: points.count)
        var payload = TAPVideoPointCloudPayload(presentationTimeSeconds: 1, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [colors[0]], cameraModel: model)
        payload.historicalFrames = [.init(presentationTimeSeconds: 0, vertices: points, colors: colors,
                                          cameraToAnchor: matrix_identity_float4x4)]
        view.present(payload)
        let history = try #require(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudHistoricalFrame", recursively: true))
        let geometry = try #require(history.geometry)
        #expect(totalPointCount(in: view) == 4 && !history.isHidden)
        // With no new playback payload, every gesture changes only the viewing transform.
        let pan = VideoPointCloudTestPan()
        pan.phase = .began
        view.handleOrbitPan(pan)
        pan.phase = .changed
        pan.offset = CGPoint(x: 32, y: 8)
        view.handleOrbitPan(pan)
        pan.phase = .began
        view.handleTranslationPan(pan)
        pan.phase = .changed
        view.handleTranslationPan(pan)
        let pinch = UIPinchGestureRecognizer()
        pinch.state = .began
        view.handlePinch(pinch)
        pinch.state = .changed
        pinch.scale = 1.2
        view.handlePinch(pinch)
        let roll = UIRotationGestureRecognizer()
        roll.state = .began
        view.handleRoll(roll)
        roll.state = .changed
        roll.rotation = 0.2
        view.handleRoll(roll)
        #expect(totalPointCount(in: view) == 4 && history.geometry === geometry && !history.isHidden)
        view.present(payload)
        #expect(totalPointCount(in: view) == 4 && !history.isHidden)
        let reset = UITapGestureRecognizer()
        reset.state = .recognized
        view.handleReset(reset)
        #expect(totalPointCount(in: view) == 4 && !history.isHidden)
        #expect(history.geometry?.sources(for: .color).first?.data == colors.withUnsafeBytes { Data($0) })
    }

    @Test @MainActor func recordedCameraRotationMovesCurrentAndHistoryWithoutChangingTheirData() throws {
        let view = TAPVideoPointCloudSceneView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let store = TAPVideoPointCloudStore()
        store.attach(view)
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480)
        var payload = TAPVideoPointCloudPayload(presentationTimeSeconds: 1, vertices: [SIMD3<Float>(0, 0, -2)],
            colors: [SIMD4<Float>(0.8, 0.4, 0.2, 1)], cameraModel: model)
        payload.historicalFrames = [.init(presentationTimeSeconds: 0, vertices: [SIMD3<Float>(-3, 0, -2)],
            colors: [SIMD4<Float>(0.2, 0.8, 0.4, 1)], cameraToAnchor: matrix_identity_float4x4)]
        store.present(payload)
        let interaction = try #require(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
        let current = try #require(interaction.childNode(withName: "TAPVideoPointCloudCurrent", recursively: false))
        let history = try #require(current.childNode(withName: "TAPVideoPointCloudHistoricalFrame", recursively: false))
        let currentGeometry = try #require(current.geometry), historyGeometry = try #require(history.geometry)
        let cameraTransform = try #require(view.pointOfView).simdTransform
        let pan = VideoPointCloudTestPan()
        pan.phase = .began
        view.handleOrbitPan(pan)
        pan.phase = .changed
        pan.offset = CGPoint(x: 32, y: 8)
        view.handleOrbitPan(pan)
        let userTransform = interaction.simdTransform
        let compensation = current.simdTransform
        let historicalTransform = history.simdTransform
        let currentWorld = current.simdWorldTransform, historyWorld = history.simdWorldTransform
        let caption = view.accessibilityValue
        let rotation = simd_float4x4(simd_quatf(angle: .pi / 6, axis: SIMD3(0, 1, 0)))
        store.rotateCamera(rotation)
        let expected = compensation * rotation
        #expect((0..<4).allSatisfy { simd_length(current.simdTransform[$0] - expected[$0]) < 0.00001 })
        #expect(interaction.simdTransform == userTransform && history.simdTransform == historicalTransform)
        #expect(view.pointOfView?.simdTransform == cameraTransform)
        #expect(current.simdWorldTransform != currentWorld && history.simdWorldTransform != historyWorld)
        #expect(current.geometry === currentGeometry && history.geometry === historyGeometry && totalPointCount(in: view) == 2)
        #expect(currentGeometry.sources(for: .vertex).first?.data == payload.vertices.withUnsafeBytes { Data($0) })
        #expect(currentGeometry.sources(for: .color).first?.data == payload.colors.withUnsafeBytes { Data($0) })
        #expect(historyGeometry.sources(for: .vertex).first?.data == payload.historicalFrames[0].vertices.withUnsafeBytes { Data($0) })
        #expect(historyGeometry.sources(for: .color).first?.data == payload.historicalFrames[0].colors.withUnsafeBytes { Data($0) })
        #expect(store.presentationTimeSeconds == 1 && view.accessibilityValue == caption)
    }

    @MainActor private func totalPointCount(in view: TAPVideoPointCloudSceneView) -> Int {
        func count(_ node: SCNNode) -> Int {
            (node.geometry?.sources(for: .vertex).first?.vectorCount ?? 0) + node.childNodes.reduce(0) { $0 + count($1) }
        }
        return view.scene.map { count($0.rootNode) } ?? 0
    }

    @Test @MainActor func defaultViewCentersTheCurrentFrameWhileHistoryMoves() throws {
        let view = TAPVideoPointCloudSceneView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        // An off-center optical principal point must not shift the image center.
        let model = TAPDepthProjectionCameraModel(fx: 300, fy: 310, cx: 140, cy: 235, imageWidth: 320, imageHeight: 480)
        let center = SIMD3<Float>((160 - model.cx) / model.fx * 2, -(240 - model.cy) / model.fy * 2, -2)
        var payload = TAPVideoPointCloudPayload(presentationTimeSeconds: 0, vertices: [center],
            colors: [SIMD4<Float>(1, 0.5, 0.25, 1)], cameraModel: model)
        for position: Float in [0, 0.5, 2] {
            payload.cameraToAnchor.columns.3.x = position
            view.present(payload)
            let camera = try #require(view.pointOfView?.camera)
            let interaction = try #require(view.scene?.rootNode.childNode(withName: "TAPVideoPointCloudInteraction", recursively: false))
            let cloud = try #require(interaction.childNode(withName: "TAPVideoPointCloudCurrent", recursively: false))
            let clip = simd_float4x4(camera.projectionTransform) * interaction.simdTransform * cloud.simdTransform * SIMD4(center, 1)
            #expect(abs(clip.x / clip.w) < 0.000_001 && abs(clip.y / clip.w) < 0.000_001)
            #expect(interaction.simdScale == SIMD3<Float>(repeating: 1))
        }
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
