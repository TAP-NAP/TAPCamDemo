//
//  TAPCameraControlServiceTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraControlServiceTests {
    @Test func cameraControlServiceAcceptsMatchingManualCommandPlanValidation() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .exposureBias(1.5),
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )

        try CameraControlService.validateManualControlCommandPlan(
            plan,
            activeDeviceID: capability.deviceID,
            activeControlSignature: plan.targetControlSignature
        )
    }

    @Test func cameraControlServiceRejectsBlockedManualCommandPlanValidation() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(supportsCustomExposure: false)
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .custom(iso: 100, shutterDurationSeconds: 1.0 / 120.0),
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )

        do {
            try CameraControlService.validateManualControlCommandPlan(
                plan,
                activeDeviceID: capability.deviceID,
                activeControlSignature: plan.targetControlSignature
            )
            Issue.record("Blocked manual-control plans must not be executable.")
        } catch TAPDepthCaptureError.cameraControlCommandPlanNotExecutable {
            #expect(plan.commands.isEmpty)
        } catch {
            Issue.record("Unexpected manual-control validation error: \(error)")
        }
    }

    @Test func cameraControlServiceRejectsStaleManualCommandPlanValidation() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(deviceID: "original-camera")
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .exposureBias(1.5),
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )

        do {
            try CameraControlService.validateManualControlCommandPlan(
                plan,
                activeDeviceID: "new-camera",
                activeControlSignature: plan.targetControlSignature
            )
            Issue.record("Manual-control plans must reject stale active camera ids.")
        } catch TAPDepthCaptureError.cameraControlTargetDeviceChanged {
            #expect(plan.targetDeviceID == "original-camera")
        } catch {
            Issue.record("Unexpected manual-control validation error: \(error)")
        }
    }

    @Test func cameraControlServiceRejectsStaleManualControlSurfaceValidation() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let activeCapability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            isoRange: .init(minimum: 200, maximum: 800)
        )
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .exposureBias(1.5),
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )

        do {
            try CameraControlService.validateManualControlCommandPlan(
                plan,
                activeDeviceID: capability.deviceID,
                activeControlSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(capability: activeCapability)
            )
            Issue.record("Manual-control plans must reject stale control surfaces.")
        } catch TAPDepthCaptureError.cameraControlTargetSurfaceChanged {
            #expect(plan.targetControlSignature != CameraManualControlCommandPlan.ControlSurfaceSignature(
                capability: activeCapability
            ))
        } catch {
            Issue.record("Unexpected manual-control validation error: \(error)")
        }
    }

    @Test func cameraControlServiceManualPlanErrorsUseFixedPublicCopy() throws {
        let publicErrors: [TAPDepthCaptureError] = [
            .cameraControlCommandPlanNotExecutable,
            .cameraControlTargetDeviceChanged,
            .cameraControlTargetSurfaceChanged,
            .cameraControlUnsupportedCommand
        ]

        for publicText in publicErrors.map(\.localizedDescription) {
            for forbidden in ["original-camera", "new-camera", "secret", "AVCaptureDevice", "proof", "key", "file://"] {
                #expect(!publicText.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }

    @Test func cameraControlServiceClampsRequestedZoomToDeviceRange() throws {
        #expect(CameraControlService.clampedZoomFactor(0.5, minimum: 1, maximum: 5) == 1)
        #expect(CameraControlService.clampedZoomFactor(3, minimum: 1, maximum: 5) == 3)
        #expect(CameraControlService.clampedZoomFactor(8, minimum: 1, maximum: 5) == 5)
    }

    @Test func continuousZoomAllowsBothDirectionsWithinOneLiveDepthRange() {
        for (current, target) in [(1.0, 3.2), (3.2, 1.0), (2.0, 2.0)] {
            #expect(CameraControlService.supportsContinuousZoom(
                from: current, to: target, minimum: 1, maximum: 5,
                depthRanges: [1...3.2, 4...5]
            ))
        }
    }

    @Test func continuousZoomRejectsDepthGapsAndDiscreteOnlyEndpoints() {
        for ranges in [[1.0...2.0, 3.0...4.0], [1.0...1.0, 4.0...4.0], []] {
            #expect(!CameraControlService.supportsContinuousZoom(
                from: 4, to: 1, minimum: 1, maximum: 5, depthRanges: ranges
            ))
        }
        #expect(CameraControlService.supportsContinuousZoom(
            from: 1, to: 1, minimum: 1, maximum: 5, depthRanges: [1...1]
        ))
    }

    @Test func continuousZoomRejectsTargetsOutsideLiveDeviceBounds() {
        for (current, target) in [(1.0, 4.0), (4.0, 2.0), (0.5, 2.0), (2.0, .nan), (.infinity, 2.0), (0.0, 2.0)] {
            #expect(!CameraControlService.supportsContinuousZoom(
                from: current, to: target, minimum: 1, maximum: 3,
                depthRanges: [0...5]
            ))
        }
    }

    @Test func zoomReadbackMustReachTheRequestedTarget() {
        #expect(CameraControlService.hasReachedZoom(3.2, actual: 3.2))
        #expect(CameraControlService.hasReachedZoom(3.2, actual: 3.20001))
        #expect(!CameraControlService.hasReachedZoom(3.2, actual: 3.19))
        #expect(!CameraControlService.hasReachedZoom(3.2, actual: .nan))
        #expect(!CameraControlService.hasReachedZoom(.infinity, actual: .infinity))
    }

    @Test func cameraControlServiceClampsRequestedExposureBiasToDeviceRange() throws {
        #expect(CameraControlService.clampedExposureBias(-4, minimum: -2, maximum: 2) == -2)
        #expect(CameraControlService.clampedExposureBias(0.7, minimum: -2, maximum: 2) == 0.7)
        #expect(CameraControlService.clampedExposureBias(4, minimum: -2, maximum: 2) == 2)
    }

    @Test func cameraControlServiceMarksOnlyTheRegisteredSessionQueueAsWritable() async throws {
        let queue = DispatchQueue(label: "tapcam.tests.camera-control.session")

        CameraControlService.registerSessionQueue(queue)

        let isMarkedOnQueue = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: CameraControlService.isRunningOnRegisteredSessionQueue)
            }
        }

        #expect(isMarkedOnQueue)
        #expect(!CameraControlService.isRunningOnRegisteredSessionQueue)
    }
}
