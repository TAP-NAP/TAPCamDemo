import Testing
@testable import TAPCamDemo

struct TAPCameraSliderDragTests {
    @Test func manualMaximumRemainsManualUntilPushedBeyondTheEnd() {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.5)

        drag.move(x: 200, width: 200, velocity: 0, time: 0, hasAuto: true)

        #expect(!drag.isAutomatic)
        #expect(drag.target == 1)
        #expect(drag.advance(at: 0, elapsed: 0.016, smoothsChanges: false) == 1)

        drag.move(x: 215, width: 200, velocity: 0, time: 0.1, hasAuto: true)
        #expect(!drag.isAutomatic)
        #expect(drag.target == 1)

        drag.move(x: 225, width: 200, velocity: 0, time: 0.2, hasAuto: true)
        #expect(drag.isAutomatic)
        #expect(drag.advance(at: 1, elapsed: 0.016, smoothsChanges: false) == nil)
    }

    @Test func autoEntryAndExitHaveSeparateThresholdsToResistJitter() {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.move(x: 225, width: 200, velocity: 0, time: 0, hasAuto: true)
        #expect(drag.isAutomatic)

        for x in [212.0, 209, 215, 212] {
            drag.move(x: x, width: 200, velocity: 0, time: 0.1, hasAuto: true)
            #expect(drag.isAutomatic)
        }

        drag.move(x: 205, width: 200, velocity: 0, time: 0.2, hasAuto: true)
        #expect(!drag.isAutomatic)

        for x in [212.0, 215, 209, 212] {
            drag.move(x: x, width: 200, velocity: 0, time: 0.3, hasAuto: true)
            #expect(!drag.isAutomatic)
        }

        drag.move(x: 225, width: 200, velocity: 0, time: 0.4, hasAuto: true)
        #expect(drag.isAutomatic)
    }

    @Test func evWithoutAutoClampsToManualEndpoints() {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.5)

        drag.move(x: 280, width: 200, velocity: 0, time: 0, hasAuto: false)
        #expect(!drag.isAutomatic)
        #expect(drag.target == 1)
        #expect(drag.advance(at: 0, elapsed: 0.016, smoothsChanges: false) == 1)

        drag.move(x: -30, width: 200, velocity: 0, time: 0.1, hasAuto: false)
        #expect(!drag.isAutomatic)
        #expect(drag.target == 0)
        #expect(drag.advance(at: 0.1, elapsed: 0.016, smoothsChanges: false) == 0)
    }

    @Test func leavingAutoWaitsForARealManualSeedBeforeEmitting() throws {
        var drag = CameraSliderDrag(isAutomatic: true)
        drag.move(x: 160, width: 200, velocity: 0, time: 0, hasAuto: true)

        #expect(!drag.isAutomatic)
        #expect(drag.target == 0.8)
        #expect(drag.advance(at: 0.1, elapsed: 0.016, smoothsChanges: true) == nil)
        #expect(drag.advance(at: 1, elapsed: 0.016, smoothsChanges: false) == nil)

        drag.beginManual(at: 0.2)
        let output = drag.advance(at: 1.1, elapsed: 0.016, smoothsChanges: true)
        let first = try #require(output)

        #expect(first > 0.2)
        #expect(first <= 0.3)
        #expect(first < drag.target)
        try expectBoundedArrival(&drag, startingAt: 1.1)
    }

    @Test func fastSweepsMoveTheTargetWithoutEmittingValues() {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.2)

        for (index, x) in [60.0, 180, 90, 170].enumerated() {
            let time = Double(index) * 0.02
            drag.move(x: x, width: 200, velocity: 1_000, time: time, hasAuto: true)

            #expect(drag.pointerX == x)
            #expect(drag.target == x / 200)
            #expect(drag.advance(at: time + 0.01, elapsed: 0.016, smoothsChanges: true) == nil)
            #expect(drag.applied == 0.2)
        }
    }

    @Test func sustainedSlowingResumesCatchUpEvenWhileMoveEventsContinue() throws {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.1)
        drag.move(x: 180, width: 200, velocity: 1_000, time: 0, hasAuto: true)
        drag.move(x: 160, width: 200, velocity: 100, time: 0.01, hasAuto: true)

        #expect(drag.advance(at: 0.03, elapsed: 0.016, smoothsChanges: true) == nil)

        drag.move(x: 165, width: 200, velocity: 100, time: 0.05, hasAuto: true)
        drag.move(x: 170, width: 200, velocity: 100, time: 0.08, hasAuto: true)
        let output = drag.advance(at: 0.09, elapsed: 0.016, smoothsChanges: true)
        let first = try #require(output)

        #expect(first > 0.1)
        #expect(first <= 0.2)
        try expectBoundedArrival(&drag, startingAt: 0.09)
    }

    @Test(arguments: [0.1, 0.9])
    func aStationaryFingerCatchesUpWithoutOvershootInEitherDirection(seed: Double) throws {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: seed)
        drag.move(x: (1 - seed) * 200, width: 200, velocity: 1_000, time: 0, hasAuto: true)

        #expect(drag.advance(at: 0.02, elapsed: 0.016, smoothsChanges: true) == nil)

        // No more move events arrive while the finger stays still. A delayed
        // frame must still make a bounded first step, rather than jump to target.
        let output = drag.advance(at: 0.2, elapsed: 1, smoothsChanges: true)
        let first = try #require(output)
        #expect(first != seed)
        #expect(abs(first - seed) <= 0.25)
        #expect(first != drag.target)
        try expectBoundedArrival(&drag, startingAt: 0.2)
    }

    @Test func releasingDuringAFastSweepStillCommitsTheFinalTarget() throws {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.1)
        drag.move(x: 173, width: 200, velocity: 1_000, time: 0, hasAuto: true)
        #expect(drag.advance(at: 0.01, elapsed: 0.016, smoothsChanges: true) == nil)

        drag.isTouching = false
        let output = drag.advance(at: 0.02, elapsed: 0.016, smoothsChanges: true)
        let first = try #require(output)
        #expect(first > 0.1)
        #expect(first <= 0.2)
        try expectBoundedArrival(&drag, startingAt: 0.02)
        #expect(drag.applied == 0.865)
    }

    @Test func catchUpFollowsTheLatestTargetWhenTheFingerReverses() throws {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.4)
        drag.move(x: 180, width: 200, velocity: 0, time: 0, hasAuto: true)
        let risingOutput = drag.advance(at: 0.1, elapsed: 0.016, smoothsChanges: true)
        let rising = try #require(risingOutput)
        #expect(rising > 0.4)

        drag.move(x: 40, width: 200, velocity: 100, time: 0.11, hasAuto: true)
        let fallingOutput = drag.advance(at: 0.12, elapsed: 0.016, smoothsChanges: true)
        let falling = try #require(fallingOutput)
        #expect(falling < rising)
        #expect(falling >= 0.2)
        try expectBoundedArrival(&drag, startingAt: 0.12)
        #expect(drag.applied == 0.2)
    }

    @Test func returningToAutoStopsCatchUpAndDiscardsThePreviousManualSeed() throws {
        var drag = CameraSliderDrag(isAutomatic: false)
        drag.beginManual(at: 0.1)
        drag.move(x: 180, width: 200, velocity: 0, time: 0, hasAuto: true)
        let output = drag.advance(at: 0.1, elapsed: 0.016, smoothsChanges: true)
        _ = try #require(output)

        drag.move(x: 230, width: 200, velocity: 100, time: 0.11, hasAuto: true)
        #expect(drag.isAutomatic)
        #expect(drag.advance(at: 0.2, elapsed: 0.016, smoothsChanges: true) == nil)
        drag.isTouching = false
        #expect(drag.advance(at: 1, elapsed: 0.016, smoothsChanges: true) == nil)
        #expect(drag.advance(at: 1, elapsed: 0.016, smoothsChanges: false) == nil)

        drag.isTouching = true
        drag.move(x: 120, width: 200, velocity: 0, time: 1.1, hasAuto: true)
        #expect(!drag.isAutomatic)
        #expect(drag.advance(at: 1.2, elapsed: 0.016, smoothsChanges: true) == nil)
    }

    private func expectBoundedArrival(_ drag: inout CameraSliderDrag, startingAt time: Double) throws {
        let target = drag.target
        var previous = try #require(drag.applied)
        for frame in 1...60 {
            if drag.hasReachedTarget { break }
            let output = drag.advance(
                at: time + Double(frame) * 0.016,
                elapsed: 0.016,
                smoothsChanges: true
            )
            let value = try #require(output)
            #expect(value >= min(previous, target))
            #expect(value <= max(previous, target))
            #expect(abs(value - previous) <= 0.1)
            previous = value
        }
        #expect(drag.hasReachedTarget)
        #expect(drag.applied == target)
        #expect(drag.advance(at: time + 2, elapsed: 0.016, smoothsChanges: true) == nil)
    }
}
