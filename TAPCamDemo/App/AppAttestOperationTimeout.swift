//
//  AppAttestOperationTimeout.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum AppAttestOperationTimeout {
    static let defaultDuration: Duration = .seconds(30)

    static func run<T: Sendable>(
        operationDescription: String,
        timeout: Duration = defaultDuration,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let race = AppAttestTimeoutRace<T>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operationTask = Task {
                    do {
                        let value = try await operation()
                        race.complete(.success(value), continuation: continuation)
                    } catch {
                        race.complete(.failure(error), continuation: continuation)
                    }
                }
                race.setOperationTask(operationTask)

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    race.complete(
                        .failure(AppAttestOperationTimeoutError(operationDescription: operationDescription)),
                        continuation: continuation
                    )
                }
                race.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            race.cancelAll()
        }
    }
}

nonisolated struct AppAttestOperationTimeoutError: LocalizedError, Sendable {
    let operationDescription: String

    var errorDescription: String? {
        "\(operationDescription) timed out."
    }
}

private final class AppAttestTimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func setOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = didComplete
        if !didComplete {
            operationTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = didComplete
        if !didComplete {
            timeoutTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func cancelAll() {
        lock.lock()
        let operationTask = operationTask
        let timeoutTask = timeoutTask
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
    }

    func complete(_ result: Result<T, Error>, continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }

        didComplete = true
        let operationTask = operationTask
        let timeoutTask = timeoutTask
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(with: result)
    }
}
