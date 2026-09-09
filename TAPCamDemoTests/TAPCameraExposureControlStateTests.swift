//
//  TAPCameraExposureControlStateTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraExposureControlStateTests {
    @Test func isoPriorityComputesOnlyShutterFromMeterBaseline() throws {
        let capability = Self.capability()
        let baseline = Self.sample(capability: capability, iso: 100, shutter: 0.01, generation: 0)
        let baselineResult = CameraExposureControlState(capability: capability)
            .receiveMeterSample(baseline)

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
            .receiveMeterSample(baseline)

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
            .receiveMeterSample(baseline)
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
            .receiveMeterSample(baseline)
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
            .receiveMeterSample(baseline)
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

    @Test func manualAdjustmentsSnapToPhotographicThirdStopValues() {
        let capability = Self.capability()
        let state = CameraExposureControlState(capability: capability)

        let isoResult = state.setISO(118)
        let shutterResult = state.setShutterDuration(1.0 / 120.0)

        #expect(isoResult.nextState.mode == .isoPriority)
        #expect(isoResult.displayState.iso == 125)
        #expect(shutterResult.nextState.mode == .shutterPriority)
        #expect(
            abs(shutterResult.displayState.shutterDurationSeconds - 1.0 / 125.0)
                < 0.000_001
        )
    }

    @Test func restoringOneAutomaticSidePreservesTheOtherManualSide() {
        let capability = Self.capability()
        let manual = CameraExposureControlState(capability: capability)
            .setISO(200)
            .nextState
            .setShutterDuration(1.0 / 50.0)
            .nextState

        let isoAutomatic = manual.makeISOAutomatic()
        let shutterAutomatic = manual.makeShutterAutomatic()

        #expect(isoAutomatic.nextState.mode == .shutterPriority)
        #expect(isoAutomatic.displayState.isoBadge == "A")
        #expect(isoAutomatic.displayState.shutterBadge == nil)
        #expect(shutterAutomatic.nextState.mode == .isoPriority)
        #expect(shutterAutomatic.displayState.isoBadge == nil)
        #expect(shutterAutomatic.displayState.shutterBadge == "A")
    }

    @Test func automaticSideUsesTheNearestNominalPhotographicStop() {
        let capability = Self.capability()
        let baseline = Self.sample(
            capability: capability,
            iso: 117,
            shutter: 0.009,
            generation: 0
        )
        let result = CameraExposureControlState(capability: capability)
            .receiveMeterSample(baseline)
            .nextState
            .setISO(200)

        let targetExposure = baseline.equivalentExposure
        let actualExposure = result.displayState.iso
            * result.displayState.shutterDurationSeconds
        let errorInStops = abs(log2(actualExposure / targetExposure))

        #expect(result.displayState.shutterDurationSeconds == 1.0 / 200.0)
        #expect(errorInStops < 0.21)
    }

    @Test func unavailablePhotographicScaleClampsWithoutInventingAStop() {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            isoRange: .init(minimum: 70, maximum: 75),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 100.0, maximum: 1.0 / 50.0)
        )
        let result = CameraExposureControlState(capability: capability).setISO(73)

        #expect(result.nextState.mode == .isoPriority)
        #expect(result.displayState.iso == 73)
        #expect(result.nextState.riskRangeForISO().isEmpty)
    }

    @Test func firstPriorityAdjustmentPreservesExposureBeforeBaselineArrives() {
        let capability = Self.capability()
        let result = CameraExposureControlState(capability: capability).setISO(200)

        #expect(result.nextState.meterBaseline == nil)
        #expect(result.nextState.mode == .isoPriority)
        #expect(result.displayState.iso == 200)
        #expect(result.displayState.shutterDurationSeconds == 1.0 / 200.0)
        #expect(
            result.manualControlIntent?.exposure
                == .custom(iso: 200, shutterDurationSeconds: 1.0 / 200.0)
        )
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
