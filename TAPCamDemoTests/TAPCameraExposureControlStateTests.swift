//
//  TAPCameraExposureControlStateTests.swift
//  TAPCamDemoTests
//

import Testing
@testable import TAPCamDemo

struct TAPCameraExposureControlStateTests {
    @Test func isoPriorityComputesOnlyShutterFromMeterBaseline() throws {
        let capability = Self.capability()
        let baseline = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 0)
        let baselineResult = CameraExposureControlState(capability: capability)
            .establishMeterBaseline(from: baseline)

        let result = baselineResult.nextState.setISO(200)

        #expect(result.nextState.mode == .isoPriority)
        #expect(result.displayState.iso == 200)
        #expect(abs(result.displayState.shutterDurationSeconds - 0.005) < 0.000_001)
        #expect(result.displayState.isoBadge == nil)
        #expect(result.displayState.shutterBadge == "A")
        #expect(result.manualControlIntent?.exposure == .custom(iso: 200, shutterDurationSeconds: 0.005))
    }

    @Test func shutterPriorityComputesOnlyISOFromMeterBaseline() throws {
        let capability = Self.capability()
        let baseline = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 0)
        let baselineResult = CameraExposureControlState(capability: capability)
            .establishMeterBaseline(from: baseline)

        let result = baselineResult.nextState.setShutterDuration(0.02)

        #expect(result.nextState.mode == .shutterPriority)
        #expect(result.displayState.shutterDurationSeconds == 0.02)
        #expect(abs(result.displayState.iso - 50) < 0.000_001)
        #expect(result.displayState.isoBadge == "A")
        #expect(result.displayState.shutterBadge == nil)
        #expect(result.manualControlIntent?.exposure == .custom(iso: 50, shutterDurationSeconds: 0.02))
    }

    @Test func adjustableEVRecalculatesOnlyTheAutomaticSide() throws {
        let capability = Self.capability()
        let baseline = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 0)
        let isoPriority = CameraExposureControlState(capability: capability)
            .establishMeterBaseline(from: baseline)
            .nextState
            .setISO(200)
            .nextState

        let result = isoPriority.setEVBias(1)

        #expect(result.nextState.mode == .isoPriority)
        #expect(result.displayState.iso == 200)
        #expect(abs(result.displayState.shutterDurationSeconds - 0.01) < 0.000_001)
        #expect(result.manualControlIntent?.exposure == .custom(iso: 200, shutterDurationSeconds: 0.01))
    }

    @Test func manualModeMakesEVReadOnlyAndDisplaysMeterDelta() throws {
        let capability = Self.capability()
        let baseline = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 0)
        let manual = CameraExposureControlState(capability: capability)
            .establishMeterBaseline(from: baseline)
            .nextState
            .setISO(200)
            .nextState
            .setShutterDuration(0.02)
            .nextState

        let result = manual.setEVBias(1.5)

        #expect(result.nextState.mode == .manual)
        #expect(result.nextState.evBias == 0)
        #expect(result.displayState.evTitle == "Meter")
        #expect(result.displayState.isEVReadOnly)
        #expect(result.displayState.evValue == "+2.0")
        #expect(result.manualControlIntent == nil)
    }

    @Test func meterSamplesWaitBehindActiveUserDragUntilInteractionEnds() throws {
        let capability = Self.capability()
        let baseline = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 0)
        let dragging = CameraExposureControlState(capability: capability)
            .establishMeterBaseline(from: baseline)
            .nextState
            .setISO(200)
            .nextState
            .beginInteraction(.iso)
            .nextState
        let pendingSample = Self.sample(capability: capability, iso: 100, shutter: 0.02, generation: 0)

        let pendingResult = dragging.receiveMeterSample(pendingSample)
        let endedResult = pendingResult.nextState.endInteraction()

        #expect(pendingResult.nextState.pendingMeterSample == pendingSample)
        #expect(abs(pendingResult.displayState.shutterDurationSeconds - 0.005) < 0.000_001)
        #expect(endedResult.nextState.pendingMeterSample == nil)
        #expect(abs(endedResult.displayState.shutterDurationSeconds - 0.01) < 0.000_001)
        #expect(endedResult.debugState.lastReadbackReason == .exposureSettled)
    }

    @Test func staleMeterSampleIsDiscardedByGeneration() throws {
        let capability = Self.capability()
        let state = CameraExposureControlState(capability: capability, generation: 2)
        let staleSample = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 1)

        let result = state.receiveMeterSample(staleSample)

        #expect(result.discardedReason == .staleGeneration)
        #expect(result.nextState.meterBaseline == nil)
        #expect(result.debugState.lastDiscardedReason == .staleGeneration)
    }

    @Test func configurationChangeReturnsToAutoAndRequestsFreshBaseline() throws {
        let capability = Self.capability(deviceID: "tele")

        let result = CameraExposureControlState.configurationChanged(
            capability: capability,
            generation: 5,
            evBias: 0.7
        )

        #expect(result.nextState.mode == .auto)
        #expect(result.nextState.generation == 5)
        #expect(result.nextState.meterBaseline == nil)
        #expect(result.displayState.isoBadge == "A")
        #expect(result.displayState.shutterBadge == "A")
        #expect(result.shouldReadback)
        #expect(result.readbackReason == .initialBaseline)
        #expect(result.manualControlIntent?.exposure == .continuousAuto)
    }

    @Test func equivalentExposureFormulaUsesExposureTargetOffsetSign() throws {
        let capability = Self.capability()
        let sample = Self.sample(
            capability: capability,
            iso: 100,
            shutter: 0.01,
            exposureTargetOffset: 1,
            generation: 0
        )

        #expect(abs(sample.equivalentExposure - 0.5) < 0.000_001)
    }

    private static func capability(deviceID: String = "wide") -> CameraControlCapabilitySnapshot {
        TAPCamDemoTestFixtures.sampleManualControlCapability(
            deviceID: deviceID,
            isoRange: .init(minimum: 25, maximum: 800),
            shutterDurationRangeSeconds: .init(minimum: 0.001, maximum: 1),
            currentISO: 100,
            currentShutterDurationSeconds: 0.01
        )
    }

    private static func sample(
        capability: CameraControlCapabilitySnapshot,
        iso: Double,
        shutter: Double,
        exposureTargetOffset: Double = 0,
        generation: Int
    ) -> CameraExposureMeterSample {
        CameraExposureMeterSample(
            deviceID: capability.deviceID,
            controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature(capability: capability),
            generation: generation,
            iso: iso,
            shutterDurationSeconds: shutter,
            exposureTargetOffset: exposureTargetOffset,
            exposureTargetBias: 0,
            isSettled: true,
            reason: .exposureSettled
        )
    }
}
