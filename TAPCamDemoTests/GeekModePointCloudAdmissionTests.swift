import Testing
@testable import TAPCamDemo

struct GeekModePointCloudAdmissionTests {
    @Test func freezeRetainsPresentedFrameByRejectingEveryInFlightGeneration() throws {
        var admission = GeekModePointCloudAdmission()
        admission.setActive(true)
        let beforeFreeze = try #require(admission.token)
        admission.setFrozen(true)
        #expect(admission.token == nil)
        #expect(!admission.accepts(beforeFreeze))
        admission.setFrozen(false)
        let afterFreeze = try #require(admission.token)
        #expect(admission.accepts(afterFreeze))
        #expect(!admission.accepts(beforeFreeze))
    }

    @Test func changingCameraAndStoppingRejectLateWorkAfterRestart() throws {
        var admission = GeekModePointCloudAdmission()
        admission.setActive(true)
        let rearCamera = try #require(admission.token)
        admission.reset()
        let frontCamera = try #require(admission.token)
        #expect(!admission.accepts(rearCamera))
        #expect(admission.accepts(frontCamera))
        admission.setActive(false)
        #expect(admission.token == nil)
        admission.setActive(true)
        #expect(!admission.accepts(frontCamera))
        #expect(!admission.accepts(rearCamera))
    }

    @Test func repeatedUIStateDoesNotDiscardCurrentWork() throws {
        var admission = GeekModePointCloudAdmission()
        admission.setActive(true)
        let current = try #require(admission.token)
        admission.setActive(true)
        admission.setFrozen(false)
        #expect(admission.accepts(current))
    }
}
