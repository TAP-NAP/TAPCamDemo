//
//  TAPLibraryNotifications.swift
//  TAPCamDemo
//

import Foundation

nonisolated extension Notification.Name {
    static let tapLibraryDidChange = Notification.Name("tapLibraryDidChange")
}

/// Optional private routing payload for queue-originated Library changes.
/// General Photos/catalog changes may continue posting `nil`; Viewer resource
/// owners use this value only to ignore unrelated pending-capture updates.
nonisolated struct TAPLibraryPendingCaptureChange: Sendable {
    let captureID: String
}

nonisolated enum TAPLibraryChangeNotifier {
    static func post(captureID: String? = nil) {
        let object = captureID.map(TAPLibraryPendingCaptureChange.init)
        if Thread.isMainThread {
            NotificationCenter.default.post(
                name: .tapLibraryDidChange,
                object: object
            )
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .tapLibraryDidChange,
                    object: object
                )
            }
        }
    }
}

nonisolated enum TAPPendingCaptureRoot {
    static var defaultURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("TAPCaptureLibrary", isDirectory: true)
            .appendingPathComponent(
                TAPPendingCaptureBundlePathPolicy.recordsDirectoryName,
                isDirectory: true
            )
    }
}
