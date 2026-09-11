import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraFocusDepthSamplerTests {
    @Test func onlyAbsoluteHighQualityUnfilteredDepthCanTeachMeters() {
        #expect(CameraFocusDepthSampler.accepts(accuracy: .absolute, quality: .high, isFiltered: false))
        #expect(!CameraFocusDepthSampler.accepts(accuracy: .relative, quality: .high, isFiltered: false))
        #expect(!CameraFocusDepthSampler.accepts(accuracy: .absolute, quality: .low, isFiltered: false))
        #expect(!CameraFocusDepthSampler.accepts(accuracy: .absolute, quality: .high, isFiltered: true))
    }

    @Test func depthMustFollowAppliedLockAndRemainFreshOnTheSameClock() {
        let applied = time(10)
        #expect(CameraFocusDepthSampler.isFresh(timestamp: time(10.1), earliestTime: applied, now: time(10.2)))
        #expect(!CameraFocusDepthSampler.isFresh(timestamp: time(9.99), earliestTime: applied, now: time(10.2)))
        #expect(!CameraFocusDepthSampler.isFresh(timestamp: time(10.1), earliestTime: applied, now: time(10.5)))
        #expect(!CameraFocusDepthSampler.isFresh(timestamp: time(10.9), earliestTime: applied, now: time(11)))
        #expect(!CameraFocusDepthSampler.isFresh(timestamp: time(10.2), earliestTime: applied, now: time(10.1)))
        #expect(!CameraFocusDepthSampler.isFresh(timestamp: .invalid, earliestTime: applied, now: time(10.1)))
    }

    @Test func canonicalCoordinatesSelectAnOffCenterTargetAndIncludeImageEdges() throws {
        let map = try makeMap(width: 24, height: 16) { x, y in
            if x >= 16 && y <= 7 { return 1.5 }
            return 4
        }
        #expect(CameraFocusDepthSampler.distance(in: map, at: .init(x: 0.85, y: 0.2)) == 1.5)
        #expect(CameraFocusDepthSampler.distance(in: map, at: .init(x: 0, y: 1)) == 4)
        #expect(CameraFocusDepthSampler.distance(in: map, at: .init(x: 1, y: 0)) == 1.5)
    }

    @Test func rowPaddingDoesNotBecomeDepthAndSmallOutlierDoesNotMoveMedian() throws {
        let map = try makeMap(width: 9, height: 9) { x, y in
            x == 2 && y == 2 ? 8 : 2
        }
        #expect(CameraFocusDepthSampler.distance(in: map, at: .init(x: 0.5, y: 0.5)) == 2)
    }

    @Test func mixedForegroundAndBackgroundCannotCreateALensDistancePair() throws {
        let map = try makeMap(width: 9, height: 9) { x, _ in x < 4 ? 1 : 6 }
        #expect(CameraFocusDepthSampler.distance(in: map, at: .init(x: 0.5, y: 0.5)) == nil)
    }

    @Test func missingCenterAndMostlyInvalidPatchCannotBorrowNeighborDistance() throws {
        let missingCenter = try makeMap(width: 9, height: 9) { x, y in
            x == 4 && y == 4 ? .nan : 2
        }
        let sparse = try makeMap(width: 9, height: 9) { x, y in
            x == 4 && y == 4 ? 2 : .infinity
        }
        #expect(CameraFocusDepthSampler.distance(in: missingCenter, at: .init(x: 0.5, y: 0.5)) == nil)
        #expect(CameraFocusDepthSampler.distance(in: sparse, at: .init(x: 0.5, y: 0.5)) == nil)
    }

    @Test func invalidCoordinatesAndNonPositiveDepthAreRejected() throws {
        let zeroMap = try makeMap(width: 9, height: 9) { _, _ in 0 }
        #expect(CameraFocusDepthSampler.distance(in: zeroMap, at: .init(x: 0.5, y: 0.5)) == nil)
        #expect(CameraFocusDepthSampler.distance(in: zeroMap, at: .init(x: -.infinity, y: 0.5)) == nil)
        #expect(CameraFocusDepthSampler.distance(in: zeroMap, at: .init(x: 1.1, y: 0.5)) == nil)
    }

    @Test func replacingAndCancellingRequestsCompletesEachExactlyOnce() {
        let sampler = CameraFocusDepthSampler()
        let first = DepthMeasurementCompletionCounter()
        let second = DepthMeasurementCompletionCounter()
        let firstID = UUID()
        let secondID = UUID()
        sampler.request(
            id: firstID, point: .init(x: 0.5, y: 0.5), earliestTime: time(1),
            clock: CMClockGetHostTimeClock()
        ) { _ in first.increment() }
        sampler.request(
            id: secondID, point: .init(x: 0.5, y: 0.5), earliestTime: time(1),
            clock: CMClockGetHostTimeClock()
        ) { _ in second.increment() }
        sampler.cancel(id: firstID)
        #expect(first.count == 1)
        #expect(second.count == 0)
        sampler.cancel(id: secondID)
        sampler.cancel()
        #expect(first.count == 1)
        #expect(second.count == 1)
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1_000)
    }

    private func makeMap(
        width: Int,
        height: Int,
        value: (Int, Int) -> Float
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_DepthFloat32,
            [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary, &buffer
        )
        #expect(status == kCVReturnSuccess)
        let map = try #require(buffer)
        CVPixelBufferLockBaseAddress(map, [])
        defer { CVPixelBufferUnlockBaseAddress(map, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(map))
        let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
        let pixels = base.assumingMemoryBound(to: Float.self)
        for y in 0..<height {
            for x in 0..<stride { pixels[y * stride + x] = x < width ? value(x, y) : -99 }
        }
        return map
    }
}

private nonisolated final class DepthMeasurementCompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
