//
//  PhotoKitRequestLifecycle.swift
//  TAPCamDemo
//

import Foundation

/// Serializes the three races shared by PhotoKit callback adapters:
/// continuation installation, request-ID installation, and terminal delivery.
/// A terminal result, request cancellation, and continuation resume are each
/// delivered at most once.
nonisolated final class PhotoKitRequestLifecycle<RequestID: Sendable, Output: Sendable>: @unchecked Sendable {
    typealias TerminalResult = Result<Output, any Error>

    private struct Delivery {
        let requestIDToCancel: RequestID?
        let continuation: CheckedContinuation<Output, any Error>?
        let result: TerminalResult
    }

    private let lock = NSLock()
    private let cancelRequest: @Sendable (RequestID) -> Void
    private let onFinish: @Sendable (TerminalResult) -> Void
    private var continuation: CheckedContinuation<Output, any Error>?
    private var installedRequestID: RequestID?
    private var terminalResult: TerminalResult?
    private var didInstallContinuation = false
    private var didInstallRequestID = false

    init(
        cancelRequest: @escaping @Sendable (RequestID) -> Void,
        onFinish: @escaping @Sendable (TerminalResult) -> Void = { _ in }
    ) {
        self.cancelRequest = cancelRequest
        self.onFinish = onFinish
    }

    /// Returns false when cancellation or another terminal event won before
    /// the async operation installed its continuation.
    @discardableResult
    func install(
        continuation: CheckedContinuation<Output, any Error>
    ) -> Bool {
        let pendingResult: TerminalResult?
        lock.lock()
        precondition(
            !didInstallContinuation,
            "PhotoKit continuation installed more than once"
        )
        didInstallContinuation = true
        if let terminalResult {
            pendingResult = terminalResult
        } else {
            self.continuation = continuation
            pendingResult = nil
        }
        lock.unlock()

        if let pendingResult {
            continuation.resume(with: pendingResult)
            return false
        }
        return true
    }

    /// A request may finish or be cancelled synchronously before PhotoKit
    /// returns its identifier. Such a late identifier is cancelled once here.
    func install(requestID: RequestID) {
        let shouldCancel: Bool
        lock.lock()
        precondition(
            !didInstallRequestID,
            "PhotoKit request identifier installed more than once"
        )
        didInstallRequestID = true
        if terminalResult != nil {
            shouldCancel = true
        } else {
            installedRequestID = requestID
            shouldCancel = false
        }
        lock.unlock()

        if shouldCancel {
            cancelRequest(requestID)
        }
    }

    func cancel() {
        complete(
            with: .failure(CancellationError()),
            cancellingInstalledRequest: true
        )
    }

    func finish(_ result: TerminalResult) {
        complete(with: result, cancellingInstalledRequest: false)
    }

    /// Produces the final sink result while callback admission is locked, so
    /// final chunks and finalization failures cannot race past completion.
    func finish(
        mapError: (any Error) -> any Error = { $0 },
        producing output: () throws -> Output
    ) {
        let delivery: Delivery?
        lock.lock()
        if terminalResult == nil {
            delivery = makeDeliveryLocked(
                result: Result { try output() }.mapError(mapError),
                cancellingInstalledRequest: false
            )
        } else {
            delivery = nil
        }
        lock.unlock()
        deliver(delivery)
    }

    /// Runs a callback only while the request is active. A sink failure wins
    /// atomically, cancels the installed PhotoKit request, and completes the
    /// continuation with the mapped error.
    func process(
        _ operation: () throws -> Void,
        mapError: (any Error) -> any Error
    ) {
        let delivery: Delivery?
        lock.lock()
        if terminalResult == nil {
            do {
                try operation()
                delivery = nil
            } catch {
                delivery = makeDeliveryLocked(
                    result: .failure(mapError(error)),
                    cancellingInstalledRequest: true
                )
            }
        } else {
            delivery = nil
        }
        lock.unlock()
        deliver(delivery)
    }

    func reportProgress(
        _ value: Double,
        to progress: @Sendable (Double?) -> Void
    ) {
        lock.lock()
        let isActive = terminalResult == nil
        lock.unlock()
        guard isActive else {
            return
        }
        progress(value.isFinite ? min(max(value, 0), 1) : nil)
    }

    private func complete(
        with result: TerminalResult,
        cancellingInstalledRequest: Bool
    ) {
        let delivery: Delivery?
        lock.lock()
        if terminalResult == nil {
            delivery = makeDeliveryLocked(
                result: result,
                cancellingInstalledRequest: cancellingInstalledRequest
            )
        } else {
            delivery = nil
        }
        lock.unlock()
        deliver(delivery)
    }

    /// The caller holds `lock` and has already established that no terminal
    /// result exists.
    private func makeDeliveryLocked(
        result: TerminalResult,
        cancellingInstalledRequest: Bool
    ) -> Delivery {
        terminalResult = result
        let requestIDToCancel = cancellingInstalledRequest ? installedRequestID : nil
        installedRequestID = nil
        let continuation = self.continuation
        self.continuation = nil
        return Delivery(
            requestIDToCancel: requestIDToCancel,
            continuation: continuation,
            result: result
        )
    }

    private func deliver(_ delivery: Delivery?) {
        guard let delivery else {
            return
        }
        if let requestIDToCancel = delivery.requestIDToCancel {
            cancelRequest(requestIDToCancel)
        }
        onFinish(delivery.result)
        delivery.continuation?.resume(with: delivery.result)
    }
}
