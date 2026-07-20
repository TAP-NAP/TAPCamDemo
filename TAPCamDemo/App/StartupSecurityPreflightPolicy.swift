//
//  StartupSecurityPreflightPolicy.swift
//  TAPCamDemo
//

import Foundation

/// Retry window for the strict first-launch backend security preflight.
///
/// This type is deliberately pure: it does not know about URLSession, App
/// Attest, SwiftUI, or OS permissions. Read it before
/// `StartupBackendSecurityPreflight` when checking the first-launch timeout
/// contract.
nonisolated struct StartupSecurityPreflightPolicy: Equatable, Sendable {
    let timeoutSeconds: TimeInterval
    let retryDelayNanoseconds: UInt64

    init(
        timeoutSeconds: TimeInterval = 30,
        retryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.timeoutSeconds = max(0, timeoutSeconds)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    var retryDelaySeconds: TimeInterval {
        TimeInterval(retryDelayNanoseconds) / 1_000_000_000
    }

    func deadline(startedAt startDate: Date) -> Date {
        startDate.addingTimeInterval(timeoutSeconds)
    }

    func canStartAttempt(now: Date, deadline: Date) -> Bool {
        now < deadline
    }

    func shouldSleepBeforeRetry(now: Date, deadline: Date) -> Bool {
        retryDelayNanoseconds > 0
            && now.addingTimeInterval(retryDelaySeconds) < deadline
    }
}
