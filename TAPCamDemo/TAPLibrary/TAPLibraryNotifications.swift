//
//  TAPLibraryNotifications.swift
//  TAPCamDemo
//

import Foundation

nonisolated extension Notification.Name {
    static let tapLibraryDidChange = Notification.Name("tapLibraryDidChange")
    static let tapCamLockedCaptureImportDidAddPendingCaptures = Notification.Name(
        "tapCamLockedCaptureImportDidAddPendingCaptures"
    )
}

nonisolated enum TAPLibraryChangeNotifier {
    static func post() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
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
