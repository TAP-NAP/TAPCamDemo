//
//  TAPPendingCaptureRetryClassifier.swift
//  TAPCamDemo
//

import Foundation

/// Maps raw worker errors to durable pending-capture retry states.
///
/// The classifier intentionally uses typed Foundation error domains and codes
/// instead of localized error text. Localized descriptions can contain URLs,
/// paths, identifiers, or translated prose; they are presentation/debug input,
/// not retry policy.
nonisolated enum TAPPendingCaptureRetryClassifier {
    static func status(for error: Error) -> TAPPendingCaptureStatus {
        isNetworkUnavailable(error) ? .waitingNetwork : .failedRetryable
    }

    static func isNetworkUnavailable(_ error: Error) -> Bool {
        containsNetworkUnavailableError(error as NSError)
    }

    private static func containsNetworkUnavailableError(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain,
           networkUnavailableCodes.contains(error.code) {
            return true
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           containsNetworkUnavailableError(underlyingError) {
            return true
        }

        if let underlyingErrors = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            return underlyingErrors.contains(where: containsNetworkUnavailableError)
        }

        return false
    }

    private static let networkUnavailableCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorTimedOut,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorDataNotAllowed,
        NSURLErrorSecureConnectionFailed
    ]
}
