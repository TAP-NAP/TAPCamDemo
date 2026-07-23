//
//  CameraManualFocusWriteCoordinator.swift
//  TAPCamDemo
//

import Foundation

/// Pure state machine for the UI-cadence MF write pump.
///
/// Entry is a completion barrier: numeric values may accumulate while the
/// current lens position is being locked, but only the latest one is released
/// after that barrier. The same rule applies while a numeric write is active.
nonisolated struct CameraManualFocusWritePumpState: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case inactive
        case entering
        case active
    }

    private var phase: Phase = .inactive
    private(set) var isWriteInFlight = false
    private(set) var pendingLensPosition: Double?

    var pendingLensPositionSnapshot: Double? {
        pendingLensPosition
    }

    mutating func queue(lensPosition: Double) {
        pendingLensPosition = lensPosition
    }

    mutating func beginEntry(preserving pendingLensPosition: Double?) {
        phase = .entering
        isWriteInFlight = true
        self.pendingLensPosition = pendingLensPosition
    }

    mutating func completeEntry() {
        guard phase == .entering, isWriteInFlight else {
            return
        }
        phase = .active
        isWriteInFlight = false
    }

    mutating func takeNextPositionIfReady() -> Double? {
        guard phase == .active,
              !isWriteInFlight,
              let pendingLensPosition else {
            return nil
        }
        self.pendingLensPosition = nil
        isWriteInFlight = true
        return pendingLensPosition
    }

    mutating func completePositionWrite() {
        guard phase == .active, isWriteInFlight else {
            return
        }
        isWriteInFlight = false
    }

    mutating func cancel() {
        phase = .inactive
        isWriteInFlight = false
        pendingLensPosition = nil
    }
}

/// Request-local autofocus settling state for MF tap assist.
///
/// A bare `isAdjustingFocus == false` immediately after the command does not
/// prove that the one-shot AF cycle has started. The runtime waits either for a
/// started -> stably-settled cycle, or for a short no-motion grace window when
/// the selected point was already in focus.
nonisolated struct CameraManualFocusAutoFocusSettleState: Equatable, Sendable {
    private(set) var didApplyRequest = false
    private(set) var didObserveAdjustment = false
    private(set) var isAdjustingFocus = false
    private(set) var revision = 0

    mutating func markRequestApplied(isAdjustingFocus: Bool) -> Int? {
        didApplyRequest = true
        return update(isAdjustingFocus: isAdjustingFocus)
    }

    mutating func observe(isAdjustingFocus: Bool) -> Int? {
        guard didApplyRequest else {
            return nil
        }
        return update(isAdjustingFocus: isAdjustingFocus)
    }

    func canSettle(
        at revision: Int,
        allowingNoObservedAdjustment: Bool
    ) -> Bool {
        didApplyRequest
            && self.revision == revision
            && !isAdjustingFocus
            && (didObserveAdjustment || allowingNoObservedAdjustment)
    }

    private mutating func update(isAdjustingFocus: Bool) -> Int? {
        revision &+= 1
        self.isAdjustingFocus = isAdjustingFocus
        if isAdjustingFocus {
            didObserveAdjustment = true
            return nil
        }
        return didObserveAdjustment ? revision : nil
    }
}

nonisolated enum CameraManualFocusTapAssistTransactionCompletion<Output: Sendable>: Sendable {
    case focused(Output)
    case recovered(Output)
}

extension CameraManualFocusTapAssistTransactionCompletion: Equatable where Output: Equatable {}

nonisolated enum CameraManualFocusTapAssistOutcome: Equatable, Sendable {
    case focused(CameraManualControlReadbackSnapshot)
    case failedButRecovered(CameraManualControlReadbackSnapshot)
    case cancelled
    case unavailable
    case manualFocusLost
}

/// Serializes physical MF operations across logical context cancellation.
///
/// Invalidating one logical context cannot cancel an operation already handed
/// to AVFoundation. Keeping this transport tail separate ensures a rapid
/// AF -> MF -> AF -> MF sequence still has at most one hardware write active.
@MainActor
final class CameraManualFocusTransportQueue {
    private var tail: Task<Void, Never>?
    private var tailID: UUID?

    func perform<Output: Sendable>(
        preflight: @escaping @MainActor () -> Bool,
        operation: @escaping @MainActor () async throws -> Output
    ) async throws -> Output {
        let predecessor = tail
        let operationID = UUID()
        let work = Task { @MainActor () throws -> Output in
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            guard preflight() else {
                throw CancellationError()
            }
            return try await operation()
        }
        let barrier = Task { @MainActor in
            _ = try? await work.value
        }
        tail = barrier
        tailID = operationID

        do {
            let output = try await work.value
            clearTail(ifMatching: operationID)
            return output
        } catch {
            clearTail(ifMatching: operationID)
            throw error
        }
    }

    private func clearTail(ifMatching operationID: UUID) {
        guard tailID == operationID else {
            return
        }
        tail = nil
        tailID = nil
    }
}

/// Runs focus-only AF and the final current-position MF lock as one transport
/// transaction. A recoverable AF failure still attempts the current-position
/// lock so the UI never claims MF while the device remains in AF.
@MainActor
enum CameraManualFocusTapAssistTransaction {
    static func perform<Output: Sendable>(
        through transport: CameraManualFocusTransportQueue,
        preflight: @escaping @MainActor () -> Bool,
        autoFocusAndWait: @escaping @MainActor () async throws -> Void,
        lockCurrent: @escaping @MainActor () async throws -> Output
    ) async throws -> CameraManualFocusTapAssistTransactionCompletion<Output> {
        try await transport.perform(preflight: preflight) {
            do {
                try await autoFocusAndWait()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard preflight() else {
                    throw CancellationError()
                }
                return .recovered(try await lockCurrent())
            }

            guard preflight() else {
                throw CancellationError()
            }
            return .focused(try await lockCurrent())
        }
    }
}
