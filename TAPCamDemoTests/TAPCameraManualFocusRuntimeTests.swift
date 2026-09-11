//
//  TAPCameraManualFocusRuntimeTests.swift
//  TAPCamDemoTests
//

import CoreGraphics
import Foundation
import QuartzCore
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPCameraManualFocusRuntimeTests {
    @Test func entryBarrierReleasesOnlyTheLatestQueuedLensPosition() {
        var state = CameraManualFocusWritePumpState()
        state.beginEntry(preserving: nil)
        state.queue(lensPosition: 0.2)
        state.queue(lensPosition: 0.6)
        state.queue(lensPosition: 0.9)

        #expect(state.takeNextPositionIfReady() == nil)

        state.completeEntry()
        #expect(state.takeNextPositionIfReady() == 0.9)
        #expect(state.isWriteInFlight)
    }

    @Test func numericWriteKeepsOnlyOneLatestPendingPosition() {
        var state = CameraManualFocusWritePumpState()
        state.beginEntry(preserving: 0.2)
        state.completeEntry()
        #expect(state.takeNextPositionIfReady() == 0.2)

        state.queue(lensPosition: 0.3)
        state.queue(lensPosition: 0.7)
        #expect(state.takeNextPositionIfReady() == nil)

        state.completePositionWrite()
        #expect(state.takeNextPositionIfReady() == 0.7)
    }

    @Test func autofocusSettleStateRequiresAStableCycleOrNoMotionGrace() {
        var alreadyFocused = CameraManualFocusAutoFocusSettleState()
        #expect(alreadyFocused.observe(isAdjustingFocus: false) == nil)
        #expect(alreadyFocused.markRequestApplied(isAdjustingFocus: false) == nil)
        #expect(alreadyFocused.canSettle(
            at: alreadyFocused.revision,
            allowingNoObservedAdjustment: true
        ))
        #expect(!alreadyFocused.canSettle(
            at: alreadyFocused.revision,
            allowingNoObservedAdjustment: false
        ))

        var moving = CameraManualFocusAutoFocusSettleState()
        #expect(moving.markRequestApplied(isAdjustingFocus: true) == nil)
        let settledRevision = moving.observe(isAdjustingFocus: false)
        #expect(settledRevision != nil)
        #expect(moving.canSettle(
            at: settledRevision ?? -1,
            allowingNoObservedAdjustment: false
        ))

        _ = moving.observe(isAdjustingFocus: true)
        #expect(!moving.canSettle(
            at: settledRevision ?? -1,
            allowingNoObservedAdjustment: false
        ))
    }

    @Test func operationTokenInvalidationWakesRegisteredWaiterExactlyOnce() {
        let token = CameraManualFocusOperationToken()
        let counter = LockedTestCounter()
        token.addInvalidationHandler {
            counter.increment()
        }

        token.invalidate()
        token.invalidate()

        #expect(counter.value == 1)
        #expect(!token.isValid)
    }

    @Test func loupeTransformCentersOffAxisTapInPortraitAndLandscape() {
        let focusPoints = [
            CameraPreviewFocusPoint(x: 0.5, y: 0.5),
            CameraPreviewFocusPoint(x: 0.12, y: 0.84),
            CameraPreviewFocusPoint(x: 0.86, y: 0.18)
        ]
        let previewSizes = [
            CGSize(width: 300, height: 400),
            CGSize(width: 400, height: 300)
        ]

        for previewSize in previewSizes {
            for focusPoint in focusPoints {
                let transform = CameraManualFocusLoupeTransform(
                    focusPoint: focusPoint,
                    previewSize: previewSize,
                    magnification: 2.4
                )
                let displayedFocus = transform.displayedPoint(for: focusPoint)

                #expect(abs(displayedFocus.x - previewSize.width / 2) < 0.0001)
                #expect(abs(displayedFocus.y - previewSize.height / 2) < 0.0001)
            }
        }
    }

    @Test func loupeTransformPreservesMagnifiedDistanceAroundTappedCenter() {
        let previewSize = CGSize(width: 320, height: 480)
        let focusPoint = CameraPreviewFocusPoint(x: 0.2, y: 0.8)
        let neighboringPoint = CameraPreviewFocusPoint(x: 0.3, y: 0.7)
        let transform = CameraManualFocusLoupeTransform(
            focusPoint: focusPoint,
            previewSize: previewSize,
            magnification: 2.4
        )

        let displayedFocus = transform.displayedPoint(for: focusPoint)
        let displayedNeighbor = transform.displayedPoint(for: neighboringPoint)

        #expect(abs((displayedNeighbor.x - displayedFocus.x) - 76.8) < 0.0001)
        #expect(abs((displayedNeighbor.y - displayedFocus.y) + 115.2) < 0.0001)
    }

    @Test @MainActor func tapAssistWaitsForAutofocusBeforeLockingCurrent() async throws {
        let transport = CameraManualFocusTransportQueue()
        let backend = ControlledManualFocusTapAssistBackend()

        let task = Task { @MainActor in
            try await CameraManualFocusTapAssistTransaction.perform(
                through: transport,
                preflight: { true },
                autoFocusAndWait: {
                    try await backend.autoFocusAndWait()
                },
                lockCurrent: {
                    try await backend.lockCurrent()
                }
            )
        }

        try await backend.waitUntilCallCount(1)
        let callsBeforeSettle = await backend.calls
        #expect(callsBeforeSettle == [.autoFocus])

        await backend.settleAutoFocus()
        try await backend.waitUntilCallCount(2)
        let callsAfterSettle = await backend.calls
        #expect(callsAfterSettle == [.autoFocus, .lockCurrent])

        await backend.finishLock(value: 72)
        let completion = try await task.value
        #expect(completion == .focused(72))
    }

    @Test @MainActor func tapAssistRelocksCurrentAfterRecoverableAutofocusFailure() async throws {
        let transport = CameraManualFocusTransportQueue()
        let backend = ControlledManualFocusTapAssistBackend()

        let task = Task { @MainActor in
            try await CameraManualFocusTapAssistTransaction.perform(
                through: transport,
                preflight: { true },
                autoFocusAndWait: {
                    try await backend.autoFocusAndWait()
                },
                lockCurrent: {
                    try await backend.lockCurrent()
                }
            )
        }

        try await backend.waitUntilCallCount(1)
        await backend.failAutoFocus()
        try await backend.waitUntilCallCount(2)
        await backend.finishLock(value: 41)

        let completion = try await task.value
        let calls = await backend.calls
        #expect(calls == [.autoFocus, .lockCurrent])
        #expect(completion == .recovered(41))
    }

    @Test @MainActor func transportRemainsSingleFlightAcrossLogicalContexts() async throws {
        let transport = CameraManualFocusTransportQueue()
        let writer = ControlledManualFocusWriter()

        let first = Task { @MainActor in
            try await transport.perform(
                preflight: { true },
                operation: { await writer.write(id: 1) }
            )
        }
        try await writer.waitUntilStarted(count: 1)

        let second = Task { @MainActor in
            try await transport.perform(
                preflight: { true },
                operation: { await writer.write(id: 2) }
            )
        }
        await Task.yield()
        let startsBeforeFirstCompletion = await writer.startedIDs
        #expect(startsBeforeFirstCompletion == [1])

        await writer.finish(id: 1)
        try await writer.waitUntilStarted(count: 2)
        await writer.finish(id: 2)

        let firstValue = try await first.value
        let secondValue = try await second.value
        let peakInFlight = await writer.peakInFlight
        #expect(firstValue == 1)
        #expect(secondValue == 2)
        #expect(peakInFlight == 1)
    }

    @Test @MainActor func targetMeasurementFinishesBeforeTheNextLensWrite() async throws {
        let transport = CameraManualFocusTransportQueue()
        let writer = ControlledManualFocusWriter()
        let assist = Task { @MainActor in
            try await CameraManualFocusTapAssistTransaction.perform(
                through: transport,
                preflight: { true },
                autoFocusAndWait: {},
                lockCurrent: { 42 },
                didFocusAndLock: { _ in _ = await writer.write(id: 1) }
            )
        }
        try await writer.waitUntilStarted(count: 1)
        let slider = Task { @MainActor in
            try await transport.perform(
                preflight: { true },
                operation: { await writer.write(id: 2) }
            )
        }
        await Task.yield()
        #expect(await writer.startedIDs == [1])
        await writer.finish(id: 1)
        try await writer.waitUntilStarted(count: 2)
        await writer.finish(id: 2)
        #expect(try await assist.value == .focused(42))
        #expect(try await slider.value == 2)
        #expect(await writer.peakInFlight == 1)
    }

    @Test @MainActor func failedAutofocusCannotCreateADistanceObservation() async throws {
        var observed = false
        let result = try await CameraManualFocusTapAssistTransaction.perform(
            through: CameraManualFocusTransportQueue(),
            preflight: { true },
            autoFocusAndWait: { throw NSError(domain: "AF did not settle", code: 1) },
            lockCurrent: { 42 },
            didFocusAndLock: { _ in observed = true }
        )
        #expect(result == .recovered(42))
        #expect(!observed)
    }

    @Test @MainActor func staleContextIsRejectedBeforeItsQueuedWriteStarts() async throws {
        let transport = CameraManualFocusTransportQueue()
        let writer = ControlledManualFocusWriter()
        var secondContextIsValid = true

        let first = Task { @MainActor in
            try await transport.perform(
                preflight: { true },
                operation: { await writer.write(id: 1) }
            )
        }
        try await writer.waitUntilStarted(count: 1)

        let second = Task { @MainActor in
            do {
                _ = try await transport.perform(
                    preflight: { secondContextIsValid },
                    operation: { await writer.write(id: 2) }
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        secondContextIsValid = false
        await writer.finish(id: 1)

        _ = try await first.value
        let rejectedAsStale = await second.value
        let startedIDs = await writer.startedIDs
        #expect(rejectedAsStale)
        #expect(startedIDs == [1])
    }

    @Test @MainActor func loupeRotationNeverMutatesItsHostViewGeometry() {
        let view = CameraManualFocusLoupeDisplayView(
            frame: CGRect(x: 0, y: 0, width: 160, height: 90)
        )
        view.layoutIfNeeded()
        let hostBounds = view.bounds

        view.previewRotationAngleDegrees = 90
        view.layoutIfNeeded()

        #expect(view.layer !== view.displayLayer)
        #expect(view.bounds == hostBounds)
        #expect(abs(view.displayLayer.bounds.width - hostBounds.height) < 0.001)
        #expect(abs(view.displayLayer.bounds.height - hostBounds.width) < 0.001)
        #expect(abs(view.displayLayer.position.x - hostBounds.midX) < 0.001)
        #expect(abs(view.displayLayer.position.y - hostBounds.midY) < 0.001)

        view.previewRotationAngleDegrees = 17
        view.layoutIfNeeded()
        #expect(view.bounds == hostBounds)
    }
}

private actor ControlledManualFocusWriter {
    private(set) var startedIDs: [Int] = []
    private(set) var peakInFlight = 0
    private var inFlight = 0
    private var continuations: [Int: CheckedContinuation<Int, Never>] = [:]

    func write(id: Int) async -> Int {
        startedIDs.append(id)
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        let value = await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
        inFlight -= 1
        return value
    }

    func finish(id: Int) {
        continuations.removeValue(forKey: id)?.resume(returning: id)
    }

    func waitUntilStarted(count: Int) async throws {
        for _ in 0..<2_000 {
            if startedIDs.count >= count {
                return
            }
            await Task.yield()
        }
        throw ControlledManualFocusWriterError.startTimedOut
    }
}

private enum ControlledManualFocusWriterError: Error {
    case startTimedOut
}

private nonisolated final class LockedTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private actor ControlledManualFocusTapAssistBackend {
    enum Call: Equatable, Sendable {
        case autoFocus
        case lockCurrent
    }

    private(set) var calls: [Call] = []
    private var autoFocusContinuation: CheckedContinuation<Void, Error>?
    private var lockContinuation: CheckedContinuation<Int, Error>?

    func autoFocusAndWait() async throws {
        calls.append(.autoFocus)
        try await withCheckedThrowingContinuation { continuation in
            autoFocusContinuation = continuation
        }
    }

    func lockCurrent() async throws -> Int {
        calls.append(.lockCurrent)
        return try await withCheckedThrowingContinuation { continuation in
            lockContinuation = continuation
        }
    }

    func settleAutoFocus() {
        autoFocusContinuation?.resume()
        autoFocusContinuation = nil
    }

    func failAutoFocus() {
        autoFocusContinuation?.resume(throwing: ControlledManualFocusTapAssistError.autoFocusFailed)
        autoFocusContinuation = nil
    }

    func finishLock(value: Int) {
        lockContinuation?.resume(returning: value)
        lockContinuation = nil
    }

    func waitUntilCallCount(_ count: Int) async throws {
        for _ in 0..<2_000 {
            if calls.count >= count {
                return
            }
            await Task.yield()
        }
        throw ControlledManualFocusTapAssistError.callTimedOut
    }
}

private enum ControlledManualFocusTapAssistError: Error {
    case autoFocusFailed
    case callTimedOut
}
