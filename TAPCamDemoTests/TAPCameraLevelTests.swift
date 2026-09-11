import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraLevelTests {
    @Test func gravityTracksHorizonInEveryCameraOrientation() throws {
        for (x, y, expected) in [
            (0.0, -1.0, 0.0),
            (-1.0, 0.0, Double.pi / 2),
            (1.0, 0.0, -Double.pi / 2),
            (0.0, 1.0, -Double.pi)
        ] {
            let reading = try #require(CameraLevelReading(gravityX: x, gravityY: y))
            #expect(abs(reading.horizonRadians - expected) < 0.0001)
            #expect(reading.isAligned)
        }

        // A clockwise-tilted phone needs a counterclockwise horizon on screen.
        let tilt = 10.0 * Double.pi / 180
        let reading = try #require(CameraLevelReading(gravityX: sin(tilt), gravityY: -cos(tilt)))
        #expect(abs(reading.horizonRadians + tilt) < 0.0001)
        #expect(!reading.isAligned)
        #expect(reading.referenceRadians == 0)
    }

    @Test func flatAndInvalidSamplesDoNotClaimToBeLevel() {
        #expect(CameraLevelReading(gravityX: 0, gravityY: 0) == nil)
        #expect(CameraLevelReading(gravityX: 0.05, gravityY: -0.05) == nil)
        #expect(CameraLevelReading(gravityX: .nan, gravityY: -1) == nil)
        #expect(CameraLevelReading(gravityX: 0, gravityY: .infinity) == nil)
    }
}
