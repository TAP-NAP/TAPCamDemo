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
import Testing
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

    @Test func depthProjectionMotionParallaxUsesCurrentAttitudeAsBaseline() {
        let baselinePitch = 0.42
        let baselineRoll = -0.31

        let recentered = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            pitch: baselinePitch,
            roll: baselineRoll,
            baselinePitch: baselinePitch,
            baselineRoll: baselineRoll
        )
        let tilted = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            pitch: baselinePitch + 0.2,
            roll: baselineRoll - 0.4,
            baselinePitch: baselinePitch,
            baselineRoll: baselineRoll
        )
        let flatDevice = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            pitch: 0,
            roll: 0,
            baselinePitch: baselinePitch,
            baselineRoll: baselineRoll
        )
        let wrappedRoll = TAPDepthProjectionInteractionPolicy.motionParallaxEulerAngles(
            pitch: 0,
            roll: -Double.pi + 0.01,
            baselinePitch: 0,
            baselineRoll: Double.pi - 0.01
        )

        #expect(abs(recentered.x) < 0.0001)
        #expect(abs(recentered.y) < 0.0001)
        #expect(abs(tilted.x - 0.012) < 0.0001)
        #expect(abs(tilted.y + 0.032) < 0.0001)
        #expect(abs(flatDevice.x) > 0.0001)
        #expect(abs(flatDevice.y) > 0.0001)
        #expect(abs(wrappedRoll.y - 0.0016) < 0.0001)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func depthProjectionDoubleTapResetRecentersMotionParallaxBaseline() throws {
        let pointCloudSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AnalysisTools/DepthPointCloudPreview.swift"
        )
        let resetHandler = try #require(TAPCamDemoTestSourceInspection.substring(
            in: pointCloudSource,
            from: "@objc func handleResetTap(_ gesture: UITapGestureRecognizer)",
            to: "func gestureRecognizer("
        ))

        #expect(resetHandler.contains("resetInteractionTransform(animated: true)"))
        #expect(resetHandler.contains("recenterMotionParallaxBaseline(animated: true)"))
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
        let samples: [(point: TAPPoint3D, imagePoint: CGPoint)] = [
            (TAPPoint3D(x: 0, y: 0, z: 1.0), CGPoint(x: 0, y: 0)),
            (TAPPoint3D(x: 0, y: 0, z: 1.2), CGPoint(x: 1, y: 0)),
            (TAPPoint3D(x: 0, y: 0, z: 1.4), CGPoint(x: 2, y: 0)),
            (TAPPoint3D(x: 0, y: 0, z: 9_999.0), CGPoint(x: 3, y: 0)),
            (TAPPoint3D(x: 0, y: 0, z: .nan), CGPoint(x: 4, y: 0))
        ]

        let renderable = TAPDepthProjectionSampleFilter.renderableSamples(from: samples)
        let targetDepth = TAPDepthProjectionSampleFilter.targetDepth(
            from: samples.map(\.point.z)
        )

        #expect(renderable.map(\.point.z) == [1.0, 1.2, 1.4])
        #expect(abs(targetDepth - 1.2) < 0.0001)
        #expect(TAPDepthProjectionSampleFilter.isRenderableDepth(100) == false)
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
        #expect(payload.stats.hasRGB)
        #expect(payload.stats.hasHighlight)
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

        let plane = try #require(TAPPlaneEstimator.estimatePlane(depthMap: depthMap, region: CGRect(x: 0, y: 0, width: 16, height: 16)))

        #expect(plane.averageResidualMeters < 0.001)
        #expect(plane.inlierRatio > 0.95)
        #expect(abs(abs(plane.normal.z) - 1) < 0.001)
    }

    @Test func planeDetectorFindsAndFiltersHighConfidenceFlatRegions() throws {
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

        let planes = TAPPlaneEstimator.detectPlanes(depthMap: depthMap)

        #expect(!planes.isEmpty)
        #expect(planes.first?.confidence ?? 0 > 0.95)
        #expect(TAPPlaneEstimator.filteredPlanes(planes, minimumConfidence: 0.95).count == planes.count)
        #expect(TAPPlaneEstimator.filteredPlanes(planes, minimumConfidence: 1.01).isEmpty)
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

    private static func samplePlaneRegion(seedPixel: CGPoint = CGPoint(x: 3, y: 3)) -> TAPPlaneRegion {
        TAPPlaneRegion(
            seedPixel: seedPixel,
            estimate: Self.samplePlaneEstimate(),
            pixelRuns: [TAPPlanePixelRun(y: 3, xStart: 3, xEndExclusive: 5)],
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
