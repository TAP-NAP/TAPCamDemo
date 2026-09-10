import Foundation
import OSLog

nonisolated enum TAPDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TAPCamDemo"

    static let appAttest = Logger(subsystem: subsystem, category: "AppAttest")
    static let cameraCapture = Logger(subsystem: subsystem, category: "CameraCapture")
    static let pendingCapture = Logger(subsystem: subsystem, category: "PendingCapture")
    static let securityPreflight = Logger(subsystem: subsystem, category: "SecurityPreflight")
    static let photoLibrary = Logger(subsystem: subsystem, category: "PhotoLibrary")
    static let depthAnalysis = Logger(subsystem: subsystem, category: "DepthAnalysis")
    static let sharePackaging = Logger(subsystem: subsystem, category: "SharePackaging")

    /// Public log-safe error summary.
    ///
    /// `localizedDescription`, failing URLs, and raw network paths may contain
    /// endpoints, file paths, or device routing details. Keep those out of
    /// public OSLog fields while preserving domain/code and low-cardinality
    /// network hints for diagnosis.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlyingDomain=\(underlying.domain)")
            parts.append("underlyingCode=\(underlying.code)")
        }

        if let streamDomain = firstUserInfoValue(for: "_kCFStreamErrorDomainKey", in: nsError) {
            parts.append("streamDomain=\(streamDomain)")
        }

        if let streamCode = firstUserInfoValue(for: "_kCFStreamErrorCodeKey", in: nsError) {
            parts.append("streamCode=\(streamCode)")
        }

        if let sslOriginalValue = firstUserInfoValue(for: "_kCFNetworkCFStreamSSLErrorOriginalValue", in: nsError) {
            parts.append("sslOriginalValue=\(sslOriginalValue)")
        }

        if let clientCertificateState = firstUserInfoValue(for: "_kCFStreamPropertySSLClientCertificateState", in: nsError) {
            parts.append("clientCertificateState=\(clientCertificateState)")
        }

        if errorLooksVPNRelated(error) {
            parts.append("vpnHint=true")
        }

        return parts.joined(separator: " ")
    }

    static func errorLooksVPNRelated(_ error: Error) -> Bool {
        guard let path = networkPathDescription(in: error as NSError)?.lowercased() else {
            return false
        }
        return path.contains("utun")
            || path.contains("vpn")
            || path.contains("198.18.")
    }

    private static func networkPathDescription(in error: NSError) -> String? {
        guard let value = firstUserInfoValue(for: "_NSURLErrorNWPathKey", in: error) else {
            return nil
        }
        return String(describing: value)
    }

    private static func firstUserInfoValue(for key: String, in error: NSError) -> Any? {
        if let value = error.userInfo[key] {
            return value
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return firstUserInfoValue(for: key, in: underlying)
        }
        return nil
    }
}
