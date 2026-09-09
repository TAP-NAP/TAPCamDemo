//
//  TAPVideoDepthDecodeAdmission.swift
//  TAPCamDemo
//

import Foundation

nonisolated final class TAPVideoDepthDecodeAdmission: @unchecked Sendable {
    nonisolated struct Owner: Hashable, Sendable {
        fileprivate let id: UUID
    }

    nonisolated struct Token: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let owner: Owner
        let generation: UInt64
    }

    private struct Waiter {
        let id: UUID
        let owner: Owner
        let expectedGeneration: UInt64
        let continuation: CheckedContinuation<Token?, Never>
    }

    private let maximumConcurrentDecodes: Int
    private let lock = NSLock()
    private var ownerGenerations: [Owner: UInt64] = [:]
    private var activeTokens: [UUID: Token] = [:]
    private var waiters: [Waiter] = []

    init(
        maximumConcurrentDecodes: Int =
            TAPVideoDepthPlaybackBudget.maximumConcurrentDecodes
    ) {
        self.maximumConcurrentDecodes = min(
            max(1, maximumConcurrentDecodes),
            TAPVideoDepthPlaybackBudget.maximumConcurrentDecodes
        )
    }

    func makeOwner() -> Owner {
        let owner = Owner(id: UUID())
        lock.lock()
        ownerGenerations[owner] = 1
        lock.unlock()
        return owner
    }

    @discardableResult
    func beginNewGeneration(for owner: Owner) -> UInt64 {
        lock.lock()
        let current = (ownerGenerations[owner] ?? 1) &+ 1
        ownerGenerations[owner] = current
        let staleWaiters = removeWaitersLocked(for: owner)
        lock.unlock()
        resume(staleWaiters, with: nil)
        return current
    }

    func admit(for owner: Owner) -> Token? {
        lock.lock()
        defer { lock.unlock() }
        guard let generation = ownerGenerations[owner],
              activeTokens.count < maximumConcurrentDecodes else {
            return nil
        }
        let token = Token(id: UUID(), owner: owner, generation: generation)
        activeTokens[token.id] = token
        return token
    }

    func admitWhenAvailable(
        for owner: Owner,
        expectedGeneration: UInt64
    ) async -> Token? {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if Task.isCancelled
                    || ownerGenerations[owner] != expectedGeneration {
                    lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                if activeTokens.count < maximumConcurrentDecodes {
                    let token = Token(
                        id: UUID(),
                        owner: owner,
                        generation: expectedGeneration
                    )
                    activeTokens[token.id] = token
                    lock.unlock()
                    continuation.resume(returning: token)
                    return
                }
                waiters.append(Waiter(
                    id: waiterID,
                    owner: owner,
                    expectedGeneration: expectedGeneration,
                    continuation: continuation
                ))
                lock.unlock()
            }
        } onCancel: {
            cancelWaiter(waiterID)
        }
    }

    func isCurrent(_ token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ownerGenerations[token.owner] == token.generation
            && activeTokens[token.id] == token
    }

    func finish(_ token: Token) {
        lock.lock()
        activeTokens[token.id] = nil
        let resumptions = admitWaitingTasksLocked()
        lock.unlock()
        for (waiter, admittedToken) in resumptions {
            waiter.continuation.resume(returning: admittedToken)
        }
    }

    func invalidate(_ owner: Owner) {
        lock.lock()
        ownerGenerations[owner] = nil
        let staleWaiters = removeWaitersLocked(for: owner)
        lock.unlock()
        resume(staleWaiters, with: nil)
    }

    var activeDecodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeTokens.count
    }

    func currentGeneration(for owner: Owner) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return ownerGenerations[owner]
    }

    var waitingAdmissionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    private func cancelWaiter(_ waiterID: UUID) {
        lock.lock()
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: index)
        lock.unlock()
        waiter.continuation.resume(returning: nil)
    }

    private func removeWaitersLocked(for owner: Owner) -> [Waiter] {
        var removed: [Waiter] = []
        waiters.removeAll { waiter in
            guard waiter.owner == owner else {
                return false
            }
            removed.append(waiter)
            return true
        }
        return removed
    }

    private func admitWaitingTasksLocked() -> [(Waiter, Token?)] {
        var resumptions: [(Waiter, Token?)] = []
        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            guard ownerGenerations[waiter.owner] == waiter.expectedGeneration else {
                waiters.remove(at: index)
                resumptions.append((waiter, nil))
                continue
            }
            guard activeTokens.count < maximumConcurrentDecodes else {
                index += 1
                continue
            }
            waiters.remove(at: index)
            let token = Token(
                id: UUID(),
                owner: waiter.owner,
                generation: waiter.expectedGeneration
            )
            activeTokens[token.id] = token
            resumptions.append((waiter, token))
        }
        return resumptions
    }

    private func resume(_ waiters: [Waiter], with token: Token?) {
        for waiter in waiters {
            waiter.continuation.resume(returning: token)
        }
    }
}
