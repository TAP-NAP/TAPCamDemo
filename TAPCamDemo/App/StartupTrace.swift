//
//  StartupTrace.swift
//  TAPCamDemo
//

import Foundation
import OSLog

nonisolated enum StartupTrace {
    private static let logger = Logger(subsystem: "TAP-NAP.TAPCamDemo", category: "Startup")
    private static let origin = CFAbsoluteTimeGetCurrent()

    @discardableResult
    static func mark(_ event: String) -> Double {
        let elapsed = elapsedSeconds()
        let line = message(prefix: "mark", name: event, elapsed: elapsed)
        logger.info("\(line, privacy: .public)")
        print(line)
        return elapsed
    }

    static func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let start = elapsedSeconds()
        logger.info("\(message(prefix: "begin", name: name, elapsed: start), privacy: .public)")
        do {
            let value = try operation()
            logEnd(name: name, start: start)
            return value
        } catch {
            logEnd(name: "\(name) failed: \(error.localizedDescription)", start: start)
            throw error
        }
    }

    static func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let start = elapsedSeconds()
        logger.info("\(message(prefix: "begin", name: name, elapsed: start), privacy: .public)")
        do {
            let value = try await operation()
            logEnd(name: name, start: start)
            return value
        } catch {
            logEnd(name: "\(name) failed: \(error.localizedDescription)", start: start)
            throw error
        }
    }

    private static func logEnd(name: String, start: Double) {
        let end = elapsedSeconds()
        let duration = max(0, end - start)
        let line = message(prefix: "end", name: name, elapsed: end, duration: duration)
        logger.info("\(line, privacy: .public)")
        print(line)
    }

    private static func elapsedSeconds() -> Double {
        CFAbsoluteTimeGetCurrent() - origin
    }

    private static func message(prefix: String, name: String, elapsed: Double, duration: Double? = nil) -> String {
        if let duration {
            return "[startup] +\(formatSeconds(elapsed))s \(prefix) \(name) duration=\(formatMilliseconds(duration))ms"
        }
        return "[startup] +\(formatSeconds(elapsed))s \(prefix) \(name)"
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.1f", value * 1_000)
    }
}
