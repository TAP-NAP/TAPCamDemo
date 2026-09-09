//
//  TAPVideoPlaybackProgressCoalescer.swift
//  TAPCamDemo
//

import Foundation

/// One-worker backpressure bridge for high-frequency file-copy progress.
///
/// The bounded signal stream and latest-value slot make callback volume
/// constant-space. Explicit 0/1 endpoints are retained, while intermediate
/// samples are replaced and delivered no more often than `minimumInterval`.
nonisolated final class TAPVideoPlaybackProgressCoalescer: @unchecked Sendable {
    typealias Delivery = @MainActor @Sendable (Double?) -> Void

    private struct Sample: Sendable {
        let progress: Double?
    }

    private enum DrainAction: Sendable {
        case deliver(Sample, isFinal: Bool)
        case wait
        case stop
    }

    private final class Buffer: @unchecked Sendable {
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

    private let buffer: Buffer
    private let signalContinuation: AsyncStream<Void>.Continuation
    private let workerTask: Task<Void, Never>

    init(
        minimumInterval: Duration = .milliseconds(50),
        delivery: @escaping Delivery
    ) {
        let buffer = Buffer()
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
