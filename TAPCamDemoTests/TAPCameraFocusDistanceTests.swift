//
//  TAPCameraFocusDistanceTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraFocusDistanceTests {
    @Test func rawLensPositionProvidesNoDistanceWithoutAnObservation() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)

        for position in [0.0, 0.5, 1.0] {
            #expect(model.estimate(lensPosition: position, context: context) == nil)
        }
    }

    @Test func aSingleObservationProvidesOnlyANarrowLocalReference() throws {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        let accepted = model.recordAutofocusLock(lensPosition: 0.4, measuredTargetMeters: 2, context: context)
        #expect(accepted)

        let atObservation = try #require(model.estimate(lensPosition: 0.4, context: context))
        let nearby = try #require(model.estimate(lensPosition: 0.404, context: context))
        #expect(atObservation.meters == 2)
        #expect(nearby == atObservation)
        #expect(nearby.basis == .nearObservation)
        #expect(model.estimate(lensPosition: 0.41, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.39, context: context) == nil)
    }

    @Test func interpolationUsesOnlyTheMeasuredLocalBracket() throws {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0.4, measuredTargetMeters: 1, context: context)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: context)

        let estimate = try #require(model.estimate(lensPosition: 0.45, context: context))
        #expect(abs(estimate.meters - 4.0 / 3) < 0.000_001)
        #expect(estimate.basis == .interpolated)
        #expect(model.estimate(lensPosition: 0.38, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.52, context: context) == nil)
        #expect(model.estimate(lensPosition: 1, context: context) == nil)
    }

    @Test func distantOrSteepBracketsDoNotSupportInterpolation() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0.2, measuredTargetMeters: 1, context: context)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: context)
        model.recordAutofocusLock(lensPosition: 0.6, measuredTargetMeters: 8, context: context)

        #expect(model.estimate(lensPosition: 0.35, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.55, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.6, context: context)?.meters == 8)
    }

    @Test func actuatorEndStopIsFiniteOnlyWhenActuallyObserved() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 1, measuredTargetMeters: 4, context: context)

        #expect(model.estimate(lensPosition: 1, context: context)?.meters == 4)
        #expect(model.estimate(lensPosition: 0.9, context: context) == nil)
    }

    @Test func reversedOrNearlyEqualDistancesCannotInventAnIntermediateCurve() {
        let context = context()
        for upperMeters in [0.8, 1, 1.03] {
            var model = CameraFocusDistanceModel()
            model.reset(context: context)
            model.recordAutofocusLock(lensPosition: 0.4, measuredTargetMeters: 1, context: context)
            model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: upperMeters, context: context)

            #expect(model.estimate(lensPosition: 0.45, context: context) == nil)
            #expect(model.estimate(lensPosition: 0.4, context: context)?.meters == 1)
            #expect(model.estimate(lensPosition: 0.5, context: context)?.meters == upperMeters)
        }
    }

    @Test func invalidNumbersCannotEnterOrQueryTheModel() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)

        for position in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            let accepted = model.recordAutofocusLock(lensPosition: position, measuredTargetMeters: 2, context: context)
            #expect(!accepted)
            #expect(model.estimate(lensPosition: position, context: context) == nil)
        }
        for meters in [Double.nan, .infinity, -.infinity, 0, -1] {
            let accepted = model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: meters, context: context)
            #expect(!accepted)
        }
        #expect(model.observationCount == 0)
    }

    @Test func deviceControlSurfaceAndGenerationEachPreventReusingObservations() {
        let original = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: original)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: original)

        let differentContexts = [
            context(deviceID: "other-device"),
            context(generation: 2),
            context(supportsCustomLensPosition: false)
        ]
        for changed in differentContexts {
            #expect(model.estimate(lensPosition: 0.5, context: changed) == nil)
            let accepted = model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 3, context: changed)
            #expect(!accepted)
        }
        #expect(model.estimate(lensPosition: 0.5, context: original)?.meters == 2)
    }

    @Test func resettingContextClearsHistoryAndRejectsLateObservations() {
        let original = context()
        let changed = context(generation: 2)
        var model = CameraFocusDistanceModel()
        model.reset(context: original)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: original)

        model.reset(context: changed)
        #expect(model.observationCount == 0)
        let acceptedLateObservation = model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: original)
        #expect(!acceptedLateObservation)
        #expect(model.estimate(lensPosition: 0.5, context: changed) == nil)
        model.reset(context: nil)
        let acceptedWithoutContext = model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: changed)
        #expect(!acceptedWithoutContext)
    }

    @Test func conflictingNearbyObservationsDisableThatRegionAndItsBrackets() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0.4, measuredTargetMeters: 1.5, context: context)
        model.recordAutofocusLock(lensPosition: 0.45, measuredTargetMeters: 2, context: context)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2.5, context: context)

        let acceptedConflict = model.recordAutofocusLock(lensPosition: 0.452, measuredTargetMeters: 4, context: context)
        #expect(!acceptedConflict)
        #expect(model.estimate(lensPosition: 0.45, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.425, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.475, context: context) == nil)
        let acceptedAfterConflict = model.recordAutofocusLock(lensPosition: 0.45, measuredTargetMeters: 2, context: context)
        #expect(!acceptedAfterConflict)
        #expect(model.estimate(lensPosition: 0.5, context: context)?.meters == 2.5)

        model.reset(context: context)
        let acceptedAfterReset = model.recordAutofocusLock(lensPosition: 0.45, measuredTargetMeters: 2, context: context)
        #expect(acceptedAfterReset)
    }

    @Test func consistentNearbyObservationRefreshesWithoutGrowingHistory() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: context)
        let accepted = model.recordAutofocusLock(lensPosition: 0.502, measuredTargetMeters: 2.1, context: context)
        #expect(accepted)

        #expect(model.observationCount == 1)
        #expect(model.estimate(lensPosition: 0.502, context: context)?.meters == 2.1)
    }

    @Test func historyIsBoundedAndConflictMarkersSurviveEviction() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0, measuredTargetMeters: 1, context: context)
        model.recordAutofocusLock(lensPosition: 0, measuredTargetMeters: 3, context: context)
        for index in 1...30 {
            model.recordAutofocusLock(
                lensPosition: Double(index) * 0.02,
                measuredTargetMeters: 2,
                context: context
            )
            #expect(model.observationCount <= 16)
        }

        #expect(model.observationCount == 16)
        #expect(model.estimate(lensPosition: 0, context: context) == nil)
        let acceptedInConflictRegion = model.recordAutofocusLock(lensPosition: 0, measuredTargetMeters: 1, context: context)
        #expect(!acceptedInConflictRegion)
        #expect(model.estimate(lensPosition: 0.02, context: context) == nil)
        #expect(model.estimate(lensPosition: 0.6, context: context)?.meters == 2)
    }

    @Test func distancePresentationRoundsWithoutInventingMissingValues() {
        #expect(CameraFocusDistanceEstimate.formattedMeters(1.234) == "1.2")
        #expect(CameraFocusDistanceEstimate.formattedMeters(2.01) == "2")
        #expect(CameraFocusDistanceEstimate.formattedMeters(0.456) == "0.46")
        #expect(CameraFocusDistanceEstimate.formattedMeters(9.99) == "10")
        #expect(CameraFocusDistanceEstimate.formattedMeters(102.3) == "102")
        #expect(CameraFocusDistanceEstimate.formattedMeters(0.02) == "0.02")
        #expect(CameraFocusDistanceEstimate.formattedMeters(0.000_000_000_1) == nil)
        #expect(CameraFocusDistanceEstimate.formattedMeters(.nan) == nil)
        #expect(CameraFocusDistanceEstimate.formattedMeters(.infinity) == nil)
        #expect(CameraFocusDistanceEstimate.formattedMeters(0) == nil)
    }

    @Test func preferencesRestoreTheSameDeviceIntoANewRuntimeContext() throws {
        let suiteName = "TAPCameraFocusDistanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldContext = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: oldContext)
        model.recordAutofocusLock(lensPosition: 0.4, measuredTargetMeters: 1, context: oldContext)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: oldContext)
        #expect(CameraFocusDistancePreferences.save(model, in: defaults))

        let newContext = context(generation: 20)
        var restored = try #require(CameraFocusDistancePreferences.load(context: newContext, in: defaults))
        #expect(restored.context == newContext)
        #expect(restored.estimate(lensPosition: 0.4, context: newContext)?.meters == 1)
        #expect(restored.estimate(lensPosition: 0.45, context: newContext)?.basis == .interpolated)
        #expect(restored.estimate(lensPosition: 0.4, context: oldContext) == nil)
        let acceptedLateObservation = restored.recordAutofocusLock(
            lensPosition: 0.4, measuredTargetMeters: 3, context: oldContext
        )
        #expect(!acceptedLateObservation)
        #expect(CameraFocusDistancePreferences.load(context: context(deviceID: "another-device"), in: defaults) == nil)
    }

    @Test func persistencePreservesConflictMarkersAndTheObservationBound() throws {
        let suiteName = "TAPCameraFocusDistanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0, measuredTargetMeters: 1, context: context)
        model.recordAutofocusLock(lensPosition: 0, measuredTargetMeters: 3, context: context)
        for index in 1...20 {
            model.recordAutofocusLock(lensPosition: Double(index) * 0.02, measuredTargetMeters: 2, context: context)
        }
        #expect(CameraFocusDistancePreferences.save(model, in: defaults))
        let restored = try #require(CameraFocusDistancePreferences.load(context: context, in: defaults))
        #expect(restored.observationCount == 16)
        #expect(restored.estimate(lensPosition: 0, context: context) == nil)
        #expect(restored.estimate(lensPosition: 0.4, context: context)?.meters == 2)
    }

    @Test func restoreRejectsInvalidOrContradictorySamplesWithoutReplacingTheModel() {
        let context = context()
        var model = CameraFocusDistanceModel()
        model.reset(context: context)
        model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: context)
        typealias Observation = CameraFocusDistanceModel.Observation
        let invalidSamples: [[Observation]] = [
            [],
            [.init(lensPosition: .nan, meters: 2)],
            [.init(lensPosition: 1.1, meters: 2)],
            [.init(lensPosition: 0.4, meters: .infinity)],
            [.init(lensPosition: 0.4, meters: -1)],
            [.init(lensPosition: 0.4, meters: 0)],
            [.init(lensPosition: 0.4, meters: 1), .init(lensPosition: 0.4, meters: 1)],
            [.init(lensPosition: 0.4, meters: 1), .init(lensPosition: 0.402, meters: 3)],
            (0...16).map { Observation(lensPosition: Double($0) * 0.02, meters: 2) }
        ]
        for observations in invalidSamples {
            let restored = model.restore(.init(deviceID: context.deviceID, observations: observations), context: context)
            #expect(!restored)
            #expect(model.observationCount == 1)
            #expect(model.estimate(lensPosition: 0.5, context: context)?.meters == 2)
        }
    }

    @Test func preferencesRejectMalformedAndOversizedStoredData() throws {
        let suiteName = "TAPCameraFocusDistanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = context()
        for data in [Data("invalid".utf8), Data(repeating: 0, count: 16_385)] {
            defaults.set(data, forKey: CameraFocusDistancePreferences.storageKey)
            #expect(CameraFocusDistancePreferences.load(context: context, in: defaults) == nil)
        }
        #expect(!CameraFocusDistancePreferences.save(CameraFocusDistanceModel(), in: defaults))
    }

    @Test func preferencesKeepOnlyTheMostRecentDeviceCalibration() throws {
        let suiteName = "TAPCameraFocusDistanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for deviceID in ["first-device", "second-device"] {
            let context = context(deviceID: deviceID)
            var model = CameraFocusDistanceModel()
            model.reset(context: context)
            model.recordAutofocusLock(lensPosition: 0.5, measuredTargetMeters: 2, context: context)
            #expect(CameraFocusDistancePreferences.save(model, in: defaults))
        }
        #expect(CameraFocusDistancePreferences.load(context: context(deviceID: "first-device"), in: defaults) == nil)
        #expect(CameraFocusDistancePreferences.load(context: context(deviceID: "second-device"), in: defaults) != nil)
    }

    private func context(
        deviceID: String = "lidar-device",
        generation: Int = 1,
        supportsCustomLensPosition: Bool = true
    ) -> CameraFocusDistanceModel.Context {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            deviceID: deviceID,
            supportsCustomLensPosition: supportsCustomLensPosition
        )
        return CameraFocusDistanceModel.Context(
            deviceID: deviceID,
            controlSurfaceSignature: .init(capability: capability),
            generation: generation
        )
    }
}
