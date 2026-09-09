//
//  MediaProgressCoalescers.swift
//  TAPCamDemo
//

import Foundation

/// Constant-space backpressure for file-copy and archive progress callbacks.
///
/// Producers can submit once per byte chunk. Consumers receive at most one
/// intermediate latest-value sample per `minimumInterval`, while explicit 0
/// and 1 endpoints are retained. Successful completion drains those endpoints
/// immediately instead of adding one fixed throttle interval to a fast Share.
/// Cancellation closes the request identity and drops every buffered or
/// delayed sample.
nonisolated final class TAPShareProgressCoalescer: @unchecked Sendable {
    typealias Delivery = @Sendable (Double?) -> Void

    private let buffer: MediaProgressBuffer
    private let delivery: Delivery
    private let deliveryGate: NSRecursiveLock
    private let signalContinuation: AsyncStream<Void>.Continuation
    private let workerTask: Task<Void, Never>

    init(
        minimumInterval: Duration = .milliseconds(50),
        delivery: @escaping Delivery
    ) {
        let buffer = MediaProgressBuffer()
        let signals = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let deliveryGate = NSRecursiveLock()
        self.buffer = buffer
        self.delivery = delivery
        self.deliveryGate = deliveryGate
        signalContinuation = signals.continuation
        workerTask = Task.detached(priority: .utility) {
            for await _ in signals.stream {
                drainLoop: while !Task.isCancelled {
                    switch buffer.nextAction() {
                    case .deliver(let sample, let isFinal):
                        // Completion cancels a throttle sleep so the final
                        // endpoint is not delayed. A sample already claimed by
                        // the worker must still be delivered in that case;
                        // explicit request cancellation closes `allowsDelivery`.
                        let didDeliver = deliveryGate.withLock {
                            guard buffer.allowsDelivery else {
                                return false
                            }
                            delivery(sample.progress)
                            return true
                        }
                        guard didDeliver else {
                            return
                        }
                        if isFinal {
                            return
                        }
                        do {
                            try await Task.sleep(for: minimumInterval)
                        } catch {
                            return
                        }
                    case .wait:
                        break drainLoop
                    case .stop:
                        return
                    }
                }
            }
        }
    }

    deinit {
        cancel()
    }

    func submit(_ progress: Double?) {
        buffer.submit(progress)
        signalContinuation.yield()
    }

    func finish() async {
        buffer.finish()
        signalContinuation.finish()
        workerTask.cancel()
        await workerTask.value
        for sample in buffer.takeCompletionSamples() {
            deliveryGate.withLock {
                guard buffer.allowsDelivery else {
                    return
                }
                delivery(sample.progress)
            }
        }
    }

    func cancel() {
        buffer.cancel()
        // Wait for an already-running callback before returning. The recursive
        // gate also permits a delivery closure to cancel its own request.
        deliveryGate.withLock {}
        signalContinuation.finish()
        workerTask.cancel()
    }
}

/// One-worker backpressure bridge for high-frequency file-copy progress.
///
/// The bounded signal stream and latest-value slot make callback volume
/// constant-space. Explicit 0/1 endpoints are retained, while intermediate
/// samples are replaced and delivered no more often than `minimumInterval`.
nonisolated final class TAPVideoPlaybackProgressCoalescer: @unchecked Sendable {
    typealias Delivery = @MainActor @Sendable (Double?) -> Void

    private let buffer: MediaProgressBuffer
    private let signalContinuation: AsyncStream<Void>.Continuation
    private let workerTask: Task<Void, Never>

    init(
        minimumInterval: Duration = .milliseconds(50),
        delivery: @escaping Delivery
    ) {
        let buffer = MediaProgressBuffer()
        let signals = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.buffer = buffer
        signalContinuation = signals.continuation
        workerTask = Task.detached(priority: .utility) {
            for await _ in signals.stream {
                drainLoop: while !Task.isCancelled {
                    switch buffer.nextAction() {
                    case .deliver(let sample, let isFinal):
                        guard !Task.isCancelled else {
                            return
                        }
                        await MainActor.run {
                            guard buffer.allowsDelivery else {
                                return
                            }
                            delivery(sample.progress)
                        }
                        if isFinal {
                            return
                        }
                        do {
                            try await Task.sleep(for: minimumInterval)
                        } catch {
                            return
                        }
                    case .wait:
                        break drainLoop
                    case .stop:
                        return
                    }
                }
            }
        }
    }

    deinit {
        cancel()
    }

    func submit(_ progress: Double?) {
        buffer.submit(progress)
        signalContinuation.yield()
    }

    func finish() async {
        buffer.finish()
        signalContinuation.yield()
        signalContinuation.finish()
        await workerTask.value
    }

    func cancel() {
        buffer.cancel()
        signalContinuation.finish()
        workerTask.cancel()
    }
}

nonisolated private final class MediaProgressBuffer: @unchecked Sendable {
    struct Sample: Sendable {
        let progress: Double?
    }

    enum DrainAction: Sendable {
        case deliver(Sample, isFinal: Bool)
        case wait
        case stop
    }

    private let lock = NSLock()
    private var latestSample: Sample?
    private var needsZeroEndpoint = false
    private var needsOneEndpoint = false
    private var didDrainZeroEndpoint = false
    private var isFinished = false
    private var isCancelled = false

    func submit(_ progress: Double?) {
        let normalizedProgress: Double?
        if let progress, progress.isFinite {
            normalizedProgress = min(max(progress, 0), 1)
        } else {
            normalizedProgress = nil
        }

        lock.withLock {
            guard !isFinished, !isCancelled else {
                return
            }
            if normalizedProgress == 0, !didDrainZeroEndpoint {
                needsZeroEndpoint = true
            }
            if normalizedProgress == 1 {
                needsOneEndpoint = true
            }
            latestSample = Sample(progress: normalizedProgress)
        }
    }

    func finish() {
        lock.withLock {
            guard !isCancelled else {
                return
            }
            isFinished = true
        }
    }

    /// Called only after the worker has stopped, so completion can retain
    /// the leading/trailing contract without waiting out a throttle sleep.
    func takeCompletionSamples() -> [Sample] {
        lock.withLock {
            guard !isCancelled else {
                return []
            }
            var samples: [Sample] = []
            if needsZeroEndpoint {
                needsZeroEndpoint = false
                didDrainZeroEndpoint = true
                samples.append(Sample(progress: 0))
            }
            if let latestSample,
               latestSample.progress != 0,
               latestSample.progress != 1 {
                samples.append(latestSample)
            }
            latestSample = nil
            if needsOneEndpoint {
                needsOneEndpoint = false
                samples.append(Sample(progress: 1))
            }
            return samples
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            latestSample = nil
            needsZeroEndpoint = false
            needsOneEndpoint = false
        }
    }

    var allowsDelivery: Bool {
        lock.withLock { !isCancelled }
    }

    func nextAction() -> DrainAction {
        lock.withLock {
            guard !isCancelled else {
                return .stop
            }
            if needsZeroEndpoint {
                needsZeroEndpoint = false
                didDrainZeroEndpoint = true
                if latestSample?.progress == 0 {
                    latestSample = nil
                }
                return .deliver(Sample(progress: 0), isFinal: false)
            }
            if needsOneEndpoint {
                needsOneEndpoint = false
                latestSample = nil
                return .deliver(Sample(progress: 1), isFinal: isFinished)
            }
            if let latestSample {
                self.latestSample = nil
                return .deliver(latestSample, isFinal: isFinished)
            }
            return isFinished ? .stop : .wait
        }
    }
}
