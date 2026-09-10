//
//  TAPDepthAnalysisPlaneRegionTests.swift
//  TAPCamDemoTests
//
//  Created by OpenAI on 2026/6/13.
//

import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import simd
import SwiftUI
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPDepthAnalysisPlaneRegionTests {
    @Test func projectorUsesCalibrationToProduceCameraCoordinates() throws {
        let depthMap = TAPMetricDepthMap(
            width: 8,
            height: 8,
            samples: Array(repeating: 2.0, count: 64),
            calibration: Self.sampleCalibration
        )

        let center = try #require(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 4, y: 4))
        let right = try #require(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 5, y: 4))

        #expect(abs(center.x) < 0.0001)
        #expect(abs(center.y) < 0.0001)
        #expect(abs(center.z - 2.0) < 0.0001)
        #expect(abs(right.x - 0.02) < 0.0001)
    }

    @Test func projectionCameraContractUsesCaptureCameraIntrinsics() throws {
        let depthMap = TAPMetricDepthMap(
            width: 8,
            height: 8,
            samples: Array(repeating: 1.5, count: 64),
            calibration: Self.sampleCalibration
        )
        let cameraModel = try #require(TAPDepthProjectionCameraModel(
            depthMap: depthMap,
            imageWidth: 16,
            imageHeight: 8
        ))
        let fitted = TAPDepthProjectionCameraContract.fittedIntrinsics(
            cameraModel: cameraModel,
            viewportSize: CGSize(width: 200, height: 100)
        )
        let matrix = TAPDepthProjectionCameraContract.projectionMatrix(
            cameraModel: cameraModel,
            viewportSize: CGSize(width: 200, height: 100),
            near: 0.01,
            far: 100
        )

        #expect(abs(cameraModel.fx - 200) < 0.0001)
        #expect(abs(cameraModel.cx - 8) < 0.0001)
        #expect(abs(fitted.fx - 2500) < 0.0001)
        #expect(abs(fitted.cx - 100) < 0.0001)
        #expect(abs(matrix.m11 - 25) < 0.0001)
        #expect(abs(matrix.m31) < 0.0001)
        #expect(abs(matrix.m34 + 1) < 0.0001)
        #expect(abs(matrix.m43 + 0.020002) < 0.0001)
    }

    @Test func depthProjectionInteractionKeepsSceneKitDefaultCameraControlDisabled() {
        #expect(TAPDepthProjectionInteractionPolicy.usesSceneKitDefaultCameraControl == false)
    }

    @Test func depthProjectionInteractionClampsUserZoomScale() {
        #expect(TAPDepthProjectionInteractionPolicy.clampedScale(0.1) == TAPDepthProjectionInteractionPolicy.minimumScale)
        #expect(TAPDepthProjectionInteractionPolicy.clampedScale(1.4) == 1.4)
        #expect(TAPDepthProjectionInteractionPolicy.clampedScale(9) == TAPDepthProjectionInteractionPolicy.maximumScale)
    }

    @Test func depthProjectionInteractionUsesNaturalScreenRollDirection() {
        let startAngle: Float = 0.4

        #expect(TAPDepthProjectionInteractionPolicy.rollAngle(startAngle: startAngle, gestureRotation: 0.2) < startAngle)
        #expect(TAPDepthProjectionInteractionPolicy.rollAngle(startAngle: startAngle, gestureRotation: -0.2) > startAngle)
    }

    @Test func depthProjectionMotionParallaxMapsRelativeAttitude() {
        let recentered = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            relativePitch: 0,
            relativeRoll: 0
        )
        let tilted = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            relativePitch: 0.2,
            relativeRoll: -0.4
        )
        let wrappedRoll = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            relativePitch: 0,
            relativeRoll: Double.pi * 2 + 0.02
        )

        #expect(abs(recentered.x) < 0.0001)
        #expect(abs(recentered.y) < 0.0001)
        #expect(abs(tilted.x - 0.012) < 0.0001)
        #expect(abs(tilted.y + 0.032) < 0.0001)
        #expect(abs(wrappedRoll.y - 0.0016) < 0.0001)
    }

    @Test func depthProjectionInteractionConvertsScreenPanUsingCaptureIntrinsics() throws {
        let cameraModel = TAPDepthProjectionCameraModel(
            fx: 100,
            fy: 200,
            cx: 50,
            cy: 50,
            imageWidth: 100,
            imageHeight: 100
        )

        let offset = TAPDepthProjectionInteractionPolicy.scenePanOffset(
            forScreenTranslation: CGPoint(x: 20, y: 30),
            cameraModel: cameraModel,
            viewportSize: CGSize(width: 100, height: 100),
            targetDepth: 2
        )

        #expect(abs(offset.x - 0.4) < 0.0001)
        #expect(abs(offset.y + 0.3) < 0.0001)
    }

    @Test func depthProjectionInteractionPivotsAroundTargetDepthWithoutChangingInitialProjection() {
        let targetDepth: Float = 2
        let interactionNode = SCNNode()
        interactionNode.position = TAPDepthProjectionInteractionPolicy.interactionPivotPosition(
            targetDepth: targetDepth
        )
        let geometryRootNode = SCNNode()
        geometryRootNode.position = TAPDepthProjectionInteractionPolicy.geometryCompensationPosition(
            targetDepth: targetDepth
        )
        interactionNode.addChildNode(geometryRootNode)

        let targetVertex = SCNVector3(0, 0, -targetDepth)
        let offCenterVertex = SCNVector3(0.4, 0, -1.2)
        let initialTarget = geometryRootNode.convertPosition(targetVertex, to: nil)
        let initialOffCenter = geometryRootNode.convertPosition(offCenterVertex, to: nil)

        interactionNode.eulerAngles.y = .pi / 2
        let rotatedTarget = geometryRootNode.convertPosition(targetVertex, to: nil)
        let rotatedOffCenter = geometryRootNode.convertPosition(offCenterVertex, to: nil)

        #expect(abs(initialTarget.z + targetDepth) < 0.0001)
        #expect(abs(initialOffCenter.x - offCenterVertex.x) < 0.0001)
        #expect(abs(initialOffCenter.z - offCenterVertex.z) < 0.0001)
        #expect(abs(rotatedTarget.x) < 0.0001)
        #expect(abs(rotatedTarget.z + targetDepth) < 0.0001)
        #expect(abs(rotatedOffCenter.x - initialOffCenter.x) > 0.01)
        #expect(abs(rotatedOffCenter.z - initialOffCenter.z) > 0.01)
    }

    @Test func depthProjectionSampleFilterRejectsFarDepthSentinels() {
        let depths: [Float] = [1, 1.2, 1.4, 9_999, .nan]
        let renderable = TAPDepthProjectionSampleFilter.sampledDepths(
            from: TAPMetricDepthMap(width: 5, height: 1, samples: depths, calibration: Self.sampleCalibration)
        )
        let targetDepth = TAPDepthProjectionSampleFilter.targetDepth(from: depths)

        #expect(renderable.map(\.depthMeters) == [1.0, 1.2, 1.4])
        #expect(abs(targetDepth - 1.2) < 0.0001)
        #expect(TAPDepthProjectionSampleFilter.isRenderableDepth(100) == false)
    }

    @Test func photoPayloadKeepsTheGeometrySamplingGridAndAdmission() throws {
        let values: [Float] = [2, .nan, .infinity, 0, -1, 100, 9_999, 0.000_000_1, 99.99]
        // Cross the 12,000-point grid's step-1/step-2 boundary, including an odd edge.
        for width in [218, 219] {
            let height = 220
            let depthMap = TAPMetricDepthMap(width: width, height: height,
                samples: (0..<(width * height)).map { values[$0 % values.count] },
                calibration: Self.calibration(width: width, height: height,
                    intrinsicMatrix: [140, 0, 0, 0, 160, 0, 50.25, 80.75, 1]))
            let oldSamples = TAPDepthGeometryProjector.sampledPoints(from: depthMap,
                in: CGRect(x: 0, y: 0, width: width, height: height), maxCount: 12_000)
                .filter { $0.point.z < 100 }
            let samples = TAPDepthProjectionSampleFilter.sampledDepths(from: depthMap)
            #expect(samples.map(\.imagePoint) == oldSamples.map(\.imagePoint))
            #expect(samples.map(\.depthMeters) == oldSamples.map(\.point.z))
            let frame = try #require(TAPDepthDisplayProjectionFrame(depthMap: depthMap,
                imageWidth: width, imageHeight: height, orientation: .rightMirrored))
            let payload = try #require(TAPDepthProjectionScenePayloadBuilder.makePayloadData(
                image: nil, depthMap: depthMap, orientation: .rightMirrored, selectedPlaneRegion: nil))
            #expect(payload.baseVertices == oldSamples.map {
                frame.sceneVertex(forDepthPoint: $0.imagePoint, depthMeters: $0.point.z)
            })
            #expect(payload.baseColors.count == oldSamples.count)
            #expect(payload.targetDepth == TAPDepthProjectionSampleFilter.targetDepth(from: oldSamples.map(\.point.z)))
        }
        let invalidMaps = [
            TAPMetricDepthMap(width: 2, height: 2, samples: [1], calibration: Self.sampleCalibration),
            TAPMetricDepthMap(width: 1, height: 1, samples: [1], calibration: nil)
        ]
        for depthMap in invalidMaps {
            #expect(TAPDepthProjectionScenePayloadBuilder.makePayloadData(
                image: nil, depthMap: depthMap, orientation: .up, selectedPlaneRegion: nil) == nil)
        }
    }

    @Test func rgbSamplerProjectsDepthPixelsBackToPrimaryImageColors() throws {
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 1,
            samples: Array(repeating: 1, count: 2),
            calibration: Self.calibration(width: 2, height: 1)
        )
        let image = try TAPDepthRGBAImageRenderer.image(
            pixels: [
                255, 0, 0, 255,
                0, 0, 255, 255
            ],
            width: 2,
            height: 1
        )
        let sampler = try #require(TAPRGBPixelSampler(image: image))
        let projectionFrame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: image.width,
            imageHeight: image.height,
            orientation: .up
        ))

        let left = sampler.color(
            atDepthPoint: CGPoint(x: 0, y: 0),
            projectionFrame: projectionFrame
        )
        let right = sampler.color(
            atDepthPoint: CGPoint(x: 1, y: 0),
            projectionFrame: projectionFrame
        )

        #expect(left.x > 0.99)
        #expect(left.z < 0.01)
        #expect(right.x < 0.01)
        #expect(right.z > 0.99)
    }

    @Test func displayProjectionFrameUsesSameRightRotationAsImageMapper() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 3,
            samples: Array(repeating: 1, count: 12),
            calibration: Self.calibration(width: 4, height: 3)
        )
        let frame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: 4,
            imageHeight: 3,
            orientation: .right
        ))

        let displayPoint = frame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 0))
        let mapperRect = TAPImageOrientationMapper.displayedRect(
            fromNative: CGRect(x: 1, y: 0, width: 1, height: 1),
            nativeSize: CGSize(width: 4, height: 3),
            orientation: .right
        )

        #expect(displayPoint == CGPoint(x: mapperRect.midX - 0.5, y: mapperRect.midY - 0.5))
        #expect(frame.cameraModel.imageWidth == 3)
        #expect(frame.cameraModel.imageHeight == 4)
    }

    @Test func displayProjectionFrameRotatesRightOrientationIntrinsicsAndPixels() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 3,
            samples: Array(repeating: 1, count: 12),
            calibration: Self.calibration(
                width: 4,
                height: 3,
                intrinsicMatrix: [40, 0, 0, 0, 30, 0, 1, 1, 1]
            )
        )
        let frame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: 4,
            imageHeight: 3,
            orientation: .right
        ))

        #expect(abs(frame.cameraModel.fx - 30) < 0.0001)
        #expect(abs(frame.cameraModel.fy - 40) < 0.0001)
        #expect(abs(frame.cameraModel.cx - 1) < 0.0001)
        #expect(abs(frame.cameraModel.cy - 1) < 0.0001)
        #expect(frame.cameraModel.imageWidth == 3)
        #expect(frame.cameraModel.imageHeight == 4)
        #expect(frame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 0)) == CGPoint(x: 2, y: 1))
        #expect(frame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 2)) == CGPoint(x: 0, y: 1))
    }

    @Test func displayProjectionFrameKeepsMirroredRotatedOrientationNamesAlignedWithImageMapper() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 3,
            samples: Array(repeating: 1, count: 12),
            calibration: Self.calibration(
                width: 4,
                height: 3,
                intrinsicMatrix: [40, 0, 0, 0, 30, 0, 0.5, 1.25, 1]
            )
        )
        let leftMirroredFrame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: 4,
            imageHeight: 3,
            orientation: .leftMirrored
        ))
        let rightMirroredFrame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: 4,
            imageHeight: 3,
            orientation: .rightMirrored
        ))

        #expect(leftMirroredFrame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 0)) == CGPoint(x: 0, y: 1))
        #expect(leftMirroredFrame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 2)) == CGPoint(x: 2, y: 1))
        #expect(rightMirroredFrame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 0)) == CGPoint(x: 2, y: 2))
        #expect(rightMirroredFrame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 2)) == CGPoint(x: 0, y: 2))
        #expect(abs(leftMirroredFrame.cameraModel.fx - 30) < 0.0001)
        #expect(abs(leftMirroredFrame.cameraModel.fy - 40) < 0.0001)
        #expect(abs(leftMirroredFrame.cameraModel.cx - 1.25) < 0.0001)
        #expect(abs(leftMirroredFrame.cameraModel.cy - 0.5) < 0.0001)
        #expect(abs(rightMirroredFrame.cameraModel.fx - 30) < 0.0001)
        #expect(abs(rightMirroredFrame.cameraModel.fy - 40) < 0.0001)
        #expect(abs(rightMirroredFrame.cameraModel.cx - 0.75) < 0.0001)
        #expect(abs(rightMirroredFrame.cameraModel.cy - 2.5) < 0.0001)
    }

    @Test func displayProjectionFrameBuildsSceneKitCameraFacingVertices() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 3,
            samples: Array(repeating: 2, count: 12),
            calibration: Self.calibration(
                width: 4,
                height: 3,
                intrinsicMatrix: [40, 0, 0, 0, 30, 0, 1, 1, 1]
            )
        )
        let frame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: 4,
            imageHeight: 3,
            orientation: .up
        ))

        let center = frame.sceneVertex(forDepthPoint: CGPoint(x: 1, y: 1), depthMeters: 2)
        let right = frame.sceneVertex(forDepthPoint: CGPoint(x: 2, y: 1), depthMeters: 2)
        let upper = frame.sceneVertex(forDepthPoint: CGPoint(x: 1, y: 0), depthMeters: 2)
        let lower = frame.sceneVertex(forDepthPoint: CGPoint(x: 1, y: 2), depthMeters: 2)

        #expect(abs(center.x) < 0.0001)
        #expect(abs(center.y) < 0.0001)
        #expect(abs(center.z + 2) < 0.0001)
        #expect(right.x > center.x)
        #expect(upper.y > center.y)
        #expect(lower.y < center.y)
    }

    @Test func rgbSamplerKeepsRawPixelColorWhenProjectionFrameRotatesGeometry() throws {
        let depthMap = TAPMetricDepthMap(
            width: 3,
            height: 2,
            samples: Array(repeating: 1, count: 6),
            calibration: Self.calibration(width: 3, height: 2)
        )
        let image = try TAPDepthRGBAImageRenderer.image(
            pixels: [
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
                0, 255, 255, 255,
                255, 0, 255, 255,
                255, 255, 0, 255
            ],
            width: 3,
            height: 2
        )
        let sampler = try #require(TAPRGBPixelSampler(image: image))
        let projectionFrame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: image.width,
            imageHeight: image.height,
            orientation: .right
        ))

        let bottomLeftRawPixel = sampler.color(
            atDepthPoint: CGPoint(x: 0, y: 1),
            projectionFrame: projectionFrame
        )

        #expect(bottomLeftRawPixel.x < 0.01)
        #expect(bottomLeftRawPixel.y > 0.99)
        #expect(bottomLeftRawPixel.z > 0.99)
    }

    @Test func projectionPayloadBuilderProducesRGBDepthVerticesAndHighlightData() throws {
        let depthMap = TAPMetricDepthMap(
            width: 2,
            height: 1,
            samples: [1, 1.25],
            calibration: Self.calibration(width: 2, height: 1)
        )
        let image = try TAPDepthRGBAImageRenderer.image(
            pixels: [
                255, 0, 0, 255,
                0, 0, 255, 255
            ],
            width: 2,
            height: 1
        )
        let base = Self.samplePlaneRegion()
        let region = TAPPlaneRegion(
            seedPixel: CGPoint(x: 1, y: 0),
            estimate: base.estimate,
            pixelRuns: [
                TAPPlanePixelRun(y: 0, xStart: 1, xEndExclusive: 2)
            ],
            gridCells: base.gridCells,
            contourPoints: base.contourPoints,
            imageBounds: CGRect(x: 1, y: 0, width: 1, height: 1),
            confidence: base.confidence,
            flatnessScore: base.flatnessScore,
            sampleCount: 1,
            areaSquareMeters: base.areaSquareMeters
        )

        let payload = try #require(TAPDepthProjectionScenePayloadBuilder.makePayloadData(
            image: image,
            depthMap: depthMap,
            orientation: .up,
            selectedPlaneRegion: region
        ))

        #expect(payload.baseVertices.count == 2)
        #expect(payload.baseColors.count == 2)
        #expect(payload.highlightVertices.count == 1)
        #expect(payload.baseColors[0].x > 0.99)
        #expect(payload.baseColors[0].z < 0.01)
        #expect(payload.baseColors[1].x < 0.01)
        #expect(payload.baseColors[1].z > 0.99)
        #expect(payload.baseVertices.allSatisfy { $0.z < 0 })
    }

    @Test func planeRegionPixelRunsBuildProjectionHighlightMask() throws {
        let depthMap = TAPMetricDepthMap(
            width: 5,
            height: 4,
            samples: Array(repeating: 1, count: 20),
            calibration: Self.sampleCalibration
        )
        let base = Self.samplePlaneRegion()
        let region = TAPPlaneRegion(
            seedPixel: base.seedPixel,
            estimate: base.estimate,
            pixelRuns: [
                TAPPlanePixelRun(y: 1, xStart: 1, xEndExclusive: 3),
                TAPPlanePixelRun(y: 2, xStart: -2, xEndExclusive: 2),
                TAPPlanePixelRun(y: 8, xStart: 0, xEndExclusive: 5)
            ],
            gridCells: base.gridCells,
            contourPoints: base.contourPoints,
            imageBounds: base.imageBounds,
            confidence: base.confidence,
            flatnessScore: base.flatnessScore,
            sampleCount: base.sampleCount,
            areaSquareMeters: base.areaSquareMeters
        )

        let indexes = TAPPlaneRegionHighlightMask.depthIndexSet(for: region, depthMap: depthMap)

        #expect(indexes == Set([6, 7, 10, 11]))
    }

    @Test @MainActor func projectionSelectionPreservesSceneAndUserTransform() async throws {
        let view = DepthProjectionSceneView.ProjectionSCNView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let coordinator = DepthProjectionSceneView.Coordinator()
        let region = Self.samplePlaneRegion()
        let color = UIColor(red: 0.2501, green: 0.5, blue: 0.75, alpha: 1)
        Self.updateProjection(coordinator, view: view, region: region, color: color)
        await (try #require(coordinator.payloadBuildTask)).value

        let scene = try #require(view.scene)
        let camera = try #require(view.pointOfView)
        let cameraObject = try #require(camera.camera)
        let interaction = try #require(scene.rootNode.childNode(withName: "DepthProjectionInteractionRoot", recursively: true))
        let motion = try #require(scene.rootNode.childNode(withName: "DepthProjectionMotionRoot", recursively: true))
        let geometryRoot = try #require(scene.rootNode.childNode(withName: "DepthProjectionGeometryRoot", recursively: true))
        let base = try #require(scene.rootNode.childNode(withName: "DepthProjectionModel", recursively: true))
        let baseGeometry = try #require(base.geometry)
        let highlight = try #require(scene.rootNode.childNode(withName: "SelectedPlaneProjection", recursively: true))
        let originalVertex = try Self.firstVertex(of: highlight)
        interaction.position = SCNVector3(0.1, 0.2, -2)
        interaction.eulerAngles = SCNVector3(0.2, 0.3, 0.4)
        interaction.scale = SCNVector3(1.5, 1.5, 1.5)
        let transform = interaction.transform

        // All former signature fields are equal; only the actual pixels move.
        let movedRegion = Self.samplePlaneRegion(pixelRuns: [TAPPlanePixelRun(y: 3, xStart: 4, xEndExclusive: 6)])
        Self.updateProjection(coordinator, view: view, region: movedRegion, color: color)
        await (try #require(coordinator.payloadBuildTask)).value
        #expect(try Self.firstVertex(of: highlight).x > originalVertex.x)

        // These colors used to collide after rounding to three decimal places.
        let changedColor = UIColor(red: 0.2502, green: 0.5, blue: 0.75, alpha: 1)
        Self.updateProjection(coordinator, view: view, region: movedRegion, color: changedColor)
        await (try #require(coordinator.payloadBuildTask)).value
        let materialColor = try #require(highlight.geometry?.firstMaterial?.diffuse.contents as? UIColor)
        var red: CGFloat = 0
        materialColor.getRed(&red, green: nil, blue: nil, alpha: nil)
        #expect(abs(red - 0.2502) < 0.00001)

        Self.updateProjection(coordinator, view: view, region: nil, color: changedColor)
        await (try #require(coordinator.payloadBuildTask)).value
        #expect(highlight.geometry == nil)
        #expect(!highlight.hasActions)
        #expect(view.scene === scene)
        #expect(view.pointOfView === camera)
        #expect(camera.camera === cameraObject)
        #expect(base.geometry === baseGeometry)
        for node in [interaction, motion, geometryRoot, base, highlight] {
            #expect(scene.rootNode.childNode(withName: try #require(node.name), recursively: true) === node)
        }
        #expect(SCNMatrix4EqualToMatrix4(interaction.transform, transform))
    }

    @Test @MainActor func cancelledProjectionBuildsCannotPublishOrClearReplacement() async throws {
        let view = DepthProjectionSceneView.ProjectionSCNView(frame: .zero)
        let gate = ProjectionPayloadGate()
        let coordinator = DepthProjectionSceneView.Coordinator(payloadBuilder: { await gate.build($0) })
        let regionA = Self.samplePlaneRegion()
        let regionB = Self.samplePlaneRegion(pixelRuns: [TAPPlanePixelRun(y: 3, xStart: 4, xEndExclusive: 6)])

        Self.updateProjection(coordinator, view: view, region: regionA)
        let firstA = try #require(coordinator.payloadBuildTask)
        await gate.waitForBuild(1)
        Self.updateProjection(coordinator, view: view, region: regionB)
        let taskB = try #require(coordinator.payloadBuildTask)
        await gate.waitForBuild(2)
        Self.updateProjection(coordinator, view: view, region: regionA)
        let latestA = try #require(coordinator.payloadBuildTask)
        await gate.waitForBuild(3)

        // The builders deliberately finish even after their tasks are cancelled.
        try await gate.finish(1)
        await firstA.value
        #expect(view.scene == nil)
        #expect(coordinator.payloadBuildTask?.isCancelled == false)
        try await gate.finish(2)
        await taskB.value
        #expect(view.scene == nil)
        #expect(coordinator.payloadBuildTask?.isCancelled == false)
        try await gate.finish(3)
        await latestA.value
        let scene = try #require(view.scene)
        let highlight = try #require(scene.rootNode.childNode(withName: "SelectedPlaneProjection", recursively: true))
        let vertex = try Self.firstVertex(of: highlight)
        #expect(coordinator.payloadBuildTask == nil)

        Self.updateProjection(coordinator, view: view, region: regionB)
        let dismantledTask = try #require(coordinator.payloadBuildTask)
        await gate.waitForBuild(4)
        DepthProjectionSceneView.dismantleUIView(view, coordinator: coordinator)
        #expect(dismantledTask.isCancelled)
        #expect(coordinator.payloadBuildTask == nil)
        try await gate.finish(4)
        await dismantledTask.value
        #expect(view.scene === scene)
        #expect(try Self.firstVertex(of: highlight) == vertex)
    }

    @Test @MainActor func projectionUsesLatestReduceMotionAndRetainsSceneOnMissingPayload() async throws {
        let view = DepthProjectionSceneView.ProjectionSCNView(frame: .zero)
        let gate = ProjectionPayloadGate()
        let coordinator = DepthProjectionSceneView.Coordinator(payloadBuilder: { await gate.build($0) })
        let region = Self.samplePlaneRegion()
        Self.updateProjection(coordinator, view: view, region: region)
        let task = try #require(coordinator.payloadBuildTask)
        await gate.waitForBuild(1)
        Self.updateProjection(coordinator, view: view, region: region, reduceMotion: true)
        #expect(!task.isCancelled)
        try await gate.finish(1)
        await task.value

        let scene = try #require(view.scene)
        let highlight = try #require(scene.rootNode.childNode(withName: "SelectedPlaneProjection", recursively: true))
        let geometry = try #require(highlight.geometry)
        #expect(highlight.opacity == 0.88)
        #expect(!highlight.hasActions)
        Self.updateProjection(coordinator, view: view, region: region, reduceMotion: false)
        #expect(coordinator.payloadBuildTask == nil)
        #expect(highlight.geometry === geometry)
        #expect(highlight.hasActions)
        Self.updateProjection(coordinator, view: view, region: region, reduceMotion: true)
        #expect(coordinator.payloadBuildTask == nil)
        #expect(highlight.opacity == 0.88)
        #expect(!highlight.hasActions)

        Self.updateProjection(coordinator, view: view, region: region, color: .red, reduceMotion: true)
        let missingTask = try #require(coordinator.payloadBuildTask)
        await gate.waitForBuild(2)
        try await gate.finish(2, missingPayload: true)
        await missingTask.value
        #expect(view.scene === scene)
        #expect(highlight.geometry === geometry)
        #expect(highlight.opacity == 0.88)
    }

    @Test func planeHighlightMaskStaysInNativeDepthSpaceWhenDisplayRotates() throws {
        let depthMap = TAPMetricDepthMap(
            width: 4,
            height: 3,
            samples: Array(repeating: 1, count: 12),
            calibration: Self.calibration(width: 4, height: 3)
        )
        let base = Self.samplePlaneRegion()
        let region = TAPPlaneRegion(
            seedPixel: CGPoint(x: 1, y: 0),
            estimate: base.estimate,
            pixelRuns: [
                TAPPlanePixelRun(y: 0, xStart: 1, xEndExclusive: 2)
            ],
            gridCells: base.gridCells,
            contourPoints: base.contourPoints,
            imageBounds: CGRect(x: 1, y: 0, width: 1, height: 1),
            confidence: base.confidence,
            flatnessScore: base.flatnessScore,
            sampleCount: 1,
            areaSquareMeters: base.areaSquareMeters
        )
        let frame = try #require(TAPDepthDisplayProjectionFrame(
            depthMap: depthMap,
            imageWidth: 4,
            imageHeight: 3,
            orientation: .right
        ))

        let selectedDisplayPoint = frame.displayImagePoint(forDepthPoint: CGPoint(x: 1, y: 0))
        let indexes = TAPPlaneRegionHighlightMask.depthIndexSet(for: region, depthMap: depthMap)

        #expect(selectedDisplayPoint == CGPoint(x: 2, y: 1))
        #expect(indexes.contains(depthMap.index(x: 1, y: 0)))
        #expect(!indexes.contains(depthMap.index(x: 2, y: 1)))
    }

    @Test func cameraIntrinsicsRejectNonFiniteAndZeroCalibration() throws {
        let zeroFocalCalibration = Self.calibration(
            width: 8,
            height: 8,
            intrinsicMatrix: [0, 0, 0, 0, 140, 0, 4, 4, 1]
        )
        let nonFiniteCalibration = Self.calibration(
            width: 8,
            height: 8,
            intrinsicMatrix: [Float.nan, 0, 0, 0, 140, 0, 4, 4, 1]
        )
        let badReferenceCalibration = Self.calibration(
            width: 8,
            height: 8,
            referenceWidth: .infinity
        )

        #expect(TAPCameraIntrinsics(calibration: zeroFocalCalibration, depthWidth: 8, depthHeight: 8) == nil)
        #expect(TAPCameraIntrinsics(calibration: nonFiniteCalibration, depthWidth: 8, depthHeight: 8) == nil)
        #expect(TAPCameraIntrinsics(calibration: badReferenceCalibration, depthWidth: 8, depthHeight: 8) == nil)

        let depthMap = TAPMetricDepthMap(
            width: 8,
            height: 8,
            samples: Array(repeating: Float(1.5), count: 64),
            calibration: nonFiniteCalibration
        )

        #expect(TAPDepthGeometryProjector.point(depthMap: depthMap, x: 4, y: 4) == nil)

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 4, y: 4),
                strictness: 0.68
            )
            Issue.record("Expected invalid calibration to use the missing-calibration plane error.")
        } catch TAPPlaneGrowthError.cameraCalibrationMissing {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected plane growth error: \(error)")
        }
    }

    @Test func seedPlaneGrowthRejectsNonFiniteSeedBeforePixelConversion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: CGFloat.nan, y: 8),
                strictness: 0.68
            )
            Issue.record("Expected non-finite seed to fail before pixel conversion.")
        } catch TAPPlaneGrowthError.invalidSeed {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected non-finite seed error: \(error)")
        }
    }

    @Test func planeEstimatorFindsSyntheticFlatDepthRegion() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: 1.5, count: 256),
            calibration: TAPDepthManifest.CameraCalibration(
                intrinsicMatrixReferenceWidth: 16,
                intrinsicMatrixReferenceHeight: 16,
                pixelSizeMillimeters: 0.001,
                lensDistortionLookupTablePresent: false,
                inverseLensDistortionLookupTablePresent: false,
                lensDistortionCenterX: 8,
                lensDistortionCenterY: 8,
                intrinsicMatrix: [120, 0, 0, 0, 120, 0, 8, 8, 1],
                extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
            )
        )

        let samples = TAPDepthGeometryProjector.sampledPoints(
            from: depthMap,
            in: CGRect(x: 0, y: 0, width: 16, height: 16)
        )
        let plane = try #require(TAPPlaneEstimator.estimatePlane(
            from: samples,
            residualThresholdMeters: 0.035
        ))

        #expect(plane.averageResidualMeters < 0.001)
        #expect(plane.inlierRatio > 0.95)
        #expect(abs(abs(plane.normal.z) - 1) < 0.001)
    }

    @Test func seedPlaneGrowthFindsLargeTiltedPlaneRegion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68
        )

        #expect(region.sampleCount > 700)
        #expect(region.confidence > 0.82)
        #expect(region.flatnessScore > 0.90)
        #expect(region.areaSquareMeters > 0)
        #expect(!region.pixelRuns.isEmpty)
        #expect(!region.gridCells.isEmpty)
        #expect(region.gridCells.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })
        #expect(!region.contourPoints.isEmpty)
    }

    @Test func seedPlaneGrowthPublishesPartialGridProgress() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)
        var progressEvents: [TAPPlaneGridProgress] = []

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68,
            progressHandler: { progressEvents.append($0) }
        )

        #expect(!progressEvents.isEmpty)
        #expect(progressEvents.first?.seedPixel == region.seedPixel)
        #expect(progressEvents.first?.gridCells.isEmpty == false)
        let progressCellCounts = progressEvents.map(\.gridCells.count)
        #expect(progressCellCounts.first == 6)
        #expect(progressCellCounts.dropLast().allSatisfy { $0.isMultiple(of: 6) })
        #expect(zip(progressCellCounts, progressCellCounts.dropFirst()).allSatisfy { $1 > $0 })
        #expect(progressEvents.first?.gridCells == Array(region.gridCells.prefix(6)))
        let orderedDistances = region.gridCells.map { Self.squaredDistanceFromSeed($0, seedPixel: region.seedPixel) }
        #expect(zip(orderedDistances, orderedDistances.dropFirst()).allSatisfy { lhs, rhs in lhs <= rhs })
        #expect(progressEvents.last?.gridCells == region.gridCells)
        #expect((progressEvents.last?.progress ?? 0) >= 0.99)
    }

    @Test func depthAnalysisPlaneRegionDetectorBuildsGeometryAndDetectsRegion() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)
        let detector = DepthAnalysisPlaneRegionDetector()

        let detection = try detector.detectRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68,
            geometryCache: nil
        )

        #expect(detection.geometryCache?.matches(depthMap: depthMap) == true)
        #expect(detection.region.sampleCount > 700)
        #expect(detection.region.confidence > 0.82)
    }

    @Test func depthAnalysisPlaneRegionDetectorReusesMatchingGeometryCache() throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 32, height: 32)
        let builtGeometryCache = try TAPDepthGeometryProjector.geometryCache(for: depthMap)
        let geometryCache = try #require(builtGeometryCache)
        var builderWasCalled = false
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { _, _ in
                builderWasCalled = true
                return nil
            },
            planeRegionGrower: { depthMap, seed, strictness, geometryCache, shouldCancel, progressHandler in
                #expect(geometryCache?.matches(depthMap: depthMap) == true)
                return try TAPPlaneEstimator.growPlaneRegion(
                    depthMap: depthMap,
                    seed: seed,
                    strictness: strictness,
                    geometryCache: geometryCache,
                    shouldCancel: shouldCancel,
                    progressHandler: progressHandler
                )
            }
        )

        let detection = try detector.detectRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 16, y: 16),
            strictness: 0.68,
            geometryCache: geometryCache
        )

        #expect(builderWasCalled == false)
        #expect(detection.geometryCache?.matches(depthMap: depthMap) == true)
    }

    @Test @MainActor func completedPlaneRegionRendersItsInteriorGridWithoutWaitingForAnimation() throws {
        let cells = (0..<2).flatMap { row in
            (0..<2).map { column in
                TAPPlaneGridCell(
                    row: row, column: column,
                    imageBounds: CGRect(x: CGFloat(column * 20), y: CGFloat(row * 20), width: 20, height: 20),
                    coverage: 1, averageResidualMeters: 0, confidence: 1, sampleCount: 400
                )
            }
        }
        let region = TAPPlaneRegion(
            seedPixel: .zero, estimate: Self.samplePlaneEstimate(), pixelRuns: [], gridCells: cells,
            contourPoints: [.zero, CGPoint(x: 39, y: 39)],
            imageBounds: CGRect(x: 0, y: 0, width: 40, height: 40),
            confidence: 1, flatnessScore: 1, sampleCount: 1_600, areaSquareMeters: 1
        )
        let image = try TAPDepthRGBAImageRenderer.image(pixels: [0, 0, 0, 255], width: 1, height: 1)
        let content = InteractiveDepthImage(
            image: image, overlayImage: nil, overlayOpacity: 0, comparisonPosition: nil,
            onComparisonPositionChanged: { _ in }, orientation: .up, depthSize: CGSize(width: 40, height: 40),
            planeRegion: region, partialPlaneGridCells: [], planeGridProgress: 1, planeSeedPoint: nil,
            highlightPalette: .fallback, onSelectionCleared: {}, onPointSelected: { _ in }
        )
        .frame(width: 320, height: 320)
        // Rendering without mounting the view leaves its local reveal state at
        // the initial value. A completed result must still draw every cell.
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let bitmap = try #require(renderer.uiImage?.cgImage)
        try #require(bitmap.width == 320 && bitmap.height == 320)
        var rgba = [UInt8](repeating: 0, count: 320 * 320 * 4)
        let converted = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress, width: 320, height: 320,
                bitsPerComponent: 8, bytesPerRow: 320 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: 320, height: 320))
            return true
        }
        try #require(converted)
        func brightness(x: Int, y: Int) -> Double {
            let offset = (y * 320 + x) * 4
            return Double(Int(rgba[offset]) + Int(rgba[offset + 1]) + Int(rgba[offset + 2])) / (3 * 255)
        }
        for x in [80, 240] {
            for y in [80, 240] {
                #expect(brightness(x: x, y: y) > 0.08, "Completed cells must retain their interior fill.")
            }
        }
        let internalEdge = (158...162).map { brightness(x: $0, y: 240) }.max() ?? 0
        #expect(internalEdge > brightness(x: 240, y: 240) + 0.1,
                "The internal grid line must remain visible, not only the plane contour.")
    }

    @Test @MainActor func completedPlaneDetectionDoesNotWaitForBufferedProgressPlayback() async throws {
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { _, _ in nil },
            planeRegionGrower: { _, seed, _, _, _, progressHandler in
                let region = Self.samplePlaneRegion(seedPixel: seed)
                for batch in 1...12 {
                    progressHandler(TAPPlaneGridProgress(
                        seedPixel: seed, gridCells: region.gridCells, progress: Double(batch) / 12
                    ))
                }
                return region
            }
        )
        let coordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: detector)
        var events: [DepthAnalysisPlaneRegionRequestEvent] = []
        coordinator.requestRegion(
            depthMap: Self.syntheticPlaneDepthMap(width: 16, height: 16),
            seed: CGPoint(x: 4, y: 4), strictness: 0.68, generationID: 1,
            eventHandler: { events.append($0) }
        )
        // The former per-batch presentation delay adds 1.65 seconds even though
        // this detector has already returned its complete result. The helper's
        // 500 ms deadline detects that artificial wait, not a native performance budget.
        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 1
        }
        let progress = Self.partialPlaneGridProgress(in: events)
        #expect(progress.map(\.progress) == (1...12).map { Double($0) / 12 })
        #expect(Self.succeededPlaneRegions(in: events).first?.gridCells == progress.last?.gridCells)
    }

    @Test @MainActor func depthAnalysisPlaneRegionRequestCoordinatorKeepsGeometryCacheAcrossRegionCancel() async throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        let builderCallCount = LockedCounter()
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { depthMap, shouldCancel in
                builderCallCount.increment()
                return try TAPDepthGeometryProjector.geometryCache(
                    for: depthMap,
                    shouldCancel: shouldCancel
                )
            },
            planeRegionGrower: { depthMap, seed, _, geometryCache, _, progressHandler in
                #expect(geometryCache?.matches(depthMap: depthMap) == true)
                let region = Self.samplePlaneRegion(seedPixel: seed)
                progressHandler(TAPPlaneGridProgress(seedPixel: seed, gridCells: region.gridCells, progress: 1))
                return region
            }
        )
        let coordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: detector)
        var events: [DepthAnalysisPlaneRegionRequestEvent] = []

        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 4, y: 4),
            strictness: 0.68,
            generationID: 1,
            eventHandler: { events.append($0) }
        )
        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 1
        }
        #expect(builderCallCount.count == 1)
        #expect(Self.partialPlaneGridProgress(in: events).contains { $0.seedPixel == CGPoint(x: 4, y: 4) })

        coordinator.cancelRegionRequest()
        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 5, y: 5),
            strictness: 0.68,
            generationID: 2,
            eventHandler: { events.append($0) }
        )
        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 2
        }

        #expect(builderCallCount.count == 1)
        #expect(Self.succeededPlaneRegions(in: events).map(\.seedPixel) == [
            CGPoint(x: 4, y: 4),
            CGPoint(x: 5, y: 5)
        ])
        #expect(Self.partialPlaneGridProgress(in: events).map(\.seedPixel).contains(CGPoint(x: 5, y: 5)))
    }

    @Test @MainActor func depthAnalysisPlaneRegionRequestCoordinatorPublishesOnlyNewestRegionRequest() async throws {
        let depthMap = Self.syntheticPlaneDepthMap(width: 16, height: 16)
        let detector = DepthAnalysisPlaneRegionDetector(
            geometryCacheBuilder: { _, _ in nil },
            planeRegionGrower: { _, seed, _, _, _, progressHandler in
                if seed == CGPoint(x: 1, y: 1) {
                    Thread.sleep(forTimeInterval: 0.06)
                }
                let region = Self.samplePlaneRegion(seedPixel: seed)
                progressHandler(TAPPlaneGridProgress(seedPixel: seed, gridCells: region.gridCells, progress: 1))
                return region
            }
        )
        let coordinator = DepthAnalysisPlaneRegionRequestCoordinator(detector: detector)
        var events: [DepthAnalysisPlaneRegionRequestEvent] = []

        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 1, y: 1),
            strictness: 0.68,
            generationID: 1,
            eventHandler: { events.append($0) }
        )
        coordinator.requestRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 2, y: 2),
            strictness: 0.68,
            generationID: 2,
            eventHandler: { events.append($0) }
        )

        try await Self.waitForCondition {
            Self.succeededPlaneRegions(in: events).count == 1
        }
        try await Task.sleep(nanoseconds: 90_000_000)

        #expect(Self.startedPlaneRequestCount(in: events) == 2)
        #expect(Self.succeededPlaneRegions(in: events).map(\.seedPixel) == [
            CGPoint(x: 2, y: 2)
        ])
    }

    @Test func seedPlaneGrowthFindsContinuousPlanesAcrossTiltAngles() throws {
        let width = 56
        let height = 44
        let cases: [(normal: SIMD3<Float>, seed: CGPoint)] = [
            (simd_normalize(SIMD3<Float>(-0.20, 0.00, 0.98)), CGPoint(x: 28, y: 22)),
            (simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70)), CGPoint(x: 22, y: 22)),
            (simd_normalize(SIMD3<Float>(0.74, -0.24, 0.63)), CGPoint(x: 34, y: 20)),
            (simd_normalize(SIMD3<Float>(-0.86, 0.18, 0.48)), CGPoint(x: 20, y: 24))
        ]

        for testCase in cases {
            let depthMap = Self.syntheticObliqueWallDepthMap(
                width: width,
                height: height,
                normal: testCase.normal
            )

            let region = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: testCase.seed,
                strictness: 0.68
            )

            #expect(region.sampleCount > Int(Double(width * height) * 0.70))
            #expect(region.confidence > 0.80)
            #expect(region.flatnessScore > 0.88)
            #expect(region.imageBounds.width > CGFloat(width) * 0.65)
            #expect(region.imageBounds.height > CGFloat(height) * 0.65)
        }
    }

    @Test func seedPlaneGrowthKeepsNoisyObliqueWallConnected() throws {
        let depthMap = Self.syntheticNoisyObliqueWallDepthMap(width: 52, height: 42)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 24, y: 21),
            strictness: 0.55
        )

        #expect(region.sampleCount > 1_100)
        #expect(region.gridCells.count > 8)
        #expect(region.confidence > 0.62)
    }

    @Test func seedPlaneGrowthDoesNotLeakAcrossObliqueWallBoundary() throws {
        let depthMap = Self.syntheticSplitPlaneDepthMap(width: 48, height: 40)

        let region = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 14, y: 20),
            strictness: 0.62
        )

        #expect(region.sampleCount > 650)
        #expect(region.imageBounds.maxX < 30)
    }

    @Test func seedPlaneGrowthShrinksOnCurvedDepthWhenStrictnessIncreases() throws {
        let depthMap = Self.syntheticCurvedDepthMap(width: 36, height: 36)

        let loose = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 18, y: 18),
            strictness: 0.35
        )
        let strict = try TAPPlaneEstimator.growPlaneRegion(
            depthMap: depthMap,
            seed: CGPoint(x: 18, y: 18),
            strictness: 0.95
        )

        #expect(strict.sampleCount <= loose.sampleCount)
        #expect(strict.flatnessScore <= loose.flatnessScore || strict.sampleCount < loose.sampleCount)
    }

    @Test func seedPlaneGrowthRejectsInvalidSeed() throws {
        var samples = Array(repeating: Float(1.4), count: 16 * 16)
        samples[8 + 8 * 16] = 0
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: samples,
            calibration: Self.calibration(width: 16, height: 16)
        )

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 8, y: 8),
                strictness: 0.68
            )
            #expect(Bool(false), "Expected invalid seed to throw.")
        } catch TAPPlaneGrowthError.invalidSeed {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func seedPlaneGrowthReportsMissingCameraCalibration() throws {
        let depthMap = TAPMetricDepthMap(
            width: 16,
            height: 16,
            samples: Array(repeating: Float(1.4), count: 16 * 16),
            calibration: nil
        )

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: depthMap,
                seed: CGPoint(x: 8, y: 8),
                strictness: 0.68
            )
            #expect(Bool(false), "Expected missing calibration to throw.")
        } catch TAPPlaneGrowthError.cameraCalibrationMissing {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    private static func syntheticPlaneDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.18, 0.08, 1.0))
        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: depthSamples(width: width, height: height, normal: normal, planeD: -1.55, calibration: calibration),
            calibration: calibration
        )
    }

    private static func samplePlaneEstimate() -> TAPPlaneEstimate {
        TAPPlaneEstimate(
            normal: SIMD3<Float>(0, 0, 1),
            centroid: SIMD3<Float>(0, 0, 1),
            averageResidualMeters: 0.01,
            inlierRatio: 0.9,
            depthRangeMeters: 1...2,
            imageBounds: CGRect(x: 1, y: 1, width: 4, height: 4)
        )
    }

    private static func samplePlaneRegion(
        seedPixel: CGPoint = CGPoint(x: 3, y: 3),
        pixelRuns: [TAPPlanePixelRun] = [TAPPlanePixelRun(y: 3, xStart: 3, xEndExclusive: 5)]
    ) -> TAPPlaneRegion {
        TAPPlaneRegion(
            seedPixel: seedPixel,
            estimate: Self.samplePlaneEstimate(),
            pixelRuns: pixelRuns,
            gridCells: [
                TAPPlaneGridCell(
                    row: 0,
                    column: 0,
                    imageBounds: CGRect(x: 3, y: 3, width: 2, height: 1),
                    coverage: 1,
                    averageResidualMeters: 0.01,
                    confidence: 0.8,
                    sampleCount: 2
                )
            ],
            contourPoints: [CGPoint(x: 3, y: 3)],
            imageBounds: CGRect(x: 3, y: 3, width: 2, height: 1),
            confidence: 0.8,
            flatnessScore: 0.9,
            sampleCount: 2,
            areaSquareMeters: 0.01
        )
    }

    @MainActor
    private static func updateProjection(
        _ coordinator: DepthProjectionSceneView.Coordinator,
        view: SCNView,
        region: TAPPlaneRegion?,
        color: UIColor = .systemYellow,
        reduceMotion: Bool = false
    ) {
        coordinator.update(
            view: view,
            image: nil,
            depthMap: TAPMetricDepthMap(width: 8, height: 8, samples: Array(repeating: 2, count: 64), calibration: sampleCalibration),
            orientation: .up,
            selectedPlaneRegion: region,
            highlightColor: color,
            enablesMotionParallax: false,
            reduceMotion: reduceMotion
        )
    }

    @MainActor
    private static func firstVertex(of node: SCNNode) throws -> SIMD3<Float> {
        let source = try #require(node.geometry?.sources(for: .vertex).first)
        return source.data.withUnsafeBytes { bytes in
            SIMD3<Float>((0..<3).map {
                bytes.loadUnaligned(fromByteOffset: source.dataOffset + $0 * source.bytesPerComponent, as: Float.self)
            })
        }
    }

    @MainActor
    private static func waitForCondition(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: () -> Bool
    ) async throws {
        let pollIntervalNanoseconds: UInt64 = 10_000_000
        let attempts = Int(max(timeoutNanoseconds / pollIntervalNanoseconds, 1))

        for _ in 0..<attempts {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        try #require(condition())
    }

    private static func startedPlaneRequestCount(in events: [DepthAnalysisPlaneRegionRequestEvent]) -> Int {
        events.filter { event in
            if case .started(_) = event {
                return true
            }
            return false
        }.count
    }

    private static func partialPlaneGridProgress(in events: [DepthAnalysisPlaneRegionRequestEvent]) -> [TAPPlaneGridProgress] {
        events.compactMap { event in
            if case .partial(let progress, _) = event {
                return progress
            }
            return nil
        }
    }

    private static func succeededPlaneRegions(in events: [DepthAnalysisPlaneRegionRequestEvent]) -> [TAPPlaneRegion] {
        events.compactMap { event in
            if case .succeeded(let detection, _) = event {
                return detection.region
            }
            return nil
        }
    }

    private static func syntheticCurvedDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.10, 0.04, 1.0))
        var samples = depthSamples(width: width, height: height, normal: normal, planeD: -1.45, calibration: calibration)
        let centerX = Float(width - 1) / 2
        let centerY = Float(height - 1) / 2

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                samples[x + y * width] += (dx * dx + dy * dy) * 0.00022
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func syntheticObliqueWallDepthMap(
        width: Int,
        height: Int,
        normal: SIMD3<Float> = simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70))
    ) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        return TAPMetricDepthMap(
            width: width,
            height: height,
            samples: depthSamples(width: width, height: height, normal: normal, planeD: -1.55, calibration: calibration),
            calibration: calibration
        )
    }

    private static func syntheticNoisyObliqueWallDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let normal = simd_normalize(SIMD3<Float>(-0.70, 0.03, 0.71))
        var samples = depthSamples(width: width, height: height, normal: normal, planeD: -1.60, calibration: calibration)

        for y in 0..<height {
            for x in 0..<width {
                let index = x + y * width
                if (x + y * 3).isMultiple(of: 23) {
                    samples[index] = 0
                } else {
                    let deterministicNoise = Float(((x * 17 + y * 29) % 11) - 5) * 0.0012
                    samples[index] += deterministicNoise
                }
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func syntheticSplitPlaneDepthMap(width: Int, height: Int) -> TAPMetricDepthMap {
        let calibration = Self.calibration(width: width, height: height)
        let leftNormal = simd_normalize(SIMD3<Float>(-0.72, 0.02, 0.70))
        let rightNormal = simd_normalize(SIMD3<Float>(0.18, -0.04, 1.0))
        let left = depthSamples(width: width, height: height, normal: leftNormal, planeD: -1.52, calibration: calibration)
        let right = depthSamples(width: width, height: height, normal: rightNormal, planeD: -2.25, calibration: calibration)
        var samples = left

        for y in 0..<height {
            for x in width / 2..<width {
                samples[x + y * width] = right[x + y * width]
            }
        }

        return TAPMetricDepthMap(width: width, height: height, samples: samples, calibration: calibration)
    }

    private static func depthSamples(
        width: Int,
        height: Int,
        normal: SIMD3<Float>,
        planeD: Float,
        calibration: TAPDepthManifest.CameraCalibration
    ) -> [Float] {
        let intrinsics = TAPCameraIntrinsics(calibration: calibration, depthWidth: width, depthHeight: height)!
        var samples: [Float] = []
        samples.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let ray = SIMD3<Float>(
                    (Float(x) - intrinsics.cx) / intrinsics.fx,
                    (Float(y) - intrinsics.cy) / intrinsics.fy,
                    1
                )
                let denominator = simd_dot(normal, ray)
                samples.append(-planeD / denominator)
            }
        }

        return samples
    }

    private static func squaredDistanceFromSeed(_ cell: TAPPlaneGridCell, seedPixel: CGPoint) -> CGFloat {
        let dx = cell.imageBounds.midX - seedPixel.x
        let dy = cell.imageBounds.midY - seedPixel.y
        return dx * dx + dy * dy
    }

    private static func calibration(
        width: Int,
        height: Int,
        referenceWidth: Double? = nil,
        referenceHeight: Double? = nil,
        intrinsicMatrix: [Float]? = nil,
        extrinsicMatrix: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    ) -> TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: referenceWidth ?? Double(width),
            intrinsicMatrixReferenceHeight: referenceHeight ?? Double(height),
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: Double(width) / 2,
            lensDistortionCenterY: Double(height) / 2,
            intrinsicMatrix: intrinsicMatrix ?? [140, 0, 0, 0, 140, 0, Float(width) / 2, Float(height) / 2, 1],
            extrinsicMatrix: extrinsicMatrix
        )
    }

    private static var sampleCalibration: TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: 8,
            intrinsicMatrixReferenceHeight: 8,
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: 4,
            lensDistortionCenterY: 4,
            intrinsicMatrix: [100, 0, 0, 0, 100, 0, 4, 4, 1],
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        )
    }
}

private actor ProjectionPayloadGate {
    private var count = 0
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    private var builds: [Int: (payload: TAPDepthProjectionScenePayloadData?, continuation: CheckedContinuation<TAPDepthProjectionScenePayloadData?, Never>)] = [:]

    func build(_ request: TAPDepthProjectionPayloadBuildRequest) async -> TAPDepthProjectionScenePayloadData? {
        let payload = TAPDepthProjectionScenePayloadBuilder.makePayloadData(request: request)
        count += 1
        return await withCheckedContinuation { continuation in
            builds[count] = (payload, continuation)
            if let waiter, count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func waitForBuild(_ expectedCount: Int) async {
        guard count < expectedCount else { return }
        await withCheckedContinuation { waiter = (expectedCount, $0) }
    }

    func finish(_ call: Int, missingPayload: Bool = false) throws {
        let pendingBuild = builds.removeValue(forKey: call)
        let build = try #require(pendingBuild)
        build.continuation.resume(returning: missingPayload ? nil : build.payload)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock {
            value
        }
    }

    func increment() {
        lock.withLock {
            value += 1
        }
    }
}
