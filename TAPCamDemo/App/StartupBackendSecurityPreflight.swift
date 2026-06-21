//
//  StartupBackendSecurityPreflight.swift
//  TAPCamDemo
//

import Foundation
import OSLog

/// Executes the strict first-launch backend security preflight.
///
/// Keep this file as the bridge between the pure retry policy and the real
/// backend. `StartupGateCoordinator` owns UI-facing status; this type owns the
/// `/healthz` query loop.
nonisolated struct StartupBackendSecurityPreflight: StartupSecurityPreflightChecking {
    private let policy: StartupSecurityPreflightPolicy
    private let healthCheckURL: @Sendable () -> URL?
    private let queryBackendHealth: @Sendable (URL) async -> Bool
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (UInt64) async -> Void

    init(
        policy: StartupSecurityPreflightPolicy = StartupSecurityPreflightPolicy(),
        healthCheckURL: @escaping @Sendable () -> URL? = StartupBackendSecurityPreflight.defaultHealthCheckURL,
        queryBackendHealth: @escaping @Sendable (URL) async -> Bool = StartupBackendSecurityPreflight.queryBackendHealth,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.policy = policy
        self.healthCheckURL = healthCheckURL
        self.queryBackendHealth = queryBackendHealth
        self.now = now
        self.sleep = sleep
    }

    func currentRequirementStatus() -> StartupGateRequirementStatus? {
        nil
    }

    func performRequiredPreflight() async -> StartupGateRequirementStatus {
        guard let url = healthCheckURL() else {
            TAPDiagnostics.securityPreflight.error("security preflight denied missing backend URL")
            return .denied
        }

        let deadline = policy.deadline(startedAt: now())
        var attempt = 0
        TAPDiagnostics.securityPreflight.info("security preflight start timeoutSeconds=\(self.policy.timeoutSeconds, privacy: .public)")
        while policy.canStartAttempt(now: now(), deadline: deadline) {
            attempt += 1
            let requestSucceeded = await queryBackendHealth(url)
            if requestSucceeded {
                TAPDiagnostics.securityPreflight.info("security preflight granted attempt=\(attempt, privacy: .public)")
                return .granted
            }

            guard policy.shouldSleepBeforeRetry(now: now(), deadline: deadline) else {
                break
            }

            TAPDiagnostics.securityPreflight.info("security preflight retry attempt=\(attempt, privacy: .public)")
            await sleep(policy.retryDelayNanoseconds)
        }

        TAPDiagnostics.securityPreflight.error("security preflight denied after timeout attemptCount=\(attempt, privacy: .public)")
        return .denied
    }

    static func queryBackendHealth(url: URL) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 3)
        request.httpMethod = "GET"

        do {
            TAPDiagnostics.securityPreflight.info("security preflight request endpoint=healthz")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                TAPDiagnostics.securityPreflight.error("security preflight failed nonHTTPResponse endpoint=healthz")
                return false
            }
            let succeeded = (200..<300).contains(httpResponse.statusCode)
            TAPDiagnostics.securityPreflight.info("security preflight response endpoint=healthz statusCode=\(httpResponse.statusCode, privacy: .public) succeeded=\(succeeded, privacy: .public)")
            return succeeded
        } catch {
            TAPDiagnostics.securityPreflight.error("security preflight failed endpoint=healthz error=\(TAPDiagnostics.describe(error), privacy: .public)")
            return false
        }
    }

    static func defaultHealthCheckURL() -> URL? {
        if let baseURL = try? AppAttestBackendConfiguration.baseURL() {
            return baseURL.appendingPathComponent("healthz", isDirectory: false)
        }

        return nil
    }
}
